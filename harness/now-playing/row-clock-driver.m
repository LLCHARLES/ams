// Capture the row's dispatch delay without replacing its timer or Now Playing setter.
#import <Foundation/Foundation.h>
extern int64_t harnessRowDelay;
static dispatch_time_t rowTime(dispatch_time_t start, int64_t delta) {
    harnessRowDelay = delta;
    return dispatch_time(start, delta);
}
#define dispatch_time rowTime
#include "LockScreenLyrics.m"
