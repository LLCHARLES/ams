#import "Core/SGCore.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Haptics/Haptics.h"
#import "SponsorBlock.h"

// Spotify 9.1.90 Objective-C metadata: v48@0:8@16@24@?32@?40. This is Spotify's
// existing timed, accessible action snackbar.
@protocol SGSponsorBlockSnackbar <NSObject>
- (void)presentSnackbarWithText:(NSString *)text buttonTitle:(NSString *)title
                   actionBlock:(dispatch_block_t)action presentationEndedBlock:(id)ended;
@end
static __weak id<SGSponsorBlockSnackbar> sg_presenter;
static SGSponsorBlockSession *sg_session;
BOOL SGSponsorBlockMarkersEnabled(void) {
    // Overlay ctors can run before this file's ctor.
    static dispatch_once_t once; static BOOL enabled;
    dispatch_once(&once, ^{ enabled = SGHidden(SGKeySponsorBlock) && SGEnabled(SGKeySponsorBlockOverlay); });
    return enabled;
}
NSArray<SGSponsorBlockSegment *> *SGSponsorBlockVisibleSegments(void) { return sg_session.visibleSegments ?: @[]; }
double SGSponsorBlockEpisodeDuration(void) { return sg_session.episodeDuration; }

@interface SGSponsorBlockObserver : NSObject <SGPlayerStateObserver>
@end
static BOOL canSeek(void) {
    return sg_presenter != nil && [SGPlayer() respondsToSelector:@selector(seekTo:)];
}

static SGSponsorBlockReading reading(SPTPlayerState *state) {
    NSDate *stamp = state.timestamp;
    return (SGSponsorBlockReading){state.position, stamp ? stamp.timeIntervalSinceReferenceDate : NAN,
        [state respondsToSelector:@selector(playbackSpeed)] ? state.playbackSpeed : 1,
        state.isPlaying && !state.isPaused && !state.isLoading};
}

static BOOL readLive(NSString *episode, SGSponsorBlockReading *sample) {
    if (!canSeek()) return NO;
    id<SPTPlayer> player = SGPlayer();
    SPTPlayerState *live = [player respondsToSelector:@selector(state)] ? player.state : nil;
    SPTPlayerState *report = SGPlayerState();
    if (![episode isEqual:SGSponsorBlockEpisodeID(SGURIString(report.track.URI))] ||
        (live && ![episode isEqual:SGSponsorBlockEpisodeID(SGURIString(live.track.URI))])) return NO;
    SPTPlayerState *state = !live.timestamp || [report.timestamp compare:live.timestamp] == NSOrderedDescending ? report : live;
    *sample = reading(state);
    return YES;
}
@implementation SGSponsorBlockObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    SGSponsorBlockReading sample = reading(state);
    sg_session.playbackRate = sample.rate;
    sg_session.reportTimestamp = sample.timestamp;
    [sg_session observeURI:SGURIString(state.track.URI) position:sample.position duration:state.duration
        playing:sample.playing
        enabled:canSeek()];
}
@end
static SGSponsorBlockObserver *sg_observer;

static dispatch_block_t scheduleBoundary(double delay, dispatch_block_t fire) {
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_time_t deadline = delay < (double)INT64_MAX / NSEC_PER_SEC
        ? dispatch_time(DISPATCH_TIME_NOW, (int64_t)ceil(delay * NSEC_PER_SEC)) : DISPATCH_TIME_FOREVER;
    dispatch_source_set_timer(timer, deadline, DISPATCH_TIME_FOREVER, 0);
    dispatch_source_set_event_handler(timer, fire);
    dispatch_resume(timer);
    return ^{ dispatch_source_cancel(timer); };
}

%group SGSponsorBlockNotice
%hook SPTSnackbarInternalPresenterImplementation
- (id)initWithTheme:(id)theme viewPresenter:(id)viewPresenter imageLoader:(id)imageLoader
              isRTL:(BOOL)isRTL properties:(id)properties messageOrchestrator:(id)orchestrator {
    id result = %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ sg_presenter = result; });
    return result;
}
%end
%end

static BOOL methodMatches(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || method_getNumberOfArguments(method) != arguments.count + 2) return NO;
    char type[64];
    method_getReturnType(method, type, sizeof(type));
    if (strcmp(type, result)) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (strcmp(type, arguments[i].UTF8String)) return NO;
    }
    return YES;
}

%ctor {
    SGSponsorBlockMarkersEnabled();
    if (!SGFlag(SGKeySponsorBlock, NO)) return;
    Class cls = NSClassFromString(@"SPTSnackbarInternalPresenterImplementation");
    if (!methodMatches(cls, @selector(initWithTheme:viewPresenter:imageLoader:isRTL:properties:messageOrchestrator:),
                       "@", @[@"@", @"@", @"@", @"B", @"@", @"@"]) ||
        !methodMatches(cls, @selector(presentSnackbarWithText:buttonTitle:actionBlock:presentationEndedBlock:),
                       "v", @[@"@", @"@", @"@?", @"@?"])) {
        SGLog(@"SponsorBlock: Spotify's action snackbar is unavailable; skipping disabled");
        return;
    }
    %init(SGSponsorBlockNotice);
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
        BOOL haptics = SGEnabled(SGKeySponsorBlockHaptics);
        NSMutableDictionary *behaviors = [NSMutableDictionary dictionary];
        for (NSString *category in SGSponsorBlockCategories())
            behaviors[category] = @(SGSponsorBlockReadBehavior(store, category));
        sg_session = [[SGSponsorBlockSession alloc] initWithBehaviors:behaviors minimum:SGSponsorBlockMinimum()
            respectManual:SGEnabled(SGKeySponsorBlockRespectManual)
            fetch:^(NSString *episode, NSSet *selected, SGSponsorBlockReply reply) {
                SGSponsorBlockFetchSegments(episode, selected, ^(NSArray *segments) {
                    if (!canSeek()) [sg_observer playerStateDidReport:SGPlayerState()];
                    reply(segments);
                });
            } seek:^(double seconds) {
                [(id<SPTPlayer>)SGPlayer() seekTo:seconds];
            } record:^dispatch_block_t(double seconds) {
                if (haptics) SGPlayFeedback(SGFeedbackSkip);
                return SGSponsorBlockRecordSkip(store, seconds);
            } notice:^(BOOL ask, SGSponsorBlockAction action) {
                NSString *text = ask ? SGL(@"settings.sponsorblock.prompt", @"Skip this podcast segment?")
                                     : SGL(@"settings.sponsorblock.skipped", @"Skipped a podcast segment");
                NSString *button = ask ? SGL(@"settings.sponsorblock.skip", @"Skip") : SGL(@"settings.sponsorblock.undo", @"Undo");
                [sg_presenter presentSnackbarWithText:text buttonTitle:button actionBlock:^{
                        dispatch_async(dispatch_get_main_queue(), action);
                    } presentationEndedBlock:nil];
            }];
        sg_session.schedule = ^dispatch_block_t(double delay, dispatch_block_t fire) { return scheduleBoundary(delay, fire); };
        sg_session.readLive = ^BOOL(NSString *episode, SGSponsorBlockReading *sample) { return readLive(episode, sample); };
        sg_observer = [SGSponsorBlockObserver new];
        SGAddPlayerStateObserver(sg_observer);
        if (SGPlayerState()) [sg_observer playerStateDidReport:SGPlayerState()];
    });
}
