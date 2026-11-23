// Checks LocalLyrics.m as the tweak compiles it: a lyrics file imported (the refusals, the name kept, a
// taken name numbered), read by its content into lines (TTML, LRC with several stamps on a line, the
// fraction's forms and the offset, plain text), linked to a local file and matched by title and artist,
// folded, with the sides of an "Artist - Title" name worked out from the track. Runs in its own home, so
// nothing of the Mac's is touched. Exits non-zero on the first wrong answer.
#import <UIKit/UIKit.h>
#import "Shared/LocalFiles/LocalFiles.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LocalFiles/LyricRetirement.h"
#import "import.h"
#import <objc/runtime.h>
#include <spawn.h>
#include <stdatomic.h>
#include <unistd.h>
extern char **environ;

#import "../harness-fail.h"
#define CHECK(cond) HARNESS_CHECK(cond)

// What LyricsSources.m and KaraokeSource.x give the tweak, here as little as the file needs.
@implementation SGLyricsResult
@end
@implementation SGLyricsQuery
@end
@implementation SGLyricsProvider
@end
static NSArray<NSString *> *sg_order;
static atomic_bool sg_requireWorker;
NSArray<NSString *> *SGLyricsOrder(void) { return sg_order ?: @[]; }
void SGLyricsSetOrder(NSArray<NSString *> *keys) { sg_order = keys; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) {
    SGLyricsProvider *provider = [SGLyricsProvider new];
    provider.key = key;
    return provider;
}
// Holds the parse of the lyrics whose first line is "Slow A" until the check releases it.
static atomic_bool sg_holdSlow;
static dispatch_semaphore_t sg_slowEntered, sg_slowRelease;
void SGLyricsPageLines(NSArray<SGKaraokeLine *> *lines, NSArray<NSNumber *> **starts, NSArray<NSString *> **texts) {
    if (atomic_load(&sg_requireWorker)) CHECK(!NSThread.isMainThread);
    if (lines.count && [SGKaraokeLineText(lines.firstObject) isEqual:@"Slow A"] && atomic_exchange(&sg_holdSlow, false)) {
        dispatch_semaphore_signal(sg_slowEntered);
        CHECK(dispatch_semaphore_wait(sg_slowRelease, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) == 0);
    }
    NSMutableArray *at = [NSMutableArray array], *said = [NSMutableArray array];
    for (SGKaraokeLine *line in lines) {
        [at addObject:@(line.start)];
        [said addObject:SGKaraokeLineText(line)];
    }
    *starts = at;
    *texts = said;
}
SPTPlayerTrack *SGKaraokeTrackFor(NSString *trackID) { return nil; }
// SGTTML.m reads it for a translation in the language the Lyrics page asks for; this fixture has no page.
NSString *SGLyricsTranslationLanguage(void) { return nil; }
// The name a paste is kept under; this fixture has no settings bundle.
NSString *SGL(NSString *key, NSString *english) { return english; }

static NSURL *temporaryDirectory;
static NSURL *fileNamed(NSString *name, NSData *data) {
    NSURL *url = [temporaryDirectory URLByAppendingPathComponent:name];
    [data writeToURL:url atomically:YES];
    return url;
}

static NSURL *lrc(NSString *name, NSString *text) {
    return fileNamed(name, [text dataUsingEncoding:NSUTF8StringEncoding]);
}

