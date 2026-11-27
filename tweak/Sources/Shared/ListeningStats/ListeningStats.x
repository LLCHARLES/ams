// ListeningStats.h says what Listening stats is. This is the recording: PlayerState's observer is told
// when the track or playing changes, never the position, so a play's length is the continuous time it
// spent playing, and it is written down when the next track takes over. The same track again, on repeat one
// or queued twice in a row, keeps its URI but gets a new playbackId, which changes no flag the observer
// announces, so that boundary is taken from the reports. A seek keeps the playbackId and splits nothing.
//
// A play in progress is also written down when the app terminates or the mod restarts it (SGWillRestartNotification).
// ponytail: a play cut off by Spotify being killed is lost; position polling would catch it.
#import "Core/SGCore.h"
#import "Core/SGDataRoot.h"
#import "Shared/Player/PlayerState.h"
#import "ListeningStats.h"
#import "SGPlayLog.h"
#import <mach/mach_time.h>
#import <stdatomic.h>

static NSTimeInterval continuousSeconds(void) {
    static mach_timebase_info_data_t timebase;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ mach_timebase_info(&timebase); });
    return (double)mach_continuous_time() * timebase.numer / timebase.denom / NSEC_PER_SEC;
}

static SGPlayLog *sg_log;

SGPlayLog *SGListeningLog(void) {
    if (!sg_log) {
        NSURL *file = [SGDataRoot(NSApplicationSupportDirectory) URLByAppendingPathComponent:@"Listening.tsv"];
        if (file) sg_log = [[SGPlayLog alloc] initWithPath:file.path];
    }
    return sg_log;
}

NSString *SGListeningStatsSummary(void) {
    if (!SGEnabled(SGKeyListeningStats)) return SGL(@"common.off", @"Off");
    // Opening settings shouldn't load the listening history just to count it.
    if (!sg_log.playsGeneration || sg_log.loadError) return SGL(@"common.on", @"On");
    return @(sg_log.plays.count).stringValue;
}

