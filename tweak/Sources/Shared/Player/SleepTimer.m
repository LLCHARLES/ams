// Skip unity-gain samples until the fade or expiry. Player reports and effective
// speed changes invalidate track-relative deadlines; fade samples keep their phase.
//
// The end of the album is read from the player's tracks to come: SPTPlayerTrack's provider (a property
// with its own ivar in the binary, beside albumURI and contextSource) and the metadata keys is_queued and
// autoplay.is_autoplay (strings in the binary) tell a track queued by hand or picked by autoplay from one
// of the album or playlist. What they read on a real queue is logged once each time the mode is set.
#import "Core/SGLog.h"
#import "Core/SGLocalize.h"
#import "Core/SGPrefs.h"
#import "Headers/SPTPlayer.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SleepTimer.h"

static const NSTimeInterval kCheckEvery = 0.25;
// The end of track and end of album timers pause this close to the end, so the next track never starts.
static const NSTimeInterval kBeforeEnd = 0.5;
// The fade's depth: 60 dB down is as good as silent, and the pause takes it from there.
static const float kFadeDecibels = 60;
// The Fade out choices, by index, and the one unless another is picked.
static const NSTimeInterval kFades[] = {0, 10, 30, 60, 120};
static const NSInteger kFadeDefault = 2;
// The gain goes back to normal this long after the pause, once what was still on its way out has played.
static const NSTimeInterval kRestoreAfter = 1;

static SGSleepTimerMode sg_mode;
static NSDate *sg_end, *sg_wallStart, *sg_wallDue, *sg_trackGrid, *sg_trackDue;
// The track and the context playing when it was set, by URI.
static NSString *sg_track, *sg_context;
static NSTimer *sg_timer;
// Whether this timer's fade has started, so the log says so once.
static BOOL sg_fading;
static NSTimeInterval sg_wallFade;

NSArray<NSString *> *SGSleepTimerFadeNames(void) {
    return @[SGL(@"common.off", @"Off"), SGL(@"settings.sleep_timer.fade.10s", @"10 s"), SGL(@"settings.sleep_timer.fade.30s", @"30 s"),
             SGL(@"settings.sleep_timer.fade.1m", @"1 minute"), SGL(@"settings.sleep_timer.fade.2m", @"2 minutes")];
}

NSInteger SGSleepTimerFadeChoice(void) {
    NSInteger index = SGInt(SGKeySleepTimerFade, kFadeDefault);
    return index >= 0 && index < (NSInteger)(sizeof kFades / sizeof *kFades) ? index : kFadeDefault;
}

NSTimeInterval SGSleepTimerFade(void) {
    return kFades[SGSleepTimerFadeChoice()];
}

SGSleepTimerMode SGSleepTimerCurrentMode(void) {
    return sg_mode;
}

NSDate *SGSleepTimerEnd(void) {
    return sg_mode == SGSleepTimerAtTime ? sg_end : nil;
}

float SGSleepTimerGain(NSTimeInterval left, NSTimeInterval fade) {
    if (fade <= 0 || left >= fade) return 1;
    return powf(10, -kFadeDecibels / 20 * (float)(1 - MAX(left, 0) / fade));
}

static BOOL metadataSays(SPTPlayerTrack *track, NSString *key) {
    NSDictionary *metadata = [track respondsToSelector:@selector(metadata)] ? track.metadata : nil;
    return [metadata isKindOfClass:NSDictionary.class] && [[metadata[key] description] isEqualToString:@"true"];
}

static NSString *providerOf(SPTPlayerTrack *track) {
    NSString *provider = [track respondsToSelector:@selector(provider)] ? track.provider : nil;
    return [provider isKindOfClass:NSString.class] ? provider : nil;
}

static BOOL isAutoplay(SPTPlayerTrack *track) {
    return [providerOf(track) isEqualToString:@"autoplay"] || metadataSays(track, @"autoplay.is_autoplay");
}

// A track of the album or playlist itself, not one queued by hand or picked by autoplay.
static BOOL isContextTrack(id track) {
    if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] || !SGURIString([(SPTPlayerTrack *)track URI])) return NO;
    return ![providerOf(track) isEqualToString:@"queue"] && !metadataSays(track, @"is_queued") && !isAutoplay(track);
}

