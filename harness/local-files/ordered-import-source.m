#import <Foundation/Foundation.h>

// Observe submission, not queue names. If B is admitted behind a held A on
// the same serial queue, waiting for B's completion would be a deadlock. If
// the product admits it independently, let it complete first to expose the race.
static char serialKey;
static void *heldQueue;
static dispatch_queue_t nextSubmission;
static BOOL observing;
static _Thread_local void *serialAttr;
static dispatch_queue_attr_t observedQos(dispatch_queue_attr_t base, dispatch_qos_class_t qos, int priority) {
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(base, qos, priority);
    if (base == DISPATCH_QUEUE_SERIAL) serialAttr = (__bridge void *)attr;
    return attr;
}
static dispatch_queue_t observedCreate(const char *label, dispatch_queue_attr_t attr) {
    dispatch_queue_t queue = dispatch_queue_create(label, attr);
    if (attr == DISPATCH_QUEUE_SERIAL || (__bridge void *)attr == serialAttr)
        dispatch_queue_set_specific(queue, &serialKey, (__bridge void *)queue, NULL);
    return queue;
}
static void observedAsync(dispatch_queue_t queue, dispatch_block_t block) {
    if (NSThread.isMainThread && observing) {
        nextSubmission = queue;
        observing = NO;
    }
    dispatch_async(queue, block);
}
void HarnessImportHeld(void) { heldQueue = dispatch_get_specific(&serialKey); }
void HarnessObserveNextImport(void) { nextSubmission = nil; observing = YES; }
BOOL HarnessImportIsQueuedBehindHeld(void) {
    return heldQueue && (__bridge void *)nextSubmission == heldQueue;
}
#define dispatch_queue_create observedCreate
#define dispatch_queue_attr_make_with_qos_class observedQos
#define dispatch_async observedAsync
#import "Shared/LocalFiles/LocalLyrics.m"
