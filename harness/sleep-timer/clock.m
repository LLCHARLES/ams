#import "clock.h"
#import <objc/runtime.h>
#import "../harness-fail.h"

@interface HarnessClockEvent : NSObject
@property NSTimeInterval at, interval;
@property NSTimer *timer;
@property (copy) dispatch_block_t block;
@end
@implementation HarnessClockEvent @end

static BOOL controlled;
static NSTimeInterval now;
static NSMutableArray<HarnessClockEvent *> *events;
static IMP originalDate, originalRemaining, originalTimer;

static NSDate *dateFromNow(id self, SEL selector, NSTimeInterval seconds) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:now + seconds];
}
static NSTimeInterval remaining(id self, SEL selector) {
    return [self timeIntervalSinceReferenceDate] - now;
}
static NSTimer *makeTimer(id self, SEL selector, NSTimeInterval interval, BOOL repeats, void (^block)(NSTimer *)) {
    NSTimer *timer = ((id (*)(id, SEL, NSTimeInterval, BOOL, id))originalTimer)(self, selector, interval, repeats, block);
    HarnessClockEvent *event = [HarnessClockEvent new];
    event.at = now + interval;
    event.interval = repeats ? interval : 0;
    event.timer = timer;
    [events addObject:event];
    return timer;
}
BOOL HarnessClockControlled(void) { return controlled; }
void HarnessClockStart(void) {
    now = NSDate.timeIntervalSinceReferenceDate;
    events = [NSMutableArray array];
    controlled = YES;
    originalDate = method_setImplementation(class_getClassMethod(NSDate.class, @selector(dateWithTimeIntervalSinceNow:)), (IMP)dateFromNow);
    // NSDate's concrete class implements this selector, so replace that class's method.
    originalRemaining = method_setImplementation(class_getInstanceMethod(NSDate.date.class, @selector(timeIntervalSinceNow)), (IMP)remaining);
    originalTimer = method_setImplementation(class_getClassMethod(NSTimer.class, @selector(timerWithTimeInterval:repeats:block:)), (IMP)makeTimer);
}
dispatch_time_t HarnessClockTime(dispatch_time_t when, int64_t delta) {
    if (!controlled) return dispatch_time(when, delta);
    HARNESS_CHECK(when == DISPATCH_TIME_NOW && delta >= 0);
    return (dispatch_time_t)delta;
}
void HarnessClockAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    if (!controlled) { dispatch_after(when, queue, block); return; }
    HARNESS_CHECK(queue == dispatch_get_main_queue());
    HarnessClockEvent *event = [HarnessClockEvent new];
    event.at = now + (double)when / NSEC_PER_SEC;
    event.block = block;
    [events addObject:event];
}
void HarnessClockAdvance(NSTimeInterval seconds) {
    NSTimeInterval end = now + seconds;
    while (YES) {
        HarnessClockEvent *next = nil;
        for (HarnessClockEvent *event in events.copy) {
            if (event.timer && !event.timer.valid) { [events removeObject:event]; continue; }
            if (event.at <= end && (!next || event.at < next.at)) next = event;
        }
        if (!next) break;
        now = next.at;
        if (next.interval) next.at += next.interval;
        else [events removeObject:next];
        if (next.timer) [next.timer fire];
        else next.block();
    }
    now = end;
}

void HarnessClockSleep(NSTimeInterval seconds) {
    now += seconds;
    for (HarnessClockEvent *event in events) event.at += seconds;
}
