#include "Diagnostics.h"
#include "AudioProbeBackend.h"
#include <assert.h>
#include <stdio.h>

static OSStatus render(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    return noErr;
}

int main(void) {
    // Spotify's five audio imports are bound to the probe in the executable,
    // so an unadmitted probe must pass every call through, not refuse it.
    AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_DefaultOutput, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    assert(component);
    AudioUnit unit = NULL;
    assert(AudioComponentInstanceNew(component, &unit) == noErr && unit);

    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof(format);
    OSStatus got = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, &size);
    printf("unadmitted get StreamFormat: %d\n", (int)got);
    assert(got == noErr && format.mSampleRate > 0);
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) == noErr);

    AURenderCallbackStruct callback = {render, (void *)(uintptr_t)77};
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)) == noErr);
    SAPSnapshot snapshot; SpotifyAudioProbeReadSnapshot(&snapshot);
    // Spotify's own render callback is installed untouched.
    assert(snapshot.backendReady && snapshot.callbackAttempts == 0 && !snapshot.pcmConfirmed);

    assert(AudioComponentInstanceDispose(unit) == noErr);
    puts("PASS: an unadmitted probe passes Spotify's audio calls through to AudioToolbox and leaves its render callback alone");
}
