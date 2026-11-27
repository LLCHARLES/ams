// Spotify's own sleep timer, the one set from the player's ⋯ menu (its sheet of times and End of track),
// faded out the way the mod's own is (SleepTimer.h): the same Fade out choice, curve and gain. Spotify's
// player core keeps that timer and pauses at its end; this only reads it off the player's state
// (SPTPlayerState's sleepTimer, Headers/SPTPlayer.h) and never pauses or changes anything of Spotify's.
//
// The watch sleeps to the fade boundary when the reported clock permits it, then samples at 4 Hz;
// a player state observer reconciles the deadline on each report. Over the last
// seconds before the time, or before the end of the track, the gain comes down. Once the timer is up (its
// time came, the track it ended changed, Spotify paused or dropped the timer within a couple of seconds of
// its end) the gain stays down until Spotify's pause has landed and comes back a second later, or 5 s on
// without a pause. A timer canceled or moved later brings the gain back at once. The core may keep a timer that went off in its state for a while,
// so one that went off is not followed again.
//
// It stands aside while the mod's own timer runs, which has the gain then, and while Spotify's own fade is
// forced on (ios-feature-sleeptimer.enable_fade_out, the Labs page's Fade out): with it, Spotify's
// DuckHandlerImpl ducks the core's volume itself (a DuckRequest of a volume and a fade_duration_ms). Off in
// the flag table 9.1.78 ships; a fade that sounds twice as deep means the server turned it on.
//
// Threading: main thread only.
#import "Core/SGFlagForce.h"
#import "Core/SGLog.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SleepTimer.h"
#import "Shared/Player/SpeedPitch.h"

static NSString *const kSpotifyFadeFlag = @"ios-feature-sleeptimer.enable_fade_out";
// SPTSleepTimer's types.
static const NSUInteger kAtTime = 1, kEndOfTrack = 2;
// A timer that goes away, or a track that changes, this close to the end means the timer went off.
static const NSTimeInterval kUpWithin = 2;
static const NSTimeInterval kRestoreAfter = 1;
static const NSTimeInterval kPauseWait = 5;

static NSTimer *sg_check;
static NSDate *sg_grid, *sg_due;
extern NSDate *SGSleepTimerNextSample(NSDate *__strong *grid, NSTimeInterval beforeBoundary);
extern void SGSleepTimerWatchOutput(void);
// A timer of Spotify's: its type, 0 for none, and for a time its end in ms since 1970.
typedef struct {
    NSUInteger type;
    long long atMs;
} SGSpotifyTimer;
// The timer followed, and one that went off.
static SGSpotifyTimer sg_following, sg_wentOff;

static BOOL sameTimer(SGSpotifyTimer a, SGSpotifyTimer b) {
    return a.type == b.type && a.atMs == b.atMs;
}
// For End of track, the track whose end it is.
static NSString *sg_track;
// Seconds to its end at the last check, -1 for not known.
static NSTimeInterval sg_left = -1;
// The gain is below 1 for Spotify's timer.
static BOOL sg_lowered;
// Set once it went off: the gain stays down until Spotify pauses, or until then.
static NSDate *sg_holdUntil;
static BOOL sg_stoodAside;

static void restoreGain(BOOL now) {
    sg_lowered = NO;
    if (SGSleepTimerCurrentMode() != SGSleepTimerOff) return;
    if (now) {
        SGPlayerSetGain(1);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestoreAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!sg_lowered && !sg_holdUntil && SGSleepTimerCurrentMode() == SGSleepTimerOff) SGPlayerSetGain(1);
    });
}

static void wentOff(NSString *why) {
    SGLog(@"sleep timer: Spotify's up (%@, %.1f s left), gain held until its pause", why, sg_left);
    sg_wentOff = sg_following;
    sg_following = (SGSpotifyTimer){0};
    sg_left = -1;
    sg_holdUntil = [NSDate dateWithTimeIntervalSinceNow:kPauseWait];
}

