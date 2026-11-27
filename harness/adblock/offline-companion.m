// Only the host admission and diagnostic boundaries are fixtures.
// Both exported transformers come from the unmodified NativeDownloads source.
#import <Foundation/Foundation.h>
#import "DiagnosticTrace.h"
#include <stdbool.h>
#include <stdatomic.h>

static atomic_bool admitted;
static dispatch_block_t admissionObserver;
__attribute__((visibility("default"))) void SGTestSetAdmitted(bool value) {
    if(!atomic_exchange(&admitted,value) && value)
        [NSNotificationCenter.defaultCenter postNotificationName:@"SAPOfflineProfileReady" object:nil];
}
__attribute__((visibility("default"))) void SGTestSetAdmissionObserver(dispatch_block_t observer) {
    @synchronized (NSObject.class) { admissionObserver = [observer copy]; }
}
__attribute__((visibility("default"))) bool SAPRuntimeProfileAdmitted(void) {
    dispatch_block_t observer;
    @synchronized (NSObject.class) { observer = admissionObserver; admissionObserver = nil; }
    if (observer) observer();
    return atomic_load(&admitted);
}
bool SAPTraceIsActive(void) { return false; }
uint64_t SAPTraceGeneration(void) { return 0; }
SAPTraceID SAPTraceBegin(NSString *kind, NSString *source, NSDictionary *facts) { return 0; }
SAPTraceID SAPTraceCurrentOperation(void) { return 0; }
void SAPTraceWithOperation(SAPTraceID operation, dispatch_block_t block) { block(); }
void SAPTraceEvent(const char *category, const char *stage, SAPTraceID operation, NSDictionary *facts) {}
void SAPTraceRegisterHook(Class cls, SEL selector, IMP installed, IMP original) {}
void SAPTraceHookCalled(Class cls, SEL selector) {}
