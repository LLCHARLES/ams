// PlayerState.h names the hooks and why they are the ones.
#import "Core/SGCore.h"
#import "PlayerState.h"
#import <os/lock.h>

NSString *SGURIString(id uri) {
    if ([uri isKindOfClass:NSString.class]) return uri;
    if ([uri isKindOfClass:NSURL.class]) return ((NSURL *)uri).absoluteString;
    return nil;
}

NSArray<SPTPlayerTrack *> *SGPlayerUpcomingTracks(SPTPlayerState *state, NSUInteger limit) {
    NSMutableArray<SPTPlayerTrack *> *tracks = [NSMutableArray array];
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    for (id track in [future isKindOfClass:NSArray.class] ? future : @[]) {
        if (![track isKindOfClass:objc_getClass("SPTPlayerTrack")]) continue;
        if (![(SPTPlayerTrack *)track trackTitle].length || !SGURIString([(SPTPlayerTrack *)track URI])) continue;
        [tracks addObject:track];
        if (tracks.count == limit) break;
    }
    return tracks;
}

SPTPlayerTrack *SGPlayerUpNextIn(SPTPlayerState *state) {
    id future = [state respondsToSelector:@selector(future)] ? state.future : nil;
    id next = [future isKindOfClass:NSArray.class] ? [future firstObject] : nil;
    if (![next isKindOfClass:objc_getClass("SPTPlayerTrack")]) return nil;
    NSString *uri = SGURIString([next URI]);
    return uri.length && ![uri isEqualToString:SGURIString(state.track.URI)] ? next : nil;
}

// Returns the last command's answer: while repeating the track it is the context command, else the one made.
id SGPlayerAdvanceRepeat(id<SPTPlayer> player, SPTPlayerOptions *options) {
    // Off, then the playlist or album, then the track, then off again, the way Spotify's button goes.
    if (options.repeatingTrack) {
        [player setRepeatingTrack:NO];
        return [player setRepeatingContext:NO];
    }
    if (options.repeatingContext) return [player setRepeatingTrack:YES];
    return [player setRepeatingContext:YES];
}

static NSHashTable<id<SGPlayerStateObserver>> *sg_stateObservers;
static SPTPlayerState *sg_playerState;
// The first player seen, weak: the app owns it.
static __weak id sg_playerInstance;
static NSString *sg_stateKey;
static NSString *sg_upNextURI, *sg_upNextCurrentURI;
// Set once the now playing platform has reported; the mod's own observer on the player stands down.
static BOOL sg_platformReported = NO;

void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {
    if (!observer) return;
    if (!sg_stateObservers) sg_stateObservers = [NSHashTable weakObjectsHashTable];
    [sg_stateObservers addObject:observer];
}

SPTPlayerState *SGPlayerState(void) {
    return sg_playerState;
}

id SGPlayerInstance(void) {
    return sg_playerInstance;
}

// What an observer is told about; the state object itself is new with every position report.
static NSString *keyOf(SPTPlayerState *state) {
    SPTPlayerOptions *options = [state respondsToSelector:@selector(options)] ? state.options : nil;
    BOOL shuffling = [options respondsToSelector:@selector(shufflingContext)] && options.shufflingContext;
    return [NSString stringWithFormat:@"%@|%@|%d%d%d%d", SGURIString(state.track.URI), SGURIString(state.contextURI),
            state.isPaused, state.isPlaying, [state respondsToSelector:@selector(isLoading)] && state.isLoading, shuffling];
}

static void publish(SPTPlayerState *state) {
    sg_playerState = state;
    for (id<SGPlayerStateObserver> observer in sg_stateObservers.allObjects) {
        if ([observer respondsToSelector:@selector(playerStateDidReport:)]) [observer playerStateDidReport:state];
    }
    NSString *next = SGURIString(SGPlayerUpNextIn(state).URI);
    NSString *current = SGURIString(state.track.URI);
    if (!(next == sg_upNextURI || [next isEqualToString:sg_upNextURI]) ||
        !(current == sg_upNextCurrentURI || [current isEqualToString:sg_upNextCurrentURI])) {
        sg_upNextURI = [next copy];
        sg_upNextCurrentURI = [current copy];
        for (id<SGPlayerStateObserver> observer in sg_stateObservers.allObjects)
            if ([observer respondsToSelector:@selector(playerUpNextDidChange:)]) [observer playerUpNextDidChange:state];
    }
    NSString *key = keyOf(state);
    if ([key isEqualToString:sg_stateKey]) return;
    sg_stateKey = key;
    for (id<SGPlayerStateObserver> observer in sg_stateObservers.allObjects) [observer playerStateDidChange:state];
}

