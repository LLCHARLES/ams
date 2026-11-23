#import "clock.h"
static void clockAsync(dispatch_queue_t queue, dispatch_block_t block) {
    if (HarnessClockControlled()) HarnessClockAfter(0, queue, block);
    else dispatch_async(queue, block);
}
#define dispatch_async clockAsync
#define UIApplicationDidBecomeActiveNotification @"UIApplicationDidBecomeActiveNotification"
#define UIApplicationSignificantTimeChangeNotification @"UIApplicationSignificantTimeChangeNotification"
#define dispatch_time HarnessClockTime
#define dispatch_after HarnessClockAfter
#import "Shared/Player/SleepTimer.m"
