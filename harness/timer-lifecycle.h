// Capture the scheduling boundary, not a page's private timer ivar. Timers never advance wall time.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "harness-fail.h"

static NSMutableArray<NSTimer *> *sg_testTimers;
static UIApplicationState sg_testAppState;
static IMP sg_testTargetOriginal, sg_testBlockOriginal, sg_testStateOriginal;
static IMP sg_testTargetReplacement, sg_testBlockReplacement, sg_testStateReplacement;

static inline void SGHarnessBeginTimerCapture(void) {
    sg_testTimers = [NSMutableArray array];
    sg_testAppState = UIApplicationStateActive;
    Method target = class_getClassMethod(NSTimer.class, @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:));
    Method block = class_getClassMethod(NSTimer.class, @selector(scheduledTimerWithTimeInterval:repeats:block:));
    Method state = class_getInstanceMethod(UIApplication.class, @selector(applicationState));
    sg_testTargetOriginal = method_getImplementation(target);
    sg_testBlockOriginal = method_getImplementation(block);
    sg_testStateOriginal = method_getImplementation(state);
    sg_testTargetReplacement = imp_implementationWithBlock(^NSTimer *(id cls, NSTimeInterval interval, id receiver, SEL selector, id info, BOOL repeats) {
        NSTimer *timer = [NSTimer timerWithTimeInterval:interval target:receiver selector:selector userInfo:info repeats:repeats];
        [sg_testTimers addObject:timer];
        return timer;
    });
    sg_testBlockReplacement = imp_implementationWithBlock(^NSTimer *(id cls, NSTimeInterval interval, BOOL repeats, void (^callback)(NSTimer *)) {
        NSTimer *timer = [NSTimer timerWithTimeInterval:interval repeats:repeats block:callback];
        [sg_testTimers addObject:timer];
        return timer;
    });
    sg_testStateReplacement = imp_implementationWithBlock(^UIApplicationState(id app) { return sg_testAppState; });
    method_setImplementation(target, sg_testTargetReplacement);
    method_setImplementation(block, sg_testBlockReplacement);
    method_setImplementation(state, sg_testStateReplacement);
}

static inline NSUInteger SGHarnessLiveTimers(void) {
    NSUInteger live = 0;
    for (NSTimer *timer in sg_testTimers) live += timer.valid;
    return live;
}

static inline void SGHarnessEndTimerCapture(void) {
    for (NSTimer *timer in sg_testTimers) [timer invalidate];
    method_setImplementation(class_getClassMethod(NSTimer.class, @selector(scheduledTimerWithTimeInterval:target:selector:userInfo:repeats:)), sg_testTargetOriginal);
    method_setImplementation(class_getClassMethod(NSTimer.class, @selector(scheduledTimerWithTimeInterval:repeats:block:)), sg_testBlockOriginal);
    method_setImplementation(class_getInstanceMethod(UIApplication.class, @selector(applicationState)), sg_testStateOriginal);
    imp_removeBlock(sg_testTargetReplacement);
    imp_removeBlock(sg_testBlockReplacement);
    imp_removeBlock(sg_testStateReplacement);
    sg_testTimers = nil;
}

static inline void SGHarnessCheckPageBackground(UIViewController *page) {
    SGHarnessBeginTimerCapture();
    [page loadViewIfNeeded];
    [page viewWillAppear:NO];
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    [page viewWillAppear:NO];
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    // UIKit has not changed applicationState yet when this notification arrives.
    [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    sg_testAppState = UIApplicationStateBackground;
    [center postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
    [page viewWillAppear:NO];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    sg_testAppState = UIApplicationStateActive;
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    [page viewDidDisappear:NO];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    HARNESS_CHECK(SGHarnessLiveTimers() == 0);
    [page viewWillAppear:NO];
    HARNESS_CHECK(SGHarnessLiveTimers() == 1);
    [page viewDidDisappear:NO];
    SGHarnessEndTimerCapture();
}
