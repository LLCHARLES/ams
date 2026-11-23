#import <Foundation/Foundation.h>
extern CFAbsoluteTime harnessExtrasNow;
static CFAbsoluteTime extrasNow(void) {
    return harnessExtrasNow ?: CFAbsoluteTimeGetCurrent();
}
#define CFAbsoluteTimeGetCurrent extrasNow
#include "NowPlayingExtras.m"
