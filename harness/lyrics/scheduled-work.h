#pragma once
#import <Foundation/Foundation.h>
// Only the compiled lyrics renderer and scheduler use these boundaries.
void HarnessLyricsAsync(dispatch_queue_t queue, dispatch_block_t block);
void HarnessLyricsAfter(dispatch_time_t when, dispatch_queue_t queue, dispatch_block_t block);
dispatch_time_t HarnessLyricsTime(dispatch_time_t base, int64_t offset);
void HarnessBeginLyricsWork(void);
void HarnessDrainLyricsWork(void);
void HarnessEndLyricsWork(void);
