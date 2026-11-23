#import "SGOptionalWork.h"
#import "SGLog.h"
#import "SGPrefs.h"
#import <Network/Network.h>
#import <os/lock.h>

// This Core source owns its framework dependency, including in standalone host checks.
__asm__(".linker_option \"-framework\", \"Network\"");

typedef struct {
    BOOL satisfied;
    BOOL constrained;
    BOOL expensive;
} SGOptionalNetwork;

static os_unfair_lock sg_networkLock = OS_UNFAIR_LOCK_INIT;
static SGOptionalNetwork sg_network;
static nw_path_monitor_t sg_monitor;

static SGOptionalNetwork networkNow(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_monitor = nw_path_monitor_create();
        nw_path_monitor_set_queue(sg_monitor, dispatch_queue_create("spotifyglass.optional-work.network", DISPATCH_QUEUE_SERIAL));
        nw_path_monitor_set_update_handler(sg_monitor, ^(nw_path_t path) {
            SGOptionalNetwork network = {
                nw_path_get_status(path) == nw_path_status_satisfied,
                nw_path_is_constrained(path),
                nw_path_is_expensive(path),
            };
            os_unfair_lock_lock(&sg_networkLock);
            sg_network = network;
            os_unfair_lock_unlock(&sg_networkLock);
        });
        nw_path_monitor_start(sg_monitor);
    });
    os_unfair_lock_lock(&sg_networkLock);
    SGOptionalNetwork network = sg_network;
    os_unfair_lock_unlock(&sg_networkLock);
    return network;
}

SGOptionalWorkReason SGOptionalWorkReasonForInputs(BOOL lowPower, NSProcessInfoThermalState thermal,
                                                  BOOL pathSatisfied, BOOL constrained, BOOL expensive,
                                                  BOOL allowsExpensive) {
    if (lowPower) return SGOptionalWorkLowPower;
    if (thermal >= NSProcessInfoThermalStateSerious) return SGOptionalWorkHeat;
    if (!pathSatisfied) return SGOptionalWorkNoPath;
    if (constrained) return SGOptionalWorkConstrained;
    if (expensive && !allowsExpensive) return SGOptionalWorkExpensive;
    return SGOptionalWorkAllowed;
}

BOOL SGOptionalWorkMayRun(BOOL allowsExpensive) {
    if (!SGEnabled(SGKeyLoadAhead)) return NO;
    SGOptionalNetwork network = networkNow();
    NSProcessInfo *process = NSProcessInfo.processInfo;
    SGOptionalWorkReason reason = SGOptionalWorkReasonForInputs(process.lowPowerModeEnabled, process.thermalState,
                                                               network.satisfied, network.constrained, network.expensive,
                                                               allowsExpensive);
    if (reason == SGOptionalWorkAllowed) return YES;
    NSString *message;
    switch (reason) {
        case SGOptionalWorkLowPower: message = @"Low Power Mode"; break;
        case SGOptionalWorkHeat: message = @"serious or critical thermal state"; break;
        case SGOptionalWorkNoPath: message = @"network path unavailable"; break;
        case SGOptionalWorkConstrained: message = @"Low Data Mode"; break;
        case SGOptionalWorkExpensive: message = @"expensive network"; break;
        case SGOptionalWorkAllowed: return YES;
    }
    // SGLogOnce owns a main-thread-only set. Never make an asking queue wait for main.
    dispatch_async(dispatch_get_main_queue(), ^{
        static NSMutableSet<NSString *> *logged;
        SGLogOnce(&logged, message, @"optional advance work skipped: %@");
    });
    return NO;
}
