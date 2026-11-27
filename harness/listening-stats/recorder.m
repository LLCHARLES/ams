// The production Logos recorder with fake player reports and an injected continuous clock.
#import "Shared/ListeningStats/ListeningStats.h"
#import "Shared/ListeningStats/SGPlayLog.h"
#import "Shared/Player/PlayerState.h"
#import "Core/SGPrefs.h"
#import <mach/mach_time.h>

#define CHECK(c) do { if (!(c)) { fprintf(stderr, "FAILED recorder line %d: %s\n", __LINE__, #c); exit(1); } } while (0)

static id<SGPlayerStateObserver> observer;
static uint64_t ticks;
uint64_t mach_continuous_time(void) { return ticks; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> value) { observer = value; }
NSString *SGURIString(id uri) { return [uri isKindOfClass:NSString.class] ? uri : [uri absoluteString]; }

@interface RecorderTrack : NSObject
@property(nonatomic, copy) NSString *URI, *trackTitle, *artistName;
@property(nonatomic, copy) NSDictionary *metadata;
@end
@implementation RecorderTrack @end
@interface RecorderState : NSObject
@property(nonatomic, strong) RecorderTrack *track;
@property(nonatomic, copy) NSString *playbackId;
@property(nonatomic) BOOL isPlaying, isPaused, isLoading;
@property(nonatomic) double duration;
@end
@implementation RecorderState @end

static SPTPlayerState *state(NSString *uri, NSString *title, NSString *artist) {
    RecorderTrack *track = [RecorderTrack new];
    track.URI = uri; track.trackTitle = title; track.artistName = artist;
    track.metadata = artist ? @{@"artist_name": artist, @"album_title": @"Late album"} : @{};
    RecorderState *state = [RecorderState new];
    state.track = track; state.isPlaying = YES; state.duration = 200;
    return (SPTPlayerState *)state;
}
static SPTPlayerState *stateWithID(NSString *uri, NSString *playbackID) {
    RecorderState *result = (RecorderState *)state(uri, uri, @"Artist");
    result.playbackId = playbackID;
    return (SPTPlayerState *)result;
}
static void setElapsed(uint64_t seconds) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    ticks = seconds * NSEC_PER_SEC * timebase.denom / timebase.numer;
}

static void recording(BOOL enabled) {
    SGSetEnabled(SGKeyListeningStats, enabled);
    // Deliver the defaults contract deterministically, including on a worker.
    // An automatic duplicate notification must not reset an enabled interval.
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
}

static NSArray<SGPlay *> *recordedPlays(void) {
    __block BOOL done = NO;
    [SGListeningLog() finishPendingWritesWithCompletion:^(NSError *error) {
        CHECK(!error); done = YES;
    }];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!done && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(done);
    return SGListeningLog().plays;
}

static void drainMain(void) {
    __block BOOL applied = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ applied = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!applied && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(applied);
}

