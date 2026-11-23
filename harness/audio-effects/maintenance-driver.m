#import <Foundation/Foundation.h>
void (^HarnessMaintenanceChanged)(BOOL);
static void maintenanceResume(dispatch_source_t source) {
    dispatch_resume(source);
    if (HarnessMaintenanceChanged) HarnessMaintenanceChanged(YES);
}
static void maintenanceSuspend(dispatch_source_t source) {
    dispatch_suspend(source);
    if (HarnessMaintenanceChanged) HarnessMaintenanceChanged(NO);
}
#define dispatch_resume maintenanceResume
#define dispatch_suspend maintenanceSuspend
#import "AudioEffects.m"