BOOL SGSleepTimerOnLastOfContext(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    SPTPlayerTrack *next = nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (isContextTrack(track)) { next = track; break; }
    }
    if (!next) return YES;
    // Repeating, the album comes round again: the next track is this one or one already played.
    if (!state.options.repeatingContext) return NO;
    NSString *uri = SGURIString(next.URI);
    if ([uri isEqualToString:SGURIString(state.track.URI)]) return YES;
    id reverse = [state respondsToSelector:@selector(reverse)] ? state.reverse : nil;
    for (id track in [reverse isKindOfClass:NSArray.class] ? reverse : @[]) {
        if ([track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")] && [SGURIString([(SPTPlayerTrack *)track URI]) isEqualToString:uri]) return YES;
    }
    return NO;
}

NSTimeInterval SGSleepTimerTrackLeft(SPTPlayerState *state) {
    double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
    NSInteger position = SGKaraokePositionMs();
    return duration > 0 && position >= 0 ? MAX(0, duration - position / 1000.0) : -1;
}

static void stopChecking(void) {
    [sg_timer invalidate];
    sg_timer = nil;
    sg_mode = SGSleepTimerOff;
    sg_end = nil;
    sg_wallStart = nil;
    sg_wallDue = nil;
    sg_trackDue = nil;
    sg_track = nil;
    sg_context = nil;
    sg_fading = NO;
}

// Seconds until the pause, or -1 when it is not in sight yet (a track whose length is not known, or the
// album still has tracks to go); 0 to pause now.
static NSTimeInterval secondsLeft(SPTPlayerState *state) {
    NSString *track = SGURIString(state.track.URI);
    switch (sg_mode) {
        case SGSleepTimerAtTime:
            return MAX(0, sg_end.timeIntervalSinceNow);
        case SGSleepTimerEndOfTrack:
            // On the next track already, should the length not have been known.
            return [track isEqualToString:sg_track] ? SGSleepTimerTrackLeft(state) : 0;
        case SGSleepTimerEndOfAlbum: {
            NSString *context = SGURIString(state.contextURI);
            if (!(context == sg_context || [context isEqualToString:sg_context]) || isAutoplay(state.track)) return 0;
            return SGSleepTimerOnLastOfContext(state) ? SGSleepTimerTrackLeft(state) : -1;
        }
        default:
            return -1;
    }
}

static void check(void);
static void sample(SPTPlayerState *state);

static void arm(NSTimeInterval seconds, BOOL repeats) {
    [sg_timer invalidate];
    sg_timer = [NSTimer timerWithTimeInterval:seconds repeats:repeats block:^(NSTimer *timer) { check(); }];
    [NSRunLoop.mainRunLoop addTimer:sg_timer forMode:NSRunLoopCommonModes];
}

// Skip only samples known to have unity gain. Land on the original sampling grid
// so a fractional boundary doesn't shift either the fade samples or the pause.
NSDate *SGSleepTimerNextSample(NSDate *__strong *grid, NSTimeInterval beforeBoundary) {
    double elapsed = -(*grid).timeIntervalSinceNow;
    if (elapsed < 0) {
        *grid = [NSDate dateWithTimeIntervalSinceNow:0];
        elapsed = 0;
    }
    double next = MAX(floor(elapsed / kCheckEvery) + 1, ceil((elapsed + beforeBoundary) / kCheckEvery));
    return [*grid dateByAddingTimeInterval:next * kCheckEvery];
}

static void scheduleTrack(SPTPlayerState *state) {
    if (sg_mode != SGSleepTimerEndOfTrack && sg_mode != SGSleepTimerEndOfAlbum) return;
    if (sg_trackDue && sg_trackDue.timeIntervalSinceNow <= 0) {
        [sg_timer invalidate];
        sample(state);
        return;
    }
    NSTimeInterval left = secondsLeft(state), fade = SGSleepTimerFade();
    // A skip/queue change/seek can also require returning the previous fade to unity.
    BOOL moreTracks = left < 0 && sg_mode == SGSleepTimerEndOfAlbum && state && !SGSleepTimerOnLastOfContext(state);
    if (!sg_fading && (moreTracks || (state.isPaused && left > MAX(fade, kBeforeEnd)))) {
        [sg_timer invalidate];
        sg_timer = nil;
        sg_trackDue = nil; // only a player report or preference change can bring the fade into view
        return;
    }
    double rate = state.playbackSpeed;
    double wait = !sg_fading && state.isPlaying && !state.isPaused && isfinite(rate) && rate > 0
        ? MAX(0, left - MAX(fade, kBeforeEnd)) / rate : 0;
    // A relative timer may have slept while the reported clock kept advancing.
    sg_trackDue = SGSleepTimerNextSample(&sg_trackGrid, wait);
    arm(MAX(0, sg_trackDue.timeIntervalSinceNow), NO);
}

extern void SGSpotifySleepOutputChanged(void);
static void outputChanged(AudioUnit output) {
    // Sing flushes the old output's read-ahead on this control callback. Read
    // the corrected clock on main, never inspect the player under the output lock.
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_mode == SGSleepTimerEndOfTrack || sg_mode == SGSleepTimerEndOfAlbum)
            scheduleTrack([(id<SPTPlayer>)SGKaraokePlayer() state]);
        SGSpotifySleepOutputChanged();
    });
}
void SGSleepTimerWatchOutput(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!SGPlayerWatchMusicOutput(outputChanged)) SGLog(@"sleep timer: cannot watch the music output for clock corrections");
    });
}

