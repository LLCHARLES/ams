// Shared by the real album and artist harness apps. Only AVFoundation's
// asynchronous boundaries are held; the queue, decoder and compositor are real.
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import "Redesigned/Kit/SGRField.h"
#import "Redesigned/Kit/SGRFluid.h"
#import "../harness-fail.h"

extern __weak UIView *harnessSettledPlayerField;
extern NSNotificationName const SGRPlayerVisibilityDidChangeNotification;
@interface UIView (HarnessMotionFile)
- (void)showFile:(NSURL *)file;
- (void)showMotion:(NSURL *)file;
@end

static BOOL reduce, lowPower, failCapture, delaySeek, delayLayer, holdClock;
static NSProcessInfoThermalState heat;
static void (^pendingSeek)(BOOL);
static AVPlayerLayer *pendingLayer;
static __weak AVPlayer *pendingPlayer;
static BOOL testingMotion;

BOOL UIAccessibilityIsReduceMotionEnabled(void) {
    if (testingMotion) return reduce;
    return ((BOOL (*)(void))dlsym(RTLD_NEXT, "UIAccessibilityIsReduceMotionEnabled"))();
}

static void untilMotion(NSString *event, BOOL (^condition)(void)) {
    double end = CACurrentMediaTime() + 8;
    while (!condition() && CACurrentMediaTime() < end)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    if (!condition()) HARNESS_FAIL(@"waiting for %@", event);
}
static void postMotion(NSNotificationName name) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
}
static void drainMotionCallbacks(void) {
    __block BOOL done = NO;
    dispatch_async(dispatch_get_main_queue(), ^{ done = YES; });
    untilMotion(@"AV callback delivered", ^BOOL{ return done; });
}
static void motionBoundaries(void) {
    testingMotion = YES;
    Class info = object_getClass(NSProcessInfo.processInfo);
    method_setImplementation(class_getInstanceMethod(info, @selector(thermalState)),
        imp_implementationWithBlock(^NSProcessInfoThermalState(id unused) { return heat; }));
    method_setImplementation(class_getInstanceMethod(info, @selector(isLowPowerModeEnabled)),
        imp_implementationWithBlock(^BOOL(id unused) { return lowPower; }));
    SEL seek = @selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:);
    Method m = class_getInstanceMethod(AVPlayerItem.class, seek);
    void (*realSeek)(id, SEL, CMTime, CMTime, CMTime, void (^)(BOOL)) = (void *)method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(AVPlayerItem *item, CMTime t, CMTime a, CMTime b, void (^done)(BOOL)) {
        // AVPlayerLooper itself seeks its replicas to zero (without a
        // completion). Hold only the page's exact, nonzero restoration seek.
        if (!delaySeek || !done || CMTimeCompare(t, kCMTimeZero) <= 0) { realSeek(item, seek, t, a, b, done); return; }
        __weak AVPlayerItem *weak = item;
        pendingSeek = ^(BOOL finish) {
            if (finish && weak) realSeek(weak, seek, t, a, b, done);
            else done(finish);
        };
    }));
    SEL make = @selector(playerLayerWithPlayer:);
    m = class_getClassMethod(AVPlayerLayer.class, make);
    id (*realLayer)(id, SEL, id) = (void *)method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^id(id cls, AVPlayer *p) {
        AVPlayerLayer *layer = realLayer(cls, make, delayLayer ? nil : p);
        if (delayLayer) {
            layer.backgroundColor = UIColor.magentaColor.CGColor; // distinguish premature reveal from the backing still
            pendingLayer = layer; pendingPlayer = p;
        }
        return layer;
    }));
    m = class_getInstanceMethod(AVPlayer.class, @selector(play));
    void (*play)(id, SEL) = (void *)method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(AVPlayer *p) {
        if (!holdClock) play(p, @selector(play));
    }));
    SEL copy = @selector(copyPixelBufferForItemTime:itemTimeForDisplay:);
    m = class_getInstanceMethod(AVPlayerItemVideoOutput.class, copy);
    CVPixelBufferRef (*realCopy)(id, SEL, CMTime, CMTime *) = (void *)method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^CVPixelBufferRef(id o, CMTime t, CMTime *pts) {
        return failCapture ? NULL : realCopy(o, copy, t, pts);
    }));
}

