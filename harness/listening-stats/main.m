// Runs SGPlayLog.m on the Mac against synthetic export files, loose and zipped, and checks what the stats
// page would read out. Exits non-zero when a check fails.
//
//     ./build.sh && build/listening-stats
#import <Foundation/Foundation.h>
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/ListeningStats/SGTopCharts.h"
#import "Shared/ListeningStats/SGRecap.h"
#include <sys/resource.h>
#include <signal.h>
#include <sys/clonefile.h>
#include <sys/stat.h>
#include <malloc/malloc.h>
#include <unistd.h>
#include <dlfcn.h>
#include <stdatomic.h>
#include <errno.h>
#import <objc/runtime.h>

// Link-time interposition of the production POSIX boundary, not a product-only test hook.
// Hold one real fsync until the caller explicitly releases it; a broken synchronous implementation
// times out with an ordinary write error instead of hanging or crashing the harness.
static atomic_bool stallNextSync, stalledSyncTimedOut, failNextSync;
static dispatch_semaphore_t syncEntered, releaseSync;
int fsync(int fd) {
    static int (*realSync)(int);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        realSync = dlsym(RTLD_NEXT, "fsync");
        if (!realSync) { fprintf(stderr, "cannot resolve system fsync\n"); exit(1); }
    });
    if (atomic_exchange(&failNextSync, false)) { errno = ENOSPC; return -1; }
    if (atomic_exchange(&stallNextSync, false)) {
        dispatch_semaphore_signal(syncEntered);
        if (dispatch_semaphore_wait(releaseSync, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
            atomic_store(&stalledSyncTimedOut, true);
            errno = ETIMEDOUT;
            return -1;
        }
    }
    return realSync(fd);
}

// Pause one scheduler barrier before its block runs. The storage probes below let a load read
// pre-erase bytes while deletion is queued behind that barrier, then allow deletion to complete.
// This exercises public persistence operations without inspecting the log's queues or ivars.
static atomic_bool pauseNextBarrier;
static dispatch_semaphore_t barrierEntered, releaseBarrier, canonicalRead;
void dispatch_sync(dispatch_queue_t queue, dispatch_block_t block) {
    static void (*realSync)(dispatch_queue_t, dispatch_block_t);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        realSync = dlsym(RTLD_NEXT, "dispatch_sync");
        if (!realSync) { fprintf(stderr, "cannot resolve system dispatch_sync\n"); exit(1); }
    });
    if (atomic_exchange(&pauseNextBarrier, false)) {
        realSync(queue, ^{
            dispatch_semaphore_signal(barrierEntered);
            if (dispatch_semaphore_wait(releaseBarrier, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
                fprintf(stderr, "scheduler barrier probe timed out\n"); exit(1);
            }
            block();
        });
    } else realSync(queue, block);
}

static NSString *eraseRacePath;
static BOOL (*originalRemoveItem)(id, SEL, NSString *, NSError **);
static atomic_bool forceCopy, holdClone;
int fclonefileat(int from, int dir, const char *to, uint32_t flags) {
    static int (*realClone)(int, int, const char *, uint32_t);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ realClone = dlsym(RTLD_NEXT, "fclonefileat"); });
    if (atomic_exchange(&holdClone, false)) {
        dispatch_semaphore_signal(syncEntered);
        if (dispatch_semaphore_wait(releaseSync, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
            fprintf(stderr, "held import clone timed out\n"); exit(1);
        }
    }
    if (atomic_exchange(&forceCopy, false)) { errno = EXDEV; return -1; }
    int result = realClone(from, dir, to, flags);
    struct stat a, b;
    if (eraseRacePath && !fstat(from, &a) && !stat(eraseRacePath.fileSystemRepresentation, &b) &&
        a.st_dev == b.st_dev && a.st_ino == b.st_ino) dispatch_semaphore_signal(canonicalRead);
    return result;
}
static BOOL removeRaceItem(id object, SEL selector, NSString *path, NSError **error) {
    if ([path isEqual:eraseRacePath] &&
        dispatch_semaphore_wait(canonicalRead, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC))) {
        fprintf(stderr, "canonical-read probe timed out\n"); exit(1);
    }
    return originalRemoveItem(object, selector, path, error);
}

static int failures = 0;
#define CHECK(cond, ...) do { if (cond) printf("ok    "); else { printf("FAIL  "); failures++; } printf(__VA_ARGS__); printf("\n"); } while (0)

// The production API is asynchronous; test sequences wait while allowing its main completion to run.
static NSUInteger mergeAndWait(SGPlayLog *log, NSArray *plays, NSError **error) {
    __block BOOL done = NO;
    __block NSUInteger count = 0;
    __block NSError *failure;
    [log merge:plays completion:^(NSUInteger added, NSError *reason) {
        count = added; failure = reason; done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "history merge timed out\n"); exit(1); }
    if (error) *error = failure;
    return count;
}
@interface SGPlayLog (Harness)
- (NSUInteger)merge:(NSArray *)plays;
@end
@implementation SGPlayLog (Harness)
- (NSUInteger)merge:(NSArray *)plays {
    NSError *error;
    NSUInteger added = mergeAndWait(self, plays, &error);
    CHECK(!error, "merge completes without a persistence error");
    return added;
}
@end

static void loadAndWait(SGPlayLog *log) {
    __block BOOL done = NO;
    [log loadWithCompletion:^{ done = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "history load timed out\n"); exit(1); }
}
static NSError *writesAndWait(SGPlayLog *log) {
    __block BOOL done = NO;
    __block NSError *failure;
    [log finishPendingWritesWithCompletion:^(NSError *error) { failure = error; done = YES; }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!done) { fprintf(stderr, "recorder acknowledgement timed out\n"); exit(1); }
    return failure;
}
static SGPlayLog *openLog(NSString *path) {
    SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
    loadAndWait(log);
    return log;
}

static NSData *json(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static NSString *stamp(int64_t t, BOOL extended) {
    NSDateFormatter *f = [NSDateFormatter new];
    f.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    f.dateFormat = extended ? @"yyyy-MM-dd'T'HH:mm:ss'Z'" : @"yyyy-MM-dd HH:mm";
    return [f stringFromDate:[NSDate dateWithTimeIntervalSince1970:t]];
}

static NSDictionary *extendedRow(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    return @{@"ts": stamp(end, YES), @"platform": @"ios", @"ms_played": @(ms), @"conn_country": @"CZ",
             @"master_metadata_track_name": title ?: (id)NSNull.null, @"master_metadata_album_artist_name": artist ?: (id)NSNull.null,
             @"master_metadata_album_album_name": album ?: (id)NSNull.null,
             @"spotify_track_uri": title ? [@"spotify:track:" stringByAppendingString:title] : (id)NSNull.null,
             @"episode_name": NSNull.null, @"spotify_episode_uri": NSNull.null, @"reason_end": @"trackdone"};
}

static NSDictionary *basicRow(int64_t end, int64_t ms, NSString *title, NSString *artist) {
    return @{@"endTime": stamp(end, NO), @"artistName": artist, @"trackName": title, @"msPlayed": @(ms)};
}

static SGPlay *play(int64_t end, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    SGPlay *p = [SGPlay new];
    p.end = end; p.ms = ms; p.title = title; p.artist = artist; p.album = album ?: @""; p.uri = @"";
    return p;
}

static void snapshotChecks(NSString *dir) {
    NSString *path = [dir stringByAppendingPathComponent:@"private.tsv"];
    NSString *odd = @"1\t2\turi\t\u0301bad\tartist\talbum";
    NSMutableString *rows = [NSMutableString stringWithFormat:@"%@\n", odd];
    for (int i = 0; i < 10000; i++) [rows appendFormat:@"%d\t30000\turi\tSong %d\tArtist\tAlbum\n", i, i];
    [rows writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    atomic_store(&forceCopy, true);
    SGPlayLog *log = openLog(path);
    NSUInteger count = 10001;
    CHECK(log.plays.count == count && [log.plays.firstObject.title isEqual:@"\u0301bad"] && log.plays.lastObject.end == 9999,
          "combining mark belongs to the field after the tab");
    malloc_statistics_t a, b;
    malloc_zone_statistics(NULL, &a);
    NSArray<SGPlay *> *suffix = [log playsFromIndex:1];
    malloc_zone_statistics(NULL, &b);
    CHECK((double)b.size_in_use - a.size_in_use < 65536 && suffix.count == count - 1, "large suffix needs no per-row materialization");
    CHECK(truncate(path.fileSystemRepresentation, 0) == 0 && suffix[9000].end == 9001 - (count - 10000),
          "published suffix remains readable past truncated EOF");
    SGPlay *p = play(1000, 48000, @"A\tB", @"C\nD", @"Album");
    CHECK([log merge:@[p]] == 1 && [log merge:@[p]] == 0 && [log merge:@[p]] == 0,
          "repeat Spotify merges match normalized title and artist");
    NSArray<SGPlay *> *committed = log.plays;
    CHECK(truncate(path.fileSystemRepresentation, 0) == 0 && [committed.firstObject.title isEqual:@"A B"],
          "just-committed snapshot survives in-place truncation");
    p.exactImport = YES;
    [NSData.data writeToFile:path atomically:YES];
    CHECK([log merge:@[p]] == 1 && openLog(path).plays.count == 1, "restore deduplicates against replacement inode, not stale snapshot");
    NSString *link = [dir stringByAppendingPathComponent:@"linked.tsv"];
    CHECK(symlink(path.fileSystemRepresentation, link.fileSystemRepresentation) == 0 &&
          openLog(link).loadError.code == ELOOP, "absolute canonical symlink rejected");
    SGPlay *accent = play(7000, 30000, @"\u0301Song", @"Artist", @"");
    CHECK([log merge:@[accent]] == 1 && [log merge:@[accent]] == 0 &&
          [log.plays.lastObject.title isEqual:accent.title] && SGStatsSince(log.plays, 7000, 1).plays == 1,
          "combining-mark title imported twice counts once in stats");

    SGPlayLog *restorer = openLog(path);
    __block NSUInteger completions = 0;
    void (^added)(NSUInteger, NSError *) = ^(NSUInteger n, NSError *error) {
        CHECK(!error && n == 1, "independent import or restore committed its row");
        completions++;
    };
    syncEntered = dispatch_semaphore_create(0); releaseSync = dispatch_semaphore_create(0);
    atomic_store(&holdClone, true);
    [log merge:@[play(8000, 30000, @"Imported", @"Artist", @"")] completion:added];
    CHECK(!dispatch_semaphore_wait(syncEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)), "import reached snapshot clone");
    SGPlay *backup = play(9000, 30000, @"Restored", @"Artist", @""); backup.exactImport = YES;
    [restorer merge:@[backup] completion:added];
    dispatch_semaphore_signal(releaseSync);
    loadAndWait(restorer);
    CHECK(completions == 2 && openLog(path).plays.count == 4, "both writers preserved in canonical TSV");
}

static void zip(NSString *dir, NSString *out, NSArray<NSString *> *names, BOOL stored) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/zip"];
    task.currentDirectoryURL = [NSURL fileURLWithPath:dir];
    NSMutableArray *args = [NSMutableArray arrayWithObjects:@"-q", stored ? @"-0" : @"-9", out, nil];
    [args addObjectsFromArray:names];
    task.arguments = args;
    [task launchAndReturnError:nil];
    [task waitUntilExit];
}

