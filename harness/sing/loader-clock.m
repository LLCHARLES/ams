#import <Foundation/Foundation.h>
#import "../harness-fail.h"

// Capture just the deadline being exercised. Slow-load logging and unrelated
// loads keep their own schedules; the model still loads on its real worker.
static int64_t captureNs;
static dispatch_block_t pending;
void HarnessCaptureLoaderDelay(int64_t ns) {
    HARNESS_CHECK(!captureNs && !pending && ns > 0);
    captureNs = ns;
}
static dispatch_time_t loaderTime(dispatch_time_t base, int64_t ns) {
    if (captureNs && ns == captureNs) return DISPATCH_TIME_FOREVER;
    return dispatch_time(base, ns);
}
static void loaderAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) {
    if (when != DISPATCH_TIME_FOREVER) { dispatch_after(when, queue, block); return; }
    HARNESS_CHECK(queue == dispatch_get_main_queue() && captureNs && !pending);
    pending = [block copy];
    captureNs = 0;
}
void HarnessFireLoaderDelay(void) {
    HARNESS_CHECK(pending != nil);
    dispatch_block_t block = pending;
    pending = nil;
    block();
}
#define dispatch_time loaderTime
#define dispatch_after loaderAfter
#import "Shared/Sing/SGSingLoader.m"
