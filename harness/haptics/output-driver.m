#import <AudioToolbox/AudioToolbox.h>
#import <stdatomic.h>
#import "Shared/Player/SpeedPitch.h"
#import "../harness-fail.h"

BOOL HarnessCheckStoppedOutput;
_Atomic(AudioUnit) HarnessHapticsAttachedOutput;

static void requireActiveOutput(AudioUnit unit) {
    if (HarnessCheckStoppedOutput && unit == atomic_load(&HarnessHapticsAttachedOutput))
        HARNESS_CHECK(SGPlayerMusicOutputRunning());
}

static OSStatus checkedProperty(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope,
                                AudioUnitElement element, void *data, UInt32 *size) {
    requireActiveOutput(unit);
    return AudioUnitGetProperty(unit, property, scope, element, data, size);
}

static OSStatus checkedRemove(AudioUnit unit, AURenderCallback callback, void *context) {
    requireActiveOutput(unit);
    return AudioUnitRemoveRenderNotify(unit, callback, context);
}

static OSStatus checkedAdd(AudioUnit unit, AURenderCallback callback, void *context) {
    requireActiveOutput(unit);
    OSStatus status = AudioUnitAddRenderNotify(unit, callback, context);
    if (status == noErr) atomic_store(&HarnessHapticsAttachedOutput, unit);
    return status;
}

#define AudioUnitGetProperty checkedProperty
#define AudioUnitRemoveRenderNotify checkedRemove
#define AudioUnitAddRenderNotify checkedAdd
static atomic_uint playerWakes;
static atomic_bool holdNextWake;
static dispatch_semaphore_t held, resume;
unsigned HarnessPlayerWakes(void) { return atomic_load(&playerWakes); }
static long countedWait(dispatch_semaphore_t semaphore, dispatch_time_t timeout) {
    long result = dispatch_semaphore_wait(semaphore, timeout);
    atomic_fetch_add(&playerWakes, 1); // signals and timeouts, on the consumer only
    if (atomic_exchange(&holdNextWake, false)) {
        dispatch_semaphore_signal(held);
        dispatch_semaphore_wait(resume, DISPATCH_TIME_FOREVER);
    }
    return result;
}
#define dispatch_semaphore_wait countedWait
#import "MusicHaptics.m"
#undef dispatch_semaphore_wait

#ifndef BEFORE
// Run a settings/producer transition on main, with the consumer stopped between two batches.
void HarnessBetweenPlayerTurns(void (^body)(void)) {
    if (!held) {
        held = dispatch_semaphore_create(0);
        resume = dispatch_semaphore_create(0);
    }
    atomic_store(&holdNextWake, true);
    dispatch_semaphore_signal(sg_wake);
    HARNESS_CHECK(!dispatch_semaphore_wait(held, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)));
    body();
    dispatch_semaphore_signal(resume);
}

// With no output unit in these scenarios, stand in for the analyzer's single producer.
void HarnessEmitLevel(float intensity) {
    unsigned before = atomic_load(&sg_ring.head);
    SGMusicEvent level = {.kind = SGMusicEventLevel, .hostTime = mach_absolute_time(), .intensity = intensity};
    pushEvent(&level, NULL);
    if (before != atomic_load(&sg_ring.head)) dispatch_semaphore_signal(sg_wake);
}
#endif
