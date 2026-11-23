// The scheduler runs 20 opportunities per simulated second. Its physical switch is independent
// of what Spotify sees through isPaused. The playback clock keeps advancing during suppression.
#import "Player.h"
#import "Shared/Player/PlayerState.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "../harness-fail.h"
#import <objc/runtime.h>

// Window geometry, not a desktop application. Mount delivers the same visibility notification
// as UIKit; geometry in these flat fixtures is already expressed in window coordinates.
@interface TrackerNode : NSObject
@property CGRect bounds;
@property CGFloat alpha;
@property (getter=isHidden) BOOL hidden;
@property BOOL clipsToBounds;
@property (nonatomic, copy) NSString *accessibilityIdentifier;
@property (nonatomic, weak) TrackerNode *superview;
@end
static TrackerNode *surface;
@implementation TrackerNode
- (instancetype)init { if ((self = [super init])) _alpha = 1; return self; }
- (id)window { return _superview.window ?: (self == surface ? self : nil); }
- (id)windowScene { return nil; }
- (void)didMoveToWindow {}
- (id)screen { return self; }
- (CGFloat)scale { return 3; }
- (CGRect)convertRect:(CGRect)rect toView:(id)view { return rect; }
@end
@interface TrackerLabel : TrackerNode
@property (copy) NSString *text;
@property (copy) NSAttributedString *attributedText;
@end
@implementation TrackerLabel
@end
// Hold the installer at the instant the runtime has published the invalidate hook, before
// method_setImplementation returns. The background caller must already be able to forward.
static dispatch_block_t atPublication;
static IMP publish(Method method, IMP imp) {
    IMP original = method_setImplementation(method, imp);
    if (method_getName(method) == @selector(invalidate) && atPublication) atPublication();
    return original;
}
#define method_setImplementation publish
#define UILabel TrackerLabel
#import "PlayerProgress.m"
#undef UILabel
#undef method_setImplementation

static CGRect cover;
static BOOL lyrics, twoColumns;
static NSUInteger position;
static char kNotice;
NSNotificationName const SGRPlayerVisibilityDidChangeNotification = @"settled";
NSString *const SGPlayerTransitionNotification = @"transition-began";
NSString *const SGPlayerTransitionEndedNotification = @"transition-ended";
NSNotificationName const SGPlayerSpeedDidChangeNotification = @"speed-changed";
@interface TrackerPlayback : NSObject
@property double duration, playbackSpeed;
@end
@implementation TrackerPlayback
@end
static TrackerPlayback *playback;
SPTPlayerState *SGPlayerState(void) { return (SPTPlayerState *)playback; }
BOOL SGRedesignedUI(void) { return NO; } // install on the scheduler double, not the system scheduler
BOOL SGRPlayerTwoColumns(void) { return twoColumns; }
BOOL SGRPlayerLyricsOpen(void) { return lyrics; }
CGRect SGRSettledPlayerRect(UIWindow *window) { return cover; }
void SGRObserveVisibility(UIView *view, dispatch_block_t changed) {
    HARNESS_CHECK(NSThread.isMainThread);
    objc_setAssociatedObject(view, &kNotice, changed, OBJC_ASSOCIATION_COPY_NONATOMIC);
}
static void settled(CGRect rect) {
    cover = rect;
    [NSNotificationCenter.defaultCenter postNotificationName:SGRPlayerVisibilityDidChangeNotification object:nil];
}
@interface TrackerSlider : TrackerNode
@property float value;
@property (getter=isTracking) BOOL tracking;
- (CGRect)trackRectForBounds:(CGRect)bounds;
@end
@implementation TrackerSlider
- (CGRect)trackRectForBounds:(CGRect)bounds { return bounds; }
- (void)setValue:(float)value animated:(BOOL)animated {
    if (SGRWritingProgress) SGRProgressSliderWrote((UISlider *)self);
    self.value = value;
}
@end

