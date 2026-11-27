// What the stand-in Core Haptics (fakehaptics.m) was asked to play since it was last asked.
#import <Foundation/Foundation.h>

typedef struct {
    unsigned kicks, snares;          // taps, told apart by their sharpness
    double tapIntensity;             // their intensities, summed
    unsigned rumbleStarts, rumbleStops, levels;
    double levelSum, levelMax;       // the rumble's intensities as sent
    BOOL rumbling;                   // carried over
    BOOL running;
} FakeHaptics;

// The counts since the last call, and a fresh start.
FakeHaptics FakeHapticsTake(void);

// One recovery scenario: a failed parameter send, a stopped callback, then a reset.
void FakeHapticsBeginRecovery(void);
BOOL FakeHapticsRecovered(void);
void FakeHapticsBeginOperationFailure(void);
BOOL FakeHapticsOperationRecovered(void);
void FakeHapticsBeginRepeatedFailures(void);
BOOL FakeHapticsEndRepeatedFailures(void);
void FakeHapticsDeferStop(void (^requested)(void));
BOOL FakeHapticsCompleteStop(void);
void FakeHapticsDeliverStoppedHandler(void);
BOOL FakeHapticsAsyncStopRecovered(void);
void FakeHapticsBeginTeardownFailure(void);
BOOL FakeHapticsTeardownRecovered(void);