// Relative timers can retain their pre-sleep delay. Keep the actual next sample date
// across reports, so reconciling neither republishes unity nor moves the fade grid.
static void reconcileWall(void) {
    if (sg_mode != SGSleepTimerAtTime) return;
    NSTimeInterval remaining = sg_wallDue.timeIntervalSinceNow;
    if (remaining <= 0 || sg_end.timeIntervalSinceNow <= 0) check();
    else arm(remaining, NO);
}

@interface SGSleepWallObserver : NSObject <SGPlayerStateObserver>
@end
@implementation SGSleepWallObserver
- (void)playerStateDidReport:(SPTPlayerState *)state { reconcileWall(); scheduleTrack(state); }
- (void)playerStateDidChange:(SPTPlayerState *)state {} // DidReport already ran.
@end

static void check(void) {
    sample([(id<SPTPlayer>)SGKaraokePlayer() state]);
}

static void sample(SPTPlayerState *state) {
    sg_trackDue = nil;
    if (sg_mode == SGSleepTimerOff) return;
    NSTimeInterval left = secondsLeft(state);
    BOOL up = left >= 0 && (sg_mode == SGSleepTimerAtTime ? left <= 0 : left < kBeforeEnd);
    if (!up) {
        NSTimeInterval fade = SGSleepTimerFade();
        // At the end of a track shorter than the fade, the fade starts with the track.
        double duration = [state respondsToSelector:@selector(duration)] ? state.duration : 0;
        if (sg_mode != SGSleepTimerAtTime && duration > 0) fade = MIN(fade, duration);
        float gain = left >= 0 ? SGSleepTimerGain(left, fade) : 1;
        if (gain < 1 && !sg_fading) {
            sg_fading = YES;
            SGLog(@"sleep timer: fading over %.0f s, %.1f s left (mode %ld, track %.1f s, at %ld ms)", fade, left, (long)sg_mode,
                  duration, (long)SGKaraokePositionMs());
        }
        SGPlayerSetGain(gain);
        sg_fading = gain < 1;
        if (sg_mode == SGSleepTimerAtTime) {
            sg_wallFade = fade;
            // Keep the old timer's sample phase (from set/add, not from fade start).
            // An extension partway through a quarter second need not end on that grid.
            left = sg_end.timeIntervalSinceNow;
            NSTimeInterval nextSample = kCheckEvery - fmod(MAX(0, -sg_wallStart.timeIntervalSinceNow), kCheckEvery);
            NSTimeInterval wait = left > fade ? left - fade : MIN(MAX(0, left), nextSample);
            sg_wallDue = [sg_end dateByAddingTimeInterval:wait - left];
            arm(wait, NO);
        } else scheduleTrack(state);
        return;
    }
    SGSleepTimerMode mode = sg_mode;
    stopChecking();
    if (!state.isPaused) [(id<SPTPlayer>)SGKaraokePlayer() pause:nil];
    SGLog(@"sleep timer: up (mode %ld), %@%@", (long)mode, state.isPaused ? @"already paused" : @"paused",
          SGSleepTimerFade() > 0 ? @"" : @", no fade (Off)");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kRestoreAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sg_mode == SGSleepTimerOff) SGPlayerSetGain(1);
    });
}