// Fades for `timer` (ending at `at` for a time), or finds it went off.
static void follow(SPTPlayerState *state, SGSpotifyTimer timer, NSDate *at) {
    NSUInteger type = timer.type;
    NSString *track = SGURIString(state.track.URI);
    if (!sameTimer(timer, sg_following)) {
        sg_following = timer;
        sg_track = track;
        sg_stoodAside = NO;
        SGLog(@"sleep timer: Spotify's set (type %lu, %@), fade %.0f s", (unsigned long)type,
              type == kAtTime ? [NSString stringWithFormat:@"ends in %.0f s", at.timeIntervalSinceNow] : @"end of track",
              SGSleepTimerFade());
    }
    if ([SGForcedFlagValue(kSpotifyFadeFlag) boolValue]) {
        if (!sg_stoodAside) SGLog(@"sleep timer: Spotify's own Fade out is forced on, its fade is left to it");
        sg_stoodAside = YES;
        sg_left = -1;
        if (sg_lowered) restoreGain(YES);
        return;
    }
    sg_stoodAside = NO;
    if (type == kEndOfTrack && !(track == sg_track || [track isEqualToString:sg_track])) {
        if (sg_left >= 0 && sg_left < kUpWithin) {
            wentOff(@"the track ended");
            return;
        }
        sg_track = track;   // skipped to another track, whose end it is now
    }
    NSTimeInterval left = type == kAtTime ? MAX(0, at.timeIntervalSinceNow) : SGSleepTimerTrackLeft(state);
    sg_left = left;
    if (type == kAtTime && left <= 0) {
        wentOff(@"its time came");
        return;
    }
    if (state.isPaused && sg_lowered && left >= 0 && left < kUpWithin) {
        wentOff(@"Spotify paused");
        return;
    }
    NSTimeInterval fade = SGSleepTimerFade();
    double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
    if (type == kEndOfTrack && duration > 0) fade = MIN(fade, duration);
    float gain = left >= 0 ? SGSleepTimerGain(left, fade) : 1;
    if (gain < 1 && !sg_lowered) SGLog(@"sleep timer: Spotify's, fading over %.0f s, %.1f s left", fade, left);
    if (gain < 1 || sg_lowered) SGPlayerSetGain(gain);
    sg_lowered = gain < 1;
}

static void check(void);
static void sample(SPTPlayerState *state);

// Spotify's timer in `state`, its end as a date to `at` unless NULL. With none, the one that went off is
// forgotten: a timer set after it is a new one.
static SGSpotifyTimer timerIn(SPTPlayerState *state, NSDate **at) {
    SPTSleepTimer *timer = [state respondsToSelector:@selector(sleepTimer)] ? state.sleepTimer : nil;
    NSUInteger type = [timer respondsToSelector:@selector(type)] ? timer.type : 0;
    NSDate *end = type == kAtTime && [timer respondsToSelector:@selector(timestamp)] ? timer.timestamp : nil;
    if (type != kEndOfTrack && !(type == kAtTime && [end isKindOfClass:NSDate.class])) type = 0;
    if (!type) sg_wentOff = (SGSpotifyTimer){0};
    if (at) *at = end;
    return (SGSpotifyTimer){type, type == kAtTime ? llround(end.timeIntervalSince1970 * 1000) : 0};
}

// Runs the check while Spotify has a timer not yet gone off, or one of its needs it.
static void watch(SPTPlayerState *state) {
    if (sg_due && sg_due.timeIntervalSinceNow <= 0) {
        [sg_check invalidate];
        sample(state);
        return;
    }
    NSDate *at;
    SGSpotifyTimer timer = timerIn(state, &at);
    BOOL needed = (timer.type && !sameTimer(timer, sg_wentOff)) || sg_following.type || sg_holdUntil || sg_lowered;
    if (!needed) {
        [sg_check invalidate];
        sg_check = nil;
        sg_grid = nil;
        sg_due = nil;
        return;
    }
    if (!sg_grid) sg_grid = [NSDate dateWithTimeIntervalSinceNow:0];
    if (timer.type == kEndOfTrack) SGSleepTimerWatchOutput();
    BOOL ownTimerHasGain = SGSleepTimerCurrentMode() != SGSleepTimerOff;
    if (timer.type && !sg_holdUntil && !sg_lowered &&
        (ownTimerHasGain || (sameTimer(timer, sg_following) && sg_stoodAside)) && [SGForcedFlagValue(kSpotifyFadeFlag) boolValue]) {
        [sg_check invalidate];
        sg_check = nil;
        sg_due = nil; // Spotify owns the gain; reports and flag edits still reconcile the watch.
        return;
    }
    double wait = 0;
    if (sameTimer(timer, sg_following) && timer.type && !sg_lowered && !sg_holdUntil && !sg_stoodAside &&
        !ownTimerHasGain) {
        double rate = timer.type == kAtTime ? 1 : state.playbackSpeed;
        double left = timer.type == kAtTime ? at.timeIntervalSinceNow : SGSleepTimerTrackLeft(state);
        if (timer.type == kEndOfTrack && state.isPaused && [SGURIString(state.track.URI) isEqual:sg_track] &&
            left > MAX(SGSleepTimerFade(), kUpWithin)) {
            [sg_check invalidate];
            sg_check = nil;
            sg_due = nil;
            return;
        }
        if (isfinite(rate) && rate > 0 && (timer.type == kAtTime ||
            (state.isPlaying && !state.isPaused && [SGURIString(state.track.URI) isEqual:sg_track])))
            wait = MAX(0, left - MAX(SGSleepTimerFade(), kUpWithin)) / rate;
    }
    // Re-arm from the remaining wall time even when the target date is unchanged.
    sg_due = SGSleepTimerNextSample(&sg_grid, wait);
    [sg_check invalidate];
    sg_check = [NSTimer timerWithTimeInterval:MAX(0, sg_due.timeIntervalSinceNow) repeats:NO block:^(NSTimer *timer) { check(); }];
    [NSRunLoop.mainRunLoop addTimer:sg_check forMode:NSRunLoopCommonModes];
}

