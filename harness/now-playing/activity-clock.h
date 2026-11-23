#import <UIKit/UIKit.h>

dispatch_time_t HarnessActivityTime(dispatch_time_t when, int64_t delta);
void HarnessActivitySetTimer(dispatch_source_t timer, dispatch_time_t start, uint64_t interval, uint64_t leeway);
extern int64_t harnessActivityDelay;
extern uint64_t harnessActivityRepeat;

#ifndef HARNESS_ACTIVITY_CLOCK_IMPLEMENTATION
#define dispatch_time HarnessActivityTime
#define dispatch_source_set_timer HarnessActivitySetTimer
#endif
