// SGPlayLog.h says what the log holds and why it is a text file.
#include <stdio.h>
#include <time.h>
#include <errno.h>
#include <compression.h>
#include <dlfcn.h>
#include <copyfile.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdatomic.h>
#include <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif
#import "Core/SGLocalize.h"
#import "SGPlayLog.h"

NSNotificationName const SGPlayLogDidChangeNotification = @"SGPlayLogDidChange";

@implementation SGPlay
@end

@implementation SGStatEntry
@end

@implementation SGStats
@end
@implementation SGListeningStreaks
@end
@implementation SGStatBucket
@end
@implementation SGHistoryImport
@end

static const NSUInteger SGHistoryFileLimit = 64 * 1024 * 1024;
static const NSUInteger SGHistoryTotalLimit = 256 * 1024 * 1024;
static const NSUInteger SGHistoryPlayLimit = 1000000;

static BOOL historyInteger(id value, int64_t *out) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    const char *text = [value stringValue].UTF8String;
    char *tail;
    errno = 0;
    long long number = strtoll(text, &tail, 10);
    if (errno || tail == text || *tail) return NO;
    *out = number;
    return YES;
}

static NSArray<SGPlay *> *localHistory(NSDictionary *root) {
    int64_t version;
    // Backups already exported under the old name keep exact-row import semantics.
    if ((![root[@"format"] isEqual:@"retrine.listening-history"] && ![root[@"format"] isEqual:@"vitrine.listening-history"]) ||
        !historyInteger(root[@"version"], &version) || version != 1 ||
        ![root[@"plays"] isKindOfClass:NSArray.class] || [root[@"plays"] count] > SGHistoryPlayLimit) return nil;
    NSMutableArray *plays = [NSMutableArray array];
    for (id row in root[@"plays"]) {
        int64_t end, ms;
        if (![row isKindOfClass:NSDictionary.class] || !historyInteger(row[@"end"], &end) ||
            !historyInteger(row[@"ms"], &ms) || ms < 0 || end < -62135596800LL || end > 253402300799LL) return nil;
        for (NSString *key in @[@"uri", @"title", @"artist", @"album"])
            if (![row[key] isKindOfClass:NSString.class]) return nil;
        SGPlay *p = [SGPlay new];
        p.end = end; p.ms = ms; p.uri = row[@"uri"]; p.title = row[@"title"];
        p.artist = row[@"artist"]; p.album = row[@"album"]; p.exactImport = YES;
        [plays addObject:p];
    }
    return plays;
}

NSData *SGHistoryJSON(NSArray<SGPlay *> *plays, NSError **error) {
    if (plays.count > SGHistoryPlayLimit) {
        if (error) *error = [NSError errorWithDomain:@"RetrineHistory" code:1 userInfo:@{NSLocalizedDescriptionKey:
            SGL(@"settings.stats.error.export_play_limit", @"History exceeds the one-million-play export limit. Your history on this phone is unchanged.")}];
        return nil;
    }
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:plays.count];
    for (SGPlay *p in plays) [rows addObject:@{@"end": @(p.end), @"ms": @(p.ms), @"uri": p.uri ?: @"",
        @"title": p.title ?: @"", @"artist": p.artist ?: @"", @"album": p.album ?: @""}];
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"format": @"retrine.listening-history", @"version": @1, @"plays": rows}
                                                 options:0 error:error];
    if (data.length > SGHistoryFileLimit) {
        if (error) *error = [NSError errorWithDomain:@"RetrineHistory" code:2 userInfo:@{NSLocalizedDescriptionKey:
            SGL(@"settings.stats.error.export_size_limit", @"History exceeds the 64 MiB JSON export limit. Your history on this phone is unchanged.")}];
        return nil;
    }
    return data;
}

BOOL SGPlayCounts(double listened, double duration) {
    return listened * 1000 >= SGPlayMinimumMs || (duration > 0 && listened >= duration / 2);
}

@implementation SGPlayClock {
    BOOL _playing;
    NSTimeInterval _since;
}
- (void)setPlaying:(BOOL)playing elapsed:(NSTimeInterval)elapsedSeconds at:(NSTimeInterval)unixSeconds {
    if (_playing) {
        _listenedSeconds += elapsedSeconds - _since;
        _endedAt = unixSeconds;
    }
    _playing = playing;
    _since = elapsedSeconds;
}
@end

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

