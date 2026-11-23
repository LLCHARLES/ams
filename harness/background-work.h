// Extend the existing fake lifecycle to common-mode timers, without advancing wall time.
#import "timer-lifecycle.h"

static IMP sg_commonOriginal, sg_commonReplacement;
static inline void SGHarnessBeginBackgroundWork(void) {
    SGHarnessBeginTimerCapture();
    Method method = class_getInstanceMethod(NSRunLoop.class, @selector(addTimer:forMode:));
    sg_commonOriginal = method_getImplementation(method);
    sg_commonReplacement = imp_implementationWithBlock(^(NSRunLoop *loop, NSTimer *timer, NSRunLoopMode mode) {
        [sg_testTimers addObject:timer];
    });
    method_setImplementation(method, sg_commonReplacement);
}
static inline void SGHarnessEndBackgroundWork(void) {
    method_setImplementation(class_getInstanceMethod(NSRunLoop.class, @selector(addTimer:forMode:)), sg_commonOriginal);
    imp_removeBlock(sg_commonReplacement);
    SGHarnessEndTimerCapture();
}
