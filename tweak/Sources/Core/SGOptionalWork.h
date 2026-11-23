#import <Foundation/Foundation.h>

#define SGKeyLoadAhead @"spotifyglass.loadAhead"
@class SGModRow;
// Defined by Shared's settings composition, not Core.
SGModRow *SGLoadAheadRow(void);

typedef NS_ENUM(NSUInteger, SGOptionalWorkReason) {
    SGOptionalWorkAllowed,
    SGOptionalWorkLowPower,
    SGOptionalWorkHeat,
    SGOptionalWorkNoPath,
    SGOptionalWorkConstrained,
    SGOptionalWorkExpensive,
};

// Pure decision seam: callers/tests supply a coherent snapshot. Foreground lyrics allow expensive
// paths; background advance work and artwork do not. Unknown paths wait for the first update.
SGOptionalWorkReason SGOptionalWorkReasonForInputs(BOOL lowPower, NSProcessInfoThermalState thermal,
                                                  BOOL pathSatisfied, BOOL constrained, BOOL expensive,
                                                  BOOL allowsExpensive);

// Any queue. Only for advance work, never a current-track or visible-page request.
BOOL SGOptionalWorkMayRun(BOOL allowsExpensive);