// Both shapes are UTC. sscanf and timegm rather than NSDateFormatter: an extended export runs to 100k
// rows and more, and the formatter costs microseconds a row.
static int64_t timeIn(NSString *text, BOOL seconds) {
    struct tm tm = {0};
    const char *c = text.UTF8String;
    int n = seconds ? sscanf(c, "%d-%d-%dT%d:%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min, &tm.tm_sec)
                    : sscanf(c, "%d-%d-%d %d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday, &tm.tm_hour, &tm.tm_min);
    if (n < (seconds ? 6 : 5)) return 0;
    tm.tm_year -= 1900;
    tm.tm_mon -= 1;
    return (int64_t)timegm(&tm);
}

// ponytail: the export has no track lengths, so an imported play counts from 30 s only; a full play of
// a track under 30 s is left out. The extended rows' reason_end could tell a finished track apart.
static SGPlay *playFrom(NSDictionary *row) {
    NSString *title, *artist, *album = @"", *uri = @"";
    int64_t end, ms;
    if (row[@"ts"]) {
        title = stringIn(row[@"master_metadata_track_name"]);
        artist = stringIn(row[@"master_metadata_album_artist_name"]);
        album = stringIn(row[@"master_metadata_album_album_name"]) ?: @"";
        uri = stringIn(row[@"spotify_track_uri"]) ?: @"";
        end = stringIn(row[@"ts"]) ? timeIn(row[@"ts"], YES) : 0;
        ms = [row[@"ms_played"] isKindOfClass:NSNumber.class] ? [row[@"ms_played"] longLongValue] : 0;
    } else {
        title = stringIn(row[@"trackName"]);
        artist = stringIn(row[@"artistName"]);
        end = stringIn(row[@"endTime"]) ? timeIn(row[@"endTime"], NO) : 0;
        ms = [row[@"msPlayed"] isKindOfClass:NSNumber.class] ? [row[@"msPlayed"] longLongValue] : 0;
    }
    if (!title || !artist || end <= 0 || ms < SGPlayMinimumMs) return nil;
    SGPlay *play = [SGPlay new];
    play.end = end;
    play.ms = ms;
    play.uri = uri;
    play.title = title;
    play.artist = artist;
    play.album = album;
    return play;
}

NSArray<SGPlay *> *SGPlaysFromExport(NSData *json) {
    if (json.length > SGHistoryFileLimit) return nil;
    id rows = json ? [NSJSONSerialization JSONObjectWithData:json options:0 error:nil] : nil;
    if ([rows isKindOfClass:NSDictionary.class]) return localHistory(rows);
    if (![rows isKindOfClass:NSArray.class]) return nil;
    if ([rows count] > SGHistoryPlayLimit) return nil;
    NSMutableArray<SGPlay *> *plays = [NSMutableArray array];
    BOOL known = NO;
    for (NSDictionary *row in rows) {
        if (![row isKindOfClass:NSDictionary.class]) continue;
        // Podcast files of either shape have their own keys, and the extended one's music rows have
        // ts and ms_played, so the keys say what a file is whatever it was renamed to.
        if (!(row[@"ts"] && row[@"ms_played"]) && !(row[@"endTime"] && row[@"msPlayed"])) continue;
        known = YES;
        SGPlay *play = playFrom(row);
        if (play) [plays addObject:play];
    }
    return known || [rows count] == 0 ? plays : nil;
}

#pragma mark - zip

static uint32_t le(const uint8_t *p, int bytes) {
    uint32_t v = 0;
    for (int i = bytes - 1; i >= 0; i--) v = v << 8 | p[i];
    return v;
}

// A declared ZIP size is not trustworthy. Give the system decoder a fixed output buffer, with one
// extra byte to detect an understated size; NSData's unbounded decompressor can allocate far more.
// Resolve from the system library so Foundation-only harnesses need no extra linker flags.
static NSData *inflateHistory(const uint8_t *bytes, size_t packed, size_t length) {
    static size_t (*decode)(uint8_t *, size_t, const uint8_t *, size_t, void *, compression_algorithm);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/usr/lib/libcompression.dylib", RTLD_LOCAL | RTLD_LAZY);
        if (library) decode = dlsym(library, "compression_decode_buffer");
    });
    if (!decode) return nil;
    void *out = malloc(length + 1);
    if (!out) return nil;
    size_t written = decode(out, length + 1, bytes, packed, NULL, COMPRESSION_ZLIB);
    if (written != length) { free(out); return nil; }
    return [NSData dataWithBytesNoCopy:out length:length freeWhenDone:YES];
}

// The central directory names each entry and where it starts; stored and raw DEFLATE entries are read.
// ponytail: no ZIP64, so a zip over 4 GB or 65535 entries reads as empty; an export is far smaller.
static NSArray<NSData *> *historyJSONFilesInZip(NSData *zip, NSUInteger *skipped, NSUInteger expandedLimit,
                                                NSUInteger *expandedConsumed) {
    NSMutableArray<NSData *> *files = [NSMutableArray array];
    const uint8_t *b = zip.bytes;
    size_t size = zip.length;
    expandedLimit = MIN(expandedLimit, SGHistoryTotalLimit);
    if (size < 22 || size > SGHistoryTotalLimit || !expandedLimit) return files;
    NSUInteger expanded = 0, jsonCount = 0;
    size_t eocd = SIZE_MAX;
    size_t floor = size > 22 + 0xFFFF ? size - 22 - 0xFFFF : 0;
    for (size_t i = size - 22; ; i--) {
        if (le(b + i, 4) == 0x06054b50) { eocd = i; break; }
        if (i == floor) break;
    }
    if (eocd == SIZE_MAX) return files;
    uint32_t count = le(b + eocd + 10, 2);
    size_t at = le(b + eocd + 16, 4);
    for (uint32_t n = 0; n < count; n++) {
        if (n >= 10000) { if (skipped) (*skipped)++; break; }
        if (at + 46 > size || le(b + at, 4) != 0x02014b50) break;
        uint32_t method = le(b + at + 10, 2), packed = le(b + at + 20, 4), length = le(b + at + 24, 4);
        uint32_t nameLength = le(b + at + 28, 2), extra = le(b + at + 30, 2), comment = le(b + at + 32, 2);
        size_t local = le(b + at + 42, 4);
        if (at + 46 + nameLength > size) break;
        NSString *name = [[NSString alloc] initWithBytes:b + at + 46 length:nameLength encoding:NSUTF8StringEncoding];
        at += 46 + nameLength + extra + comment;

        BOOL json = [name.lowercaseString hasSuffix:@".json"];
        for (NSString *component in name.pathComponents)
            if ([component hasPrefix:@"."] || [component isEqualToString:@"__MACOSX"]) json = NO;
        if (!json) continue;
        if (++jsonCount > 1000) { if (skipped) (*skipped)++; continue; }
        if (local + 30 > size || le(b + local, 4) != 0x04034b50) { if (skipped) (*skipped)++; continue; }
        size_t data = local + 30 + le(b + local + 26, 2) + le(b + local + 28, 2);
        if (data + packed > size || length > SGHistoryFileLimit || length > expandedLimit - expanded || files.count >= 1000) {
            if (skipped) (*skipped)++;
            continue;
        }
        expanded += length; // Failed decoding consumes the budget too.
        if (method == 0 && packed == length) {
            [files addObject:[zip subdataWithRange:NSMakeRange(data, packed)]];
        } else if (method == 8 && length) {
            NSData *out = inflateHistory(b + data, packed, length);
            if (out.length == length) [files addObject:out];
            else if (skipped) (*skipped)++;
        } else if (skipped) (*skipped)++;
    }
    if (expandedConsumed) *expandedConsumed = expanded;
    return files;
}

