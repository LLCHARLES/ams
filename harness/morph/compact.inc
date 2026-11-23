// 9.1.90's ownership contract: one property animator, setup before start/pause, UIKit progress,
// Spotify's finish/cancel intent and its completion. No production-private geometry helpers.
static CGFloat recordedFactor;
static CGFloat cancelledFractionAtRelease;
static id<UITimingCurveProvider> recordedTiming;
static void (*continueUIKit)(id, SEL, id<UITimingCurveProvider>, CGFloat);
static void recordContinue(id object, SEL selector, id<UITimingCurveProvider> timing, CGFloat factor) {
    recordedFactor = factor;
    recordedTiming = timing;
    continueUIKit(object, selector, timing, factor);
}

@interface MorphUIKitBoundary : NSObject
@end
@implementation MorphUIKitBoundary
+ (void)load {
    // +load precedes Logos constructors: record what the hook hands to UIKit, not its input.
    Method method = class_getInstanceMethod(UIViewPropertyAnimator.class, @selector(continueAnimationWithTimingParameters:durationFactor:));
    continueUIKit = (void *)method_setImplementation(method, (IMP)recordContinue);
}
@end

@interface CompactContext : NSObject <UIViewControllerContextTransitioning>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UIViewController *from, *to;
@property (nonatomic, getter=isInteractive) BOOL interactive;
@property (nonatomic) BOOL cancelled, completed, result;
@end
@implementation CompactContext
- (BOOL)isAnimated { return YES; }
- (BOOL)transitionWasCancelled { return self.cancelled; }
- (UIModalPresentationStyle)presentationStyle { return UIModalPresentationFullScreen; }
- (CGAffineTransform)targetTransform { return CGAffineTransformIdentity; }
- (UIViewController *)viewControllerForKey:(UITransitionContextViewControllerKey)key {
    return [key isEqual:UITransitionContextFromViewControllerKey] ? self.from : self.to;
}
- (UIView *)viewForKey:(UITransitionContextViewKey)key {
    return [key isEqual:UITransitionContextFromViewKey] ? self.from.view : self.to.view;
}
- (CGRect)initialFrameForViewController:(UIViewController *)vc { return self.containerView.bounds; }
- (CGRect)finalFrameForViewController:(UIViewController *)vc { return self.containerView.bounds; }
- (void)updateInteractiveTransition:(CGFloat)p {}
- (void)finishInteractiveTransition { self.interactive = NO; }
- (void)cancelInteractiveTransition { self.cancelled = YES; self.interactive = NO; }
- (void)pauseInteractiveTransition {}
- (void)completeTransition:(BOOL)didComplete { self.completed = YES; self.result = didComplete; }
@end

@interface CompactPresentedController : UIViewController
@end
@implementation CompactPresentedController
- (BOOL)isBeingPresented { return YES; }
@end