// Hold a real file read after it obtained the old bytes, while main deletes/reimports its name.
static void invalidationCheck(BOOL asynchronous) {
    NSString *uri = @"spotify:local:Race:Album:Track:120";
    NSURL *source = lrc(@"race.lrc", @"[00:01]Old lyrics");
    CHECK(importLRC(source, uri, nil));
    dispatch_semaphore_t read = dispatch_semaphore_create(0), resume = dispatch_semaphore_create(0), finished = dispatch_semaphore_create(0);
    SEL selector = @selector(stringWithContentsOfFile:encoding:error:);
    Method method = class_getClassMethod(NSString.class, selector);
    IMP original = method_getImplementation(method);
    static atomic_bool intercept;
    atomic_store(&intercept, true);
    IMP blocked = imp_implementationWithBlock(^id(id receiver, NSString *path, NSStringEncoding encoding, NSError **error) {
        if (asynchronous) CHECK(!NSThread.isMainThread);
        id text = ((id (*)(id, SEL, id, NSStringEncoding, NSError **))original)(receiver, selector, path, encoding, error);
        if ([path.lastPathComponent isEqual:@"race.lrc"] && !NSThread.isMainThread && atomic_exchange(&intercept, false)) {
            dispatch_semaphore_signal(read);
            if (dispatch_semaphore_wait(resume, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC))) {
                fprintf(stderr, "cache read barrier timed out\n"); exit(1);
            }
        }
        return text;
    });
    method_setImplementation(method, blocked);
    __block SGLyricsResult *stale;
    __block BOOL delivered = NO;
    if (asynchronous) {
        SGImportedLRCFetch(uri, @"Track", @"Race", ^(SGLyricsResult *result) {
            CHECK(NSThread.isMainThread);
            stale = result; delivered = YES;
        });
        CHECK(!delivered);
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            stale = SGImportedLRCFor(uri, @"Track", @"Race");
            dispatch_semaphore_signal(finished);
        });
    }
    CHECK(dispatch_semaphore_wait(read, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    CHECK(deleteLRC(@"race.lrc"));
    CHECK([importLRC(lrc(@"race.lrc", @"[00:01]Replacement lyrics"), uri, nil) isEqual:@"race.lrc"]);
    dispatch_semaphore_signal(resume);
    if (asynchronous) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!delivered && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        CHECK(delivered && [stale.texts.firstObject isEqual:@"Replacement lyrics"]);
    } else {
        CHECK(dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        CHECK(!stale);
    }
    method_setImplementation(method, original);
    imp_removeBlock(blocked);
    CHECK([SGImportedLRCFor(uri, @"Track", @"Race").texts.firstObject isEqual:@"Replacement lyrics"]);
    CHECK(deleteLRC(@"race.lrc"));
}

static SGLyricsResult *asyncLyrics(NSString *track, NSString *title) {
    __block BOOL done = NO;
    __block SGLyricsResult *answer;
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = track; query.title = title; query.artist = @"Cache";
    SGImportedLRCAsk(query, ^(SGLyricsResult *result) {
        CHECK(NSThread.isMainThread); answer = result; done = YES;
    });
    CHECK(!done);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(done);
    return answer;
}

// A second launch of the same binary over the same home: the links and the retired list as the defaults
// on disk hold them, with none of this process's caches. It reports nothing itself; its own launch step
// has run by the time it exits, which is what the caller compares the folder against.
static void freshLaunch(void) {
    const char *executable = NSProcessInfo.processInfo.arguments.firstObject.fileSystemRepresentation;
    char *args[] = {(char *)executable, (char *)"fresh-launch", NULL};
    pid_t child;
    CHECK(posix_spawn(&child, executable, NULL, NULL, args, environ) == 0);
    int status;
    CHECK(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

static NSString *lyricsPath(NSString *name) {
    return [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
             stringByAppendingPathComponent:@"Retrine/Lyrics"] stringByAppendingPathComponent:name];
}

// A fresh launch, then the lyrics folder and the retired list as that launch leaves them.
static NSArray<NSString *> *freshFolder(void) {
    freshLaunch();
    return SGImportedLRCFiles();
}

static NSArray<NSString *> *retiredNames(void) {
    return [[NSUserDefaults.standardUserDefaults arrayForKey:SGKeyRetiredImportedLyrics] valueForKey:@"name"] ?: @[];
}

// Every asynchronous store request this check makes is counted, so the wait below knows when all of them
// have answered. A fixed pause is a guess: under load it either calls the store idle while a request is
// still in it, or ends before a completion has run the checks that live in it.
static atomic_int sg_pendingStore;

static void pending(void) { atomic_fetch_add(&sg_pendingStore, 1); }
static void answered(void) { atomic_fetch_sub(&sg_pendingStore, 1); }

// Runs the main queue until every request made so far has answered. A completion that never arrives is a
// failure, never the wait's end: the deadline is this check giving up, and it says so.
static void waitForStore(void) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:30];
    while (atomic_load(&sg_pendingStore) > 0 && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    if (atomic_load(&sg_pendingStore) > 0) {
        fprintf(stderr, "FAILED: %d store request(s) never answered within 30 s\n", atomic_load(&sg_pendingStore));
        exit(1);
    }
}

// The store's asynchronous entries, counted as they are asked for, so waitForStore has something to wait
// on that is not a guess.
static void pasteLyrics(NSString *text, NSString *uri, void (^done)(NSString *, NSError *)) {
    pending();
    SGImportPastedLyrics(text, uri, ^(NSString *name, NSError *error) { answered(); done(name, error); });
}

static void importLyrics(NSURL *url, NSString *uri, void (^done)(NSString *, NSError *)) {
    pending();
    SGImportLRC(url, uri, ^(NSString *name, NSError *error) { answered(); done(name, error); });
}

static void deleteLyrics(NSString *name, void (^done)(BOOL)) {
    pending();
    SGDeleteImportedLRC(name, ^(BOOL deleted) { answered(); done(deleted); });
}

static void retireLyrics(void (^done)(NSArray<NSString *> *)) {
    pending();
    SGRetireImportedLyrics(^(NSArray<NSString *> *removed) { answered(); done(removed); });
}

// The reuse race: a retire step is pending on the store's queue, and a delete and an import that takes the
// retired name are asked for after it. The store's one queue runs them in that order, so the new file that
// now carries the retired name must survive and the list must not name it any more.
static void reuseRaceCheck(void) {
    NSString *name = @"reused.lrc";
    NSString *uri = @"spotify:local:Reuse:Album:Song:150";
    // The state a replacement leaves behind, with a retire step about to run over it.
    NSError *error = nil;
    NSDictionary *receipt = nil;
    CHECK(SGWriteImportedLyric(@"[00:01]Retired words", [NSURL fileURLWithPath:lyricsPath(name)], &receipt, &error) && receipt);
    [NSUserDefaults.standardUserDefaults setObject:@[receipt] forKey:SGKeyRetiredImportedLyrics];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
    __block BOOL imported = NO, retired = NO, deleted = YES;
    retireLyrics(^(NSArray<NSString *> *removed) {
        CHECK([removed isEqual:(@[name])]);   // the step did run first, and it did delete that file
        retired = YES;
    });
    deleteLyrics(name, ^(BOOL answer) { deleted = answer; });   // the retire step took it before this ran
    importLyrics(lrc(@"reused.lrc", @"[00:02]New words"), uri, ^(NSString *name, NSError *error) {
        CHECK([name isEqual:@"reused.lrc"]);
        imported = YES;
    });
    waitForStore();
    CHECK(retired && imported);
    CHECK(!deleted);   // the order held: the retire step had already removed the file
    CHECK([SGImportedLRCLinkedTo(uri) isEqual:name]);
    CHECK([[NSString stringWithContentsOfFile:lyricsPath(name) encoding:NSUTF8StringEncoding error:nil] isEqual:@"[00:02]New words"]);
    CHECK(![retiredNames() containsObject:name]);
    // And a launch over that state leaves the file the import now owns.
    CHECK([freshFolder() containsObject:name]);
    CHECK([[NSString stringWithContentsOfFile:lyricsPath(name) encoding:NSUTF8StringEncoding error:nil] isEqual:@"[00:02]New words"]);
    CHECK(deleteLRC(name));
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
    puts("reuse race: a retired name taken again by an import survives the launch's retire step");
}

// Every store change is announced on the main queue: the observers touch UIKit and the lyrics state.
static void notificationCheck(void) {
    static atomic_bool offMain, seen;
    atomic_store(&offMain, false);
    atomic_store(&seen, false);
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:SGImportedLRCDidChangeNotification object:nil queue:nil
                                                             usingBlock:^(NSNotification *note) {
        if (!NSThread.isMainThread) atomic_store(&offMain, true);
        atomic_store(&seen, true);
    }];
    pasteLyrics(@"Notification line one\nNotification line two", @"spotify:local:Notify:Album:Song:60", ^(NSString *name, NSError *error) {
        CHECK(name != nil);
    });
    waitForStore();
    CHECK(atomic_load(&seen));
    CHECK(!atomic_load(&offMain));
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    CHECK(deleteLRC(@"Pasted lyrics.txt"));
    puts("store notifications: posted on the main thread");
}