NSArray<NSData *> *SGJSONFilesInZip(NSData *zip) { return historyJSONFilesInZip(zip, NULL, SGHistoryTotalLimit, NULL); }

#pragma mark - selected files and folders

SGHistoryImport *SGReadHistoryURLs(NSArray<NSURL *> *urls) {
    SGHistoryImport *result = [SGHistoryImport new];
    NSMutableArray *plays = [NSMutableArray array];
    __block NSUInteger visited = 0, files = 0, inputBytes = 0, jsonBytes = 0;
    NSArray *keys = @[NSURLIsDirectoryKey, NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey, NSURLIsHiddenKey,
                      NSURLIsPackageKey, NSURLFileSizeKey];
    void (^readFile)(NSURL *) = ^(NSURL *url) {
        NSString *ext = url.pathExtension.lowercaseString;
        if (![@[@"json", @"zip"] containsObject:ext]) return;
        if (++files > 1000) { result.skipped++; return; }
        NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        NSError *error;
        [coordinator coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *reading) {
            NSDictionary *values = [reading resourceValuesForKeys:keys error:nil];
            NSUInteger size = [values[NSURLFileSizeKey] unsignedIntegerValue];
            NSUInteger limit = [ext isEqualToString:@"zip"] ? SGHistoryTotalLimit : SGHistoryFileLimit;
            if (![values[NSURLIsRegularFileKey] boolValue] || [values[NSURLIsSymbolicLinkKey] boolValue] ||
                !size || size > limit || size > SGHistoryTotalLimit - inputBytes) { result.skipped++; return; }
            inputBytes += size;
            // Read at most the budget even if a provider changes the file after the size check.
            NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:reading error:nil];
            NSData *data = [handle readDataUpToLength:size + 1 error:nil];
            [handle closeAndReturnError:nil];
            if (!data || data.length > size) { result.skipped++; return; }
            NSUInteger zipSkipped = 0, zipExpanded = 0;
            NSUInteger remaining = SGHistoryTotalLimit - jsonBytes;
            BOOL zipped = [ext isEqualToString:@"zip"];
            NSArray *jsons = zipped ? historyJSONFilesInZip(data, &zipSkipped, remaining, &zipExpanded) : @[data];
            if (zipped) jsonBytes += zipExpanded; // Failed entries consume the shared allocation/decode budget too.
            result.skipped += zipSkipped;
            if (!jsons.count) result.skipped++;
            for (NSData *json in jsons) {
              @autoreleasepool {
                if (result.files >= 1000) { result.skipped++; break; }
                if (!zipped) {
                    if (json.length > SGHistoryTotalLimit - jsonBytes) { result.skipped++; continue; }
                    jsonBytes += json.length;
                }
                NSArray *found = SGPlaysFromExport(json);
                if (!found || found.count > SGHistoryPlayLimit - plays.count) { result.skipped++; continue; }
                result.files++;
                [plays addObjectsFromArray:found];
              }
            }
        }];
        if (error) result.skipped++;
    };
    for (NSURL *url in urls) {
        if (++visited > 10000) { result.skipped++; break; }
        if (!url.isFileURL) { result.skipped++; continue; }
        BOOL scoped = [url startAccessingSecurityScopedResource];
        @try {
            NSDictionary *values = [url resourceValuesForKeys:keys error:nil];
            if (!values || [values[NSURLIsSymbolicLinkKey] boolValue] || [values[NSURLIsHiddenKey] boolValue] ||
                [values[NSURLIsPackageKey] boolValue]) { result.skipped++; continue; }
            if (![values[NSURLIsDirectoryKey] boolValue]) { readFile(url); continue; }
            NSString *root = [url.URLByResolvingSymlinksInPath.path stringByAppendingString:@"/"];
            NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtURL:url includingPropertiesForKeys:keys
                options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
                errorHandler:^BOOL(NSURL *failed, NSError *error) { result.skipped++; return YES; }];
            for (NSURL *child in enumerator) {
                if (++visited > 10000) { result.skipped++; break; }
                NSDictionary *v = [child resourceValuesForKeys:keys error:nil];
                if (!v || [v[NSURLIsSymbolicLinkKey] boolValue] || [v[NSURLIsPackageKey] boolValue] ||
                    [child.lastPathComponent isEqualToString:@"__MACOSX"] ||
                    ![child.URLByResolvingSymlinksInPath.path hasPrefix:root] || enumerator.level > 8) {
                    [enumerator skipDescendants]; result.skipped++; continue;
                }
                if (![v[NSURLIsDirectoryKey] boolValue] && [child.pathExtension.lowercaseString isEqualToString:@"json"]) readFile(child);
            }
        } @finally {
            if (scoped) [url stopAccessingSecurityScopedResource];
        }
    }
    result.plays = plays;
    return result;
}

#pragma mark - the log

static NSString *field(NSString *text) {
    if (!text) return @"";
    NSArray *parts = [text componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\t\r\n"]];
    return [parts componentsJoinedByString:@" "];
}

static NSString *lineOf(SGPlay *play) {
    return [NSString stringWithFormat:@"%lld\t%lld\t%@\t%@\t%@\t%@\n", play.end, play.ms, field(play.uri), field(play.title),
            field(play.artist), field(play.album)];
}

NSString *SGTrackKey(SGPlay *play) {
    return [NSString stringWithFormat:@"%@\x1f%@", play.title.lowercaseString, play.artist.lowercaseString];
}


static NSMutableArray<SGPlay *> *playsFromTSV(NSString *text) {
    NSMutableArray *plays = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray<NSString *> *f = [line componentsSeparatedByString:@"\t"];
        if (f.count < 6) continue;
        SGPlay *play = [SGPlay new];
        play.end = f[0].longLongValue; play.ms = f[1].longLongValue;
        play.uri = f[2]; play.title = f[3]; play.artist = f[4]; play.album = f[5];
        [plays addObject:play];
    }
    return plays;
}