static void check(void) {
    sample([(id<SPTPlayer>)SGKaraokePlayer() state]);
}

static void sample(SPTPlayerState *state) {
    sg_due = nil;
    if (!state) {
        // A report armed this watch, but the player instance is temporarily unreachable.
        sg_due = SGSleepTimerNextSample(&sg_grid, 0);
        sg_check = [NSTimer timerWithTimeInterval:sg_due.timeIntervalSinceNow repeats:NO block:^(NSTimer *timer) { check(); }];
        [NSRunLoop.mainRunLoop addTimer:sg_check forMode:NSRunLoopCommonModes];
        return;
    }
    NSDate *at;
    SGSpotifyTimer timer = timerIn(state, &at);

    if (sg_holdUntil) {
        if (state.isPaused || sg_holdUntil.timeIntervalSinceNow <= 0) {
            SGLog(@"sleep timer: Spotify's %@, gain back in %.0f s", state.isPaused ? @"paused" : @"did not pause", kRestoreAfter);
            sg_holdUntil = nil;
            restoreGain(NO);
        }
    } else if (SGSleepTimerCurrentMode() != SGSleepTimerOff) {
        sg_lowered = NO;   // the mod's own timer has the gain
        sg_following = (SGSpotifyTimer){0};
    } else if (timer.type && !sameTimer(timer, sg_wentOff)) {
        follow(state, timer, at);
    } else if (sg_following.type) {
        if (!timer.type && sg_left >= 0 && sg_left < kUpWithin) wentOff(@"timer cleared at its end");
        else {
            SGLog(@"sleep timer: Spotify's canceled%@", sg_lowered ? @", gain back" : @"");
            sg_following = (SGSpotifyTimer){0};
            sg_left = -1;
            if (sg_lowered) restoreGain(YES);
        }
    }
    watch(state);
}

void SGSpotifySleepOutputChanged(void) {
    if (sg_following.type == kEndOfTrack) watch([(id<SPTPlayer>)SGKaraokePlayer() state]);
}

@interface SGSpotifySleepTimerWatch : NSObject <SGPlayerStateObserver>
@end

@implementation SGSpotifySleepTimerWatch
- (void)playerStateDidChange:(SPTPlayerState *)state {
}
// A timer set or canceled changes none of what playerStateDidChange: is told about.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    watch(state);
}
@end

__attribute__((constructor)) static void sg_watchSpotifySleepTimer(void) {
    static SGSpotifySleepTimerWatch *watcher;   // the observers are held weakly
    watcher = [SGSpotifySleepTimerWatch new];
    SGAddPlayerStateObserver(watcher);
    for (NSString *name in @[SGPlayerSpeedDidChangeNotification, NSUserDefaultsDidChangeNotification,
                             NSSystemClockDidChangeNotification, UIApplicationDidBecomeActiveNotification,
                             UIApplicationSignificantTimeChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (sg_grid) watch([(id<SPTPlayer>)SGKaraokePlayer() state]);
            });
        }];
    }
}
