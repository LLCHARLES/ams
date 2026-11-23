#import <Foundation/Foundation.h>

static inline BOOL SGRMotionHeldFor(BOOL lowPower, NSProcessInfoThermalState thermal) {
    return lowPower || thermal >= NSProcessInfoThermalStateSerious;
}

static inline BOOL SGRMotionHeldForPowerOrHeat(void) {
    NSProcessInfo *info = NSProcessInfo.processInfo;
    return SGRMotionHeldFor(info.lowPowerModeEnabled, info.thermalState);
}