@interface NowPlaying_ElementsImpl_TestWeakWrapper : NSObject
@property (nonatomic) TrackerSlider *slider;
@property (nonatomic) TrackerLabel *label;
@property (nonatomic) TrackerLabel *remaining;
@property NSUInteger fires;
@end
@implementation NowPlaying_ElementsImpl_TestWeakWrapper
- (void)displayLinkFired:(id)link {
    ++_fires;
    [_slider setValue:position animated:NO];
    _label.text = @(position).stringValue;
    _remaining.text = @(position).stringValue;
}
@end
@interface TrackerLink : NSObject
@property (getter=isPaused) BOOL paused;
@property NowPlaying_ElementsImpl_TestWeakWrapper *target;
@property BOOL invalidatedOnWorker;
@property CAFrameRateRange preferredFrameRateRange;
@end
@implementation TrackerLink
- (void)setPreferredFramesPerSecond:(NSInteger)fps {
    _preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
}
+ (instancetype)displayLinkWithTarget:(id)owner selector:(SEL)selector {
    TrackerLink *link = [self new]; link.target = owner;
    link.preferredFrameRateRange = CAFrameRateRangeMake(20, 20, 20);
    return link;
}
- (NSUInteger)second {
    NSUInteger before = _target.fires;
    int opportunities = _preferredFrameRateRange.preferred;
    for (int i = 0; i < opportunities; ++i) if (!_paused) [_target displayLinkFired:self];
    return _target.fires - before;
}
- (void)invalidate { _paused = YES; _target = nil; _invalidatedOnWorker = !NSThread.isMainThread; }
@end
static void invalidateOnWorker(TrackerLink *link) {
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{ [link invalidate]; });
    HARNESS_CHECK(!dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)));
    HARNESS_CHECK(link.invalidatedOnWorker);
}

static TrackerSlider *railIn(TrackerNode *parent) {
    TrackerSlider *slider = [TrackerSlider new];
    slider.bounds = CGRectMake(0, 0, 342, 17);
    slider.superview = parent;
    return slider;
}

static void checkBindingAndRange(TrackerNode *bar) {
    NSMutableArray *failed = [NSMutableArray array];
    surface.accessibilityIdentifier = nil; // mini player's window is not the full-player container
    settled(CGRectNull);
    playback = [TrackerPlayback new];
    playback.duration = 150;
    playback.playbackSpeed = 1;
    SGRProgressPlaybackChanged(150, 1);
    NowPlaying_ElementsImpl_TestWeakWrapper *tracker = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    __attribute__((objc_precise_lifetime)) TrackerSlider *old = railIn(bar);
    tracker.slider = old;
    TrackerLink *clock = [TrackerLink displayLinkWithTarget:tracker selector:@selector(displayLinkFired:)];
    CAFrameRateRange own = CAFrameRateRangeMake(16, 30, 24);
    clock.preferredFrameRateRange = own;
    [clock second]; // confirm old
    HARNESS_CHECK([clock second] == 10);
    playback.playbackSpeed = 2;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerSpeedDidChangeNotification object:nil];
    if ([clock second] != 24) [failed addObject:@"notification-only 2x speed"];
    playback.playbackSpeed = 1;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerSpeedDidChangeNotification object:nil];
    settled(surface.bounds);
    HARNESS_CHECK([clock second] == 0);
    clock.paused = YES;
    old.superview = nil;
    settled(CGRectNull);
    tracker.slider = railIn(bar);
    SGRProgressOutputMounted((UIView *)tracker.slider);
    position = 137;
    HARNESS_CHECK([clock second] == 0);
    clock.paused = NO;
    // The first, unconfirmed second starts at Spotify's cadence. The scheduler snapshots
    // its opportunities at the start of each simulated second.
    if ([clock second] != 24 || tracker.slider.value != 137 || [clock second] != 10)
        [failed addObject:@"replacement while Spotify-paused"];

    TrackerNode *sticky = [TrackerNode new];
    sticky.accessibilityIdentifier = @"now-playing-sticky-header";
    sticky.superview = surface;
    NowPlaying_ElementsImpl_TestWeakWrapper *header = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    header.slider = railIn(sticky);
    TrackerLink *h = [TrackerLink displayLinkWithTarget:header selector:@selector(displayLinkFired:)];
    h.preferredFrameRateRange = own;
    [h second];
    if ([h second] != 24) [failed addObject:@"sticky slider range"];
    [h invalidate];

    NowPlaying_ElementsImpl_TestWeakWrapper *last = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    last.slider = railIn(bar);
    TrackerLink *l = [TrackerLink displayLinkWithTarget:last selector:@selector(displayLinkFired:)];
    l.preferredFrameRateRange = own;
    [l second];
    HARNESS_CHECK([l second] == 10);
    [l invalidate];
    if (!CAFrameRateRangeIsEqualToRange(l.preferredFrameRateRange, own))
        [failed addObject:@"range after invalidation"];
    [clock invalidate];
    if (failed.count) HARNESS_FAIL(@"%@", [failed componentsJoinedByString:@"; "]);
}