// The alternate owner still performs Spotify's transition, but exposes no overlayView ivar.
// Compile the same fixture methods against its renamed storage, not a subclass inheriting the ivar.
#if MORPH_UNSUPPORTED_OWNER
#define overlayView unsupportedOverlayStorage
#endif
@interface _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition : NSObject {
@public
    UIViewPropertyAnimator *animator;
    CompactContext *transitionContext;
    UIView *overlayView, *npbSnapshotView, *tabBarSnapshotView, *blockingContentView;
    CGRect npbFrame;
}
- (void)animateTransition:(CompactContext *)context;
- (void)startInteractiveTransition:(CompactContext *)context;
- (NSTimeInterval)transitionDuration:(CompactContext *)context;
- (void)releaseCancelling:(BOOL)cancel;
@end
@implementation _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (NSTimeInterval)transitionDuration:(CompactContext *)context { return 0.30; }
- (void)setup:(CompactContext *)context {
    transitionContext = context;
    BOOL presenting = context.to.isBeingPresented;
    overlayView = presenting ? context.to.view : context.from.view;
    npbFrame = CGRectMake(0, 697, 390, 64); // Device trace: same top as the card, different width/height.
    npbSnapshotView = [[UIView alloc] initWithFrame:npbFrame];
    npbSnapshotView.alpha = 0;
    tabBarSnapshotView = [UIView new];
    blockingContentView = [UIView new];
    [context.containerView addSubview:npbSnapshotView];
    [context.containerView addSubview:tabBarSnapshotView];
    [context.containerView addSubview:blockingContentView];
    UIView *overlay = overlayView, *bar = npbSnapshotView;
    if (presenting) {
        overlay.frame = CGRectOffset(context.containerView.bounds, 0, 697);
        overlay.alpha = 0;
    }
    animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.30 curve:UIViewAnimationCurveEaseOut animations:^{
        overlay.frame = CGRectOffset(context.containerView.bounds, 0, presenting ? 0 : 697);
        overlay.alpha = presenting ? 1 : 0;
        bar.alpha = presenting ? 0 : 1;
    }];
    [animator addCompletion:^(__unused UIViewAnimatingPosition position) {
        if (context.transitionWasCancelled) {
            overlay.frame = context.containerView.bounds;
            overlay.alpha = 1;
        } else if (!presenting) {
            [overlay removeFromSuperview];
        }
        [context completeTransition:!context.transitionWasCancelled];
    }];
}
- (void)animateTransition:(CompactContext *)context { [self setup:context]; [animator startAnimation]; }
- (void)startInteractiveTransition:(CompactContext *)context { [self setup:context]; [animator pauseAnimation]; }
- (void)releaseCancelling:(BOOL)cancel {
    if (cancel) [transitionContext cancelInteractiveTransition];
    else [transitionContext finishInteractiveTransition];
    animator.reversed = cancel;
    CGFloat fraction = animator.fractionComplete;
    if (cancel) cancelledFractionAtRelease = fraction;
    [animator continueAnimationWithTimingParameters:[[UICubicTimingParameters alloc] initWithAnimationCurve:2]
                                    durationFactor:cancel ? fraction : 1 - fraction];
}
@end

#if MORPH_UNSUPPORTED_OWNER
#undef overlayView
#endif

@interface CompactPan : UIPanGestureRecognizer
@property (nonatomic) CGFloat progress, velocity;
@property (nonatomic) UIGestureRecognizerState testState;
@end
@implementation CompactPan
- (CGPoint)translationInView:(UIView *)view { return CGPointMake(0, self.progress * 697); }
- (CGPoint)velocityInView:(UIView *)view { return CGPointMake(0, self.velocity * 697); }
- (UIGestureRecognizerState)state { return self.testState; }
@end

@interface _TtC19MainUI_TabBarUIImpl25CompactGestureCoordinator : NSObject
@property (nonatomic, strong) _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition *transition;
@property (nonatomic) BOOL cancel;
- (void)handleDismissPan:(CompactPan *)pan;
- (void)scrollPanAction:(CompactPan *)pan;
@end
@implementation _TtC19MainUI_TabBarUIImpl25CompactGestureCoordinator
- (void)handleDismissPan:(CompactPan *)pan {
    if (pan.state == UIGestureRecognizerStateChanged) {
        self.transition->animator.fractionComplete = [pan translationInView:pan.view].y / 697;
        [self.transition->transitionContext updateInteractiveTransition:pan.progress];
    } else {
        [self.transition releaseCancelling:self.cancel];
    }
}
- (void)scrollPanAction:(CompactPan *)pan { [self handleDismissPan:pan]; }
@end

static void nearValue(CGFloat actual, CGFloat expected, NSString *what) {
    if (fabs(actual - expected) > 0.15)
        HARNESS_FAIL(@"%@ expected %.6f, got %.6f", what, expected, actual);
}
static void afterFrames(void (^block)(void)) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), block);
}