int main(void) { @autoreleasepool {
    CHECK(observer && [observer respondsToSelector:@selector(playerStateDidReport:)]);
    // The switch persists in this process's defaults and the last run leaves it off.
    recording(YES);
    setElapsed(100);
    [observer playerStateDidChange:state(@"spotify:track:first", nil, nil)];
    setElapsed(120);
    [observer playerStateDidReport:state(@"spotify:track:unrelated", @"Wrong title", @"Wrong artist")];
    [observer playerStateDidReport:state(@"spotify:track:first", @"Late title", @"Late artist")];
    setElapsed(140);
    SPTPlayerState *next = state(@"spotify:track:second", @"Next title", @"Next artist");
    [observer playerStateDidReport:next]; // PlayerState reports before announcing the transition
    [observer playerStateDidChange:next];
    NSArray<SGPlay *> *plays = recordedPlays();
    CHECK(plays.count == 1);
    SGPlay *play = plays.firstObject;
    CHECK(play.ms == 40000 && [play.uri isEqual:@"spotify:track:first"]);
    CHECK([play.title isEqual:@"Late title"] && [play.artist isEqual:@"Late artist"] && [play.album isEqual:@"Late album"]);
    puts("recorder: metadata-only reports enrich exactly one forty-second play; unrelated reports do not overwrite it");

    // MEDIA-01: off -> play forty seconds -> pause -> on -> skip saves nothing.
    recording(NO);
    [observer playerStateDidChange:state(@"spotify:track:disabled", @"Disabled", @"Artist")];
    setElapsed(180);
    RecorderState *paused = (RecorderState *)state(@"spotify:track:disabled", @"Disabled", @"Artist");
    paused.isPaused = YES;
    [observer playerStateDidChange:(SPTPlayerState *)paused];
    recording(YES);
    [observer playerStateDidChange:state(@"spotify:track:enabled", @"Enabled", @"Artist")];
    CHECK(recordedPlays().count == 1);
    puts("recorder: disabled listening is not saved by enabling while paused");

    setElapsed(220);
    [observer playerStateDidChange:state(@"spotify:track:waiting", @"Waiting", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 2 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:enabled"]);
    puts("recorder: a qualifying play after enabling still records");

    // Enabling while already playing must not wait for another player callback.
    recording(NO);
    [observer playerStateDidChange:state(@"spotify:track:in-progress", @"In progress", @"Artist")];
    setElapsed(260);
    recording(YES);
    setElapsed(280);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"harness.unrelated"];
    [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
    setElapsed(300);
    [observer playerStateDidChange:state(@"spotify:track:before-off", @"Before off", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 3 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:in-progress"]);
    puts("recorder: enabling mid-play starts at the boundary; unrelated preferences do not split it");

    setElapsed(340);
    recording(NO);
    plays = recordedPlays();
    CHECK(plays.count == 4 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:before-off"]);
    setElapsed(400);
    recording(YES);
    setElapsed(410);
    [observer playerStateDidChange:state(@"spotify:track:worker", @"Worker", @"Artist")];
    CHECK(recordedPlays().count == 4);
    puts("recorder: disabling finishes enabled time; re-enabling resets the threshold");

    // Main is busy for a worker's off/on pair. Neither notification may wait
    // for main, and the captured values/times must retain the disabled gap.
    dispatch_semaphore_t posted = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        setElapsed(420);
        recording(NO);
        setElapsed(460);
        recording(YES);
        dispatch_semaphore_signal(posted);
    });
    CHECK(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0);
    drainMain();
    setElapsed(500);
    [observer playerStateDidChange:state(@"spotify:track:last", @"Last", @"Artist")];
    plays = recordedPlays();
    CHECK(plays.count == 5 && plays.lastObject.ms == 40000 &&
          [plays.lastObject.uri isEqual:@"spotify:track:worker"]);
    puts("recorder: worker-thread off/on notifications preserve the gap without blocking on main");

    // A worker captures YES while main is busy. Main then switches recording
    // off synchronously, before draining that older YES from the main queue.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:NSUserDefaultsDidChangeNotification object:nil];
        dispatch_semaphore_signal(posted);
    });
    CHECK(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0);
    setElapsed(510);
    recording(NO);
    drainMain();
    setElapsed(550);
    [observer playerStateDidChange:state(@"spotify:track:still-off", @"Still off", @"Artist")];
    CHECK(recordedPlays().count == 5);
    puts("recorder: an older queued YES cannot override a synchronous NO or save disabled listening");

    // The same URI again is told apart by the state's playbackId, which no announced flag follows, so these
    // arrive as reports only. Time moves only through setElapsed, from a recording start with no play.
    setElapsed(600);
    recording(YES);
    NSUInteger base = recordedPlays().count;
    NSString *repeated = @"spotify:track:repeated";
    [observer playerStateDidChange:stateWithID(repeated, @"a0301e2f")];
    setElapsed(640);
    [observer playerStateDidReport:stateWithID(repeated, @"3f073725")]; // first wrap
    setElapsed(690);
    [observer playerStateDidReport:stateWithID(repeated, @"9df725c3")]; // second wrap
    setElapsed(725);
    [observer playerStateDidReport:stateWithID(repeated, @"16c4b020")]; // third wrap
    setElapsed(735); // the fourth lap is stopped after 10 s, too short to count
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-repeat", @"5a5a5a5a")];
    plays = recordedPlays();
    CHECK(plays.count == base + 3);
    CHECK(plays[base].ms == 40000 && plays[base + 1].ms == 50000 && plays[base + 2].ms == 35000);
    for (NSUInteger i = base; i < base + 3; i++) CHECK([plays[i].uri isEqual:repeated]);
    puts("recorder: three repeat-one wraps of one URI record three plays with their own durations");

    // A seek to 0 is a report with the same playbackId: one play of 20 s + 20 s.
    setElapsed(800);
    [observer playerStateDidReport:stateWithID(@"spotify:track:after-repeat", @"5a5a5a5a")];
    [observer playerStateDidChange:stateWithID(@"spotify:track:seeked", @"7b7b7b7b")];
    setElapsed(820);
    [observer playerStateDidReport:stateWithID(@"spotify:track:seeked", @"7b7b7b7b")];
    setElapsed(840);
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-seek", @"8c8c8c8c")];
    plays = recordedPlays();
    CHECK(plays.count == base + 5 && plays.lastObject.ms == 40000 && [plays.lastObject.uri isEqual:@"spotify:track:seeked"]);
    puts("recorder: a seek to 0 keeps the playbackId and the play whole");

    // Without a playbackId the URI alone decides, as before.
    setElapsed(900);
    [observer playerStateDidChange:stateWithID(@"spotify:track:no-id", nil)];
    setElapsed(920);
    [observer playerStateDidReport:stateWithID(@"spotify:track:no-id", nil)];
    setElapsed(940);
    [observer playerStateDidReport:stateWithID(@"spotify:track:no-id", @"")];
    setElapsed(960);
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-no-id", nil)];
    plays = recordedPlays();
    CHECK(plays.count == base + 7 && plays.lastObject.ms == 60000 && [plays.lastObject.uri isEqual:@"spotify:track:no-id"]);
    puts("recorder: a missing or empty playbackId leaves one play per URI");

    // The same track queued twice: the second item's report carries a new playbackId, then the flags may follow.
    setElapsed(1000);
    [observer playerStateDidChange:stateWithID(@"spotify:track:twice", @"d1d1d1d1")];
    setElapsed(1040);
    SPTPlayerState *second = stateWithID(@"spotify:track:twice", @"d2d2d2d2");
    [observer playerStateDidReport:second];
    [observer playerStateDidChange:second];
    setElapsed(1075);
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-twice", @"d3d3d3d3")];
    plays = recordedPlays();
    CHECK(plays.count == base + 10);
    CHECK(plays[base + 8].ms == 40000 && plays[base + 9].ms == 35000);
    CHECK([plays[base + 8].uri isEqual:@"spotify:track:twice"] && [plays[base + 9].uri isEqual:@"spotify:track:twice"]);
    puts("recorder: the same track queued twice in a row records two plays");

    // The playbackId first appears in a report, with no change callback after it: later wraps still split.
    setElapsed(1100);
    [observer playerStateDidChange:stateWithID(@"spotify:track:late-id", nil)];
    base = recordedPlays().count;
    setElapsed(1120);
    [observer playerStateDidReport:stateWithID(@"spotify:track:late-id", @"e1e1e1e1")];
    setElapsed(1140);
    [observer playerStateDidReport:stateWithID(@"spotify:track:late-id", @"e2e2e2e2")]; // wrap
    setElapsed(1175);
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-late-id", @"e3e3e3e3")];
    plays = recordedPlays();
    CHECK(plays.count == base + 2 && plays[base].ms == 40000 && plays[base + 1].ms == 35000);
    puts("recorder: a playbackId first seen in a report is adopted, so the next wrap records a second play");

    // Reports can arrive out of order: B, then an older A, then B again is one wrap, not three.
    setElapsed(1200);
    [observer playerStateDidChange:stateWithID(@"spotify:track:reordered", @"f1f1f1f1")];
    base = recordedPlays().count;
    setElapsed(1240);
    [observer playerStateDidReport:stateWithID(@"spotify:track:reordered", @"f2f2f2f2")]; // B
    setElapsed(1250);
    [observer playerStateDidReport:stateWithID(@"spotify:track:reordered", @"f1f1f1f1")]; // late A
    setElapsed(1260);
    [observer playerStateDidReport:stateWithID(@"spotify:track:reordered", @"f2f2f2f2")]; // B
    setElapsed(1290);
    [observer playerStateDidChange:stateWithID(@"spotify:track:after-reordered", @"f3f3f3f3")];
    plays = recordedPlays();
    CHECK(plays.count == base + 2 && plays[base].ms == 40000 && plays[base + 1].ms == 50000);
    CHECK([plays[base].uri isEqual:@"spotify:track:reordered"] && [plays[base + 1].uri isEqual:@"spotify:track:reordered"]);
    puts("recorder: a late report of the finished playbackId neither splits the play nor loses its time");

    // A deliberate restart exits without UIApplicationWillTerminateNotification: the step before its exit(0)
    // must write the 40 s play in progress, which a log opened afresh then holds exactly once.
    setElapsed(1300);
    [observer playerStateDidChange:stateWithID(@"spotify:track:restarting", @"a1a1a1a1")];
    NSUInteger beforeRestart = recordedPlays().count;
    setElapsed(1340);
    SGRestartPrepareExit();
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    SGPlayLog *reopened = [[SGPlayLog alloc] initWithPath:[support stringByAppendingPathComponent:@"Retrine/Listening.tsv"]];
    __block BOOL loaded = NO;
    [reopened loadWithCompletion:^{ loaded = YES; }];
    NSDate *loadDeadline = [NSDate dateWithTimeIntervalSinceNow:60];
    while (!loaded && loadDeadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    CHECK(loaded && !reopened.loadError);
    NSUInteger restarted = 0;
    for (SGPlay *reopenedPlay in reopened.plays)
        if ([reopenedPlay.uri isEqual:@"spotify:track:restarting"]) {
            restarted++;
            CHECK(reopenedPlay.ms == 40000);
        }
    CHECK(restarted == 1 && reopened.plays.count == beforeRestart + 1);
    puts("recorder: a restart's pre-exit step writes the 40 s play in progress, once");
    return 0;
} }
