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
#import "MusicHaptics.m"
