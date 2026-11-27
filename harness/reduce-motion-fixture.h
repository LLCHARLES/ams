// Include in one translation unit per harness app. Only the selected scenario's
// main thread gets a fixture value; never write the machine's accessibility preferences.
#import <UIKit/UIKit.h>
#import <dlfcn.h>

static _Thread_local enum { useHostMotion, allowMotion, reduceMotion } harnessMotion;
static BOOL hostReducesMotion(void) {
    return ((BOOL (*)(void))dlsym(RTLD_NEXT, "UIAccessibilityIsReduceMotionEnabled"))();
}
BOOL UIAccessibilityIsReduceMotionEnabled(void) {
    return harnessMotion == useHostMotion ? hostReducesMotion() : harnessMotion == reduceMotion;
}