// At a held boundary the host samples the composited screen, not a backing
// layer. A FIFO ack keeps the *first* exposed frame in place for simctl io.
static void shot(NSString *name, UIView *header) {
    [CATransaction flush];
    CGRect rect = [header convertRect:header.bounds toView:header.window];
    CGFloat scale = header.window.screen.scale;
    NSString *pipe = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame.fifo"];
    unlink(pipe.fileSystemRepresentation);
    HARNESS_CHECK(mkfifo(pipe.fileSystemRepresentation, 0600) == 0);
    NSLog(@"[harness] FRAME %@ %.0f %.0f %.0f %.0f %@", name, rect.origin.x*scale, rect.origin.y*scale,
          rect.size.width*scale, rect.size.height*scale, pipe);
    int fd = open(pipe.fileSystemRepresentation, O_RDONLY);
    char ack;
    HARNESS_CHECK(fd >= 0 && read(fd, &ack, 1) == 1);
    close(fd);
    unlink(pipe.fileSystemRepresentation);
}

static AVQueuePlayer *graph(UIView *h) { return [h valueForKeyPath:@"clip.player"]; }
static CALayer *surface(UIView *h) { return [h valueForKeyPath:@"clip.layer"]; }
static void releaseCheck(UIView *h, dispatch_block_t hide) {
    AVQueuePlayer *p = graph(h);
    NSArray<AVPlayerItem *> *items = p.items;
    AVPlayerLayer *layer = [h valueForKeyPath:@"clip.video"];
    HARNESS_CHECK(p && items.count);
    hide();
    untilMotion(@"hidden graph released after transition", ^BOOL{ return !graph(h); });
    HARNESS_CHECK(!graph(h) && ![h valueForKeyPath:@"clip.looper"] && ![h valueForKeyPath:@"clip.output"] &&
                  ![h valueForKeyPath:@"clip.replica"] && !layer.player && !p.items.count);
    for (AVPlayerItem *item in items) HARNESS_CHECK(!item.outputs.count);
}

@interface MotionPop : NSObject <UINavigationControllerDelegate, UIViewControllerAnimatedTransitioning>
@property (strong) UIPercentDrivenInteractiveTransition *driver;
@property (weak) UIView *outgoing;
@end
@implementation MotionPop
- (id<UIViewControllerAnimatedTransitioning>)navigationController:(UINavigationController *)nav
    animationControllerForOperation:(UINavigationControllerOperation)op fromViewController:(UIViewController *)from
    toViewController:(UIViewController *)to { return op == UINavigationControllerOperationPop ? self : nil; }
- (id<UIViewControllerInteractiveTransitioning>)navigationController:(UINavigationController *)nav
    interactionControllerForAnimationController:(id<UIViewControllerAnimatedTransitioning>)anim { return self.driver; }
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)ctx { return 0.35; }
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)ctx {
    UIView *from = [ctx viewForKey:UITransitionContextFromViewKey], *to = [ctx viewForKey:UITransitionContextToViewKey];
    [ctx.containerView insertSubview:to belowSubview:from];
    self.outgoing = from;
    [UIView animateWithDuration:[self transitionDuration:ctx] delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        from.transform = CGAffineTransformMakeTranslation(from.bounds.size.width, 0);
    } completion:^(BOOL finished) {
        self.outgoing = nil;
        [ctx completeTransition:!ctx.transitionWasCancelled];
        from.transform = CGAffineTransformIdentity;
    }];
}
@end

static double footprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    HARNESS_CHECK(task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) == KERN_SUCCESS);
    return info.phys_footprint / 1048576.;
}

