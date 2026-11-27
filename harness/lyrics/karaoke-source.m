#import "scheduled-work.h"
#import "../dispatch-clock.h"
#import "../harness-wait.h"

static dispatch_group_t work(void) {
    static dispatch_once_t once;
    static dispatch_group_t group;
    dispatch_once(&once, ^{ group = dispatch_group_create(); });
    return group;
}
void HarnessLyricsAsync(dispatch_queue_t queue, dispatch_block_t block) {
    dispatch_group_async(work(), queue, block);
}
dispatch_time_t HarnessLyricsTime(dispatch_time_t base, int64_t offset) { return HarnessTime(base, offset); }
void HarnessLyricsAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block) { HarnessAfter(when, queue, block); }
void HarnessBeginLyricsWork(void) {
    HarnessStartClock();
}
void HarnessDrainLyricsWork(void) {
    // A language/layout worker can enqueue main publication, which can in
    // turn enqueue the debounce or a provider fallback.
    NSTimeInterval end = NSProcessInfo.processInfo.systemUptime + HarnessWaitSeconds;
    do {
        HARNESS_AWAIT(dispatch_group_wait(work(), DISPATCH_TIME_NOW) == 0);
        if (!harnessTimers.count) break;
        if (NSProcessInfo.processInfo.systemUptime >= end) HARNESS_FAIL(@"lyrics work kept scheduling delayed callbacks");
        HarnessAdvanceClock(NSEC_PER_SEC);
    } while (YES);
}
void HarnessEndLyricsWork(void) {
    HarnessDrainLyricsWork();
    HarnessStopClock();
}
#define dispatch_async HarnessLyricsAsync
#define dispatch_time HarnessLyricsTime
#define dispatch_after HarnessLyricsAfter
#import "Redesigned/Lyrics/SGRKaraokeView.m"