static double since(NSDate *start) {
    return -start.timeIntervalSinceNow * 1000;
}

static NSDate *date(NSString *iso) {
    return [[NSISO8601DateFormatter new] dateFromString:iso];
}

static SGPlay *dated(NSString *iso, int64_t ms) {
    return play((int64_t)date(iso).timeIntervalSince1970, ms, @"Calendar song", @"Artist", @"Album");
}

static void calendarChecks(void) {
    NSCalendar *ny = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    ny.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSArray *spring = @[dated(@"2026-03-07T23:30:00-05:00", 20000), dated(@"2026-03-08T23:30:00-04:00", 60000),
                        dated(@"2026-03-09T00:30:00-04:00", 120000), dated(@"2026-03-08T12:00:00-04:00", 60000)];
    SGListeningStreaks *s = SGStreaks(spring, date(@"2026-03-09T12:00:00-04:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: spring DST, duplicate local day and counted short play = 3 days");
    s = SGStreaks(spring, date(@"2026-03-10T12:00:00-04:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: yesterday remains current when today has no play");
    s = SGStreaks(spring, date(@"2026-03-11T00:00:00-04:00"), ny);
    CHECK(s.current == 0 && s.best == 3, "streak: missing yesterday ends current but keeps best");
    s = SGStreaks(@[], date(@"2026-03-09T12:00:00-04:00"), ny);
    CHECK(s.current == 0 && s.best == 0, "streak: empty history");
    NSArray *fall = @[dated(@"2026-10-31T23:45:00-04:00", 60000), dated(@"2026-11-01T01:30:00-04:00", 60000),
                      dated(@"2026-11-01T01:30:00-05:00", 120000), dated(@"2026-11-02T00:05:00-05:00", 30000)];
    s = SGStreaks(fall, date(@"2026-11-02T12:00:00-05:00"), ny);
    CHECK(s.current == 3 && s.best == 3, "streak: fall DST repeated hour counts as one day");
    NSArray<SGStatEntry *> *hours = SGHourlyStats(fall, 0, ny);
    CHECK(hours.count == 24 && hours[1].plays == 2 && hours[1].ms == 180000 && hours[0].plays == 1 && hours[23].plays == 1,
          "hours: both fall 01:30 plays combine; midnight and 23:45 use local hours");
    hours = SGHourlyStats(fall, (int64_t)date(@"2026-11-01T01:30:00-05:00").timeIntervalSince1970, ny);
    CHECK(hours[1].plays == 1 && hours[1].ms == 120000 && hours[23].plays == 0, "hours: selected period includes exact cutoff only once");
    hours = SGHourlyStats(@[dated(@"2026-03-08T01:59:00-05:00", 60000), dated(@"2026-03-08T03:00:00-04:00", 90000)], 0, ny);
    CHECK(hours[1].plays == 1 && hours[2].plays == 0 && hours[3].ms == 90000, "hours: missing spring hour stays empty");
    hours = SGHourlyStats(@[], 0, ny);
    CHECK(hours.count == 24 && hours[0].plays == 0 && hours[23].ms == 0, "hours: empty history still has 24 zero buckets");
    NSArray *leap = @[dated(@"2024-02-28T23:00:00-05:00", 60000), dated(@"2024-02-29T23:00:00-05:00", 60000),
                      dated(@"2024-03-01T01:00:00-05:00", 60000), dated(@"2024-03-04T01:00:00-05:00", 60000),
                      dated(@"2024-03-05T01:00:00-05:00", 60000)];
    s = SGStreaks(leap, date(@"2024-03-04T12:00:00-05:00"), ny);
    CHECK(s.current == 1 && s.best == 3, "streak: leap day/month boundary, gap, future day ignored");
    NSArray *year = @[dated(@"2025-12-31T23:59:00-05:00", 60000), dated(@"2026-01-01T00:01:00-05:00", 60000)];
    s = SGStreaks(year, date(@"2026-01-01T12:00:00-05:00"), ny);
    CHECK(s.current == 2 && s.best == 2, "streak: year boundary uses calendar days, not UTC days");
    NSCalendar *buddhist = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierBuddhist];
    buddhist.timeZone = ny.timeZone;
    s = SGStreaks(year, date(@"2026-01-01T12:00:00-05:00"), buddhist);
    CHECK(s.current == 2 && s.best == 2, "streak: non-Gregorian calendar");
    NSCalendar *kathmandu = [ny copy];
    kathmandu.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Kathmandu"];
    hours = SGHourlyStats(@[dated(@"2026-01-01T18:30:00Z", 20000)], 0, kathmandu);
    CHECK(hours[0].plays == 1 && hours[0].ms == 20000, "hours: fractional timezone and counted short track");
    NSCalendar *brazil = [ny copy];
    brazil.timeZone = [NSTimeZone timeZoneWithName:@"America/Sao_Paulo"];
    NSArray *midnightDST = @[dated(@"2018-11-03T12:00:00-03:00", 60000), dated(@"2018-11-04T12:00:00-02:00", 60000),
                             dated(@"2018-11-05T12:00:00-02:00", 60000)];
    s = SGStreaks(midnightDST, date(@"2018-11-06T12:00:00-02:00"), brazil);
    CHECK(s.current == 3 && s.best == 3, "streak: timezone skipping midnight at DST start");
}

static BOOL spans(NSDateInterval *interval, NSString *start, NSString *end) {
    return [interval.startDate isEqualToDate:date(start)] && [interval.endDate isEqualToDate:date(end)];
}

static int64_t unixOf(NSString *iso) {
    return (int64_t)date(iso).timeIntervalSince1970;
}

static void periodChecks(void) {
    NSCalendar *monday = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    monday.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    monday.firstWeekday = 2;
    NSCalendar *sunday = [monday copy];
    sunday.firstWeekday = 1;
    NSCalendar *saturday = [monday copy];
    saturday.firstWeekday = 7;

    // Weeks: a non-Sunday first weekday, DST inside the week, a week across New Year.
    CHECK(spans(SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-03-11T15:00:00-04:00"), monday), @"2026-03-09T00:00:00-04:00", @"2026-03-16T00:00:00-04:00"),
          "week: Monday-first week of Wed 11 Mar 2026 is Mon 9 – Mon 16");
    NSDateInterval *dstWeek = SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-03-08T12:00:00-04:00"), monday);
    CHECK(spans(dstWeek, @"2026-03-02T00:00:00-05:00", @"2026-03-09T00:00:00-04:00") && dstWeek.duration == 167 * 3600,
          "week: Monday-first week of DST Sunday 8 Mar ends on it, 167 h long");
    NSDateInterval *sundayWeek = SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-03-08T12:00:00-04:00"), sunday);
    CHECK(spans(sundayWeek, @"2026-03-08T00:00:00-05:00", @"2026-03-15T00:00:00-04:00"),
          "week: the same Sunday starts a Sunday-first week");
    CHECK(spans(SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-10-23T12:00:00-04:00"), saturday), @"2026-10-17T00:00:00-04:00", @"2026-10-24T00:00:00-04:00"),
          "week: Saturday-first week of Fri 23 Oct 2026 is Sat 17 – Sat 24");
    CHECK(spans(SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-01-01T12:00:00-05:00"), monday), @"2025-12-29T00:00:00-05:00", @"2026-01-05T00:00:00-05:00"),
          "week: the week of 1 Jan 2026 starts Mon 29 Dec 2025");
    CHECK(spans(SGPeriodInterval(SGStatsPeriodWeek, date(@"2026-03-09T00:00:00-04:00"), monday), @"2026-03-09T00:00:00-04:00", @"2026-03-16T00:00:00-04:00"),
          "week: a week's first instant belongs to it");
    CHECK(spans(SGPeriodStep(SGStatsPeriodWeek, date(@"2026-03-11T15:00:00-04:00"), -1, monday), @"2026-03-02T00:00:00-05:00", @"2026-03-09T00:00:00-04:00") &&
          spans(SGPeriodStep(SGStatsPeriodWeek, date(@"2026-03-02T00:00:00-05:00"), 1, monday), @"2026-03-09T00:00:00-04:00", @"2026-03-16T00:00:00-04:00") &&
          spans(SGPeriodStep(SGStatsPeriodWeek, date(@"2026-01-01T12:00:00-05:00"), -1, monday), @"2025-12-22T00:00:00-05:00", @"2025-12-29T00:00:00-05:00"),
          "week: stepping back and forward across DST and New Year");
    NSCalendar *brazil = [sunday copy];
    brazil.timeZone = [NSTimeZone timeZoneWithName:@"America/Sao_Paulo"];
    NSDateInterval *skipped = SGPeriodInterval(SGStatsPeriodWeek, date(@"2018-11-06T12:00:00-02:00"), brazil);
    CHECK([skipped.startDate isEqualToDate:date(@"2018-11-04T01:00:00-02:00")] &&
          spans(SGPeriodStep(SGStatsPeriodWeek, skipped.startDate, -1, brazil), @"2018-10-28T00:00:00-03:00", @"2018-11-04T01:00:00-02:00"),
          "week: a week starting on a day without midnight starts at 01:00, and steps back cleanly");

    // Months and years.
    CHECK(spans(SGPeriodInterval(SGStatsPeriodMonth, date(@"2024-02-15T12:00:00-05:00"), monday), @"2024-02-01T00:00:00-05:00", @"2024-03-01T00:00:00-05:00"),
          "month: leap February");
    CHECK(spans(SGPeriodStep(SGStatsPeriodMonth, date(@"2026-01-31T23:00:00-05:00"), 1, monday), @"2026-02-01T00:00:00-05:00", @"2026-03-01T00:00:00-05:00") &&
          spans(SGPeriodStep(SGStatsPeriodMonth, date(@"2026-03-31T23:00:00-04:00"), -1, monday), @"2026-02-01T00:00:00-05:00", @"2026-03-01T00:00:00-05:00"),
          "month: stepping from the 31st does not skip February");
    CHECK(spans(SGPeriodStep(SGStatsPeriodMonth, date(@"2026-01-10T12:00:00-05:00"), -1, monday), @"2025-12-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00") &&
          spans(SGPeriodStep(SGStatsPeriodMonth, date(@"2026-01-10T12:00:00-05:00"), 12, monday), @"2027-01-01T00:00:00-05:00", @"2027-02-01T00:00:00-05:00"),
          "month: stepping across years");
    CHECK(spans(SGPeriodInterval(SGStatsPeriodYear, date(@"2024-06-01T12:00:00-04:00"), monday), @"2024-01-01T00:00:00-05:00", @"2025-01-01T00:00:00-05:00") &&
          spans(SGPeriodStep(SGStatsPeriodYear, date(@"2026-10-24T12:00:00-04:00"), -1, monday), @"2025-01-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00") &&
          spans(SGPeriodStep(SGStatsPeriodYear, date(@"2024-02-29T12:00:00-05:00"), 1, monday), @"2025-01-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00"),
          "year: leap year bounds, stepping back, stepping from 29 Feb");

    // Adding up between bounds: [start, end).
    NSArray *plays = @[dated(@"2026-03-02T00:00:00-05:00", 60000), dated(@"2026-03-08T23:30:00-04:00", 120000),
                       dated(@"2026-03-09T00:00:00-04:00", 180000), dated(@"2026-03-01T23:59:59-05:00", 240000),
                       dated(@"2026-03-08T01:30:00-05:00", 30000)];
    SGStats *week = SGStatsBetween(plays, (int64_t)dstWeek.startDate.timeIntervalSince1970, (int64_t)dstWeek.endDate.timeIntervalSince1970, 10);
    CHECK(week.plays == 3 && week.ms == 210000 && week.tracks.firstObject.plays == 3, "between: start included, end excluded (3 plays, 210 s)");
    SGStats *open = SGStatsBetween(plays, unixOf(@"2026-03-02T00:00:00-05:00"), INT64_MAX, 10), *from = SGStatsSince(plays, unixOf(@"2026-03-02T00:00:00-05:00"), 10);
    CHECK(open.plays == from.plays && open.ms == from.ms && open.plays == 4, "between: INT64_MAX end equals since");
    NSArray<SGStatEntry *> *hours = SGHourlyStatsBetween(plays, (int64_t)dstWeek.startDate.timeIntervalSince1970, (int64_t)dstWeek.endDate.timeIntervalSince1970, monday);
    CHECK(hours[0].plays == 1 && hours[23].plays == 1 && hours[1].plays == 1 && hours[0].ms == 60000, "hours between: end-of-week midnight left to the next week");

    // Chart buckets: a DST week's days, a month's days, a year's months, one bucket per play.
    NSArray<SGStatBucket *> *days = SGPeriodBuckets(plays, SGStatsPeriodWeek, date(@"2026-03-05T12:00:00-05:00"), monday);
    CHECK(days.count == 7 && days[6].end - days[6].start == 23 * 3600 && days[0].start == unixOf(@"2026-03-02T00:00:00-05:00") &&
          days[6].end == unixOf(@"2026-03-09T00:00:00-04:00"), "buckets: 7 days, DST Sunday 23 h, ends where the week does");
    CHECK(days[0].plays == 1 && days[6].plays == 2 && days[6].ms == 150000 && days[1].plays == 0, "buckets: plays land on their local day, the DST day included");
    NSArray<SGStatBucket *> *fall = SGPeriodBuckets(@[dated(@"2026-11-01T01:30:00-05:00", 60000)], SGStatsPeriodWeek, date(@"2026-11-01T12:00:00-05:00"), monday);
    CHECK(fall.count == 7 && fall[6].end - fall[6].start == 25 * 3600 && fall[6].plays == 1, "buckets: fall-back Sunday 25 h, its repeated hour counted");
    NSArray<SGStatBucket *> *march = SGPeriodBuckets(plays, SGStatsPeriodMonth, date(@"2026-03-20T12:00:00-04:00"), monday);
    NSUInteger marchPlays = 0;
    for (SGStatBucket *b in march) marchPlays += b.plays;
    SGStats *marchStats = SGStatsBetween(plays, unixOf(@"2026-03-01T00:00:00-05:00"), unixOf(@"2026-04-01T00:00:00-04:00"), 1);
    CHECK(march.count == 31 && marchPlays == marchStats.plays && marchPlays == 5 && march[0].plays == 1 && march[8].plays == 1,
          "buckets: March has 31 days and its bars add up to the month's plays");
    NSArray *yearPlays = @[dated(@"2026-02-28T23:59:00-05:00", 1000), dated(@"2026-03-01T00:00:00-05:00", 2000),
                           dated(@"2026-12-31T23:59:59-05:00", 4000), dated(@"2027-01-01T00:00:00-05:00", 8000)];
    NSArray<SGStatBucket *> *months = SGPeriodBuckets(yearPlays, SGStatsPeriodYear, date(@"2026-07-01T12:00:00-04:00"), monday);
    CHECK(months.count == 12 && months[1].ms == 1000 && months[2].ms == 2000 && months[11].ms == 4000 &&
          months[11].end == unixOf(@"2027-01-01T00:00:00-05:00"), "buckets: a year's 12 months, its last second in, the next year's first out");
    NSArray<SGStatBucket *> *skippedDays = SGPeriodBuckets(@[], SGStatsPeriodWeek, date(@"2018-11-06T12:00:00-02:00"), brazil);
    CHECK(skippedDays.count == 7 && skippedDays[0].end - skippedDays[0].start == 23 * 3600, "buckets: a day without midnight is 23 h");
    NSCalendar *hebrew = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierHebrew];
    hebrew.timeZone = monday.timeZone;
    CHECK(SGPeriodBuckets(@[], SGStatsPeriodYear, date(@"2024-03-01T12:00:00-05:00"), hebrew).count == 13, "buckets: a Hebrew leap year has 13 months");

    // Streak date ranges.
    NSArray *runs = @[dated(@"2024-02-28T23:00:00-05:00", 60000), dated(@"2024-02-29T23:00:00-05:00", 60000),
                      dated(@"2024-03-01T01:00:00-05:00", 60000), dated(@"2024-03-04T01:00:00-05:00", 60000),
                      dated(@"2024-03-05T01:00:00-05:00", 60000), dated(@"2024-03-06T01:00:00-05:00", 60000)];
    SGListeningStreaks *s = SGStreaks(runs, date(@"2024-03-07T12:00:00-05:00"), monday);
    CHECK(s.best == 3 && [s.bestStart isEqualToDate:date(@"2024-03-04T00:00:00-05:00")] && [s.bestEnd isEqualToDate:date(@"2024-03-06T00:00:00-05:00")],
          "streak range: of two 3-day runs the latest is the best's");
    CHECK(s.current == 3 && [s.currentStart isEqualToDate:date(@"2024-03-04T00:00:00-05:00")] && [s.currentEnd isEqualToDate:date(@"2024-03-06T00:00:00-05:00")],
          "streak range: a current streak ending yesterday");
    s = SGStreaks([runs subarrayWithRange:NSMakeRange(0, 4)], date(@"2024-03-04T12:00:00-05:00"), monday);
    CHECK(s.best == 3 && [s.bestStart isEqualToDate:date(@"2024-02-28T00:00:00-05:00")] && [s.bestEnd isEqualToDate:date(@"2024-03-01T00:00:00-05:00")] &&
          s.current == 1 && [s.currentStart isEqualToDate:s.currentEnd], "streak range: across leap day, and a one-day current streak");
    s = SGStreaks(@[], date(@"2024-03-04T12:00:00-05:00"), monday);
    CHECK(!s.bestStart && !s.bestEnd && !s.currentStart && !s.currentEnd, "streak range: none without plays");
}

static SGPlay *at(NSString *iso, int64_t ms, NSString *title, NSString *artist, NSString *album) {
    return play(unixOf(iso), ms, title, artist, album);
}

static SGChartEntry *entryNamed(SGChart *chart, NSString *name) {
    for (SGChartEntry *entry in chart.entries) if ([entry.name isEqualToString:name]) return entry;
    return nil;
}

// A Monday-first week of January 2026 in New York (no DST), against the week before and the two before that.
static void chartChecks(void) {
    NSCalendar *ny = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    ny.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    ny.firstWeekday = 2;
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    void (^times)(NSUInteger, NSString *, int64_t, NSString *) = ^(NSUInteger n, NSString *iso, int64_t ms, NSString *title) {
        for (NSUInteger i = 0; i < n; i++) [plays addObject:at(iso, ms, title, @"Artist", @"")];
    };
    // Two weeks back: Old only. One week back (12 Jan): Delta at the top.
    times(1, @"2026-01-06T12:00:00-05:00", 30000, @"Old");
    times(1, @"2026-01-13T12:00:00-05:00", 60000, @"Delta");
    // The week before (19 Jan): Beta 5, Delta 4, Alpha 3, then 50 two-play fillers, then Epsilon at 54th.
    times(5, @"2026-01-20T12:00:00-05:00", 60000, @"Beta");
    times(4, @"2026-01-20T13:00:00-05:00", 60000, @"Delta");
    times(3, @"2026-01-20T14:00:00-05:00", 60000, @"Alpha");
    for (int i = 0; i < 50; i++) times(2, @"2026-01-21T12:00:00-05:00", 60000, [NSString stringWithFormat:@"Filler %02d", i]);
    times(1, @"2026-01-22T12:00:00-05:00", 60000, @"Epsilon");
    // The week shown (26 Jan): Delta 4 plays, then three with three plays apart only by time and name.
    times(4, @"2026-01-27T12:00:00-05:00", 25000, @"Delta");
    times(2, @"2026-01-27T13:00:00-05:00", 300000, @"Gamma");
    times(1, @"2026-01-26T00:00:00-05:00", 300000, @"Gamma");   // the week's first instant is in it
    times(3, @"2026-01-28T12:00:00-05:00", 200000, @"Beta");
    times(3, @"2026-01-28T13:00:00-05:00", 200000, @"Alpha");
    times(1, @"2026-01-29T12:00:00-05:00", 200000, @"Epsilon");
    times(1, @"2026-01-29T13:00:00-05:00", 30000, @"Old");
    times(1, @"2026-02-02T00:00:00-05:00", 600000, @"Boundary");   // the next week's first instant
    for (int i = 0; i < 10; i++) {
        SGPlay *episode = at(@"2026-01-30T12:00:00-05:00", 600000, @"Podcast", @"Host", @"");
        episode.uri = @"spotify:episode:1";
        [plays addObject:episode];
    }
    NSDate *shown = date(@"2026-01-28T12:00:00-05:00");
    SGChart *chart = SGChartBuild(plays, SGChartKindSongs, SGStatsPeriodWeek, shown, ny);
    NSArray *names = [chart.entries valueForKey:@"name"];
    CHECK(([names isEqualToArray:@[@"Delta", @"Gamma", @"Alpha", @"Beta", @"Epsilon", @"Old"]]),
          "chart: plays, then listening time, then name (%s)", [names componentsJoinedByString:@", "].UTF8String);
    CHECK(!entryNamed(chart, @"Boundary") && !entryNamed(chart, @"Podcast") && chart.played == 6 && chart.plays == 15,
          "chart: a play ending at the week's end belongs to the next; an episode is not music");
    SGChartEntry *delta = entryNamed(chart, @"Delta"), *gamma = entryNamed(chart, @"Gamma"), *alpha = entryNamed(chart, @"Alpha"),
                 *beta = entryNamed(chart, @"Beta"), *epsilon = entryNamed(chart, @"Epsilon");
    CHECK(delta.previousRank == 2 && alpha.previousRank == 3 && beta.previousRank == 1 && delta.rank == 1 && beta.rank == 4,
          "chart: moves against the week before (Delta up 1, Alpha same, Beta down 3)");
    CHECK(gamma.previousRank == 0 && epsilon.previousRank == 0,
          "chart: New when absent the week before, or there but outside its top 50 (Epsilon was 54th)");
    CHECK(delta.run == 3 && alpha.run == 2 && beta.run == 2 && gamma.run == 1 && entryNamed(chart, @"Old").run == 0,
          "chart: run of 3 weeks in the top 5 including this one; 0 outside the top 5");
    CHECK(chart.discovered == 1, "chart: discovered = never played before the week (Gamma only, not Old from two weeks back)");
    SGChart *empty = SGChartBuild(plays, SGChartKindSongs, SGStatsPeriodWeek, date(@"2025-06-04T12:00:00-04:00"), ny);
    CHECK(empty && !empty.entries.count && !empty.played && !empty.discovered && !empty.plays, "chart: a week without plays is empty");

    NSArray *named = @[at(@"2026-01-27T12:00:00-05:00", 60000, @"One", @"Beyoncé", @"Lemonade"),
                       at(@"2026-01-27T13:00:00-05:00", 60000, @"Two", @" BEYONCE", @"lemonade"),
                       at(@"2026-01-27T14:00:00-05:00", 60000, @"Three", @"Other", @"Lemonade")];
    SGChart *artists = SGChartBuild(named, SGChartKindArtists, SGStatsPeriodWeek, shown, ny);
    SGChart *albums = SGChartBuild(named, SGChartKindAlbums, SGStatsPeriodWeek, shown, ny);
    CHECK(artists.played == 2 && artists.entries.firstObject.plays == 2 && albums.played == 2 && albums.entries.firstObject.plays == 2,
          "chart: an artist by name without case, diacritics or spaces; an album by its name with its artist");

    SGStatEntry *(^entry)(NSUInteger, int64_t, NSString *, NSString *) = ^SGStatEntry *(NSUInteger plays, int64_t ms, NSString *name, NSString *detail) {
        SGStatEntry *e = [SGStatEntry new];
        e.plays = plays; e.ms = ms; e.name = name; e.detail = detail;
        return e;
    };
    SGStatEntry *zed = entry(2, 60000, @"Lemonade", @"Zed"), *abe = entry(2, 60000, @"lemonade", @"Abe");
    CHECK(SGTopOrder(entry(3, 1, @"Z", nil), zed) == NSOrderedAscending && SGTopOrder(entry(2, 60001, @"Z", nil), zed) == NSOrderedAscending &&
          SGTopOrder(entry(2, 60000, @"Alpha", nil), zed) == NSOrderedAscending && SGTopOrder(zed, abe) == NSOrderedSame,
          "top lists: plays, then time, then name without case; a tie on all three stays a tie, the artist not consulted");
    NSArray *twins = @[at(@"2026-01-27T12:00:00-05:00", 60000, @"One", @"Zed", @"Lemonade"), at(@"2026-01-27T13:00:00-05:00", 60000, @"Two", @"Abe", @"Lemonade")];
    NSArray *twinArtists = [SGChartBuild(twins, SGChartKindAlbums, SGStatsPeriodWeek, shown, ny).entries valueForKey:@"detail"];
    CHECK([twinArtists isEqualToArray:(@[@"Abe", @"Zed"])], "chart: albums tied on plays, time and name go by artist (%s)", [twinArtists componentsJoinedByString:@", "].UTF8String);
}

static NSDate *localDay(NSCalendar *cal, NSInteger year, NSInteger month, NSInteger day, NSInteger hour, NSInteger minute) {
    NSDateComponents *c = [NSDateComponents new];
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute;
    return [cal dateFromComponents:c];
}

static void recapChecks(void) {
    NSCalendar *ny = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    ny.timeZone = [NSTimeZone timeZoneWithName:@"America/New_York"];
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    SGPlay *(^on)(NSDate *, int64_t, NSString *, NSString *) = ^SGPlay *(NSDate *end, int64_t ms, NSString *title, NSString *artist) {
        SGPlay *p = play((int64_t)end.timeIntervalSince1970, ms, title, artist, @"");
        [plays addObject:p];
        return p;
    };
    on(localDay(ny, 2024, 6, 1, 12, 0), 60000, @"Song A", @"Veteran");                    // before the year
    for (NSInteger d = 1; d <= 10; d++) on(localDay(ny, 2025, 3, d, 21, 30), 300000, @"Song A", @"Veteran");   // a 10-day streak at 21h
    for (NSInteger d = 1; d <= 29; d += 2) on(localDay(ny, 2025, 6, d, 9, 15), 60000, @"Song B", @"Newcomer"); // 15 days
    for (NSInteger d = 1; d <= 7; d += 2) on(localDay(ny, 2025, 8, d, 9, 15), 60000, @"Song B", @"Newcomer");  // 4 days
    SGPlay *aug7 = plays.lastObject;
    on(date(@"2025-12-31T23:59:59-05:00"), 30000, @"Song C", @"Newcomer");                // the year's last second
    on(date(@"2026-01-01T00:00:00-05:00"), 30000, @"Song D", @"Future");                  // the next year's first
    on(localDay(ny, 2025, 9, 1, 12, 0), 900000, @"Episode", @"Host").uri = @"spotify:episode:1";

    NSArray<SGRecapYear *> *years = SGRecapYears(plays, ny);
    CHECK(years.count == 3 && years[0].activeDays == 1 && years[1].activeDays == 30 && years[1].eligible && years[2].activeDays == 1,
          "recap years: 2026, 2025 (30 active days, eligible), 2024, the latest first");
    NSMutableArray *fewer = [plays mutableCopy];
    [fewer removeObject:aug7];
    years = SGRecapYears(fewer, ny);
    CHECK(years[1].activeDays == 29 && !years[1].eligible, "recap years: 29 active days is not enough");

    SGRecap *recap = SGRecapBuild(plays, localDay(ny, 2025, 7, 1, 12, 0), date(@"2026-03-01T12:00:00-05:00"), ny);
    CHECK(spans(recap.year, @"2025-01-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00") && recap.eligible && recap.activeDays == 30,
          "recap: the calendar year, 30 active days");
    CHECK(recap.plays == 30 && recap.ms == 10 * 300000 + 19 * 60000 + 30000,
          "recap: plays by end, the last second in, the next year's first and the episode out");
    CHECK(([[recap.artists valueForKey:@"name"] isEqualToArray:@[@"Newcomer", @"Veteran"]] &&
           [[recap.songs valueForKey:@"name"] isEqualToArray:@[@"Song B", @"Song A", @"Song C"]] && recap.songs.firstObject.plays == 19 && !recap.albums.count),
          "recap: top artists and songs in chart order; no album names, no albums");
    CHECK(recap.newArtists == 1 && recap.newSongs == 2 && [recap.topNewArtist.name isEqualToString:@"Newcomer"],
          "recap: discoveries leave out what was played before 1 January (Veteran, Song A)");
    CHECK(recap.longestStreak == 10 && [recap.streakStart isEqualToDate:localDay(ny, 2025, 3, 1, 0, 0)] && [recap.streakEnd isEqualToDate:localDay(ny, 2025, 3, 10, 0, 0)],
          "recap: the longest streak, 1–10 March, across the DST change");
    CHECK(recap.peakHour == 21 && recap.peakHourMs == 3000000 && [recap.peakMonth isEqualToDate:localDay(ny, 2025, 3, 1, 0, 0)] && recap.peakMonthMs == 3000000,
          "recap: the peak hour (21h) and month (March)");
    NSArray *cards = @[@(SGRecapCardTotal), @(SGRecapCardArtists), @(SGRecapCardSongs), @(SGRecapCardDiscoveries), @(SGRecapCardDays), @(SGRecapCardPeak)];
    CHECK([recap.cards isEqualToArray:cards], "recap: the album card is dropped, the others kept in order");

    CHECK(!SGRecapAnnouncedYear(date(@"2025-12-31T12:00:00-05:00"), ny), "announcement: not on 31 December");
    CHECK(spans(SGRecapAnnouncedYear(date(@"2026-01-01T00:00:00-05:00"), ny), @"2025-01-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00"),
          "announcement: 1 January announces the year just ended");
    CHECK(SGRecapAnnouncedYear(date(@"2026-01-14T23:59:59-05:00"), ny) != nil, "announcement: still on 14 January");
    CHECK(!SGRecapAnnouncedYear(date(@"2026-01-15T00:00:00-05:00"), ny), "announcement: over on 15 January");
    CHECK(SGRecapAnnouncementFrom(0) == SGRecapAnnounceOnLaunch && SGRecapAnnouncementFrom(2) == SGRecapAnnounceOff &&
          SGRecapAnnouncementFrom(3) == SGRecapAnnounceInSettings && SGRecapAnnouncementFrom(-1) == SGRecapAnnounceInSettings,
          "announcement: an invalid stored value reads as In Retrine Settings");

    // The announced year is stored as its number, so a move across time zones neither repeats nor skips it.
    NSCalendar *tokyo = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    tokyo.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Tokyo"];
    NSDate *tokyoJan2 = date(@"2026-01-02T12:00:00+09:00"), *nyJan2 = date(@"2026-01-02T12:00:00-05:00"), *nyJan15 = date(@"2026-01-15T00:00:00-05:00");
    NSDateInterval *tokyoEnded = SGRecapAnnouncedYear(tokyoJan2, tokyo), *nyEnded = SGRecapAnnouncedYear(nyJan2, ny);
    NSInteger marked = SGRecapYearNumber(tokyoEnded, tokyo);
    CHECK(marked == 2025 && SGRecapYearNumber(tokyoEnded, ny) == 2025 && SGRecapYearNumber(nyEnded, tokyo) == 2025 && [SGRecapYearTitle(nyEnded, ny) isEqualToString:@"2025"],
          "announcement: the year ended is 2025 in either time zone, written as plain digits");
    CHECK(!SGRecapUnannouncedYear(nyJan2, ny, SGRecapAnnounceInSettings, marked) && spans(SGRecapUnannouncedYear(nyJan2, ny, SGRecapAnnounceInSettings, 2024),
          @"2025-01-01T00:00:00-05:00", @"2026-01-01T00:00:00-05:00") && !SGRecapUnannouncedYear(nyJan2, ny, SGRecapAnnounceOff, 2024),
          "announcement: announced in Tokyo stays announced in New York; an earlier year marked does not count; Off announces nothing");
    // The launch prompt is checked again just before it shows.
    CHECK(SGRecapPromptDue(tokyoEnded, nyJan2, ny, SGRecapAnnounceOnLaunch, 2024), "prompt: due on 2 January with When Spotify opens, queued in another time zone");
    CHECK(!SGRecapPromptDue(nyEnded, nyJan2, ny, SGRecapAnnounceOnLaunch, 2025) && !SGRecapPromptDue(nyEnded, nyJan2, ny, SGRecapAnnounceInSettings, 2024) &&
          !SGRecapPromptDue(nyEnded, nyJan2, ny, SGRecapAnnounceOff, 2024) && !SGRecapPromptDue(nyEnded, nyJan15, ny, SGRecapAnnounceOnLaunch, 2024),
          "prompt: not once the year was announced, the preference changed from When Spotify opens, or the days are over");
}

static void localHistoryChecks(NSString *dir, NSArray<SGPlay *> *existing) {
    SGPlay *shortPlay = play(1700000001, 12500, @"짧은 곡 🎵", @"가수", @"");
    shortPlay.uri = @"spotify:local:short";
    NSArray *records = [existing arrayByAddingObject:shortPlay];
    NSError *error;
    NSData *data = SGHistoryJSON(records, &error);
    NSArray<SGPlay *> *decoded = SGPlaysFromExport(data);
    BOOL equal = data && !error && decoded.count == records.count;
    for (NSUInteger i = 0; equal && i < records.count; i++) {
        SGPlay *a = records[i], *b = decoded[i];
        equal = a.end == b.end && a.ms == b.ms && [a.uri isEqual:b.uri] && [a.title isEqual:b.title] &&
                [a.artist isEqual:b.artist] && [a.album isEqual:b.album];
    }
    CHECK(equal && decoded.lastObject.ms == 12500, "Retrine JSON: all six fields round-trip, including Unicode and counted short tracks");
    SGPlay *escaped = play(1700000002, 1000, @"Tab\tquote\"newline\n", @"Artist", @"Album");
    CHECK([SGPlaysFromExport(SGHistoryJSON(@[escaped], nil)).firstObject.title isEqual:escaped.title], "Retrine JSON: escaped text round-trips");
    CHECK(SGPlaysFromExport(SGHistoryJSON(@[], nil)).count == 0, "Retrine JSON: empty versioned history is recognized");
    SGPlay *nearA = play(1700000100, 40000, @"Repeat", @"Artist", @"Album");
    SGPlay *nearB = play(1700000160, 41000, @"Repeat", @"Artist", @"Album");
    NSArray *nearby = SGPlaysFromExport(SGHistoryJSON(@[nearA, nearB], nil));
    SGPlayLog *nearLog = [[SGPlayLog alloc] initWithPath:[dir stringByAppendingPathComponent:@"nearby.tsv"]];
    CHECK([nearLog merge:nearby] == 2 && [nearLog merge:nearby] == 0 && nearLog.plays.count == 2,
          "Retrine JSON: distinct plays 60 seconds apart both restore, while an exact second import adds nothing");
    NSString *path = [dir stringByAppendingPathComponent:@"local-roundtrip.tsv"];
    SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
    CHECK([log merge:decoded] == records.count && [log merge:decoded] == 0, "Retrine JSON: merge once, duplicate import adds nothing");
    NSData *before = [NSData dataWithContentsOfFile:path];
    [log merge:@[play(1900000000, 40000, @"Another", @"Artist", @"Album")]];
    NSData *after = [NSData dataWithContentsOfFile:path];
    CHECK(after.length > before.length && [[after subdataWithRange:NSMakeRange(0, before.length)] isEqual:before], "TSV: importing appends without rewriting any existing byte");
    SGPlayLog *reopened = openLog(path);
    CHECK(reopened.plays.count == records.count + 1 && reopened.plays[records.count - 1].ms == 12500, "TSV: imported local short play persists after reload");
    NSMutableDictionary *root = [[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] mutableCopy];
    CHECK([root[@"format"] isEqual:@"retrine.listening-history"], "new listening history export format");
    root[@"format"] = @"vitrine.listening-history";
    CHECK(SGPlaysFromExport(json(root)).count == records.count, "legacy listening history still imports");
    root[@"version"] = @2;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: unknown version rejected");
    root[@"version"] = @YES;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: boolean version rejected");
    root[@"version"] = @1; root[@"format"] = @"other.history";
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: unknown format rejected");
    root[@"format"] = @"retrine.listening-history";
    NSMutableDictionary *row = [root[@"plays"][0] mutableCopy];
    for (id bad in @[@"123", @YES, @(-1), @1.5, NSNull.null, @(INT64_MAX), @18446744073709551615ULL]) {
        row[@"ms"] = bad; root[@"plays"] = @[row];
        CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: malformed milliseconds rejected (%s)", [[bad description] UTF8String]);
    }
    row[@"ms"] = @40000; row[@"title"] = NSNull.null;
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: malformed text rejects whole file");
    root[@"plays"] = @[@1];
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: non-object row rejected");
    [root removeObjectForKey:@"plays"];
    CHECK(SGPlaysFromExport(json(root)) == nil, "Retrine JSON: missing plays rejected");

    NSString *folder = [dir stringByAppendingPathComponent:@"selected"];
    NSString *nested = [folder stringByAppendingPathComponent:@"nested"];
    [NSFileManager.defaultManager createDirectoryAtPath:nested withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:[nested stringByAppendingPathComponent:@"history.json"] atomically:YES];
    [data writeToFile:[folder stringByAppendingPathComponent:@".hidden.json"] atomically:YES];
    [data writeToFile:[folder stringByAppendingPathComponent:@"ignore.txt"] atomically:YES];
    [@"invalid" writeToFile:[folder stringByAppendingPathComponent:@"bad.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *outside = [dir stringByAppendingPathComponent:@"outside.json"];
    [data writeToFile:outside atomically:YES];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[folder stringByAppendingPathComponent:@"escape.json"] withDestinationPath:outside error:nil];
    [NSFileManager.defaultManager createSymbolicLinkAtPath:[folder stringByAppendingPathComponent:@"escape-folder"] withDestinationPath:dir error:nil];
    NSString *deep = folder;
    for (NSUInteger i = 0; i < 9; i++) deep = [deep stringByAppendingPathComponent:@"deeper"];
    [NSFileManager.defaultManager createDirectoryAtPath:deep withIntermediateDirectories:YES attributes:nil error:nil];
    [data writeToFile:[deep stringByAppendingPathComponent:@"too-deep.json"] atomically:YES];
    NSString *large = [folder stringByAppendingPathComponent:@"too-large.json"];
    [NSFileManager.defaultManager createFileAtPath:large contents:nil attributes:nil];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:large];
    [handle truncateAtOffset:65 * 1024 * 1024 error:nil]; [handle closeAndReturnError:nil];
    SGHistoryImport *import = SGReadHistoryURLs(@[[NSURL fileURLWithPath:folder]]);
    CHECK(import.files == 1 && import.plays.count == records.count && import.skipped >= 4,
          "folder: nested JSON only, hidden/irrelevant/symlink/oversized/deep/malformed entries excluded (%lu files, %lu skips)",
          (unsigned long)import.files, (unsigned long)import.skipped);
    import = SGReadHistoryURLs(@[[NSURL fileURLWithPath:[folder stringByAppendingPathComponent:@"escape.json"]]]);
    CHECK(import.files == 0 && import.skipped == 1, "folder: explicitly selected symlink is refused");

    SGPlayLog *asyncLog = [[SGPlayLog alloc] initWithPath:path];
    __block NSUInteger completions = 0;
    [asyncLog loadWithCompletion:^{ completions++; }];
    [asyncLog loadWithCompletion:^{ completions++; }];
    [asyncLog record:play(1900000500, 10000, @"During load", @"Recorder", @"")];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (completions < 2 && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(!writesAndWait(asyncLog), "recording during initial load is acknowledged independently");
    CHECK(completions == 2 && asyncLog.plays.count == records.count + 2 && [asyncLog.plays.lastObject.title isEqual:@"During load"],
          "async TSV load: both callbacks complete, concurrent recording included exactly once");
    CHECK(openLog(path).plays.count == asyncLog.plays.count, "async TSV load: memory and append-only file agree");
    SGPlayLog *erasedDuringLoad = [[SGPlayLog alloc] initWithPath:path];
    __block BOOL done = NO;
    [erasedDuringLoad loadWithCompletion:^{ done = YES; }];
    [erasedDuringLoad erase];
    [erasedDuringLoad record:play(1900000600, 20000, @"After erase", @"Recorder", @"")];
    deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(!writesAndWait(erasedDuringLoad), "erase and subsequent recording finish in order");
    CHECK(done && erasedDuringLoad.plays.count == 1 && [erasedDuringLoad.plays.firstObject.title isEqual:@"After erase"],
          "async TSV load: erase during loading cannot resurrect old records");
    NSString *corruptPath = [dir stringByAppendingPathComponent:@"corrupt.tsv"];
    uint8_t invalidUTF8[] = {0xff, 0xff};
    [[NSData dataWithBytes:invalidUTF8 length:2] writeToFile:corruptPath atomically:YES];
    SGPlayLog *corrupt = [[SGPlayLog alloc] initWithPath:corruptPath];
    done = NO;
    [corrupt loadWithCompletion:^{ done = YES; }];
    deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    CHECK(done && corrupt.loadError != nil, "async TSV load: corrupt encoding is an explicit error, not empty history");
}

static void persistenceChecks(NSString *dir) {
    NSString *path = [dir stringByAppendingPathComponent:@"transaction.tsv"];
    SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
    [log record:play(1000, 35000, @"Original", @"Artist", @"")];
    [log merge:@[]]; // fold the committed journal before checking the canonical TSV bytes
    NSData *before = [NSData dataWithContentsOfFile:path];
    CHECK(log.plays.count == 1, "record is committed before becoming visible");

    struct rlimit saved;
    CHECK(getrlimit(RLIMIT_FSIZE, &saved) == 0, "read file-size limit for failed-write fixture");
    struct rlimit limited = saved;
    limited.rlim_cur = before.length + 12;
    void (*handler)(int) = signal(SIGXFSZ, SIG_IGN);
    CHECK(setrlimit(RLIMIT_FSIZE, &limited) == 0, "limit staged writes to provoke a real short write");
    SGPlay *incoming = play(2000, 45000, @"This record cannot fit inside the file limit", @"Artist", @"");
    NSError *error;
    NSUInteger added = mergeAndWait(log, @[incoming], &error);
    [log record:incoming];
    CHECK(writesAndWait(log) != nil, "failed recorder write is reported through its acknowledgement");
    CHECK(added == 0 && error && log.plays.count == 1 &&
          [[NSData dataWithContentsOfFile:path] isEqual:before],
          "failed import and recorder writes publish nothing and leave no truncated record");
    CHECK(setrlimit(RLIMIT_FSIZE, &saved) == 0, "restore file-size limit");
    signal(SIGXFSZ, handler);
    CHECK([log merge:@[incoming]] == 1, "a failed addition remains eligible for a later successful import");

    SGPlayLog *indexed = [[SGPlayLog alloc] initWithPath:[dir stringByAppendingPathComponent:@"indexed.tsv"]];
    NSMutableArray *repeats = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10000; i++)
        [repeats addObject:play(1000000 + i * 300, 180000, @"Repeat", @"Artist", @"")];
    __block BOOL done = NO;
    [indexed merge:repeats completion:^(NSUInteger count, NSError *failure) {
        CHECK(count == 10000 && !failure, "indexed import retains ten thousand distinct repeated-track plays");
        done = YES;
    }];
    [indexed record:play(5000000, 30000, @"Concurrent", @"Recorder", @"")];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(!writesAndWait(indexed), "concurrent recorder write finishes without waiting for import completion");
    CHECK(done && indexed.plays.count == 10001 &&
          openLog([dir stringByAppendingPathComponent:@"indexed.tsv"]).plays.count == 10001,
          "recording during bulk import survives exactly once in memory and on disk");
    CHECK(([indexed merge:@[play(1000090, 30000, @"Repeat", @"Artist", @""),
                            play(1000091, 30000, @"Repeat", @"Artist", @""),
                            play(999910, 30000, @"Repeat", @"Artist", @""),
                            play(999909, 30000, @"Repeat", @"Artist", @"")]] == 2),
          "indexed matching keeps the inclusive 90-second boundary on either side");
}

static void recorderClockChecks(void) {
    SGPlayClock *clock = [SGPlayClock new];
    [clock setPlaying:YES elapsed:1000 at:1000];
    [clock setPlaying:NO elapsed:1035 at:1035];
    [clock setPlaying:NO elapsed:86400 at:86400];
    CHECK(clock.listenedSeconds == 35 && clock.endedAt == 1035,
          "a paused play ends at its last listened instant, not the next day's track switch");
    [clock setPlaying:YES elapsed:86400 at:86400];
    [clock setPlaying:NO elapsed:86410 at:86410];
    [clock setPlaying:NO elapsed:90000 at:90000];
    CHECK(clock.listenedSeconds == 45 && clock.endedAt == 86410,
          "resuming adds only the new playing interval and preserves its end through termination");
    SGPlayClock *backward = [SGPlayClock new];
    [backward setPlaying:YES elapsed:100 at:10000];
    [backward setPlaying:NO elapsed:130 at:6430]; // calendar moved back an hour
    [backward setPlaying:YES elapsed:190 at:6490]; // a minute paused
    [backward setPlaying:NO elapsed:220 at:6520];
    [backward setPlaying:NO elapsed:999 at:20000];
    CHECK(backward.listenedSeconds == 60 && backward.endedAt == 6520,
          "a backward calendar jump and pause preserve sixty seconds of listening and its last end date");
    SGPlayClock *forward = [SGPlayClock new];
    [forward setPlaying:YES elapsed:500 at:10000];
    [forward setPlaying:NO elapsed:560 at:13660]; // calendar moved forward an hour
    CHECK(forward.listenedSeconds == 60 && forward.endedAt == 13660,
          "a forward calendar jump does not add an hour to a sixty-second play");
}

// An import blocked while serializing its staged row. Neither the main-thread recorder nor
// snapshot getters may depend on this worker returning. Each probe runs in a separate process.
static dispatch_semaphore_t importEntered;
@interface SGBlockedImportPlay : SGPlay
@end
@implementation SGBlockedImportPlay
- (NSString *)uri {
    dispatch_semaphore_signal(importEntered);
    dispatch_semaphore_t never = dispatch_semaphore_create(0);
    dispatch_semaphore_wait(never, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    fprintf(stderr, "blocked import probe exceeded its lifetime\n");
    _exit(91);
}
@end

static void interruptedImport(NSString *path, NSString *mode) {
    BOOL erase = [mode isEqual:@"erase"];
    SGPlayLog *log = openLog(path);
    importEntered = dispatch_semaphore_create(0);
    SGPlay *blocked = [SGBlockedImportPlay new];
    blocked.end = 2000; blocked.ms = 30000;
    blocked.title = @"Uncommitted import"; blocked.artist = @"Artist"; blocked.album = @"";
    [log merge:@[blocked] completion:^(NSUInteger added, NSError *error) { _exit(92); }];
    if (dispatch_semaphore_wait(importEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) _exit(93);
    if ([mode isEqual:@"terminate"]) {
        syncEntered = dispatch_semaphore_create(0);
        releaseSync = dispatch_semaphore_create(0);
        atomic_store(&stallNextSync, true);
        [log record:play(3000, 30000, @"Queued first", @"Artist", @"")];
        if (dispatch_semaphore_wait(syncEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC))) _exit(99);
        [log record:play(4000, 30000, @"Final at termination", @"Artist", @"")];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 10), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            dispatch_semaphore_signal(releaseSync);
        });
        if (![log drainForTermination]) _exit(100);
        _exit(0); // no main-loop callback can acknowledge or finish the final record for us
    }
    [log record:play(3000, 30000, @"Recorded one", @"Artist", @"")];
    [log record:play(4000, 30000, @"Recorded two", @"Artist", @"")];
    if (writesAndWait(log)) _exit(97);
    // These getters previously waited on the blocked queue. The parent enforces a bounded lifetime.
    if (log.loadError || log.plays.count != 3) _exit(94);
    if (erase) {
        [log erase];
        if (log.loadError || log.plays.count) _exit(95);
        [log record:play(5000, 30000, @"After erase", @"Artist", @"")];
        if (writesAndWait(log)) _exit(98);
        if (log.loadError || log.plays.count != 1) _exit(96);
    }
    // No termination callback, bulk queue drain, or deallocation: acknowledged recorder writes survive.
    _exit(0);
}

static void slowRecorderChecks(NSString *dir) {
    for (NSNumber *erasing in @[@NO, @YES]) {
        NSString *path = [dir stringByAppendingPathComponent:erasing.boolValue ? @"slow-erase.tsv" : @"rapid.tsv"];
        SGPlayLog *log = openLog(path);
        syncEntered = dispatch_semaphore_create(0);
        releaseSync = dispatch_semaphore_create(0);
        atomic_store(&stalledSyncTimedOut, false);
        atomic_store(&stallNextSync, true);
        [log record:play(100, 30000, @"First", @"Artist", @"")];
        CHECK(!atomic_load(&stalledSyncTimedOut), "record returns while its fsync is still blocked");
        CHECK(!dispatch_semaphore_wait(syncEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
              "slow-write probe reached the real persistence boundary");
        [log record:play(200, 30000, @"Second", @"Artist", @"")];
        [log record:play(300, 30000, @"Third", @"Artist", @"")];
        CHECK(log.plays.count == 0 && !log.loadError, "snapshot/error readers stay responsive and do not publish uncommitted plays");
        if (!erasing.boolValue)
            CHECK(![log drainForTermination] && !atomic_load(&stalledSyncTimedOut),
                  "termination drain times out without waiting indefinitely on a stalled recorder");
        if (erasing.boolValue) {
            [log erase];
            CHECK(!atomic_load(&stalledSyncTimedOut), "erase returns without waiting for a pending fsync");
            [log record:play(400, 30000, @"Survivor", @"Artist", @"")];
        }
        dispatch_semaphore_signal(releaseSync);
        CHECK(!writesAndWait(log), "pending-write completion acknowledges durable writes and erase in order");
        SGPlayLog *recovered = openLog(path);
        NSArray *expected = erasing.boolValue ? @[@"Survivor"] : @[@"First", @"Second", @"Third"];
        CHECK(!recovered.loadError && [[recovered.plays valueForKey:@"title"] isEqual:expected],
              "rapid records recover in order; erase during a pending write cannot resurrect older plays");
    }
}

static void eraseGenerationChecks(NSString *dir) {
    Method removeMethod = class_getInstanceMethod(NSFileManager.class, @selector(removeItemAtPath:error:));
    originalRemoveItem = (void *)method_setImplementation(removeMethod, (IMP)removeRaceItem);
    NSString *path = [dir stringByAppendingPathComponent:@"erase-generation.tsv"];
    [@"10\t30000\t\tErased\tArtist\t\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    eraseRacePath = path;
    barrierEntered = dispatch_semaphore_create(0);
    releaseBarrier = dispatch_semaphore_create(0);
    canonicalRead = dispatch_semaphore_create(0);
    atomic_store(&pauseNextBarrier, true);
    SGPlayLog *log = [[SGPlayLog alloc] initWithPath:path];
    CHECK(!dispatch_semaphore_wait(barrierEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
          "initial load is concurrent with a queued erase");
    [log erase];
    dispatch_semaphore_signal(releaseBarrier);
    CHECK(!writesAndWait(log), "concurrent erase is acknowledged");
    [log merge:@[]]; // complete outstanding bulk reads without adding any new history
    CHECK(!log.loadError && log.plays.count == 0,
          "a load of pre-erase bytes cannot restore history after an acknowledged erase");
    eraseRacePath = nil;
    method_setImplementation(removeMethod, (IMP)originalRemoveItem);
}

static void recorderRecoveryChecks(NSString *dir) {
    NSString *path = [dir stringByAppendingPathComponent:@"transient-write.tsv"];
    SGPlayLog *log = openLog(path);
    atomic_store(&failNextSync, true);
    [log record:play(100, 30000, @"Failed", @"Artist", @"")];
    CHECK(writesAndWait(log) != nil && !log.loadError,
          "recorder failure is acknowledged separately from the readable history's load status");
    [log record:play(200, 30000, @"Recovered", @"Artist", @"")];
    CHECK(!writesAndWait(log) && !log.loadError,
          "a later successful record clears transient writer failure without erase or restart");
    loadAndWait(log);
    CHECK(!log.loadError && ([[openLog(path).plays valueForKey:@"title"] isEqual:@[@"Recovered"]]),
          "non-destructive recovery persists only the successful record");
}

static void reviewPersistenceChecks(NSString *dir) {
    slowRecorderChecks(dir);
    eraseGenerationChecks(dir);
    recorderRecoveryChecks(dir);
    NSString *legacy = @"500\t30000\t\tLegacy\tArtist\t\n";
    for (NSString *mode in @[@"keep", @"erase", @"terminate"]) {
        BOOL erase = [mode isEqual:@"erase"];
        NSString *path = [dir stringByAppendingPathComponent:[mode stringByAppendingString:@".tsv"]];
        CHECK([legacy writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil], "prepare unchanged six-column legacy history");
        NSString *abandoned = [path stringByAppendingString:@".11111111-1111-4111-8111-111111111111"];
        [legacy writeToFile:abandoned atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *unrelated = [path stringByAppendingString:@".notes"];
        [@"not owned by the writer" writeToFile:unrelated atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSTask *child = [NSTask new];
        child.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments[0]];
        child.arguments = @[@"--interrupted-import", path, mode];
        NSError *error;
        BOOL launched = [child launchAndReturnError:&error];
        CHECK(launched, "launch interrupted-import probe");
        if (!launched) continue;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (child.running) [child terminate];
        });
        [child waitUntilExit];
        CHECK(child.terminationStatus == 0, "record and snapshot/error reads complete while the import disk queue is blocked");
        if (child.terminationStatus != 0) continue;
        if (!erase) {
            NSFileHandle *tail = [NSFileHandle fileHandleForWritingAtPath:[path stringByAppendingString:@".journal"]];
            [tail seekToEndOfFile];
            [tail writeData:[@"incomplete final row" dataUsingEncoding:NSUTF8StringEncoding]];
            [tail closeFile];
        }
        SGPlayLog *recovered = openLog(path);
        NSArray *expected = erase ? @[@"After erase"] : [mode isEqual:@"terminate"] ?
            @[@"Legacy", @"Queued first", @"Final at termination"] : @[@"Legacy", @"Recorded one", @"Recorded two"];
        CHECK(!recovered.loadError && [[recovered.plays valueForKey:@"title"] isEqual:expected],
              "process restart preserves committed recorder order, drops partial imports/tails, and respects erase");
        NSArray *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:dir error:nil];
        NSPredicate *owned = [NSPredicate predicateWithBlock:^BOOL(NSString *name, NSDictionary *bindings) {
            return [name hasPrefix:[path.lastPathComponent stringByAppendingString:@"."]] && ![name hasSuffix:@".notes"];
        }];
        CHECK([names filteredArrayUsingPredicate:owned].count == 0 &&
              [NSFileManager.defaultManager fileExistsAtPath:unrelated],
              "startup reclaims writer stages/journals, preserving unrelated sibling files");
        [recovered record:play(6000, 30000, @"Erase this journal", @"Artist", @"")];
        [legacy writeToFile:abandoned atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [recovered erase];
        CHECK(!writesAndWait(recovered), "erase acknowledges removal of writer-owned files");
        CHECK(!recovered.loadError && openLog(path).plays.count == 0 &&
              ![NSFileManager.defaultManager fileExistsAtPath:abandoned] &&
              ![NSFileManager.defaultManager fileExistsAtPath:[path stringByAppendingString:@".journal"]],
              "erase removes canonical history, unmerged records and abandoned clones");
    }
    // A crash after commit but before segment deletion must not duplicate a journal row.
    NSString *path = [dir stringByAppendingPathComponent:@"committed.tsv"];
    NSString *row = @"10\t30000\t\tOnce\tArtist\t\t22222222-2222-4222-8222-222222222222\n";
    [row writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [row writeToFile:[path stringByAppendingString:@".journal.00000000000000000001"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    SGPlayLog *once = openLog(path);
    CHECK(!once.loadError && once.plays.count == 1 && [once.plays.firstObject.title isEqual:@"Once"],
          "journal recovery is exactly-once across canonical commit and segment cleanup");
    for (NSNumber *incomplete in @[@NO, @YES]) {
        NSString *brokenPath = [dir stringByAppendingPathComponent:incomplete.boolValue ? @"broken-tail.tsv" : @"no-newline.tsv"];
        NSString *canonical = incomplete.boolValue ? [legacy stringByAppendingString:@"123\tunfinished"]
                                                   : [legacy substringToIndex:legacy.length - 1];
        [canonical writeToFile:brokenPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSString *journal = [brokenPath stringByAppendingString:@".journal"];
        [row writeToFile:journal atomically:YES encoding:NSUTF8StringEncoding error:nil];
        SGPlayLog *folded = openLog(brokenPath);
        SGPlayLog *reopened = openLog(brokenPath);
        NSArray *expected = @[@"Legacy", @"Once"];
        CHECK(!folded.loadError && !reopened.loadError &&
              [[folded.plays valueForKey:@"title"] isEqual:expected] &&
              [[reopened.plays valueForKey:@"title"] isEqual:expected],
              "unterminated legacy tail cannot absorb a journal play during a durable fold");
    }
    NSString *tailPath = [dir stringByAppendingPathComponent:@"startup-tail.tsv"];
    [[row stringByAppendingString:@"unfinished"] writeToFile:[tailPath stringByAppendingString:@".journal"]
                                                atomically:YES encoding:NSUTF8StringEncoding error:nil];
    SGPlayLog *early = [[SGPlayLog alloc] initWithPath:tailPath];
    [early record:play(20, 30000, @"Before initial load", @"Artist", @"")];
    loadAndWait(early);
    CHECK(!early.loadError && ([[early.plays valueForKey:@"title"] isEqual:@[@"Once", @"Before initial load"]]) &&
          openLog(tailPath).plays.count == 2,
          "recording before startup finishes cannot append into a previous process's partial row");
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 4 && !strcmp(argv[1], "--interrupted-import"))
            interruptedImport(@(argv[2]), @(argv[3]));
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *exportDir = [dir stringByAppendingPathComponent:@"export"];
        [NSFileManager.defaultManager createDirectoryAtPath:[exportDir stringByAppendingPathComponent:@"__MACOSX"] withIntermediateDirectories:YES attributes:nil error:nil];
        if (argc == 2 && !strcmp(argv[1], "--persistence-review")) {
            reviewPersistenceChecks(dir);
            [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
            return failures ? 1 : 0;
        }

        // A fixed "now" on a whole minute, so the basic export's minute stamps land exactly.
        snapshotChecks(dir);
        int64_t now = 1790000000 - 1790000000 % 60, day = 86400;

        // Extended: Song A twice and Song B 3 days ago, Song C 20 days ago, Song D 200 days ago, Song A
        // 2 years ago; then a podcast row (nulls), a 10 s skip and a row without a ts.
        NSArray *extended = @[
            extendedRow(now - 3 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 300, 180000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 3 * day + 600, 60000, @"Song B", @"Artist 2", @"Album Y"),
            extendedRow(now - 20 * day, 240000, @"Song C", @"Artist 1", @"Album Z"),
            extendedRow(now - 200 * day, 210000, @"Song D", @"Artist 3", @"Album W"),
            extendedRow(now - 730 * day, 200000, @"Song A", @"Artist 1", @"Album X"),
            extendedRow(now - 4 * day, 1800000, nil, nil, nil),
            extendedRow(now - 4 * day + 100, 10000, @"Song E", @"Artist 4", @"Album V"),
            @{@"ms_played": @50000, @"ts": NSNull.null},
        ];
        NSArray<SGPlay *> *ext = SGPlaysFromExport(json(extended));
        for (NSDictionary *override in @[@{@"ms_played": @(INT64_MAX)}, @{@"ts": @"10000-01-01T00:00:00Z"},
                                         @{@"master_metadata_album_album_name": [@"" stringByPaddingToLength:8192 withString:@"a" startingAtIndex:0]}]) {
            NSMutableDictionary *row = [extended.firstObject mutableCopy];
            [row addEntriesFromDictionary:override];
            CHECK(SGPlaysFromExport(json(@[row])).count == 0, "reject out-of-range Spotify field: %s",
                  [override.allKeys.firstObject UTF8String]);
        }
        CHECK(ext.count == 6, "extended: 6 music plays kept of 9 rows (podcast, skip, no ts out): %lu", (unsigned long)ext.count);
        CHECK(ext.firstObject.end == now - 3 * day, "extended: ts read as UTC to the second");
        CHECK([ext.firstObject.album isEqualToString:@"Album X"] && [ext.firstObject.uri isEqualToString:@"spotify:track:Song A"],
              "extended: album and URI read");

        // Basic: the same two Song A plays 20 s later than the extended ts (minute stamps and drift), a play
        // only the basic file has, a 5 s skip and a podcast-shaped row.
        NSArray *basic = @[
            basicRow(now - 3 * day + 20, 200000, @"Song A", @"Artist 1"),
            basicRow(now - 3 * day + 300 + 20, 180000, @"Song A", @"Artist 1"),
            basicRow(now - 1 * day, 100000, @"Song F", @"Artist 2"),
            basicRow(now - 1 * day + 400, 5000, @"Song F", @"Artist 2"),
            @{@"endTime": stamp(now, NO), @"podcastName": @"Pod", @"episodeName": @"Ep", @"msPlayed": @900000},
        ];
        NSArray<SGPlay *> *bas = SGPlaysFromExport(json(basic));
        CHECK(bas.count == 3, "basic: 3 music plays kept of 5 rows: %lu", (unsigned long)bas.count);
        CHECK(bas.firstObject.end == now - 3 * day, "basic: endTime read as UTC, to the minute");
        CHECK(SGPlaysFromExport(json(@[@{@"spotify": @"settings"}])) == nil, "a JSON array that is not an export is refused");
        CHECK(SGPlaysFromExport(json(@{@"settings": @{}})) == nil, "a JSON object is refused");
        CHECK(SGPlaysFromExport([@"not json" dataUsingEncoding:NSUTF8StringEncoding]) == nil, "not JSON is refused");

        // Zips as the export arrives, stored and deflated, with a PDF and a __MACOSX twin beside the JSON.
        [json(extended) writeToFile:[exportDir stringByAppendingPathComponent:@"Streaming_History_Audio_2023.json"] atomically:YES];
        [json(basic) writeToFile:[exportDir stringByAppendingPathComponent:@"StreamingHistory_music_0.json"] atomically:YES];
        [@"readme" writeToFile:[exportDir stringByAppendingPathComponent:@"ReadMeFirst.pdf"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [@"junk" writeToFile:[exportDir stringByAppendingPathComponent:@"__MACOSX/._StreamingHistory_music_0.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        NSArray *names = @[@"Streaming_History_Audio_2023.json", @"StreamingHistory_music_0.json", @"ReadMeFirst.pdf", @"__MACOSX/._StreamingHistory_music_0.json"];
        for (NSNumber *stored in @[@YES, @NO]) {
            NSString *path = [dir stringByAppendingPathComponent:stored.boolValue ? @"stored.zip" : @"deflated.zip"];
            zip(exportDir, path, names, stored.boolValue);
            SGHistoryImport *imported = SGReadHistoryURLs(@[[NSURL fileURLWithPath:path]]);
            CHECK(imported.files == 2 && !imported.skipped && imported.plays.count == 9,
                  "coordinated ZIP import keeps plays from both JSON entries");
            NSArray<NSData *> *files = SGJSONFilesInZip([NSData dataWithContentsOfFile:path]);
            NSUInteger plays = 0;
            for (NSData *file in files) plays += SGPlaysFromExport(file).count;
            CHECK(files.count == 2 && plays == 9, "%s zip: 2 JSON files, 9 plays: %lu files, %lu plays",
                  stored.boolValue ? "stored" : "deflated", (unsigned long)files.count, (unsigned long)plays);
        }
        CHECK(SGJSONFilesInZip(json(extended)).count == 0, "a file that is not a zip has no files in it");
        NSData *deflated = [NSData dataWithContentsOfFile:[dir stringByAppendingPathComponent:@"deflated.zip"]];
        CHECK(SGJSONFilesInZip([deflated subdataWithRange:NSMakeRange(0, deflated.length / 2)]).count == 0, "a cut-off zip reads as empty");
        for (NSNumber *declared in @[@1, @(65 * 1024 * 1024)]) {
            NSMutableData *forged = [deflated mutableCopy];
            uint8_t *bytes = forged.mutableBytes;
            for (NSUInteger i = 0; i + 46 <= forged.length; i++) {
                if (bytes[i] != 0x50 || bytes[i + 1] != 0x4b || bytes[i + 2] != 1 || bytes[i + 3] != 2) continue;
                uint32_t size = declared.unsignedIntValue;
                for (NSUInteger b = 0; b < 4; b++) bytes[i + 24 + b] = (uint8_t)(size >> (8 * b));
            }
            CHECK(SGJSONFilesInZip(forged).count == 0, "zip: understated/oversized expanded lengths rejected (%u)", declared.unsignedIntValue);
        }

        // The log: Song B recorded on the phone 30 s after the export's, then both files merged, twice.
        NSString *logPath = [dir stringByAppendingPathComponent:@"Retrine/plays.tsv"];
        SGPlayLog *log = [[SGPlayLog alloc] initWithPath:logPath];
        SGPlay *recorded = play(now - 3 * day + 630, 61000, @"Song B", @"Artist 2", @"Album Y");
        recorded.uri = @"spotify:track:b";
        [log record:recorded];
        NSUInteger added = [log merge:ext];
        CHECK(added == 5, "merge extended: 5 added, the recorded Song B already there: %lu", (unsigned long)added);
        added = [log merge:bas];
        CHECK(added == 1, "merge basic: only Song F is new: %lu", (unsigned long)added);
        added = [log merge:ext] + [log merge:bas];
        CHECK(added == 0, "importing the same files again adds nothing: %lu", (unsigned long)added);
        CHECK([log merge:@[play(now, 40000, @"Tab\there", @"New\nline", @"")]] == 1, "a title with a tab and an artist with a newline merge");

        SGPlayLog *reread = openLog(logPath);
        CHECK(reread.plays.count == 8, "the log reads back 8 plays: %lu", (unsigned long)reread.plays.count);
        SGPlay *last = reread.plays.lastObject;
        CHECK([last.title isEqualToString:@"Tab here"] && [last.artist isEqualToString:@"New line"], "tab and newline become spaces");
        CHECK([reread.plays.firstObject.uri isEqualToString:@"spotify:track:b"] && reread.plays.firstObject.ms == 61000, "the recorded play round-trips");

        // Periods from the fixed now. Week: Song A x2, Song B, Song F, Tab here. Month adds Song C, year
        // Song D, all time the old Song A.
        NSArray *plays = reread.plays;
        SGStats *week = SGStatsSince(plays, now - 7 * day, 10), *month = SGStatsSince(plays, now - 30 * day, 10);
        SGStats *year = SGStatsSince(plays, now - 365 * day, 10), *all = SGStatsSince(plays, 0, 10);
        CHECK(week.plays == 5 && month.plays == 6 && year.plays == 7 && all.plays == 8, "plays per period 5/6/7/8: %lu/%lu/%lu/%lu",
              (unsigned long)week.plays, (unsigned long)month.plays, (unsigned long)year.plays, (unsigned long)all.plays);
        CHECK(week.ms == 200000 + 180000 + 61000 + 100000 + 40000, "week: listening time adds up: %lld", week.ms);
        CHECK([week.tracks.firstObject.name isEqualToString:@"Song A"] && week.tracks.firstObject.plays == 2, "week: Song A tops the tracks with 2 plays");
        CHECK([week.artists[0].name isEqualToString:@"Artist 1"] && [week.artists[1].name isEqualToString:@"Artist 2"] && week.artists[1].plays == 2,
              "week: Artists 1 and 2 tie on 2 plays, and the one listened to longer leads");
        CHECK(all.tracks.firstObject.plays == 3 && [all.tracks.firstObject.name isEqualToString:@"Song A"], "all time: Song A x3");
        CHECK([all.artists.firstObject.name isEqualToString:@"Artist 1"] && all.artists.firstObject.plays == 4, "all time: Artist 1 x4");
        CHECK(all.albums.count == 4 && [all.albums.firstObject.name isEqualToString:@"Album X"], "all time: 4 albums (basic plays have none), Album X first");
        CHECK(SGStatsSince(plays, 0, 2).tracks.count == 2, "a top list is capped");

        CHECK(SGPlayCounts(30, 300) && !SGPlayCounts(29, 300) && SGPlayCounts(20, 40) && !SGPlayCounts(19, 40) && !SGPlayCounts(10, 0),
              "a play counts past 30 s or half the track");

        calendarChecks();
        periodChecks();
        chartChecks();
        recapChecks();
        localHistoryChecks(dir, reread.plays);
        persistenceChecks(dir);
        recorderClockChecks();
        reviewPersistenceChecks(dir);

        // An export's size: 100k extended rows.
        NSMutableArray *big = [NSMutableArray arrayWithCapacity:100000];
        for (int i = 0; i < 100000; i++) {
            [big addObject:extendedRow(now - i * 200, 120000, [NSString stringWithFormat:@"Track %d", i % 3000],
                                       [NSString stringWithFormat:@"Artist %d", i % 400], [NSString stringWithFormat:@"Album %d", i % 900])];
        }
        NSData *bigData = json(big);
        NSString *bigPath = [dir stringByAppendingPathComponent:@"big.tsv"];
        NSDate *start = [NSDate date];
        NSArray *bigPlays = SGPlaysFromExport(bigData);
        double parse = since(start);
        SGPlayLog *bigLog = [[SGPlayLog alloc] initWithPath:bigPath];
        start = [NSDate date];
        NSUInteger bigAdded = [bigLog merge:bigPlays];
        double merge = since(start);
        start = [NSDate date];
        NSUInteger again = [bigLog merge:bigPlays];
        double remerge = since(start);
        start = [NSDate date];
        SGPlayLog *bigReread = openLog(bigPath);
        NSUInteger readBack = bigReread.plays.count;
        double load = since(start);
        start = [NSDate date];
        SGStatsSince(bigReread.plays, 0, 10);
        double stats = since(start);
        start = [NSDate date];
        SGListeningStreaks *largeStreak = SGStreaks(bigReread.plays, [NSDate dateWithTimeIntervalSince1970:now], NSCalendar.currentCalendar);
        NSArray<SGStatEntry *> *largeHours = SGHourlyStats(bigReread.plays, 0, NSCalendar.currentCalendar);
        NSUInteger hourlyPlays = 0;
        for (SGStatEntry *hour in largeHours) hourlyPlays += hour.plays;
        double calendar = since(start);
        CHECK(bigAdded == 100000 && again == 0 && readBack == 100000, "100k rows: all added, none twice, all read back");
        CHECK(largeStreak.best > 200 && hourlyPlays == 100000, "100k rows: calendar aggregations retain every play");
        printf("      100k rows (%.1f MB JSON): parse %.0f ms, merge %.0f ms, merge again %.0f ms, load %.0f ms, add up %.0f ms\n",
               bigData.length / 1e6, parse, merge, remerge, load, stats);
        printf("      100k rows: streaks + hourly buckets %.0f ms\n", calendar);

        printf(failures ? "\n%d FAILED\n" : "\nall passed\n", failures);
        [NSFileManager.defaultManager removeItemAtPath:dir error:nil];
        return failures ? 1 : 0;
    }
}