@implementation SGPlayLog {
    NSString *_path;
    dispatch_queue_t _io, _writer;
    NSObject *_journalLock; // only journal append/rotation, erase, and the atomic commit; never bulk work
    BOOL _journalPrepared;
    _Atomic(NSUInteger) _generation;
    NSUInteger _workerGeneration;
    NSUInteger _appliedGeneration; // recorder queue: advances only after erase has run
    NSError *_writerError; // recorder queue only
    // IO queue only.
    NSMutableArray<SGPlay *> *_plays;
    NSMutableSet<NSString *> *_recordIDs;
    BOOL _ready;
    NSError *_loadError;
    // Main only. Records not yet included in an IO snapshot are overlaid when it is published.
    NSMutableArray<SGPlay *> *_visible;
    NSMutableArray<NSDictionary *> *_pending;
    NSError *_publishedError;
    NSUInteger _playsGeneration;
}

- (instancetype)initWithPath:(NSString *)path {
    if ((self = [super init])) {
        _path = [path copy];
        _io = dispatch_queue_create("spotifyglass.history.io", DISPATCH_QUEUE_SERIAL);
        _writer = dispatch_queue_create("spotifyglass.history.recorder", DISPATCH_QUEUE_SERIAL);
        _journalLock = [NSObject new];
        _workerGeneration = NSUIntegerMax;
        _visible = [NSMutableArray array];
        _pending = [NSMutableArray array];
        dispatch_async(_io, ^{
            [self load];
            [self publishWithCompletion:nil announce:NO];
        });
    }
    return self;
}

static NSError *historyPOSIXError(int code, NSString *path) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSFilePathErrorKey: path}];
}

// Acquired on main before enqueueing, released on main after acknowledgement or expiration.
// UIKit gives in-flight journal writes time to finish when Spotify enters the background.
static dispatch_block_t beginHistoryWriteTask(void) {
#if TARGET_OS_IOS
    UIApplication *app = UIApplication.sharedApplication;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    dispatch_block_t finish = ^{
        if (task != UIBackgroundTaskInvalid) {
            [app endBackgroundTask:task];
            task = UIBackgroundTaskInvalid;
        }
    };
    task = [app beginBackgroundTaskWithExpirationHandler:finish];
    return finish;
#else
    return ^{};
#endif
}

// Restrict cleanup to this writer's exact names, including its former bare-UUID staging names.
// Segment ordinals preserve record order across repeated interruptions, independent of wall-clock changes.
typedef NS_ENUM(NSUInteger, SGHistoryFileKind) { SGHistoryOther, SGHistoryStage, SGHistorySegment, SGHistoryActive };
static SGHistoryFileKind historyFileKind(NSString *suffix) {
    if ([suffix isEqual:@"journal"]) return SGHistoryActive;
    NSString *uuid = [suffix hasPrefix:@"stage."] ? [suffix substringFromIndex:6] : suffix;
    if ([[NSUUID alloc] initWithUUIDString:uuid]) return SGHistoryStage;
    if (![suffix hasPrefix:@"journal."]) return SGHistoryOther;
    NSString *ordinal = [suffix substringFromIndex:8];
    if (ordinal.length != 20) return SGHistoryOther;
    for (NSUInteger i = 0; i < ordinal.length; i++) {
        unichar c = [ordinal characterAtIndex:i];
        if (c < '0' || c > '9') return SGHistoryOther;
    }
    return SGHistorySegment;
}

- (NSArray<NSString *> *)ownedFilesOfKind:(SGHistoryFileKind)kind {
    NSString *prefix = [_path.lastPathComponent stringByAppendingString:@"."];
    NSMutableArray *found = [NSMutableArray array];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:_path.stringByDeletingLastPathComponent error:nil]) {
        if (![name hasPrefix:prefix]) continue;
        SGHistoryFileKind actual = historyFileKind([name substringFromIndex:prefix.length]);
        if (actual != SGHistoryOther && (!kind || kind == actual))
            [found addObject:[_path.stringByDeletingLastPathComponent stringByAppendingPathComponent:name]];
    }
    return [found sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<SGPlay *> *)plays { return [_visible copy]; }
- (NSError *)loadError { return _publishedError; }
- (NSUInteger)playsGeneration { return _playsGeneration; }
- (NSArray<SGPlay *> *)playsFromIndex:(NSUInteger)index {
    return [_visible subarrayWithRange:NSMakeRange(index, _visible.count - index)];
}

- (BOOL)drainForTermination {
    dispatch_semaphore_t drained = dispatch_semaphore_create(0);
    __block BOOL saved = NO;
    dispatch_async(_writer, ^{
        saved = self->_writerError == nil;
        dispatch_semaphore_signal(drained);
    });
    // Termination cannot wait for main-queue acknowledgements or a bulk import.
    const int64_t terminationBudgetNanoseconds = NSEC_PER_SEC;
    return dispatch_semaphore_wait(drained, dispatch_time(DISPATCH_TIME_NOW, terminationBudgetNanoseconds)) == 0 && saved;
}

- (void)finishPendingWritesWithCompletion:(void (^)(NSError *))completion {
    dispatch_async(_writer, ^{
        NSError *error = self->_writerError;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    });
}

- (void)publishWithCompletion:(dispatch_block_t)completion announce:(BOOL)announce {
    NSArray *snapshot = [_plays copy] ?: @[];
    NSSet *included = [_recordIDs copy] ?: [NSSet set];
    NSError *error = _loadError;
    NSUInteger generation = _workerGeneration;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation == self->_generation) {
            self->_publishedError = error;
            self->_visible = [snapshot mutableCopy];
            self->_playsGeneration++;
            NSMutableArray *pending = [NSMutableArray array];
            for (NSDictionary *row in self->_pending) {
                if ([included containsObject:row[@"id"]]) continue;
                [pending addObject:row];
                [self->_visible addObject:row[@"play"]];
            }
            self->_pending = pending;
            if (announce) [self changed];
        }
        if (completion) completion();
    });
}

