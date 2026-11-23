// NowPlayingExtras.h says what this is and why it stores nothing of Spotify's.
#import <MediaPlayer/MediaPlayer.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Shared/Player/NowPlayingExtras.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Player/SpeedPitch.h"

// Read on whatever thread Spotify sets the info from, written on the main one.
static NSObject *sg_lock;
static NSMutableDictionary<NSString *, NSDictionary *> *sg_extras;   // by owner
static NSMutableDictionary<NSString *, NSString *> *sg_titles;       // by owner
static double sg_elapsed, sg_rate;
static CFAbsoluteTime sg_clockAt;
NSNotificationName const SGNowPlayingInfoDidChangeNotification = @"spotifyglass.nowPlayingInfoDidChange";
static BOOL sg_notificationPending;   // under sg_lock
static _Thread_local BOOL sg_resendingExtras;
// A newer player clock wins over the last MediaPlayer setter. Read its live position
// only on an actual resend, not on every report when nobody needs metadata.
static atomic_bool sg_playerClockNewer;

@interface SGExtrasClockObserver : NSObject <SGPlayerStateObserver>
@end
@implementation SGExtrasClockObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state { atomic_store(&sg_playerClockNewer, true); }
@end

static void infoChanged(void) {
    if (sg_resendingExtras) return;
    @synchronized (sg_lock) {
        if (sg_notificationPending) return;
        sg_notificationPending = YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        @synchronized (sg_lock) { sg_notificationPending = NO; }
        [NSNotificationCenter.defaultCenter postNotificationName:SGNowPlayingInfoDidChangeNotification object:nil];
    });
}

// `stale` are an owner's old keys: the info the getter gives back can still carry them, and the hook puts
// back only the extras that are current.
static void resend(NSArray *stale) {
    MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
    NSMutableDictionary *info = [center.nowPlayingInfo mutableCopy];
    if (!info) return;
    [info removeObjectsForKeys:stale];
    @synchronized (sg_lock) {
        if (sg_clockAt > 0) {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(sg_elapsed + sg_rate * (CFAbsoluteTimeGetCurrent() - sg_clockAt));
            info[MPNowPlayingInfoPropertyPlaybackRate] = @(sg_rate);
        }
    }
    if (atomic_load(&sg_playerClockNewer) && info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
        SPTPlayerState *state = SGPlayerState();
        if ([state.track.trackTitle isEqual:info[MPMediaItemPropertyTitle]]) {
            BOOL paused = state.isPaused;
            double rate = paused ? 0 : state.playbackSpeed;
            // position already runs forward at the effective speed, including the mod's.
            double seconds = paused ? state.positionAsOfTimestamp : state.position;
            if (isfinite(rate) && rate >= 0 && isfinite(seconds) && seconds >= 0) {
                info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(seconds);
                info[MPNowPlayingInfoPropertyPlaybackRate] = @(rate);
            }
        }
    }
    BOOL resending = sg_resendingExtras;
    sg_resendingExtras = YES;
    center.nowPlayingInfo = info;
    sg_resendingExtras = resending;
}

void SGNowPlayingSetExtras(NSString *owner, NSDictionary *extras, NSString *title) {
    NSDictionary *old;
    @synchronized (sg_lock) {
        old = sg_extras[owner];
        sg_extras[owner] = extras.count ? extras : nil;
        sg_titles[owner] = extras.count ? title : nil;
    }
    if (extras.count) {
        resend(old.allKeys ?: @[]);
        return;
    }
    // Cleared, they are taken off if they are still on: the next track can have the same title, and then
    // the last track's artwork or ISRC rode on its info.
    NSDictionary *info = MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo;
    for (id key in old) {
        if (![info[key] isEqual:old[key]]) continue;
        resend(old.allKeys);
        return;
    }
}

%hook MPNowPlayingInfoCenter
- (void)setNowPlayingInfo:(NSDictionary *)info {
    NSMutableDictionary *added = nil;
    @synchronized (sg_lock) {
        if (info[MPNowPlayingInfoPropertyElapsedPlaybackTime]) {
            if (!sg_resendingExtras) atomic_store(&sg_playerClockNewer, false);
            sg_elapsed = [info[MPNowPlayingInfoPropertyElapsedPlaybackTime] doubleValue];
            // A rate left out runs at 1, as LockScreenLyrics.x reads it.
            NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
            sg_rate = rate ? rate.doubleValue : 1;
            sg_clockAt = CFAbsoluteTimeGetCurrent();
        }
        id title = info[MPMediaItemPropertyTitle];
        for (NSString *owner in sg_extras) {
            if (![title isEqual:sg_titles[owner]]) continue;
            if (!added) added = [NSMutableDictionary dictionary];
            [added addEntriesFromDictionary:sg_extras[owner]];
        }
    }
    if (!added) {
        %orig;
        infoChanged();
        return;
    }
    NSMutableDictionary *withExtras = [info mutableCopy];
    [withExtras addEntriesFromDictionary:added];
    %orig(withExtras);
    infoChanged();
}
%end

%ctor {
    sg_lock = [NSObject new];
    sg_extras = [NSMutableDictionary dictionary];
    sg_titles = [NSMutableDictionary dictionary];
    static SGExtrasClockObserver *observer;
    observer = [SGExtrasClockObserver new];
    SGAddPlayerStateObserver(observer);
    [NSNotificationCenter.defaultCenter addObserverForName:SGPlayerSpeedDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        atomic_store(&sg_playerClockNewer, true);
    }];
    %init;
}
