#import <Foundation/Foundation.h>

void HarnessClockStart(void);
void HarnessClockAdvance(NSTimeInterval seconds);
void HarnessClockSleep(NSTimeInterval seconds);
BOOL HarnessClockControlled(void);
dispatch_time_t HarnessClockTime(dispatch_time_t when, int64_t delta);
void HarnessClockAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
