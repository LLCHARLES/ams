// Capture the row's dispatch delay without replacing its timer or Now Playing setter.
#import <Foundation/Foundation.h>
extern int64_t harnessRowDelay;
extern CFAbsoluteTime harnessExtrasNow;
static CFAbsoluteTime rowNow(void) { return harnessExtrasNow ?: CFAbsoluteTimeGetCurrent(); }
BOOL harnessManualRow;
static __weak dispatch_source_t armed;
static dispatch_block_t handler;
BOOL HarnessRowArmed(void) { return armed && !dispatch_source_testcancel(armed); }
BOOL HarnessFireRow(void) {
    if (!HarnessRowArmed() || !handler) return NO;
    handler();
    return YES;
}
static dispatch_time_t rowTime(dispatch_time_t start, int64_t delta) {
    harnessRowDelay = delta;
    return harnessManualRow ? DISPATCH_TIME_FOREVER : dispatch_time(start, delta);
}
#define dispatch_time rowTime
extern NSUInteger harnessRowFires;
static void rowHandler(dispatch_source_t source, dispatch_block_t block) {
    armed = source;
    handler = ^{ harnessRowFires++; block(); };
    dispatch_source_set_event_handler(source, handler);
}
#define CFAbsoluteTimeGetCurrent rowNow
#define dispatch_source_set_event_handler rowHandler
#include "LockScreenLyrics.m"