static void report(id state, BOOL platform) {
    if (![state isKindOfClass:objc_getClass("SPTPlayerState")]) return;
    dispatch_block_t apply = ^{
        if (platform) sg_platformReported = YES;
        else if (sg_platformReported) return;
        publish(state);
    };
    if (NSThread.isMainThread) apply();
    else dispatch_async(dispatch_get_main_queue(), apply);
}

@interface SGPlayerObserver : NSObject
@end

@implementation SGPlayerObserver
- (void)player:(id)player stateDidChange:(id)state {
    report(state, NO);
}
@end

static SGPlayerObserver *sg_ownObserver;
static __weak id sg_player;

id SGPlayer(void) {
    return sg_player;
}

%hook _TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation
- (void)player:(id)player stateDidChange:(id)state {
    %orig;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"player state: from %@, a %@, on the main thread %d", [player class], [state class], NSThread.isMainThread);
    });
    report(state, YES);
}
%end

// Observers are added from several threads as the app starts; the first player seen is the one
// watched, the way KaraokeSource.x takes the first player the app asks.
%hook SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer {
    %orig;
    id player = self;
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    os_unfair_lock_lock(&lock);
    if (!sg_playerInstance) {
        sg_playerInstance = player;
        dispatch_async(dispatch_get_main_queue(), ^{
            sg_player = player;
            sg_ownObserver = [SGPlayerObserver new];
            [(id<SPTPlayer>)player addPlayerObserver:sg_ownObserver];
            id state = [player respondsToSelector:@selector(state)] ? [(id<SPTPlayer>)player state] : nil;
            if (state) report(state, NO);
        });
    }
    os_unfair_lock_unlock(&lock);
}
%end

%ctor {
    %init;
    SGRequireClasses(@[@"_TtC23NowPlaying_PlatformImpl28StatefulPlayerImplementation", @"SPTEsperantoPlayer", @"SPTPlayerState"]);
}

// SPTPlayerState has no device/locality field. Connect's own state observer supplies it.
// These selectors and the BOOL getter are present in Spotify 9.1.90's Objective-C metadata.
@protocol SGPlayerConnectLocation <NSObject>
- (BOOL)isPlayingLocally;
- (void)addStateObserver:(id)observer;
@end

NSNotificationName const SGPlayerPlaybackLocationDidChangeNotification = @"SGPlayerPlaybackLocationDidChangeNotification";
static BOOL sg_localPlayback;
static BOOL sg_reportedRemotePlayback;
static __weak id<SGPlayerConnectLocation> sg_connectManager;

BOOL SGPlayerPlaybackIsLocal(void) {
    return sg_localPlayback;
}

BOOL SGPlayerPlaybackIsRemote(void) {
    return sg_connectManager != nil && !sg_localPlayback;
}

static void updateLocation(id<SGPlayerConnectLocation> manager) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (manager != sg_connectManager) return;
        BOOL wasLocal = sg_localPlayback;
        sg_localPlayback = [manager isPlayingLocally];
        BOOL remote = SGPlayerPlaybackIsRemote();
        if (sg_localPlayback == wasLocal && remote == sg_reportedRemotePlayback) return;
        sg_reportedRemotePlayback = remote;
        [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerPlaybackLocationDidChangeNotification object:nil];
    });
}

@interface SGPlayerConnectObserver : NSObject
@end
@implementation SGPlayerConnectObserver
- (void)aggregator:(id<SGPlayerConnectLocation>)aggregator didUpdateAggregatorState:(id)state {
    updateLocation(aggregator);
}
@end

static SGPlayerConnectObserver *sg_connectObserver;
%group SGPlayerConnectLocationHooks
%hook _TtC22Connect_AggregatorImpl24ConnectAggregatorManager
- (void)addStateObserver:(id)observer {
    %orig;
    if (observer == sg_connectObserver) return;
    id<SGPlayerConnectLocation> manager = (id)self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_connectManager == manager) return;
        sg_connectManager = manager;
        if (!sg_connectObserver) sg_connectObserver = [SGPlayerConnectObserver new];
        [manager addStateObserver:sg_connectObserver];
        updateLocation(manager);
    });
}
%end
%end

%ctor {
    Class cls = NSClassFromString(@"_TtC22Connect_AggregatorImpl24ConnectAggregatorManager");
    Method local = class_getInstanceMethod(cls, @selector(isPlayingLocally));
    Method add = class_getInstanceMethod(cls, @selector(addStateObserver:));
    char type[16] = {0};
    if (local) method_getReturnType(local, type, sizeof(type));
    if (!local || !add || strcmp(type, @encode(BOOL)) ||
        method_getNumberOfArguments(local) != 2 || method_getNumberOfArguments(add) != 3) return;
    %init(SGPlayerConnectLocationHooks);
}
