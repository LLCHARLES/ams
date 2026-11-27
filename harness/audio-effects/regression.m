#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdatomic.h>
#include <unistd.h>
#include <math.h>
#include "Shared/AudioEffects/SGDSPEngine.h"
#include "Shared/Player/SGRenderGate.h"
#import "../reader-handoff.h"

static int failures;
static void check(bool ok, const char *name) {
    printf("%s %s\n", ok ? "ok" : "FAIL", name);
    failures += !ok;
}

// Hold a real effect setter at the framework boundary, on its config thread.
// The render thread is never delayed by this test double.
static atomic_bool holdParameters, setterEntered, releaseSetter;
OSStatus AudioUnitSetParameter(AudioUnit unit, AudioUnitParameterID parameter, AudioUnitScope scope,
                              AudioUnitElement element, AudioUnitParameterValue value, UInt32 offset) {
    static OSStatus (*realSet)(AudioUnit, AudioUnitParameterID, AudioUnitScope, AudioUnitElement, AudioUnitParameterValue, UInt32);
    if (!realSet) realSet = dlsym(RTLD_NEXT, "AudioUnitSetParameter");
    if (atomic_load(&holdParameters)) {
        atomic_store(&setterEntered, true);
        while (!atomic_load(&releaseSetter)) usleep(100);
    }
    return realSet(unit, parameter, scope, element, value, offset);
}

static void constantBlock(SGDSPEngine *engine, float *left, float *right) {
    for (unsigned i = 0; i < kSGDSPEngineBlock; ++i) left[i] = right[i] = 1;
    SGDSPEngineProcess(engine, left, right, kSGDSPEngineBlock);
}

static void limiter(void) {
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    SGDSPEngineSetOutput(engine, 0, -12, 60);
    float left[kSGDSPEngineBlock], right[kSGDSPEngineBlock];
    constantBlock(engine, left, right);
    constantBlock(engine, left, right);
    bool ok = true;
    for (unsigned i = 0; i < kSGDSPEngineBlock; ++i)
        ok &= fabsf(left[i] - 0.25118864f) < 0.000001f && fabsf(right[i] - 0.25118864f) < 0.000001f;
    check(ok, "standalone -12 dB limiter at unity post gain");
    SGDSPEngineFree(engine);
}

static void *changeRoom(void *context) {
    SGDSPEngineSetReverb(context, true, 1, 0);
    return NULL;
}

static void contention(void) {
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    SGDSPEngineSetOutput(engine, -12, 0, 60);
    SGDSPEngineSetReverb(engine, true, 0, 0);
    float left[kSGDSPEngineBlock], right[kSGDSPEngineBlock];
    for (unsigned i = 0; i < 4; ++i) constantBlock(engine, left, right);
    atomic_store(&holdParameters, true);
    pthread_t writer;
    pthread_create(&writer, NULL, changeRoom, engine);
    HARNESS_AWAIT(atomic_load(&setterEntered));
    // No retired state: maintenance must finish even with configuration admission held.
    dispatch_semaphore_t collected = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        SGDSPEngineCollect(engine);
        dispatch_semaphore_signal(collected);
    });
    bool collectedEarly = !dispatch_semaphore_wait(collected, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    check(collectedEarly, "steady-state collection needs no configuration admission");
    bool ok = true;
    // Every block is processed while the setting remains in flight.
    for (unsigned block = 0; block < 8; ++block) {
        constantBlock(engine, left, right);
        for (unsigned i = 0; i < kSGDSPEngineBlock; ++i)
            ok &= fabsf(left[i] - 0.25118864f) < 0.000001f && fabsf(right[i] - 0.25118864f) < 0.000001f;
    }
    atomic_store(&releaseSetter, true);
    pthread_join(writer, NULL);
    if (!collectedEarly) dispatch_semaphore_wait(collected, DISPATCH_TIME_FOREVER);
    atomic_store(&holdParameters, false);
    check(ok, "in-flight effect update never bypasses -12 dB post gain");
    SGDSPEngineFree(engine);
}

typedef struct {
    SGRenderGate gate;
    atomic_bool closed, transferred;
    int owner;
} Handoff;

static void *transfer(void *context) {
    Handoff *handoff = context;
    SGRenderGateClose(&handoff->gate);
    atomic_store(&handoff->closed, true);
    harnessRetiring = YES;
    while (!SGRenderGateIdle(&handoff->gate)) HarnessWriterSleep(100);
    handoff->owner = 2;
    SGRenderGateOpen(&handoff->gate);
    atomic_store(&handoff->transferred, true);
    return NULL;
}

static void admission(void) {
    Handoff handoff = {.owner = 1};
    check(SGRenderGateEnter(&handoff.gate), "first post-render reader admitted");
    pthread_t writer;
    HarnessStartHandoff();
    pthread_create(&writer, NULL, transfer, &handoff);
    HarnessWaitForHeldReader();
    check(!atomic_load(&handoff.transferred) && handoff.owner == 1,
          "ownership waits for the admitted post-render reader, without a timeout");
    bool entered = SGRenderGateEnter(&handoff.gate);
    check(!entered, "another output cannot enter during handoff");
    if (entered) SGRenderGateLeave(&handoff.gate);
    SGRenderGateLeave(&handoff.gate);
    dispatch_semaphore_signal(harnessResumeWriter);
    pthread_join(writer, NULL);
    entered = SGRenderGateEnter(&handoff.gate);
    check(entered && handoff.owner == 2, "next output enters after the old reader exits");
    if (entered) SGRenderGateLeave(&handoff.gate);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        limiter();
        if (argc == 1 || strcmp(argv[1], "limiter")) {
            contention();
            admission();
        }
        return failures ? 1 : 0;
    }
}