static UIView *mountMotion(UIView *parent, BOOL artist) {
    UIView *header = [[NSClassFromString(artist ? @"SGRArtistMotionView" : @"SGRAlbumHero") alloc]
                      initWithFrame:CGRectMake(0, 0, 240, 144)];
    header.backgroundColor = UIColor.magentaColor;
    [parent addSubview:header];
    [header layoutIfNeeded];
    return header;
}
static void deliver(UIView *h, NSURL *file, BOOL artist) {
    if (artist) [h showFile:file]; else [h showMotion:file];
}
static void awaitPlaying(UIView *h) {
    untilMotion(@"visible clip playing", ^BOOL{ return graph(h).rate > 0; });
}
static void awaitPausedFrame(UIView *h) {
    untilMotion(@"decoded target revealed", ^BOOL{
        AVPlayerLayer *video = [h valueForKeyPath:@"clip.video"];
        if (!video || video.opacity != 1) return NO;
        CVPixelBufferRef pixel = [video copyDisplayedPixelBuffer];
        if (!pixel) return NO;
        CVPixelBufferRelease(pixel);
        return YES;
    });
}

static void exerciseMotion(UINavigationController *nav, BOOL artist) {
    // Start sampling after a completed page entrance, not while SpringBoard
    // is still scaling the launching window into its final pixel coordinates.
    [nav pushViewController:[UIViewController new] animated:YES];
    untilMotion(@"header page entrance committed", ^BOOL{ return !nav.transitionCoordinator; });
    motionBoundaries();
    UIWindow *window = nav.view.window;
    UIViewController *owner = nav.topViewController, *cover = [UIViewController new];
    cover.view.backgroundColor = UIColor.blackColor;
    MotionPop *pop = [MotionPop new];
    nav.delegate = pop;
    UIScrollView *list = [[UIScrollView alloc] initWithFrame:CGRectMake(12, 160, 240, 144)];
    list.showsVerticalScrollIndicator = NO; // the poster-only reference has no scroll indicator
    list.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    list.contentSize = CGSizeMake(240, 1000);
    [owner.view addSubview:list];
    UIView *h = mountMotion(list, artist);
    // The compositor can still be fading in the *window* on the first
    // sample. Compare poster paths with a simultaneous poster-only hero.
    UIViewController *sibling = [UIViewController new];
    [owner addChildViewController:sibling];
    sibling.view.frame = CGRectOffset(list.frame, 0, 200);
    [owner.view addSubview:sibling.view];
    [sibling didMoveToParentViewController:owner];
    mountMotion(sibling.view, artist);
    NSURL *file = [NSBundle.mainBundle URLForResource:@"motion-fixture" withExtension:@"mp4"];
    HARNESS_CHECK(file && window);
    untilMotion(@"navigation owner's view mounted", ^BOOL{ return h.window != nil; });
    reduce = YES;
    list.hidden = YES;
    deliver(h, file, artist);
    HARNESS_CHECK(!graph(h));
    postMotion(UIApplicationDidReceiveMemoryWarningNotification);
    delayLayer = YES;
    list.hidden = NO; // already held: prepare a static frame, not a playing graph
    untilMotion(@"first frame held", ^BOOL{ return pendingLayer != nil; });
    AVPlayer *beforeFrame = graph(h);
    postMotion(UIApplicationDidReceiveMemoryWarningNotification);
    HARNESS_CHECK(beforeFrame == graph(h) && beforeFrame && !surface(h).opacity);
    shot(@"poster", h);
    releaseCheck(h, ^{ list.hidden = YES; });
    pendingLayer = nil;
    beforeFrame = nil;
    reduce = NO;
    list.hidden = NO;
    untilMotion(@"second visible layer preparing", ^BOOL{ return pendingLayer != nil; });
    reduce = YES; // switch the hold on *after* preparation but before readiness
    postMotion(UIAccessibilityReduceMotionStatusDidChangeNotification);
    drainMotionCallbacks();
    delayLayer = NO;
    pendingLayer.backgroundColor = nil;
    pendingLayer.player = pendingPlayer;
    pendingLayer = nil;
    awaitPausedFrame(h);
    HARNESS_CHECK(!graph(h).rate);
    untilMotion(@"held entrance complete", ^BOOL{ return ![surface(h) animationForKey:@"fade"]; });
    shot(@"held-first", h);
    reduce = NO;
    postMotion(UIAccessibilityReduceMotionStatusDidChangeNotification);
    awaitPlaying(h);
    AVPlayer *outgoing = graph(h);
    pop.driver = [UIPercentDrivenInteractiveTransition new];
    [nav popViewControllerAnimated:YES];
    untilMotion(@"playing outgoing animation installed", ^BOOL{ return pop.outgoing != nil; });
    [pop.driver updateInteractiveTransition:0.25];
    untilMotion(@"outgoing model offscreen, presentation visible", ^BOOL{
        return CGRectGetMinX(pop.outgoing.frame) >= window.bounds.size.width &&
               CGRectGetMinX(((CALayer *)pop.outgoing.layer.presentationLayer).frame) < window.bounds.size.width / 2;
    });
    [h setNeedsLayout]; [h layoutIfNeeded];
    postMotion(UIApplicationDidReceiveMemoryWarningNotification);
    if (graph(h) != outgoing || !outgoing.rate)
        HARNESS_FAIL(@"outgoing graph changed mid-pop: window=%@ owner=%@ bound owner=%@ leaving=%@ rate=%g same=%d",
            h.window, owner, [h valueForKeyPath:@"clipPage.owner"], [h valueForKeyPath:@"clipPage.subscribers.leaving"],
            outgoing.rate, graph(h) == outgoing);
    [pop.driver cancelInteractiveTransition];
    untilMotion(@"outgoing pop cancelled", ^BOOL{ return !nav.transitionCoordinator; });
    HARNESS_CHECK(nav.topViewController == owner);
    HARNESS_CHECK(graph(h) == outgoing && outgoing.rate > 0);
    // A container can retain the disappeared view in the same viewport.
    [owner beginAppearanceTransition:NO animated:NO];
    releaseCheck(h, ^{ [owner endAppearanceTransition]; });
    HARNESS_CHECK(h.window);
    [owner beginAppearanceTransition:YES animated:NO];
    [owner endAppearanceTransition];
    awaitPlaying(h);
    outgoing = nil;
    UIView *field = [[UIView alloc] initWithFrame:CGRectOffset(list.frame, 239, 0)];
    [owner.view addSubview:field];
    harnessSettledPlayerField = field;
    postMotion(SGRPlayerVisibilityDidChangeNotification);
    HARNESS_CHECK(graph(h).rate > 0);
    field.frame = list.frame;
    [sibling beginAppearanceTransition:NO animated:NO];
    [sibling endAppearanceTransition];
    drainMotionCallbacks();
    HARNESS_CHECK(graph(h).rate > 0); // no visibility event for h's owner
    releaseCheck(h, ^{ postMotion(SGRPlayerVisibilityDidChangeNotification); });
    harnessSettledPlayerField = nil;
    postMotion(SGRPlayerVisibilityDidChangeNotification);
    awaitPlaying(h);
    releaseCheck(h, ^{ list.contentOffset = CGPointMake(0, 144); });
    list.contentOffset = CGPointMake(0, 143);
    awaitPlaying(h);
    list.contentOffset = CGPointZero;
    AVPlayer *visible = graph(h);
    postMotion(UIApplicationDidReceiveMemoryWarningNotification);
    HARNESS_CHECK(visible == graph(h) && visible.rate > 0);
    SGRArtworkField *art = [[SGRArtworkField alloc] initWithFrame:field.frame];
    [owner.view insertSubview:art atIndex:0];
    art.fluid = YES;
    SGRFluidLayer *fluid = [art valueForKey:@"fluidLayer"];
    for (NSNumber *state in @[@1,@2,@0,@3,@1,@4,@1]) {
        BOOL wasLowPower = lowPower;
        lowPower = state.intValue == 4;
        heat = lowPower ? NSProcessInfoThermalStateFair : (NSProcessInfoThermalState)state.intValue;
        NSNotificationName name = lowPower != wasLowPower ? NSProcessInfoPowerStateDidChangeNotification : NSProcessInfoThermalStateDidChangeNotification;
        __block BOOL delivered = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            postMotion(name);
            // Both observers enqueue their updates on main. Don't advance the
            // input just because playback already matched before they read it.
            dispatch_async(dispatch_get_main_queue(), ^{ delivered = YES; });
        });
        BOOL moving = !lowPower && heat < NSProcessInfoThermalStateSerious;
        double deadline = CACurrentMediaTime() + 30;
        while (!delivered || (visible.rate > 0) != moving || fluid.moving != moving) {
            if (CACurrentMediaTime() >= deadline)
                HARNESS_FAIL(@"%@ heat %ld low power %d delivered %d: expected moving %d; rate %g same graph %d fluid %d app state %ld",
                             name, (long)heat, lowPower, delivered, moving, visible.rate, visible == graph(h), fluid.moving,
                             (long)UIApplication.sharedApplication.applicationState);
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
    }
    untilMotion(@"numbered frame 3", ^BOOL{ double t = CMTimeGetSeconds(visible.currentTime); return t > 3.15 && t < 3.8; });
    postMotion(UIApplicationWillResignActiveNotification);
    HARNESS_CHECK(visible == graph(h) && !visible.rate);
    shot(@"last", h);
    holdClock = YES;
    postMotion(UIApplicationDidBecomeActiveNotification);
    releaseCheck(h, ^{ [nav pushViewController:cover animated:NO]; });
    HARNESS_CHECK(surface(h).contents);
    visible = nil;
    delaySeek = YES;
    for (NSNumber *cancel in @[@YES,@NO]) {
        pop.driver = [UIPercentDrivenInteractiveTransition new];
        [nav popViewControllerAnimated:YES];
        untilMotion(@"interactive animation installed", ^BOOL{ return pop.outgoing != nil; });
        [pop.driver updateInteractiveTransition:0.12];
        untilMotion(@"first exposed strip", ^BOOL{
            return h.window && ((CALayer *)pop.outgoing.layer.presentationLayer).frame.origin.x > 32;
        });
        shot(cancel.boolValue ? @"cancel-strip" : @"return-strip", h);
        [pop.driver updateInteractiveTransition:0.86];
        untilMotion(@"exposed destination", ^BOOL{
            return h.window && ((CALayer *)pop.outgoing.layer.presentationLayer).frame.origin.x > 255;
        });
        shot(cancel.boolValue ? @"cancel" : @"exposed", h);
        if (cancel.boolValue) [pop.driver cancelInteractiveTransition]; else [pop.driver finishInteractiveTransition];
        untilMotion(@"pop settled", ^BOOL{ return !nav.transitionCoordinator; });
        if (cancel.boolValue) HARNESS_CHECK(nav.topViewController == cover && !graph(h));
    }
    untilMotion(@"seek held", ^BOOL{ return pendingSeek != nil; });
    shot(@"seeking", h);
    pendingSeek(NO); pendingSeek = nil;
    // A failed seek must not expose the replica's frame zero.
    drainMotionCallbacks();
    if ([h valueForKeyPath:@"clip.video"]) awaitPausedFrame(h);
    shot(@"failed-seek", h);
    HARNESS_CHECK(![h valueForKeyPath:@"clip.video"]);
    list.hidden = YES;
    list.hidden = NO;
    untilMotion(@"second seek held", ^BOOL{ return pendingSeek != nil; });
    delayLayer = YES;
    pendingSeek(YES); pendingSeek = nil;
    untilMotion(@"target layer requested", ^BOOL{ return pendingLayer != nil; });
    drainMotionCallbacks();
    shot(@"unready", h);
    delaySeek = delayLayer = NO;
    pendingLayer.backgroundColor = nil;
    pendingLayer.player = pendingPlayer;
    pendingLayer = nil;
    awaitPausedFrame(h);
    // Sample the decoded target, not its indistinguishable backing still.
    [CATransaction begin]; [CATransaction setDisableActions:YES]; surface(h).contents = nil; [CATransaction commit];
    shot(@"resumed", h);
    holdClock = NO;
    postMotion(SGRPlayerVisibilityDidChangeNotification);
    awaitPlaying(h);
    releaseCheck(h, ^{ postMotion(UIApplicationDidEnterBackgroundNotification); });
    reduce = YES;
    postMotion(UIApplicationDidBecomeActiveNotification);
    HARNESS_CHECK(!graph(h) && surface(h).contents);
    shot(@"reduce", h);
    reduce = NO;
    delaySeek = YES;
    postMotion(UIAccessibilityReduceMotionStatusDidChangeNotification);
    untilMotion(@"old seek held", ^BOOL{ return pendingSeek != nil; });
    list.hidden = YES;
    NSURL *other = [NSBundle.mainBundle URLForResource:@"replacement" withExtension:@"mp4"];
    deliver(h, other, artist);
    pendingSeek(YES); pendingSeek = nil;
    delaySeek = NO;
    list.hidden = NO;
    awaitPlaying(h);
    untilMotion(@"replacement entrance complete", ^BOOL{ return ![surface(h) animationForKey:@"fade"]; });
    shot(@"replacement", h);
    failCapture = YES;
    releaseCheck(h, ^{ list.hidden = YES; });
    reduce = YES;
    delayLayer = YES;
    list.hidden = NO;
    untilMotion(@"failed capture leaves poster until replacement ready", ^BOOL{ return pendingLayer != nil; });
    HARNESS_CHECK(!graph(h).rate && !surface(h).contents);
    shot(@"failed-capture", h);
    delayLayer = NO;
    pendingLayer.backgroundColor = nil;
    pendingLayer.player = pendingPlayer;
    pendingLayer = nil;
    failCapture = reduce = NO;

    // Warm process, same mounted page/view count for both readings. Spin the
    // outer run loop between pages so autoreleased AV/CA resources drain.
    NSMutableArray *pages = [NSMutableArray array], *owners = [NSMutableArray array];
    UIViewController *top = [UIViewController new];
    for (int i=0; i<5; ++i) {
        UIViewController *page = [UIViewController new];
        UIView *hero = mountMotion(page.view, artist);
        [pages addObject:hero];
        [owners addObject:page];
        [nav pushViewController:page animated:NO];
    }
    [nav pushViewController:top animated:NO];
    [CATransaction flush];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    double base = footprint();
    [nav setViewControllers:@[owner] animated:NO];
    [nav pushViewController:owners.firstObject animated:NO];
    NSHashTable *retired = [NSHashTable weakObjectsHashTable];
    for (NSUInteger i = 0; i < pages.count; i++) @autoreleasepool {
        UIView *hero = pages[i];
        deliver(hero, file, artist);
        awaitPlaying(hero);
        // These five pages measure *retained stills*. Wait for a displayed
        // numbered frame, not just a nonzero requested playback rate.
        untilMotion(@"stack page has a decoded frame", ^BOOL{
            AVPlayerItem *item = graph(hero).currentItem;
            AVPlayerItemVideoOutput *out = [hero valueForKeyPath:@"clip.output"];
            return CMTimeGetSeconds(item.currentTime) >= 1 && [out hasNewPixelBufferForItemTime:item.currentTime];
        });
        [retired addObject:graph(hero)];
        [retired addObject:[hero valueForKeyPath:@"clip.looper"]];
        [retired addObject:[hero valueForKeyPath:@"clip.output"]];
        releaseCheck(hero, ^{ [nav pushViewController:i+1 < owners.count ? owners[i+1] : top animated:NO]; });
        HARNESS_CHECK(surface(hero).contents);
    }
    [CATransaction flush];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
    NSUInteger bytes = 0;
    untilMotion(@"retired player/looper/output objects deallocated", ^BOOL{ return !retired.allObjects.count; });
    for (UIView *hero in pages) {
        HARNESS_CHECK(!graph(hero) && ![hero valueForKeyPath:@"clip.looper"] && ![hero valueForKeyPath:@"clip.output"]);
        CGImageRef image = (__bridge CGImageRef)surface(hero).contents;
        bytes += CGImageGetBytesPerRow(image) * CGImageGetHeight(image);
    }
    double after = footprint();
    NSLog(@"[harness] FOOTPRINT poster %.2f suspended %.2f delta/page %.2f MiB; five stills %.2f MiB",
          base, after, (after-base)/5, bytes/1048576.);
    NSLog(@"[harness] PASS %@ header playback: return, guards, release and holds", h.class);
    exit(0);
}

static void motionVisibilityCheck(UIWindow *window, BOOL artist) {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    nav.navigationBarHidden = YES;
    window.rootViewController = nav;
    [window makeKeyAndVisible];
    __block id observation = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            [NSNotificationCenter.defaultCenter removeObserver:observation];
            // The checks run UIKit's run loop while AV/KVO replies arrive on
            // the main dispatch queue; don't nest that wait inside its drain.
            [NSTimer scheduledTimerWithTimeInterval:0 repeats:NO block:^(NSTimer *timer) { exerciseMotion(nav, artist); }];
        }];
}