// What the tracks to come say about themselves, once per End of album, so the phone's log shows whether
// the provider and the two keys read the way SGSleepTimerOnLastOfContext expects.
static void logQueue(SPTPlayerState *state) {
    NSMutableArray<NSString *> *seen = [NSMutableArray array];
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (seen.count == 4) break;
        if (![track isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) continue;
        [seen addObject:[NSString stringWithFormat:@"%@ provider %@ is_queued %@ autoplay %@ -> %@", [(SPTPlayerTrack *)track trackTitle],
                         providerOf(track), [(SPTPlayerTrack *)track metadata][@"is_queued"],
                         [(SPTPlayerTrack *)track metadata][@"autoplay.is_autoplay"], isContextTrack(track) ? @"album" : @"not album"]];
    }
    SGLog(@"sleep timer: end of album, context %@, playing %@ (provider %@), %lu to come, last of it %@: %@", SGURIString(state.contextURI),
          state.track.trackTitle, providerOf(state.track), (unsigned long)[future count], SGSleepTimerOnLastOfContext(state) ? @"yes" : @"no",
          [seen componentsJoinedByString:@"; "]);
}

void SGSetSleepTimer(SGSleepTimerMode mode, NSTimeInterval seconds) {
    stopChecking();
    if (mode == SGSleepTimerOff || (mode == SGSleepTimerAtTime && seconds <= 0)) {
        SGPlayerSetGain(1);
        return;
    }
    SPTPlayerState *state = [(id<SPTPlayer>)SGKaraokePlayer() state];
    sg_mode = mode;
    if (mode != SGSleepTimerAtTime) SGSleepTimerWatchOutput();
    if (mode == SGSleepTimerAtTime) {
        sg_wallStart = [NSDate dateWithTimeIntervalSinceNow:0];
        sg_end = [sg_wallStart dateByAddingTimeInterval:seconds];
    }
    sg_track = SGURIString(state.track.URI);
    sg_context = SGURIString(state.contextURI);
    if (mode == SGSleepTimerEndOfAlbum) logQueue(state);
    SGLog(@"sleep timer: set (mode %ld, %.0f s), fade %.0f s", (long)mode, seconds, SGSleepTimerFade());
    sg_trackGrid = [NSDate dateWithTimeIntervalSinceNow:0];
    {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            static SGSleepWallObserver *observer;
            observer = [SGSleepWallObserver new];
            SGAddPlayerStateObserver(observer);
            for (NSString *name in @[NSUserDefaultsDidChangeNotification, NSSystemClockDidChangeNotification,
                                     UIApplicationDidBecomeActiveNotification, UIApplicationSignificantTimeChangeNotification,
                                     SGPlayerSpeedDidChangeNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (sg_mode == SGSleepTimerEndOfTrack || sg_mode == SGSleepTimerEndOfAlbum)
                            scheduleTrack([(id<SPTPlayer>)SGKaraokePlayer() state]);
                        else if ([note.name isEqual:SGPlayerSpeedDidChangeNotification]) return;
                        else if ([note.name isEqual:UIApplicationDidBecomeActiveNotification]) reconcileWall();
                        else if (sg_mode == SGSleepTimerAtTime &&
                            (![note.name isEqual:NSUserDefaultsDidChangeNotification] || sg_wallFade != SGSleepTimerFade())) check();
                    });
                }];
            }
        });
    }
    check();
}

void SGSleepTimerAdd(NSTimeInterval seconds) {
    NSDate *end = SGSleepTimerEnd();
    NSTimeInterval from = end && end.timeIntervalSinceNow > 0 ? end.timeIntervalSinceNow : 0;
    SGSetSleepTimer(SGSleepTimerAtTime, from + seconds);
}