int main(void) { @autoreleasepool { @try {
    installProgress(TrackerLink.class);
    cover = CGRectNull;
    surface = [TrackerNode new];
    surface.bounds = CGRectMake(0, 0, 390, 840);
    TrackerNode *bar = [TrackerNode new];
    bar.bounds = CGRectMake(8, 720, 360, 30);
    bar.accessibilityIdentifier = @"SPTNowPlayingBar";
    bar.superview = surface;
    NowPlaying_ElementsImpl_TestWeakWrapper *mini = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    mini.slider = [TrackerSlider new];
    mini.slider.bounds = bar.bounds;
    mini.slider.superview = bar;
    TrackerLink *unrelated = [TrackerLink new];
    atPublication = ^{ invalidateOnWorker(unrelated); };
    TrackerLink *m = [TrackerLink displayLinkWithTarget:mini selector:@selector(displayLinkFired:)];
    atPublication = nil;
    HARNESS_CHECK(unrelated.isPaused);
    position = 11;
    HARNESS_CHECK([m second] == 20 && mini.slider.value == 11);
    mini.slider.bounds = CGRectMake(0, 0, 342, 17);
    SGRProgressRailChanged((UISlider *)mini.slider, NO);
    CAFrameRateRange own = CAFrameRateRangeMake(16, 30, 20);
    m.preferredFrameRateRange = own;
    SGRProgressPlaybackChanged(200, 1);
    HARNESS_CHECK([m second] == 10 && CAFrameRateRangeIsEqualToRange(m.preferredFrameRateRange, own));
    [m setPreferredFramesPerSecond:24];
    HARNESS_CHECK([m second] == 10 && m.preferredFrameRateRange.preferred == 24);
    mini.slider.tracking = YES;
    SGRProgressRailChanged((UISlider *)mini.slider, YES);
    HARNESS_CHECK([m second] == 24);
    m.preferredFrameRateRange = own;
    mini.slider.tracking = NO;
    SGRProgressRailChanged((UISlider *)mini.slider, NO);
    HARNESS_CHECK([m second] == 10);
    SGRProgressPlaybackChanged(60, 1);
    HARNESS_CHECK([m second] == 20);
    settled(surface.bounds);
    position = 97;
    HARNESS_CHECK(!m.isPaused && [m second] == 0 && mini.slider.value == 11);
    NSUInteger before = mini.fires;
    bar.hidden = YES;
    settled(CGRectNull);
    HARNESS_CHECK(mini.fires == before + 1 && mini.slider.value == 97);
    bar.hidden = NO;
    HARNESS_CHECK([m second] == 20);
    settled(surface.bounds);
    m.paused = YES;
    before = mini.fires;
    position = 99;
    settled(CGRectNull);
    HARNESS_CHECK(m.isPaused && [m second] == 0 && mini.fires == before);
    m.paused = NO;
    SGRProgressVisibilityChanged();
    HARNESS_CHECK(mini.slider.value == 99 && mini.fires == before + 1);
    HARNESS_CHECK([m second] == 20);

    NowPlaying_ElementsImpl_TestWeakWrapper *times = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    times.label = [TrackerLabel new];
    times.label.accessibilityIdentifier = @"now-playing-time-take-label-internal";
    times.remaining = [TrackerLabel new];
    times.remaining.accessibilityIdentifier = @"now-playing-time-remaning-label-internal";
    times.label.bounds = CGRectZero;
    TrackerLink *t = [TrackerLink displayLinkWithTarget:times selector:@selector(displayLinkFired:)];
    HARNESS_CHECK([t second] == 1 && [t second] == 0);
    position = 101;
    times.label.superview = surface;
    dispatch_block_t mounted = objc_getAssociatedObject(times.label, &kNotice);
    HARNESS_CHECK(mounted != nil);
    mounted();
    HARNESS_CHECK([times.label.text isEqual:@"101"] && [t second] == 20);
    times.label.bounds = CGRectMake(20, 100, 80, 20);
    surface.accessibilityIdentifier = @"SPTNowPlayingViewContainerViewController";
    settled(surface.bounds);
    // A held property animator has written the overlay's final model alpha. Neither the
    // held frames nor the reversal write another alpha; only the coordinator knows it ended.
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
    surface.alpha = 0;
    SGRProgressVisibilityChanged();
    HARNESS_CHECK([t second] == 20 && [t second] == 20);
    surface.alpha = 1;
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionEndedNotification object:nil];
    lyrics = YES;
    times.label.alpha = 0;
    SGRProgressVisibilityChanged();
    HARNESS_CHECK([t second] == 20);
    SGRProgressControlsFaded(YES);
    HARNESS_CHECK([t second] == 0);
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionNotification object:nil];
    HARNESS_CHECK([t second] == 20);
    [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerTransitionEndedNotification object:nil];
    HARNESS_CHECK([t second] == 0);
    twoColumns = YES;
    SGRProgressVisibilityChanged();
    HARNESS_CHECK([t second] == 20);
    twoColumns = NO;
    SGRProgressVisibilityChanged();
    position = 131;
    SGRProgressControlsFaded(NO);
    HARNESS_CHECK([times.label.text isEqual:@"131"] && times.label.alpha == 0);
    times.label.alpha = 1;

    NowPlaying_ElementsImpl_TestWeakWrapper *unknown = [NowPlaying_ElementsImpl_TestWeakWrapper new];
    TrackerLink *empty = [TrackerLink displayLinkWithTarget:unknown selector:@selector(displayLinkFired:)];
    settled(surface.bounds);
    HARNESS_CHECK([empty second] == 20);
    TrackerNode *sticky = [TrackerNode new];
    sticky.accessibilityIdentifier = @"now-playing-sticky-header";
    times.label.superview = sticky; // no window
    mounted();
    HARNESS_CHECK([t second] == 20);
    invalidateOnWorker(t);
    HARNESS_CHECK(t.isPaused && objc_getAssociatedObject(times.label, &kNotice) != nil);
    __block BOOL drained = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained = YES; });
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!drained && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:deadline];
    HARNESS_CHECK(drained && !objc_getAssociatedObject(times.label, &kNotice));
    [m invalidate]; [empty invalidate];
    HARNESS_CHECK(m.isPaused && t.isPaused && empty.isPaused);
    checkBindingAndRange(bar);
    puts("progress: covered mini 20/0/20 Hz, detached/mounted times 0/20 Hz, unknown 20 Hz; first reveal and requested pause passed");
    return 0;
} @catch (NSException *e) { HARNESS_FAIL(@"%@", e); } } }