// The validator and each reading of a file or a paste, on data as the import hands it over: a TTML
// sample, an LRC sample, a text sample, empty data, 1 MB + 1, binary garbage, UTF-16 with a BOM, and the
// plain text fallback of a document that looks like TTML or LRC and holds no line. Then the replacement:
// a failed write leaves the track's old lyrics, links and stored file as they were.
static void validatorCheck(void) {
    NSError *error = nil;
    NSString *ttml = @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div>"
        @"<p begin=\"0:01.000\" end=\"0:03.000\"><span begin=\"0:01.000\" end=\"0:01.500\">First</span> <span begin=\"0:01.500\" end=\"0:03.000\">line</span></p>"
        @"<p begin=\"0:05.000\" end=\"0:07.000\"><span begin=\"0:05.000\" end=\"0:07.000\">Second line</span></p>"
        @"</div></body></tt>";
    SGImportedLyrics *sheet = SGImportedLyricsFromData([ttml dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindTTML && !error);
    CHECK(sheet.synced && sheet.lines.count == 2);
    CHECK(([[sheet.lines valueForKey:@"start"] isEqual:(@[@1000, @5000])]));
    CHECK([SGKaraokeLineText(sheet.lines.firstObject) isEqual:@"First line"]);

    NSString *lrcSample = @"[ti:Sample]\n[ar:Someone]\n[00:01.00]One\n[00:02.50]Two\n";
    sheet = SGImportedLyricsFromData([lrcSample dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindLRC && sheet.synced && sheet.lines.count == 2);
    CHECK([sheet.title isEqual:@"Sample"] && [sheet.artist isEqual:@"Someone"]);
    CHECK(([[sheet.lines valueForKey:@"start"] isEqual:(@[@1000, @2500])]));

    NSString *txt = @"  First line \r\n\r\n\tSecond line\r\nThird line  \r\n";
    sheet = SGImportedLyricsFromData([txt dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindText && !sheet.synced && sheet.lines.count == 3);
    CHECK(([sheet.texts isEqual:(@[@"First line", @"Second line", @"Third line"])]));
    CHECK(([sheet.starts isEqual:(@[@0, @0, @0])]));

    error = nil;
    CHECK(!SGImportedLyricsFromData([NSData data], &error) && error.code == SGLyricsImportErrorNothing);
    error = nil;
    NSData *oneOver = [NSMutableData dataWithLength:1024 * 1024 + 1];
    CHECK(!SGImportedLyricsFromData(oneOver, &error) && error.code == SGLyricsImportErrorTooLarge);
    error = nil;
    CHECK(!SGImportedLyricsFromData([NSMutableData dataWithBytes:"\xC3\x28\xA0\xA1\xE2\x28\xA1\xF0\x28\x8C\x28" length:11], &error)
          && error.code == SGLyricsImportErrorUnreadable);
    // UTF-16 is read only with a BOM, which says which order it is in.
    error = nil;
    sheet = SGImportedLyricsFromData([@"First line\nSecond line" dataUsingEncoding:NSUTF16StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindText && sheet.lines.count == 2 && !error);
    CHECK([sheet.texts.firstObject isEqual:@"First line"]);

    // A TTML that gives no line is read for what it has, and so is an LRC with no stamp.
    error = nil;
    sheet = SGImportedLyricsFromData([@"<tt><body><div><p>no time</p></div></body></tt>" dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindText && ([sheet.texts isEqual:(@[@"no time"])]) && !error);
    sheet = SGImportedLyricsFromData([@"[ti:Tag only]\nA line\nAnother" dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindText && ([sheet.texts isEqual:(@[@"A line", @"Another"])]));
    // Plain text keeps every non-empty line, a line in brackets too; a file that is LRC does not.
    sheet = SGImportedLyricsFromData([@"[Chorus]\nSing it\n[Verse]" dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindText && ([sheet.texts isEqual:(@[@"[Chorus]", @"Sing it", @"[Verse]"])]));
    sheet = SGImportedLyricsFromData([@"[ti:Tags]\n[00:01]Sung\n[x] comment" dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet.kind == SGLyricsImportKindLRC && ([sheet.texts isEqual:(@[@"Sung"])]));
    // An LRC whose timestamps are all malformed keeps its lyric text as plain text: the broken stamps and
    // the tags go, the words stay, and it is not refused as unreadable.
    error = nil;
    sheet = SGImportedLyricsFromData([@"[ti:Song]\n[00:bad]Hello\n[ar:Someone]\n[??]There" dataUsingEncoding:NSUTF8StringEncoding], &error);
    CHECK(sheet && sheet.kind == SGLyricsImportKindText && !sheet.synced && !error);
    CHECK(([sheet.texts isEqual:(@[@"Hello", @"There"])]));

    // Replacing: the new file is written and linked, and the one it replaced is only retired, so a launch
    // that ends before the link reaches disk finds the old file still there.
    NSString *uri = @"spotify:local:Replace:Album:Song:200";
    CHECK([importLRC(lrc(@"first.lrc", @"[00:01]First words"), uri, &error) isEqual:@"first.lrc"]);
    CHECK([importLRC(lrc(@"second-letters.txt", @"Plain words"), uri, &error) isEqual:@"second-letters.txt"]);
    CHECK([SGImportedLRCLinkedTo(uri) isEqual:@"second-letters.txt"]);
    CHECK([SGImportedLRCFor(uri, nil, nil).texts.firstObject isEqual:@"Plain words"]);
    CHECK([SGImportedLRCFiles() containsObject:@"first.lrc"]);   // still there: nothing is deleted at import
    CHECK(([retiredNames() isEqual:@[@"first.lrc"]]));

    // No import ever deletes for not being linked: a by-name file and one copied in by hand are nobody's
    // links, and they are still there after any number of launches.
    CHECK([importLRC(lrc(@"By Name - A Song.lrc", @"[00:02]By name words"), nil, &error) isEqual:@"By Name - A Song.lrc"]);
    NSString *hand = lyricsPath(@"hand-copied.lrc");
    CHECK([[@"[00:03]Hand words" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:hand atomically:YES]);
    for (NSUInteger launch = 0; launch < 3; launch++) {
        NSArray<NSString *> *folder = freshFolder();
        CHECK([folder containsObject:@"By Name - A Song.lrc"]);
        CHECK([folder containsObject:@"hand-copied.lrc"]);
        CHECK(![folder containsObject:@"first.lrc"]);
        CHECK(([retiredNames() isEqual:@[]]));
    }
    SGLyricsResult *byName = SGImportedLRCFor(@"spotify:local:::y:120", @"A Song", @"By Name");
    CHECK(byName != nil);

    // Normal persistence, done: the replaced file is gone and the linked one serves the track.
    CHECK(![SGImportedLRCFiles() containsObject:@"first.lrc"]);
    CHECK([SGImportedLRCFiles() containsObject:@"second-letters.txt"]);
    CHECK([SGImportedLRCFor(uri, nil, nil).texts.firstObject isEqual:@"Plain words"]);
    CHECK(![NSUserDefaults.standardUserDefaults arrayForKey:SGKeyRetiredImportedLyrics]);

    // Simulated crash: the replacement retired the old file, but the link update never reached disk, so the
    // durable link still names it. The next launch keeps it, and keeps it on the list for the launch after.
    NSString *replacedName = importLRC(lrc(@"third-replaced.lrc", @"[00:09]Three"), uri, &error);
    CHECK([replacedName isEqual:@"third-replaced.lrc"]);
    [NSUserDefaults.standardUserDefaults setObject:@{uri: @"second-letters.txt"} forKey:SGKeyImportedLRCLinks];
    [NSUserDefaults.standardUserDefaults synchronize];
    CHECK([retiredNames() containsObject:@"second-letters.txt"]);
    CHECK(([freshFolder() containsObject:@"second-letters.txt"]));
    CHECK(([retiredNames() isEqual:@[@"second-letters.txt"]]));
    // The link the app has in memory still names the file the failed launch left, and it still holds its
    // words: the crash cost nothing.
    CHECK([SGImportedLRCLinkedTo(uri) isEqual:@"third-replaced.lrc"]);
    CHECK([[NSString stringWithContentsOfFile:lyricsPath(@"second-letters.txt") encoding:NSUTF8StringEncoding error:nil] isEqual:@"Plain words"]);
    // With the link now naming the new file, the next launch takes the old one away.
    [NSUserDefaults.standardUserDefaults setObject:@{uri: @"third-replaced.lrc"} forKey:SGKeyImportedLRCLinks];
    [NSUserDefaults.standardUserDefaults synchronize];
    NSArray<NSString *> *afterCrash = freshFolder();
    CHECK(![afterCrash containsObject:@"second-letters.txt"]);
    CHECK([afterCrash containsObject:@"third-replaced.lrc"]);
    CHECK(([retiredNames() isEqual:@[]]));

    // A retired name that is a directory, a symlink or nothing at all is never deleted: only a regular file
    // directly in the lyrics directory is.
    NSString *lyricsDirectory = lyricsPath(@"folder.lrc").stringByDeletingLastPathComponent;
    NSString *folder = [lyricsDirectory stringByAppendingPathComponent:@"folder.lrc"];
    NSString *symlink = [lyricsDirectory stringByAppendingPathComponent:@"link.lrc"];
    // A run that stopped here leaves them behind; the check starts from neither.
    [NSFileManager.defaultManager removeItemAtPath:symlink error:nil];
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];
    CHECK([NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil]);
    CHECK(([NSFileManager.defaultManager createSymbolicLinkAtPath:symlink withDestinationPath:folder error:nil]));
    [NSUserDefaults.standardUserDefaults setObject:(@[@"folder.lrc", @"link.lrc", @"already-gone.lrc"]) forKey:SGKeyRetiredImportedLyrics];
    [NSUserDefaults.standardUserDefaults synchronize];
    freshLaunch();
    CHECK([NSFileManager.defaultManager fileExistsAtPath:folder]);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:symlink]);
    CHECK(![NSUserDefaults.standardUserDefaults arrayForKey:SGKeyRetiredImportedLyrics]);
    [NSFileManager.defaultManager removeItemAtPath:symlink error:nil];
    [NSFileManager.defaultManager removeItemAtPath:folder error:nil];

    // The same with a write that fails: the old lyrics, the link and the stored file stand as they were.
    CHECK([importLRC(lrc(@"kept.lrc", @"[00:01]Kept words"), uri, &error) isEqual:@"kept.lrc"]);
    SEL write = @selector(writeToURL:atomically:encoding:error:);
    Method method = class_getInstanceMethod(NSString.class, write);
    IMP original = method_getImplementation(method);
    static atomic_bool failWrites;
    atomic_store(&failWrites, true);
    IMP failing = imp_implementationWithBlock(^BOOL(id receiver, NSURL *url, BOOL atomically, NSStringEncoding encoding, NSError **out) {
        if (atomic_load(&failWrites)) {
            if (out) *out = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:nil];
            return NO;
        }
        return ((BOOL (*)(id, SEL, id, BOOL, NSStringEncoding, NSError **))original)(receiver, write, url, atomically, encoding, out);
    });
    method_setImplementation(method, failing);
    error = nil;
    CHECK(!importLRC(lrc(@"third-replacement.lrc", @"[00:01]Newer words"), uri, &error) && error.code == SGLyricsImportErrorStorage);
    atomic_store(&failWrites, false);
    method_setImplementation(method, original);
    imp_removeBlock(failing);
    CHECK([SGImportedLRCLinkedTo(uri) isEqual:@"kept.lrc"]);
    CHECK([SGImportedLRCFor(uri, nil, nil).texts.firstObject isEqual:@"Kept words"]);
    CHECK([SGImportedLRCFiles() containsObject:@"kept.lrc"]);
    CHECK(deleteLRC(@"kept.lrc"));
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];

    // A paste is held to the same rules, and kept as text under the linked file's name.
    __block NSString *pasted = nil, *pasteUri = @"spotify:local:Paste:Album:Song:100";
    __block NSError *pasteError = nil;
    pasteLyrics(@"\n  Pasted one\r\n\r\nPasted two\n", pasteUri, ^(NSString *name, NSError *reason) {
        CHECK(NSThread.isMainThread);
        pasted = name; pasteError = reason;
    });
    waitForStore();
    CHECK([pasted isEqual:@"Pasted lyrics.txt"] && !pasteError);
    CHECK([SGImportedLRCLinkedTo(pasteUri) isEqual:pasted]);
    CHECK(([SGImportedLRCFor(pasteUri, nil, nil).texts isEqual:(@[@"Pasted one", @"Pasted two"])]));
    CHECK(deleteLRC(pasted));
    // A paste is kept under what it turned out to hold, like a file: an LRC paste as .lrc, not .txt.
    // A timed paste reaches SGLyricsPageLines while it is parsed, which must happen off main.
    atomic_store(&sg_requireWorker, true);
    pasteLyrics(@"[ti:Pasted]\n[00:01]Pasted line", nil, ^(NSString *name, NSError *reason) {
        pasted = name; pasteError = reason;
    });
    waitForStore();
    atomic_store(&sg_requireWorker, false);
    CHECK([pasted isEqual:@"Pasted lyrics.lrc"] && !pasteError);
    CHECK(deleteLRC(pasted));
    // A slow paste followed by a fast one for the same track: the stores happen in the order they were
    // made, so the later paste owns the link and the first one is the file it replaced.
    sg_slowEntered = dispatch_semaphore_create(0);
    sg_slowRelease = dispatch_semaphore_create(0);
    atomic_store(&sg_holdSlow, true);
    NSMutableArray<NSString *> *completed = [NSMutableArray array];
    pasteLyrics(@"[00:01]Slow A", pasteUri, ^(NSString *name, NSError *reason) { CHECK(name && !reason); [completed addObject:@"A"]; pasted = name; });
    CHECK(dispatch_semaphore_wait(sg_slowEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    __block NSString *fastName = nil;
    pasteLyrics(@"[00:01]Fast B", pasteUri, ^(NSString *name, NSError *reason) { CHECK(name && !reason); [completed addObject:@"B"]; fastName = name; });
    // Where pastes could overtake each other, B is stored and answered while A is still held.
    NSDate *overtaking = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!fastName && overtaking.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    dispatch_semaphore_signal(sg_slowRelease);
    waitForStore();
    CHECK(([completed isEqual:(@[@"A", @"B"])]));
    CHECK([SGImportedLRCLinkedTo(pasteUri) isEqual:fastName] && ![fastName isEqual:pasted]);
    CHECK([SGImportedLRCFor(pasteUri, nil, nil).texts.firstObject isEqual:@"Fast B"]);
    CHECK(deleteLRC(pasted));
    CHECK(deleteLRC(fastName));
    // The same through a file import: it and a later paste share one order, so the paste still wins.
    atomic_store(&sg_holdSlow, true);
    [completed removeAllObjects];
    importLyrics(lrc(@"slow-import.lrc", @"[00:01]Slow A"), pasteUri, ^(NSString *name, NSError *reason) { CHECK(name && !reason); [completed addObject:@"A"]; pasted = name; });
    CHECK(dispatch_semaphore_wait(sg_slowEntered, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    fastName = nil;
    pasteLyrics(@"[00:01]Fast B", pasteUri, ^(NSString *name, NSError *reason) { CHECK(name && !reason); [completed addObject:@"B"]; fastName = name; });
    overtaking = [NSDate dateWithTimeIntervalSinceNow:1];
    while (!fastName && overtaking.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    dispatch_semaphore_signal(sg_slowRelease);
    waitForStore();
    CHECK(([completed isEqual:(@[@"A", @"B"])]));
    CHECK([SGImportedLRCLinkedTo(pasteUri) isEqual:fastName] && ![fastName isEqual:pasted]);
    CHECK([SGImportedLRCFor(pasteUri, nil, nil).texts.firstObject isEqual:@"Fast B"]);
    CHECK(deleteLRC(pasted));
    CHECK(deleteLRC(fastName));
    pasteLyrics(@"   \n\n", nil, ^(NSString *name, NSError *reason) {
        CHECK(!name && reason.code == SGLyricsImportErrorNothing);
    });
    waitForStore();
    puts("lyrics import: validator, TTML/LRC/text readings, malformed-timestamp fallback, retired-file launch and failed write passed");
}

static void asyncLibraryCheck(void) {
    for (NSUInteger i = 0; i < 80; i++) {
        NSString *name = [NSString stringWithFormat:@"cache-%02lu.lrc", (unsigned long)i];
        NSString *uri = [NSString stringWithFormat:@"spotify:local:Cache:Album:Track%lu:120", (unsigned long)i];
        CHECK(importLRC(lrc(name, [NSString stringWithFormat:@"[ti:Track%lu]\n[ar:Cache]\n[00:01]Cached words", (unsigned long)i]), uri, nil));
    }
    atomic_store(&sg_requireWorker, true);
    // No link: the library scan and every parser run must happen off main.
    CHECK([asyncLyrics(@"spotify:local:::unlinked:120", @"Track79").texts.firstObject isEqual:@"Cached words"]);
    NSHashTable *retainedLines = [NSHashTable weakObjectsHashTable];
    for (NSUInteger i = 0; i < 80; i++) {
        @autoreleasepool {
            NSString *uri = [NSString stringWithFormat:@"spotify:local:Cache:Album:Track%lu:120", (unsigned long)i];
            SGLyricsResult *result = asyncLyrics(uri, nil);
            CHECK([result.texts.firstObject isEqual:@"Cached words"]);
            [retainedLines addObject:result.karaokeLines];
        }
    }
    CHECK(retainedLines.allObjects.count <= 40);
    CHECK([asyncLyrics(@"spotify:local:Cache:Album:Track0:120", nil).texts.firstObject isEqual:@"Cached words"]);
    atomic_store(&sg_requireWorker, false);
    puts("LRC async: worker-only scanning/parsing, main completion and bounded retained sheets passed");
}

static SGLyricsResult *playbackTag(NSString *file) {
    __block BOOL delivered = NO;
    __block SGLyricsResult *sheet;
    NSString *path = [@(getenv("SG_TEST_TAGS")) stringByAppendingPathComponent:file];
    SGPlaybackLyricsFetch(@"spotify:local:Fixture:Record:Embedded:240", path, ^(SGLyricsResult *result) {
        HARNESS_CHECK(NSThread.isMainThread);
        sheet = result; delivered = YES;
    });
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!delivered && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    HARNESS_CHECK(delivered);
    return sheet;
}

static void embeddedCheck(void) {
    atomic_store(&sg_requireWorker, true);
    for (NSInteger v = 2; v <= 4; v++) {
        SGLyricsResult *plain = playbackTag([NSString stringWithFormat:@"plain%ld",(long)v]);
        CHECK([plain.texts.firstObject isEqual:@"café"] && !plain.synced && [plain.provider isEqual:@"From the file"]);
        SGLyricsResult *sync = playbackTag([NSString stringWithFormat:@"sync%ld",(long)v]);
        CHECK((sync.synced && [sync.starts isEqual:@[@511,@4000]] && [sync.texts isEqual:@[@"First",@"Second"]]));
    }
    CHECK([playbackTag(@"flac-plain").texts.firstObject isEqual:@"Plain text"]);
    SGLyricsResult *flac = playbackTag(@"flac-synced");
    CHECK(flac.synced && [flac.starts isEqual:@[@1250]] && [flac.texts.firstObject isEqual:@"Stamped"]);
    CHECK([playbackTag(@"tail.m4a").texts.firstObject isEqual:@"가사"]);
    SGLyricsResult *afterBreaks = playbackTag(@"breaks-and-plain");
    CHECK([SGKaraokeLineText(afterBreaks.karaokeLines.firstObject) isEqual:@"Words after breaks"] &&
          !afterBreaks.synced && !playbackTag(@"only-breaks"));
    CHECK(!playbackTag(@"missing") && !playbackTag(@"frame-clock") && !playbackTag(@"too-large"));
    atomic_store(&sg_requireWorker, false);
    puts("embedded: ID3 ULT/SLT and v2.3/2.4 USLT/SYLT, FLAC LYRICS/UNSYNCEDLYRICS and tail M4A ©lyr passed");
}

static void reviewFileChecks(void) {
    // Modest pre-fix expansion (not a stress test); the text after removing stamps
    // is copied 512 times by the timing builder.
    NSString *stamps = [@"" stringByPaddingToLength:512*7 withString:@"[00:01]" startingAtIndex:0];
    NSString *text = [@"" stringByPaddingToLength:512 withString:@"note" startingAtIndex:0];
    NSError *error = nil;
    BOOL bounded = !SGImportedLyricsFromText([stamps stringByAppendingString:text], &error)
        && error.code == SGLyricsImportErrorUnreadable;
    SGLyricsResult *tag = playbackTag(@"large-picture");
    BOOL artwork = [tag.texts.firstObject isEqual:@"After artwork"] && tag.karaokeLines.firstObject.fileOwned;
    NSString *uri = @"spotify:local:Fixture::Dangling:100";
    NSString *matched = importLRC(lrc(@"Fixture - Dangling.lrc", @"Matched after removal"),nil,nil);
    NSString *linked = importLRC(lrc(@"linked.txt", @"Linked override"),uri,nil);
    HARNESS_CHECK(linked && matched && SGImportedLRCFor(uri,nil,nil).karaokeLines.firstObject.fileOwned);
    HARNESS_CHECK([NSFileManager.defaultManager removeItemAtPath:lyricsPath(linked) error:nil]);
    BOOL dangling = deleteLRC(linked) && !SGImportedLRCLinkedTo(uri)
        && [SGImportedLRCFor(uri,nil,nil).texts.firstObject isEqual:@"Matched after removal"];
    HARNESS_CHECK(deleteLRC(matched));
    if (!bounded || !artwork || !dangling)
        HARNESS_FAIL(@"bounded expansion=%d, lyrics after large artwork=%d, dangling removal=%d", bounded, artwork, dangling);
    puts("file review: bounded expansion, lyrics after large artwork and dangling link removal passed");
}

// A second launch of the same binary over the same home: the links and the retired list as the defaults
int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc > 1 && strcmp(argv[1], "fresh-launch") == 0) {
            // The launch's own step is already in the store's queue, so this call runs after it: once its
            // answer is in, the launch has done everything it would do on its own.
            retireLyrics(^(NSArray<NSString *> *removed) {});
            waitForStore();
            [NSUserDefaults.standardUserDefaults synchronize];
            return 0;
        }
    }
    @autoreleasepool {
        temporaryDirectory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        CHECK([NSFileManager.defaultManager createDirectoryAtURL:temporaryDirectory withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        [NSFileManager.defaultManager removeItemAtPath:[documents stringByAppendingPathComponent:@"Retrine/Lyrics"] error:nil];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyImportedLRCLinks];
        [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyRetiredImportedLyrics];
        sg_order = @[@"lrclib"];
        NSError *error = nil;

        // Refusals: empty, over 1 MB, and data no text reads. Text with no line is refused too.
        CHECK(!importLRC(lrc(@"empty.lrc", @""), nil, &error) && error.code == SGLyricsImportErrorNothing);
        CHECK(!importLRC(fileNamed(@"big.lrc", [NSMutableData dataWithLength:1024 * 1024 + 1]), nil, &error) && error.code == SGLyricsImportErrorTooLarge);
        NSMutableData *garbage = [NSMutableData dataWithBytes:"\xC3\x28\xA0\xA1\xE2\x28\xA1" length:7];
        CHECK(!importLRC(fileNamed(@"garbage.lrc", garbage), nil, &error) && error.code == SGLyricsImportErrorUnreadable);
        CHECK(!importLRC(lrc(@"blank.lrc", @"\n \n\t\n"), nil, &error) && error.code == SGLyricsImportErrorNothing);
        NSURL *huge = fileNamed(@"sparse.lrc", [NSData data]);
        NSFileHandle *sparse = [NSFileHandle fileHandleForWritingToURL:huge error:nil];
        CHECK([sparse truncateAtOffset:8ULL * 1024 * 1024 * 1024 error:nil]);
        CHECK([sparse closeAndReturnError:nil]);
        CHECK(!importLRC(huge, nil, &error) && error.code == SGLyricsImportErrorTooLarge);
        CHECK(SGImportedLRCFiles().count == 0);

        // The validator and the three readings, on data as the page hands it over.
        validatorCheck();
        notificationCheck();
        reuseRaceCheck();

        // Several stamps on a line, every fraction form, an offset, a line with no text skipped.
        NSString *sheet = @"﻿[ti:Halo]\n[ar:Beyoncé]\n[offset:+500]\n[00:10.5][01:00:250]Remember\n[00:20.25]those walls\n[00:30]\n[1:05.123]I built\n";
        NSString *name = importLRC(lrc(@"halo.lrc", sheet), nil, &error);
        CHECK([name isEqualToString:@"halo.lrc"]);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // the first import goes on top
        CHECK(!SGImportedLRCFor(@"spotify:track:x", @"HALO", @"beyonce"));
        SGLyricsResult *found = SGImportedLRCFor(@"spotify:local:::x:120", @"HALO", @"beyonce");
        CHECK(found.synced && found.karaokeLines.count == 4);
        NSArray<NSNumber *> *starts = [found.karaokeLines valueForKey:@"start"];
        CHECK([starts isEqualToArray:(@[@10000, @19750, @59750, @64623])]);
        CHECK([SGKaraokeLineText(found.karaokeLines[2]) isEqualToString:@"Remember"]);
        CHECK([found.title isEqualToString:@"Halo"] && [found.provider isEqualToString:@"Imported LRC"]);
        CHECK(!SGImportedLRCFor(@"spotify:local:::x:120", @"Halo", @"Someone else"));
        CHECK(!SGImportedLRCFor(@"spotify:local:::x:120", nil, @"Beyoncé"));   // never without a matching title

        // A taken name is numbered.
        CHECK([importLRC(lrc(@"halo.lrc", sheet), nil, &error) isEqualToString:@"halo (2).lrc"]);
        CHECK(deleteLRC(@"halo (2).lrc"));

        // "Artist - Title" and "Title – Artist" with no tags: the sides come from the track.
        importLRC(lrc(@"Daft Punk - One More Time.lrc", @"[00:01.00]One more time"), nil, &error);
        importLRC(lrc(@"Around the World – Daft Punk.lrc", @"[00:01.00]Around the world"), nil, &error);
        CHECK(SGImportedLRCFor(@"spotify:local:::y:120", @"one more time!", @"DAFT PUNK"));
        CHECK(SGImportedLRCFor(@"spotify:local:::y:120", @"Around The World", @"Daft Punk"));
        CHECK(!SGImportedLRCFor(@"spotify:local:::y:120", @"One More Time", @"Justice"));
        CHECK(!SGImportedLRCFor(@"spotify:local:::y:120", @"Discovery", @"Daft Punk"));

        // A local file named by its URI; one linked has its file whatever the names say, and keeps it
        // through a rename's lyrics key. A file with a tag in it is LRC: its tags go, and what a bracketed
        // row has after the brackets stays as its line.
        NSString *uri = @"spotify:local:Daft+Punk:Discovery:One+More+Time:320";
        CHECK(SGImportedLRCFor(uri, nil, nil));
        NSString *other = @"spotify:local:::Track+01:200";
        CHECK(!SGImportedLRCFor(other, nil, nil));
        sg_order = @[@"lrclib", SGImportedLRCKey];
        NSString *plain = importLRC(lrc(@"notes.lrc", @"[by:me]\nFirst line\n\nSecond line\n[x] bracketed"), other, &error);
        CHECK([SGLyricsOrder().firstObject isEqualToString:SGImportedLRCKey]);   // a link goes on top
        CHECK([SGImportedLRCLinkedTo([other stringByAppendingString:@"#123"]) isEqualToString:plain]);
        found = SGImportedLRCFor(other, nil, nil);
        CHECK(found && !found.synced && found.karaokeLines.count == 3 && [found.title isEqualToString:@"Track 01"]);
        CHECK(([found.texts isEqual:(@[@"First line", @"Second line", @"bracketed"])]));
        NSString *songFile = importLRC(lrc(@"song.XmL", @"[00:01]My song"), @"spotify:track:z", &error);
        CHECK([songFile isEqual:@"song.lrc"] && [SGImportedLRCFor(@"z",nil,nil).texts.firstObject isEqual:@"My song"]);
        CHECK(deleteLRC(songFile) && !SGImportedLRCFor(@"z",nil,nil));
        CHECK(!importLRC(lrc(@"wrong.mp3", @"plain"), nil, &error) && error.code == SGLyricsImportErrorType);
        NSString *limit = [@"Words" stringByPaddingToLength:1048576 withString:@" " startingAtIndex:0];
        CHECK([importLRC(lrc(@"limit.TXT",limit), nil, &error) isEqual:@"limit.txt"]);

        // Deleting the file takes its link and its lyrics.
        CHECK(deleteLRC(plain));
        CHECK(!SGImportedLRCLinkedTo(other) && !SGImportedLRCFor(other, nil, nil));
        CHECK(![[NSUserDefaults.standardUserDefaults dictionaryForKey:SGKeyImportedLRCLinks] count]);

        // UTF-16 is read and kept as UTF-8.
        NSString *utf16 = importLRC(fileNamed(@"wide.lrc", [@"[ti:Wide]\n[00:02.00]wide" dataUsingEncoding:NSUTF16StringEncoding]), nil, &error);
        NSString *kept = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:[@"Retrine/Lyrics" stringByAppendingPathComponent:utf16]]
                                                   encoding:NSUTF8StringEncoding error:nil];
        CHECK([kept hasPrefix:@"[ti:Wide]"]);
        invalidationCheck(NO);
        invalidationCheck(YES);
        asyncLibraryCheck();
        embeddedCheck();
        reviewFileChecks();
        [NSFileManager.defaultManager removeItemAtURL:temporaryDirectory error:nil];
        printf("lrc: all checks passed\n");
    }
    return 0;
}