- (void)loadWithCompletion:(void (^)(void))completion {
    dispatch_async(_io, ^{
        BOOL ready = self->_ready;
        NSUInteger generation = self->_workerGeneration;
        [self load];
        if (!ready || generation != self->_workerGeneration) {
            [self publishWithCompletion:completion announce:NO];
        } else if (completion) {
            // load's writer barrier orders completed record acknowledgements before this callback.
            // An already-loaded history has no replacement to publish or copy.
            dispatch_async(dispatch_get_main_queue(), completion);
        }
    });
}

// Bulk imports and startup journal folding only. A per-play record never clones the history.
- (BOOL)append:(NSArray<SGPlay *> *)plays journalRows:(NSString *)rows error:(NSError **)error {
    if (!plays.count && !rows.length) return YES;
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    NSString *temporary = [_path stringByAppendingFormat:@".stage.%@", NSUUID.UUID.UUIDString];
    int failure = 0, source = -1, destination = -1;
    @synchronized (_journalLock) {
        if (_generation != _workerGeneration) failure = ECANCELED;
        else {
            source = open(_path.fileSystemRepresentation, O_RDONLY);
            if (source < 0 && errno != ENOENT) failure = errno;
            if (!failure) {
                destination = open(temporary.fileSystemRepresentation, O_CREAT | O_EXCL | O_RDWR, 0600);
                if (destination < 0) failure = errno;
            }
        }
    }
    // Use open descriptors so erase can unlink a writer's stage even while it is copying.
    // The writer cannot recreate the old pathname after that privacy boundary.
    if (!failure && source >= 0 && fcopyfile(source, destination, NULL, COPYFILE_ALL) != 0) failure = errno;
    if (source >= 0 && close(source) != 0 && !failure) failure = errno;
    NSError *writeError;
    NSFileHandle *handle = destination < 0 ? nil : [[NSFileHandle alloc] initWithFileDescriptor:destination closeOnDealloc:YES];
    unsigned long long end = 0;
    BOOL written = !failure && handle && [handle seekToEndReturningOffset:&end error:&writeError];
    // Old versions appended directly and could leave an unterminated canonical row. Preserve
    // the old loader's interpretation of that row, but never join the first new row to it.
    if (written && end) {
        uint8_t last;
        ssize_t read = pread(destination, &last, 1, (off_t)end - 1);
        if (read != 1) { written = NO; writeError = historyPOSIXError(read < 0 ? errno : EIO, temporary); }
        else if (last != '\n') written = [handle writeData:[NSData dataWithBytes:"\n" length:1] error:&writeError];
    }
    if (written && rows.length) written = [handle writeData:[rows dataUsingEncoding:NSUTF8StringEncoding] error:&writeError];
    for (SGPlay *play in plays) {
        if (!written) break;
        @autoreleasepool {
            written = [handle writeData:[lineOf(play) dataUsingEncoding:NSUTF8StringEncoding] error:&writeError];
        }
    }
    if (written) written = [handle synchronizeAndReturnError:&writeError];
    NSError *closeError;
    if (handle && ![handle closeAndReturnError:&closeError]) { written = NO; writeError = writeError ?: closeError; }
    if (written) {
        @synchronized (_journalLock) {
            if (_generation != _workerGeneration) failure = ECANCELED;
            else if (rename(temporary.fileSystemRepresentation, _path.fileSystemRepresentation) == 0) return YES;
            else failure = errno;
        }
    }
    [files removeItemAtPath:temporary error:nil];
    if (error) *error = writeError ?: historyPOSIXError(failure, _path);
    return NO;
}

// Caller holds the journal lock. Before the first append, isolate any interrupted final row
// from the previous process so it cannot absorb a newly completed play.
- (NSArray<NSString *> *)rotateJournal:(NSError **)error {
    NSArray *segments = [self ownedFilesOfKind:SGHistorySegment];
    unsigned long long next = segments.count ? strtoull([segments.lastObject pathExtension].UTF8String, NULL, 10) + 1 : 1;
    NSString *active = [_path stringByAppendingString:@".journal"];
    NSString *rotated = [_path stringByAppendingFormat:@".journal.%020llu", next];
    if (rename(active.fileSystemRepresentation, rotated.fileSystemRepresentation) == 0) segments = [segments arrayByAddingObject:rotated];
    else if (errno != ENOENT) { *error = historyPOSIXError(errno, active); return nil; }
    _journalPrepared = YES;
    return segments;
}

// A complete journal row carries a recovery identity in column seven. The six-column legacy
// TSV still parses unchanged. Identity, not title/time matching, makes folding exactly-once
// even if a process dies after the canonical rename but before deleting the consumed segment.
- (BOOL)foldJournal:(NSError **)error {
    __block NSArray *segments;
    __block NSError *rotationError;
    // Only the bulk worker waits. Rotation is ordered after all previously enqueued appends
    // and their fsyncs; the recorder never waits for a bulk import.
    dispatch_sync(_writer, ^{
        @synchronized (self->_journalLock) {
            if (self->_generation != self->_workerGeneration) rotationError = historyPOSIXError(ECANCELED, self->_path);
            else segments = [self rotateJournal:&rotationError];
        }
    });
    if (rotationError) *error = rotationError;
    if (!segments) return NO;
    NSMutableString *rows = [NSMutableString string];
    NSMutableSet *ids = [_recordIDs mutableCopy];
    for (NSString *segment in segments) {
        NSData *data = [NSData dataWithContentsOfFile:segment options:0 error:error];
        if (!data) return NO;
        // A process killed inside write() can leave only the final row incomplete.
        const uint8_t *bytes = data.bytes;
        NSUInteger end = data.length;
        while (end && bytes[end - 1] != '\n') end--;
        NSString *text = [[NSString alloc] initWithBytes:bytes length:end encoding:NSUTF8StringEncoding];
        if (!text) { *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil]; return NO; }
        for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
            if (!line.length) continue;
            NSArray *fields = [line componentsSeparatedByString:@"\t"];
            if (fields.count != 7 || ![[NSUUID alloc] initWithUUIDString:fields[6]]) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:nil]; return NO;
            }
            if ([ids containsObject:fields[6]]) continue;
            [ids addObject:fields[6]];
            [rows appendFormat:@"%@\n", line];
        }
    }
    if (![self append:@[] journalRows:rows error:error]) return NO;
    [_plays addObjectsFromArray:playsFromTSV(rows)];
    _recordIDs = ids;
    for (NSString *segment in segments) {
        if (![NSFileManager.defaultManager removeItemAtPath:segment error:error]) return NO;
    }
    return YES;
}