@interface CompactChecks : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) CompactContext *context;
@property (nonatomic, strong) _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition *transition;
@property (nonatomic, strong) _TtC19MainUI_TabBarUIImpl25CompactGestureCoordinator *coordinator;
@property (nonatomic, strong) CompactPan *pan;
@property (nonatomic) NSTimeInterval declaredDuration;
@end
@implementation CompactChecks
- (void)fixtureInteractive:(BOOL)interactive opening:(BOOL)opening {
    for (UIView *view in self.window.rootViewController.view.subviews) [view removeFromSuperview];
    UIView *root = self.window.rootViewController.view;
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(8, 697, 374, 56)];
    [root addSubview:card];
    sg_card = card;
    sg_barArt = nil;
    sg_cover = nil;
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    [root addSubview:container];
    CompactContext *context = [CompactContext new];
    context.containerView = container;
    context.from = [UIViewController new];
    context.to = opening ? [CompactPresentedController new] : [UIViewController new];
    context.from.view = [[UIView alloc] initWithFrame:container.bounds];
    context.from.view.backgroundColor = UIColor.blackColor;
    if (opening) {
        context.to.view = [[UIView alloc] initWithFrame:container.bounds];
        [container addSubview:context.to.view];
    } else {
        [container addSubview:context.from.view];
    }
    context.interactive = interactive;
    self.context = context;
    self.transition = [_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition new];
    self.declaredDuration = [self.transition transitionDuration:context]; // UIKit asks before setup.
    self.coordinator = [_TtC19MainUI_TabBarUIImpl25CompactGestureCoordinator new];
    self.coordinator.transition = self.transition;
    self.pan = [CompactPan new];
    [context.from.view addGestureRecognizer:self.pan];
    if (interactive) [self.transition startInteractiveTransition:context];
    else [self.transition animateTransition:context];
}
- (void)drag:(CGFloat)p velocity:(CGFloat)velocity {
    self.pan.progress = p;
    self.pan.velocity = velocity;
    self.pan.testState = UIGestureRecognizerStateChanged;
    [self.coordinator scrollPanAction:self.pan];
}
- (void)checkFrozen:(NSInteger)index {
    // Independent literals from the specification on the 390x844 / {{8,697},{374,56}} fixture.
    static const CGFloat values[][6] = {
        {0.55, 0, 383.35, 390, 460.65, 55},
        {0.70, 0, 487.90, 390, 356.10, 46.962963},
        {0.80, 2.074074, 557.60, 385.851852, 286.40, 36.927298},
        {1.00, 8, 697, 374, 56, 24}
    };
    CGFloat p = values[index][0];
    [self drag:p velocity:1];
    afterFrames(^{
        UIView *overlay = self.context.from.view;
        CALayer *shown = overlay.layer.presentationLayer;
        CALayer *mask = overlay.maskView.layer.presentationLayer;
        HARNESS_CHECK(shown && mask);
        CGFloat scale = shown.frame.size.width / overlay.bounds.size.width;
        CGRect visible = CGRectMake(shown.frame.origin.x + mask.frame.origin.x * scale,
                                    shown.frame.origin.y + mask.frame.origin.y * scale,
                                    mask.frame.size.width * scale, mask.frame.size.height * scale);
        nearValue(visible.origin.x, values[index][1], [NSString stringWithFormat:@"frozen p=%.2f left", p]);
        nearValue(visible.origin.y, values[index][2], @"frozen top");
        nearValue(visible.size.width, values[index][3], @"frozen width");
        nearValue(visible.size.height, values[index][4], @"frozen height");
        nearValue(mask.cornerRadius * scale, values[index][5], @"frozen radius");
        HARNESS_CHECK(fabs(shown.opacity - (index == 3 ? 0 : 1)) < 0.001);
        UIView *dim;
        for (UIView *view in self.context.containerView.subviews)
            if (view != overlay && CGRectEqualToRect(view.frame, CGRectMake(0, 0, 390, 844))) dim = view;
        HARNESS_CHECK(dim && fabs(dim.layer.presentationLayer.opacity - 0.30 * (1 - p)) < 0.001);
        HARNESS_CHECK(!self.context.completed && self.context.containerView.layer.speed == 1);
        // A frozen drag must survive beyond the old follower's 0.9-second timeout.
        if (index < 3) [self checkFrozen:index + 1];
        else dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            HARNESS_CHECK(overlay.maskView && !self.context.completed);
            [self cancelThen:^{ [self releaseCase:0]; }];
        });
    });
}
- (void)cancelThen:(void (^)(void))next {
    [self drag:0.0237 velocity:2];
    self.coordinator.cancel = YES;
    self.pan.testState = UIGestureRecognizerStateEnded;
    [self.coordinator handleDismissPan:self.pan];
    HARNESS_CHECK(fabs(cancelledFractionAtRelease - 0.9763) < 0.0001);
    HARNESS_CHECK(fabs(recordedFactor - 0.9763) < 0.0001);
    HARNESS_CHECK(fabs(((UICubicTimingParameters *)recordedTiming).controlPoint2.x - 0.13) < 0.0001);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        HARNESS_CHECK(self.context.completed && !self.context.result);
        HARNESS_CHECK(!self.context.from.view.maskView && !self.context.from.view.layer.mask);
        HARNESS_CHECK(CGRectEqualToRect(self.context.from.view.frame, CGRectMake(0, 0, 390, 844)));
        HARNESS_CHECK(self.context.from.view.alpha == 1 && self.context.containerView.layer.speed == 1);
        next();
    });
}
- (void)releaseCase:(NSInteger)index {
    // p, normalized velocity, duration seconds (0 means fixed curve), stale sample.
    static const CGFloat cases[][4] = {
        {0.50, 4, 0.1375, 0}, {0.50, 100, 0.05, 0}, {0.50, 0.1, 0.32, 0},
        {0.50, -4, 0, 0}, {0.99, 4, 0, 0}, {0.50, 4, 0, 1}
    };
    [self fixtureInteractive:YES opening:NO];
    [self drag:cases[index][0] velocity:cases[index][1]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (cases[index][3] ? 200 : 20) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (cases[index][3]) {
            [self.transition releaseCancelling:NO]; // delayed pending terminal intent, outside a gesture sample
        } else {
            self.pan.testState = UIGestureRecognizerStateEnded;
            [self.coordinator handleDismissPan:self.pan];
        }
        UICubicTimingParameters *timing = (id)recordedTiming;
        CGPoint a = timing.controlPoint1, b = timing.controlPoint2;
        HARNESS_CHECK(fabs(a.x - 0.245) < 0.0001 && fabs(a.y - 0.222) < 0.0001);
        CGFloat expectedFactor = cases[index][2] > 0 ? cases[index][2] / 0.32 : 1 - cases[index][0];
        HARNESS_CHECK(fabs(recordedFactor - expectedFactor) < 0.0001);
        HARNESS_CHECK(fabs(b.x - (cases[index][2] > 0 ? 0.7 : 0.13)) < 0.0001 && b.y == 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            HARNESS_CHECK(self.context.completed && self.context.result);
            HARNESS_CHECK(!self.context.from.view.superview && !self.context.from.view.layer.mask);
            if (index < 5) [self releaseCase:index + 1];
            else [self tapCheck];
        });
    });
}
- (void)tapCheck {
    [self fixtureInteractive:NO opening:NO];
    HARNESS_CHECK(fabs(self.transition->animator.duration - 0.32) < 0.0001);
    HARNESS_CHECK(fabs([self.transition transitionDuration:self.context] - 0.32) < 0.0001);
    HARNESS_CHECK(self.context.containerView.layer.speed == 1);
    UIViewPropertyAnimator *running = self.transition->animator;
    __weak id owner = self.transition;
    self.coordinator.transition = nil;
    self.transition = nil; // The real owner is already gone when its animator completes.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        HARNESS_CHECK(!owner && running.state == UIViewAnimatingStateInactive);
        HARNESS_CHECK(self.context.completed && self.context.result);
        [self protectedPathsCheck];
    });
}
- (void)backgroundCheck {
    // Capture UIKit's link boundary; the transition fixture itself uses a property animator.
    Method factory = class_getClassMethod(CADisplayLink.class, @selector(displayLinkWithTarget:selector:));
    Method invalidation = class_getInstanceMethod(CADisplayLink.class, @selector(invalidate));
    IMP originalFactory = method_getImplementation(factory), originalInvalidation = method_getImplementation(invalidation);
    __block CADisplayLink *captured;
    __block BOOL invalidated = NO;
    IMP capture = imp_implementationWithBlock(^CADisplayLink *(id cls, id target, SEL selector) {
        captured = ((id (*)(id, SEL, id, SEL))originalFactory)(cls, @selector(displayLinkWithTarget:selector:), target, selector);
        return captured;
    });
    IMP invalidate = imp_implementationWithBlock(^(CADisplayLink *link) {
        if (link == captured) invalidated = YES;
        ((void (*)(id, SEL))originalInvalidation)(link, @selector(invalidate));
    });
    method_setImplementation(factory, capture);
    method_setImplementation(invalidation, invalidate);
    [self fixtureInteractive:YES opening:NO];
    HARNESS_CHECK(captured && !invalidated && self.context.from.view.layer.mask);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    HARNESS_CHECK(invalidated && !self.context.from.view.layer.mask);
    HARNESS_CHECK(!self.context.completed && self.context.containerView.layer.speed == 1);
    method_setImplementation(factory, originalFactory);
    method_setImplementation(invalidation, originalInvalidation);
    imp_removeBlock(capture);
    imp_removeBlock(invalidate);
    [self.transition->animator stopAnimation:YES];
    puts("PASS resign cancels the interactive morph follower without completing Spotify's transition");
    exit(0);
}