static NSString *stringIn(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

// The playback instance of a state, nil when this Spotify does not give one.
static NSString *playbackIDOf(SPTPlayerState *state) {
    SEL selector = NSSelectorFromString(@"playbackId");
    if (![state respondsToSelector:selector]) return nil;
    NSString *playbackID = stringIn([(NSObject *)state valueForKey:@"playbackId"]);
    return playbackID.length ? playbackID : nil;
}

@interface SGPlayRecorder : NSObject <SGPlayerStateObserver>
@end

@implementation SGPlayRecorder {
    SGPlay *_play;
    double _duration;
    SGPlayClock *_clock;
    NSString *_playbackID; // the playing one's, nil until a state gives it
    NSString *_finishedPlaybackID; // the one finished last: a late report of it is stale, not a replay
    SPTPlayerState *_state;
    BOOL _recordingEnabled;
}

- (instancetype)init {
    if ((self = [super init])) _recordingEnabled = SGEnabled(SGKeyListeningStats);
    return self;
}

// Songs and local files; not ads, episodes or the silence between.
static BOOL isMusic(NSString *uri) {
    return [uri hasPrefix:@"spotify:track:"] || [uri hasPrefix:@"spotify:local:"];
}

// The metadata can come after the track does, so what is missing is filled in on every report.
- (void)fill:(SPTPlayerState *)state {
    SPTPlayerTrack *track = state.track;
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    if (!_play.title.length) _play.title = stringIn(track.trackTitle) ?: stringIn(metadata[@"title"]) ?: @"";
    if (!_play.artist.length) _play.artist = stringIn(metadata[@"artist_name"]) ?: stringIn(track.artistName) ?: @"";
    if (!_play.album.length) _play.album = stringIn(metadata[@"album_title"]) ?: @"";
    if (_duration <= 0) _duration = state.duration;
}

- (void)finish {
    if (_play && _play.title.length && _play.artist.length && SGPlayCounts(_clock.listenedSeconds, _duration)) {
        _play.end = (int64_t)_clock.endedAt;
        _play.ms = (int64_t)(_clock.listenedSeconds * 1000);
        [SGListeningLog() record:_play];
    }
    _play = nil;
    _clock = nil;
    _finishedPlaybackID = _playbackID;
    _playbackID = nil;
}

// The playing track began again: same URI, a different playback instance. Reports from other threads can
// arrive late, so the id of the play just finished never starts one.
- (BOOL)replayedIn:(SPTPlayerState *)state {
    NSString *playbackID = playbackIDOf(state);
    return _playbackID && playbackID && ![playbackID isEqualToString:_playbackID] &&
        ![playbackID isEqualToString:_finishedPlaybackID];
}

- (void)playerStateDidReport:(SPTPlayerState *)state {
    _state = state;
    if (![SGURIString(state.track.URI) isEqualToString:_play.uri]) return;
    if ([self replayedIn:state]) {
        [self updateState:state elapsed:continuousSeconds() at:NSDate.date.timeIntervalSince1970];
        return;
    }
    if (!_playbackID) _playbackID = playbackIDOf(state);
    [self fill:state];
}

- (void)updateState:(SPTPlayerState *)state elapsed:(NSTimeInterval)elapsed at:(NSTimeInterval)now {
    _state = state;
    if (!_recordingEnabled) return;
    [_clock setPlaying:NO elapsed:elapsed at:now];
    NSString *uri = SGURIString(state.track.URI);
    if (![uri isEqualToString:_play.uri] || [self replayedIn:state]) {
        [self finish];
        if (isMusic(uri)) {
            _play = [SGPlay new];
            _play.uri = uri;
            _duration = 0;
            _clock = [SGPlayClock new];
        }
    }
    if (!_play) return;
    if (!_playbackID) _playbackID = playbackIDOf(state);
    [self fill:state];
    BOOL loading = [state respondsToSelector:@selector(isLoading)] && state.isLoading;
    [_clock setPlaying:state.isPlaying && !state.isPaused && !loading elapsed:elapsed at:now];
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    [self updateState:state elapsed:continuousSeconds() at:NSDate.date.timeIntervalSince1970];
}

// Only enabled intervals own a play. Finish the old interval before changing
// consent, then start afresh from the latest state without waiting for a report.
- (void)recordingChanged:(BOOL)enabled elapsed:(NSTimeInterval)elapsed at:(NSTimeInterval)now {
    if (enabled == _recordingEnabled) return;
    [_clock setPlaying:NO elapsed:elapsed at:now];
    [self finish];
    _recordingEnabled = enabled;
    if (enabled) [self updateState:_state elapsed:elapsed at:now];
}

- (void)terminate {
    [_clock setPlaying:NO elapsed:continuousSeconds() at:NSDate.date.timeIntervalSince1970];
    [self finish];
    if (![SGListeningLog() drainForTermination])
        NSLog(@"[spotifyglass] history: final recorder write not confirmed before termination");
}

@end

%ctor {
    static SGPlayRecorder *recorder;
    static atomic_uint_fast64_t notificationRevision;
    // Accessed only on main, including when the enabled value did not change.
    static uint_fast64_t appliedRevision;
    recorder = [SGPlayRecorder new];
    SGAddPlayerStateObserver(recorder);
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            // Invalidate before reading: defaults observers have no ordering.
            // Capture each transition on the posting thread; a later main-queue
            // read could miss an off/on pair while main was busy.
            uint_fast64_t revision = atomic_fetch_add_explicit(&notificationRevision, 1, memory_order_relaxed) + 1;
            SGPrefsChanged();
            BOOL enabled = SGEnabled(SGKeyListeningStats);
            NSTimeInterval elapsed = continuousSeconds();
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            dispatch_block_t apply = ^{
                // Main can apply a newer notification synchronously before a
                // worker's queued snapshot arrives. Never replay the older one.
                if (revision <= appliedRevision) return;
                appliedRevision = revision;
                [recorder recordingChanged:enabled elapsed:elapsed at:now];
            };
            if (NSThread.isMainThread) apply();
            else dispatch_async(dispatch_get_main_queue(), apply);
        }];
    [NSNotificationCenter.defaultCenter addObserver:recorder selector:@selector(terminate) name:UIApplicationWillTerminateNotification object:nil];
    // A deliberate restart exits without that notification, so it posts its own.
    [NSNotificationCenter.defaultCenter addObserver:recorder selector:@selector(terminate) name:SGWillRestartNotification object:nil];
}