// IO queue only. Initial recovery consumes journals once; ordinary snapshot requests do not
// fold on every song. Later imports fold records completed before their journal rotation.
- (BOOL)load {
    __block NSUInteger generation;
    // Readers include completed recorder writes and cannot race an earlier queued erase.
    dispatch_sync(_writer, ^{ generation = self->_appliedGeneration; });
    if (generation != _workerGeneration) {
        _workerGeneration = generation;
        _ready = NO;
        _plays = nil;
        _recordIDs = nil;
        _loadError = nil;
    }
    if (_ready) return YES;
    NSError *error;
    for (NSString *stage in [self ownedFilesOfKind:SGHistoryStage]) {
        if (![NSFileManager.defaultManager removeItemAtPath:stage error:&error] && error.code != NSFileNoSuchFileError) {
            _loadError = error; return NO;
        }
    }
    NSString *text = [NSString stringWithContentsOfFile:_path encoding:NSUTF8StringEncoding error:&error];
    if ([error.domain isEqual:NSCocoaErrorDomain] && error.code == NSFileReadNoSuchFileError) error = nil;
    _loadError = error;
    if (error) return NO;
    _plays = playsFromTSV(text);
    _recordIDs = [NSMutableSet set];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSArray *fields = [line componentsSeparatedByString:@"\t"];
        if (fields.count == 7 && [[NSUUID alloc] initWithUUIDString:fields[6]]) [_recordIDs addObject:fields[6]];
    }
    if (![self foldJournal:&error]) { _loadError = error; return NO; }
    _ready = YES;
    return YES;
}

- (void)changed {
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayLogDidChangeNotification object:self];
}

// Recorder queue only. Neither the caller nor the UI waits for a write or fsync.
- (BOOL)writeRecordRow:(NSData *)row generation:(NSUInteger)generation error:(NSError **)error {
    NSString *journal = [_path stringByAppendingString:@".journal"];
    @synchronized (_journalLock) {
        if (generation != _generation) { *error = historyPOSIXError(ECANCELED, journal); return NO; }
        if (!_journalPrepared && ![self rotateJournal:error]) return NO;
        if (![NSFileManager.defaultManager createDirectoryAtPath:_path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        int fd = open(journal.fileSystemRepresentation, O_CREAT | O_RDWR | O_APPEND, 0600);
        int failure = fd < 0 ? errno : 0;
        off_t start = fd < 0 ? -1 : lseek(fd, 0, SEEK_END);
        if (fd >= 0 && start < 0) failure = errno;
        NSUInteger written = 0;
        while (!failure && written < row.length) {
            ssize_t n = write(fd, (const uint8_t *)row.bytes + written, row.length - written);
            if (n < 0 && errno == EINTR) continue;
            if (n <= 0) failure = n < 0 ? errno : EIO;
            else written += (NSUInteger)n;
        }
        if (!failure && fsync(fd) != 0) failure = errno;
        if (failure && start >= 0) {
            if (ftruncate(fd, start) != 0 || fsync(fd) != 0)
                NSLog(@"[spotifyglass] history: journal rollback failed: %s", strerror(errno));
        }
        if (fd >= 0 && close(fd) != 0 && !failure) failure = errno;
        if (failure) { *error = historyPOSIXError(failure, journal); return NO; }
    }
    return YES;
}

- (void)record:(SGPlay *)play {
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSString *line = lineOf(play);
    NSData *row = [[[line substringToIndex:line.length - 1] stringByAppendingFormat:@"\t%@\n", identifier] dataUsingEncoding:NSUTF8StringEncoding];
    NSUInteger generation = _generation;
    dispatch_block_t finishTask = beginHistoryWriteTask();
    dispatch_async(_writer, ^{
        NSError *error;
        [self writeRecordRow:row generation:generation error:&error];
        if (generation == self->_generation) self->_writerError = error;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self->_generation) {
                if (error) {
                    NSLog(@"[spotifyglass] history: record not saved: %@", error);
                } else {
                    [self->_pending addObject:@{@"id":identifier, @"play":play}];
                    [self->_visible addObject:play];
                }
                [self changed];
            }
            finishTask();
        });
    });
}

// A bucket spans the inclusive tolerance plus one second. Same-bucket timestamps always match;
// only the closest timestamp in either adjacent bucket can match across its boundary.
enum { SGHistoryMatchSeconds = 90, SGHistoryBucketSeconds = SGHistoryMatchSeconds + 1 };
static int64_t timeBucket(int64_t end) {
    int64_t bucket = end / SGHistoryBucketSeconds;
    return end < 0 && end % SGHistoryBucketSeconds ? bucket - 1 : bucket;
}
static void indexEnd(NSMutableDictionary *ends, NSString *key, int64_t end) {
    NSMutableDictionary *buckets = ends[key];
    if (!buckets) ends[key] = buckets = [NSMutableDictionary dictionary];
    NSNumber *bucket = @(timeBucket(end));
    NSArray *bounds = buckets[bucket];
    buckets[bucket] = bounds ? @[@(MIN(end, [bounds[0] longLongValue])), @(MAX(end, [bounds[1] longLongValue]))] : @[@(end), @(end)];
}
static BOOL hasNearbyEnd(NSDictionary *buckets, int64_t end) {
    int64_t bucket = timeBucket(end);
    if (buckets[@(bucket)]) return YES;
    NSArray *before = buckets[@(bucket - 1)], *after = buckets[@(bucket + 1)];
    return (before && end - [before[1] longLongValue] <= SGHistoryMatchSeconds) ||
           (after && [after[0] longLongValue] - end <= SGHistoryMatchSeconds);
}

