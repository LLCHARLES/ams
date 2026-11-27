#pragma once
#import "harness-fail.h"

// A per-fixture main-queue clock. Scope dispatch_time/dispatch_after to
// the imported unit under test; UIKit, network and worker queues stay real.
static NSMutableArray<NSDictionary *> *harnessTimers;
static dispatch_time_t harnessNow;

static inline void HarnessStartClock(void) {
    HARNESS_CHECK(!harnessTimers);
    harnessTimers = [NSMutableArray array];
    harnessNow = 1;
}
static inline dispatch_time_t HarnessTime(dispatch_time_t base, int64_t ns) {
    if (!harnessTimers) return dispatch_time(base, ns);
    HARNESS_CHECK(base == DISPATCH_TIME_NOW && ns >= 0);
    return harnessNow + ns;
}
static inline void HarnessAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t callback) {
    if (!harnessTimers) { dispatch_after(when, queue, callback); return; }
    HARNESS_CHECK(NSThread.isMainThread && queue == dispatch_get_main_queue());
    [harnessTimers addObject:@{@"when": @(when), @"run": [callback copy]}];
}
static inline void HarnessAdvanceClock(int64_t ns) {
    uint64_t end = harnessNow + ns;
    for (;;) {
        NSDictionary *next = nil;
        for (NSDictionary *timer in harnessTimers) {
            uint64_t when = [timer[@"when"] unsignedLongLongValue];
            if (when <= end && (!next || when < [next[@"when"] unsignedLongLongValue])) next = timer;
        }
        if (!next) break;
        [harnessTimers removeObjectIdenticalTo:next];
        harnessNow = [next[@"when"] unsignedLongLongValue];
        ((dispatch_block_t)next[@"run"])();
    }
    harnessNow = end;
}
static inline void HarnessStopClock(void) {
    HARNESS_CHECK(harnessTimers.count == 0);
    harnessTimers = nil;
}
