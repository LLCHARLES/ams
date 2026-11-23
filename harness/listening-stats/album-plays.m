// Offline integration of the public log cursor with the album's asynchronous aggregation.
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Redesigned/Album/Album.h"
#import "../harness-fail.h"

static SGPlayLog *history;
SGPlayLog *SGListeningLog(void) { return history; }

static void waitFor(BOOL (^condition)(void), NSString *what) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    if (!condition()) HARNESS_FAIL(@"Timed out: %@", what);
}

static void loaded(void) {
    __block BOOL done = NO;
    [history loadWithCompletion:^{ done = YES; }];
    waitFor(^BOOL { return done; }, @"history load");
    HARNESS_CHECK(!history.loadError);
}

static SGPlay *play(int64_t end, NSString *title) {
    SGPlay *value = [SGPlay new];
    value.end = end; value.ms = 30000;
    value.uri = @"spotify:track:test"; value.title = title;
    value.artist = @"Artist"; value.album = @"Album";
    return value;
}

static void recorded(SGPlay *value) {
    [history record:value];
    __block BOOL done = NO;
    [history finishPendingWritesWithCompletion:^(NSError *error) {
        HARNESS_CHECK(!error);
        done = YES;
    }];
    waitFor(^BOOL { return done; }, @"record acknowledgement");
}

static void countIs(NSUInteger expected, NSString *title) {
    waitFor(^BOOL { return SGRAlbumPlayCount(@"Album", title) == expected; },
            [NSString stringWithFormat:@"%@ count = %lu", title, (unsigned long)expected]);
}

int main(void) {
    @autoreleasepool {
        char directory[] = "/tmp/retrine-album-plays.XXXXXX";
        HARNESS_CHECK(mkdtemp(directory) != NULL);
        NSString *root = [NSString stringWithUTF8String:directory];
        history = [[SGPlayLog alloc] initWithPath:[root stringByAppendingPathComponent:@"plays.tsv"]];
        loaded();
        recorded(play(1000, @"Track"));
        recorded(play(1200, @"Track"));
        countIs(2, @"Track");
        NSUInteger generation = history.playsGeneration;
        recorded(play(1400, @"Track"));
        loaded();
        HARNESS_CHECK(history.playsGeneration == generation);
        NSArray<SGPlay *> *suffix = [history playsFromIndex:2];
        HARNESS_CHECK(suffix.count == 1 && suffix.firstObject.end == 1400);
        countIs(3, @"Track");
        puts("PASS append preserves generation, exposes one-play suffix, and totals three plays");

        __block BOOL merged = NO;
        [history merge:@[play(100, @"Imported")] completion:^(NSUInteger added, NSError *error) {
            HARNESS_CHECK(!error && added == 1);
            merged = YES;
        }];
        waitFor(^BOOL { return merged; }, @"import");
        HARNESS_CHECK(history.playsGeneration != generation);
        HARNESS_CHECK([history playsFromIndex:0].count == 4);
        countIs(1, @"Imported");
        countIs(3, @"Track");
        puts("PASS import replaces generation and recounts the complete history");

        generation = history.playsGeneration;
        [history erase];
        HARNESS_CHECK(history.playsGeneration != generation);
        HARNESS_CHECK([history playsFromIndex:0].count == 0);
        countIs(0, @"Imported");
        countIs(0, @"Track");
        recorded(play(1600, @"Track"));
        countIs(1, @"Track");
        puts("PASS erase drops prior counts and subsequent recording starts at one");
        HARNESS_CHECK([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        puts("album-plays: all passed");
    }
    return 0;
}