- (NSUInteger)mergeOnQueue:(NSArray<SGPlay *> *)incoming error:(NSError **)error {
    if (![self load]) { *error = _loadError; return 0; }
    if (![self foldJournal:error]) return 0;
    BOOL needsExact = [incoming indexOfObjectPassingTest:^BOOL(SGPlay *play, NSUInteger index, BOOL *stop) {
        return play.exactImport;
    }] != NSNotFound;
    NSMutableDictionary *ends = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *exact = needsExact ? [NSMutableSet set] : nil;
    // An exact import matches on the persisted line itself, field normalization included; NSString's
    // content hash keeps million-row imports linear instead of making equal-length tuple arrays collide.
    for (SGPlay *play in _plays) {
        indexEnd(ends, SGTrackKey(play), play.end);
        if (needsExact) [exact addObject:lineOf(play)];
    }
    NSMutableArray<SGPlay *> *added = [NSMutableArray array];
    for (SGPlay *play in incoming) {
        NSString *key = SGTrackKey(play);
        NSString *exactKey = needsExact ? lineOf(play) : nil;
        BOOL have = play.exactImport && [exact containsObject:exactKey];
        if (!play.exactImport) have = hasNearbyEnd(ends[key], play.end);
        if (have) continue;
        indexEnd(ends, key, play.end);
        if (needsExact) [exact addObject:exactKey];
        [added addObject:play];
    }
    if (![self append:added journalRows:nil error:error]) return 0;
    [_plays addObjectsFromArray:added];
    return added.count;
}

- (void)merge:(NSArray<SGPlay *> *)incoming completion:(void (^)(NSUInteger, NSError *))completion {
    NSArray *snapshot = [incoming copy];
    dispatch_async(_io, ^{
        NSError *error;
        NSUInteger added = [self mergeOnQueue:snapshot error:&error];
        [self publishWithCompletion:^{ completion(added, error); } announce:added > 0];
    });
}

- (void)erase {
    NSUInteger generation = ++_generation;
    _playsGeneration++;
    _publishedError = nil;
    [_visible removeAllObjects];
    [_pending removeAllObjects];
    dispatch_block_t finishTask = beginHistoryWriteTask();
    dispatch_async(_writer, ^{
        NSError *failure;
        @synchronized (self->_journalLock) {
            for (NSString *file in [[self ownedFilesOfKind:SGHistoryOther] arrayByAddingObject:self->_path]) {
                NSError *error;
                if (![NSFileManager.defaultManager removeItemAtPath:file error:&error] && error.code != NSFileNoSuchFileError)
                    failure = failure ?: error;
            }
            self->_journalPrepared = NO;
        }
        self->_writerError = failure;
        self->_appliedGeneration = generation;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self->_generation) {
                self->_publishedError = failure;
                if (failure) NSLog(@"[spotifyglass] history: erase failed: %@", failure);
                [self changed];
            }
            finishTask();
        });
    });
    [self changed];
}

@end

#pragma mark - stats

NSComparisonResult SGTopOrder(SGStatEntry *a, SGStatEntry *b) {
    if (a.plays != b.plays) return a.plays > b.plays ? NSOrderedAscending : NSOrderedDescending;
    if (a.ms != b.ms) return a.ms > b.ms ? NSOrderedAscending : NSOrderedDescending;
    return [a.name localizedCaseInsensitiveCompare:b.name];
}

static NSArray<SGStatEntry *> *topOf(NSDictionary<NSString *, SGStatEntry *> *entries, NSUInteger top) {
    NSArray<SGStatEntry *> *sorted = [entries.allValues sortedArrayUsingComparator:^NSComparisonResult(SGStatEntry *a, SGStatEntry *b) {
        return SGTopOrder(a, b);
    }];
    return [sorted subarrayWithRange:NSMakeRange(0, MIN(top, sorted.count))];
}

static void count(NSMutableDictionary<NSString *, SGStatEntry *> *entries, NSString *key, NSString *name, NSString *detail, SGPlay *play) {
    SGStatEntry *entry = entries[key];
    if (!entry) {
        entry = [SGStatEntry new];
        entry.name = name;
        entry.detail = detail;
        entries[key] = entry;
    }
    entry.plays++;
    entry.ms += play.ms;
}

// Tracks go by title and artist rather than URI: the basic export has no URIs, and a track's URI can
// differ between its single and its album.
SGStats *SGStatsSince(NSArray<SGPlay *> *plays, int64_t since, NSUInteger top) {
    return SGStatsBetween(plays, since, INT64_MAX, top);
}

SGStats *SGStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSUInteger top) {
    NSMutableDictionary<NSString *, SGStatEntry *> *tracks = [NSMutableDictionary dictionary], *artists = [NSMutableDictionary dictionary],
                                                   *albums = [NSMutableDictionary dictionary];
    SGStats *stats = [SGStats new];
    for (SGPlay *play in plays) {
        if (play.end < start || (end != INT64_MAX && play.end >= end)) continue;
        stats.plays++;
        stats.ms += play.ms;
        NSString *artist = play.artist.lowercaseString;
        count(tracks, SGTrackKey(play), play.title, play.artist, play);
        count(artists, artist, play.artist, nil, play);
        if (play.album.length) count(albums, [NSString stringWithFormat:@"%@\x1f%@", play.album.lowercaseString, artist], play.album, play.artist, play);
    }
    stats.tracks = topOf(tracks, top);
    stats.artists = topOf(artists, top);
    stats.albums = topOf(albums, top);
    return stats;
}

