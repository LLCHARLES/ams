#pragma once
#include <unistd.h>
#import "harness-wait.h"

// Advance the retiring writer's wait calls, not wall time. A writer which
// gives up after the old 100 ms limit cannot reach this rendezvous.
static _Thread_local BOOL harnessRetiring;
static _Thread_local unsigned harnessWaitedUS;
static dispatch_semaphore_t harnessPastLimit, harnessResumeWriter;
static inline void HarnessStartHandoff(void) {
    harnessPastLimit = dispatch_semaphore_create(0);
    harnessResumeWriter = dispatch_semaphore_create(0);
}
static inline int HarnessWriterSleep(useconds_t us) {
    if (!harnessRetiring) return usleep(us);
    harnessWaitedUS += us;
    if (harnessWaitedUS >= 150000) {
        dispatch_semaphore_signal(harnessPastLimit);
        HARNESS_CHECK(!dispatch_semaphore_wait(harnessResumeWriter, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)));
        harnessRetiring = NO;
    }
    return 0;
}
static inline void HarnessWaitForHeldReader(void) {
    HARNESS_CHECK(!dispatch_semaphore_wait(harnessPastLimit, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)));
}