- (void)offCheck {
    [self fixtureInteractive:YES opening:NO];
    HARNESS_CHECK(fabs(self.transition->animator.duration - 0.30) < 0.0001);
    HARNESS_CHECK(fabs([self.transition transitionDuration:self.context] - 0.30) < 0.0001);
    [self drag:0.55 velocity:1];
    afterFrames(^{
        // Today's follower: t=1-p, linear rect, uniform width scale, no UIView mask.
        UIView *overlay = self.context.from.view;
        HARNESS_CHECK(!overlay.maskView && overlay.layer.mask);
        nearValue(overlay.layer.mask.bounds.size.width, 381.2, @"off linear width");
        nearValue(overlay.layer.mask.bounds.size.height, 410.6, @"off linear height");
        nearValue(overlay.layer.mask.cornerRadius, 37.95, @"off linear radius");
        HARNESS_CHECK(fabs(overlay.layer.sublayerTransform.m11 - 381.2 / 390) < 0.0001);
        [self drag:0.10 velocity:1];
        [self.transition releaseCancelling:NO];
        afterFrames(^{
            HARNESS_CHECK(self.context.containerView.layer.speed == 1.5);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                HARNESS_CHECK(self.context.completed && self.context.result);
                HARNESS_CHECK(!overlay.layer.mask && self.context.containerView.layer.speed == 1);
                [self protectedPathsCheck];
            });
        });
    });
}
- (void)protectedPathsCheck {
    [self fixtureInteractive:NO opening:YES];
    HARNESS_CHECK(fabs(self.transition->animator.duration - 0.30) < 0.0001);
    HARNESS_CHECK(fabs([self.transition transitionDuration:self.context] - 0.30) < 0.0001);
    HARNESS_CHECK(self.context.containerView.layer.speed == 1);
    HARNESS_CHECK(!self.context.to.view.maskView && self.context.to.view.layer.mask);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_CHECK(self.context.completed && !self.context.to.view.layer.mask);
        SPTBarOverlayPresentationTransition *legacy = [SPTBarOverlayPresentationTransition new];
        legacy.overlayView = self.context.to.view;
        legacy.bottomBarView = sg_card;
        [legacy holdFrom:self.context.containerView at:0.45];
        nearValue(legacy.overlayView.layer.mask.bounds.size.width, 381.2, @"legacy linear width");
        nearValue(legacy.overlayView.layer.mask.bounds.size.height, 410.6, @"legacy linear height");
        nearValue(legacy.overlayView.layer.mask.cornerRadius, 37.95, @"legacy radius");
        [legacy destroyTransitioningContext];
        HARNESS_CHECK(!legacy.overlayView.layer.mask);
        sg_card = nil;
        self.context.from = self.context.to;
        self.context.to = [UIViewController new];
        self.context.from.view.frame = self.context.containerView.bounds;
        self.context.from.view.alpha = 1;
        self.context.completed = NO;
        self.transition = [_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition new];
        [self.transition animateTransition:self.context];
        HARNESS_CHECK(fabs([self.transition transitionDuration:self.context] - 0.30) < 0.0001);
        HARNESS_CHECK(fabs(self.transition->animator.duration - 0.30) < 0.0001);
        HARNESS_CHECK(!self.context.from.view.layer.mask && self.context.containerView.layer.speed == 1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            HARNESS_CHECK(self.context.completed && self.context.result);
            NSLog(@"[morph] PASS %@; opening, legacy and missing-card paths unchanged",
                  SGHidden(@"spotifyglass.redesign.player.musicClose") ?
                  @"compact geometry, dim, frozen lifetime, velocity release, cancel, tap" :
                  @"switch off preserves linear geometry, speed and teardown");
            exit(0);
        });
    });
}
- (void)unsupportedOwnerCheck {
    [self fixtureInteractive:NO opening:NO];
    if (fabs(self.declaredDuration - 0.30) > 0.0001)
        HARNESS_FAIL(@"unsupported owner duration expected 0.30, got %.2f", self.declaredDuration);
    HARNESS_CHECK(fabs([self.transition transitionDuration:self.context] - 0.30) < 0.0001);
    HARNESS_CHECK(fabs(self.transition->animator.duration - 0.30) < 0.0001);
    // The original follower, not Music-close geometry or its clock, still handles the close.
    HARNESS_CHECK(!self.context.from.view.maskView && self.context.from.view.layer.mask);
    HARNESS_CHECK(self.context.containerView.layer.speed == 1.5);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_CHECK(self.context.completed && self.context.result);
        HARNESS_CHECK(!self.context.from.view.layer.mask && self.context.containerView.layer.speed == 1);
        NSLog(@"[morph] PASS unsupported owner keeps original duration, animator and follower with switch on");
        exit(0);
    });
}
- (void)run {
    class_replaceMethod(UIScreen.class, NSSelectorFromString(@"_displayCornerRadius"),
                        imp_implementationWithBlock(^CGFloat(id screen) { return 55; }), "d@:");
#if MORPH_UNSUPPORTED_OWNER
    [self unsupportedOwnerCheck];
    return;
#endif
    if (getenv("MORPH_BACKGROUND")) { [self backgroundCheck]; return; }
    if (!SGHidden(@"spotifyglass.redesign.player.musicClose")) { [self offCheck]; return; }
    [self fixtureInteractive:YES opening:NO];
    HARNESS_CHECK(fabs(self.transition->animator.duration - 0.32) < 0.0001);
    UICubicTimingParameters *timing = (id)self.transition->animator.timingParameters;
    HARNESS_CHECK(fabs(timing.controlPoint1.x - 0.245) < 0.0001 && fabs(timing.controlPoint2.x - 0.13) < 0.0001);
    [self checkFrozen:0];
}
@end

static void runCompactChecks(UIWindow *window) {
    static CompactChecks *checks;
    checks = [CompactChecks new];
    checks.window = window;
    afterFrames(^{ [checks run]; });
}