SGListeningStreaks *SGStreaks(NSArray<SGPlay *> *plays, NSDate *now, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSDate *today = [cal startOfDayForDate:now];
    NSMutableSet<NSDate *> *days = [NSMutableSet set];
    for (SGPlay *play in plays) {
        // NSDate/Calendar cannot represent arbitrary int64 timestamps from a damaged legacy log.
        if (play.end < -62135596800LL || play.end > 253402300799LL) continue;
        NSDate *day = [cal startOfDayForDate:[NSDate dateWithTimeIntervalSince1970:play.end]];
        if (day && [day compare:today] != NSOrderedDescending) [days addObject:day];
    }
    SGListeningStreaks *result = [SGListeningStreaks new];
    NSUInteger run = 0;
    NSDate *previous, *runStart;
    for (NSDate *day in [days.allObjects sortedArrayUsingSelector:@selector(compare:)]) {
        NSDate *next = previous ? [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:previous options:0] : nil;
        if (next) next = [cal startOfDayForDate:next]; // Some zones skip midnight at DST start.
        run = [next isEqualToDate:day] ? run + 1 : 1;
        if (run == 1) runStart = day;
        if (run >= result.best) {
            result.best = run;
            result.bestStart = runStart;
            result.bestEnd = day;
        }
        previous = day;
    }
    NSDate *last = [days containsObject:today] ? today : [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:today options:0];
    if (last) last = [cal startOfDayForDate:last];
    while (last && [days containsObject:last]) {
        if (!result.current) result.currentEnd = last;
        result.currentStart = last;
        result.current++;
        last = [cal dateByAddingUnit:NSCalendarUnitDay value:-1 toDate:last options:0];
        if (last) last = [cal startOfDayForDate:last];
    }
    return result;
}

NSArray<SGStatEntry *> *SGHourlyStats(NSArray<SGPlay *> *plays, int64_t since, NSCalendar *calendar) {
    return SGHourlyStatsBetween(plays, since, INT64_MAX, calendar);
}

NSArray<SGStatEntry *> *SGHourlyStatsBetween(NSArray<SGPlay *> *plays, int64_t start, int64_t end, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSMutableArray<SGStatEntry *> *hours = [NSMutableArray arrayWithCapacity:24];
    for (NSUInteger i = 0; i < 24; i++) [hours addObject:[SGStatEntry new]];
    for (SGPlay *play in plays) {
        if (play.end < start || play.end >= end || play.end < -62135596800LL || play.end > 253402300799LL) continue;
        NSInteger hour = [cal component:NSCalendarUnitHour fromDate:[NSDate dateWithTimeIntervalSince1970:play.end]];
        if (hour < 0 || hour > 23) continue;
        hours[hour].plays++;
        hours[hour].ms += play.ms;
    }
    return hours;
}

#pragma mark - calendar periods

static NSCalendarUnit periodUnit(SGStatsPeriod period) {
    return period == SGStatsPeriodYear ? NSCalendarUnitYear : period == SGStatsPeriodMonth ? NSCalendarUnitMonth : NSCalendarUnitWeekOfYear;
}

static int64_t unixSeconds(NSDate *date) {
    return (int64_t)floor(date.timeIntervalSince1970);
}

// The unit holding `date`, as [its start, the next one's start). The next start is looked up from a date one
// unit past the middle of this one, so neither a DST hour, a skipped midnight nor a short month can land
// it in the wrong unit, and the unit's length is the calendar's rather than a fixed count of seconds.
static NSDateInterval *unitInterval(NSCalendar *cal, NSCalendarUnit unit, NSDate *date) {
    NSDate *start, *next;
    NSTimeInterval length = 0, nextLength = 0;
    if (!date || ![cal rangeOfUnit:unit startDate:&start interval:&length forDate:date]) return nil;
    NSDate *ahead = [cal dateByAddingUnit:unit value:1 toDate:[start dateByAddingTimeInterval:length / 2] options:0];
    if (!ahead || ![cal rangeOfUnit:unit startDate:&next interval:&nextLength forDate:ahead] ||
        [next compare:start] != NSOrderedDescending) return nil;
    return [[NSDateInterval alloc] initWithStartDate:start endDate:next];
}

NSDateInterval *SGPeriodInterval(SGStatsPeriod period, NSDate *date, NSCalendar *calendar) {
    return unitInterval([calendar copy], periodUnit(period), date);
}

NSDateInterval *SGPeriodStep(SGStatsPeriod period, NSDate *date, NSInteger steps, NSCalendar *calendar) {
    NSCalendar *cal = [calendar copy];
    NSCalendarUnit unit = periodUnit(period);
    NSDateInterval *shown = unitInterval(cal, unit, date);
    if (!shown) return nil;
    // From the middle, so stepping a month never clamps (the 31st) and a week never meets a skipped midnight.
    NSDate *middle = [shown.startDate dateByAddingTimeInterval:shown.duration / 2];
    return unitInterval(cal, unit, [cal dateByAddingUnit:unit value:steps toDate:middle options:0]);
}

NSArray<SGStatBucket *> *SGPeriodBuckets(NSArray<SGPlay *> *plays, SGStatsPeriod period, NSDate *date, NSCalendar *calendar) {
    enum { most = 64 };   // 31 days, or 13 months in a Hebrew leap year
    NSCalendar *cal = [calendar copy];
    NSDateInterval *whole = unitInterval(cal, periodUnit(period), date);
    NSMutableArray<SGStatBucket *> *buckets = [NSMutableArray array];
    if (!whole) return buckets;
    NSCalendarUnit part = period == SGStatsPeriodYear ? NSCalendarUnitMonth : NSCalendarUnitDay;
    int64_t starts[most], end = unixSeconds(whole.endDate);
    NSDate *at = whole.startDate;
    while (buckets.count < most && [at compare:whole.endDate] == NSOrderedAscending) {
        NSDateInterval *piece = unitInterval(cal, part, at);
        if (!piece) break;
        SGStatBucket *bucket = [SGStatBucket new];
        bucket.start = unixSeconds(at);
        bucket.end = MIN(unixSeconds(piece.endDate), end);
        starts[buckets.count] = bucket.start;
        [buckets addObject:bucket];
        at = piece.endDate;
    }
    NSUInteger n = buckets.count;
    if (!n) return buckets;
    int64_t first = starts[0], last = buckets[n - 1].end;
    for (SGPlay *play in plays) {
        if (play.end < first || play.end >= last) continue;
        NSUInteger lo = 0, hi = n;   // the last bucket starting at or before the play's end
        while (hi - lo > 1) {
            NSUInteger mid = (lo + hi) / 2;
            if (starts[mid] <= play.end) lo = mid; else hi = mid;
        }
        buckets[lo].plays++;
        buckets[lo].ms += play.ms;
    }
    return buckets;
}
