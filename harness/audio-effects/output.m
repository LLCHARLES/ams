// Compile the real callbacks in this translation unit so the harness can supply
// AudioUnit-owned buffers and pause retirement at the loaded-reader boundary.
// Assertions concern output samples, ownership admission and live-unit access.
#import <UIKit/UIKit.h>
#include <pthread.h>
#include <unistd.h>
#import "../reader-handoff.h"
#define usleep HarnessWriterSleep
#import "SpeedPitch.m"
#undef usleep

SPTPlayerState *SGPlayerState(void) { return nil; }
void SGAddPlayerStateObserver(id<SGPlayerStateObserver> observer) {}

static int testFailures;
static void expect(BOOL ok, const char *name) {
    printf("%s %s\n", ok ? "ok" : "FAIL", name);
    testFailures += !ok;
}

static void formatAt(Format *format, double rate) {
    uint64_t bits;
    memcpy(&bits, &rate, sizeof bits);
    atomic_store(&format->rateBits, bits);
    atomic_store(&format->channels, 2);
    atomic_store(&format->bytes, 4);
    atomic_store(&format->flags, kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved);
}

static void renderConstant(Output *output, float *left, float *right, BOOL pre) {
    const UInt32 frames = 1024;
    for (UInt32 i = 0; i < frames; ++i) left[i] = right[i] = 1;
    struct { AudioBufferList list; AudioBuffer second; } data =
        {{2, {{1, frames * sizeof(float), left}}}, {1, frames * sizeof(float), right}};
    AudioTimeStamp stamp = {0};
    AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
    if (pre) rendered(output, &flags, &stamp, 0, frames, &data.list);
    flags = kAudioUnitRenderAction_PostRender;
    rendered(output, &flags, &stamp, 0, frames, &data.list);
}

static BOOL samplesEqual(float *left, float *right, float expected) {
    for (unsigned i = 0; i < 1024; ++i)
        if (fabsf(left[i] - expected) > 0.000001f || fabsf(right[i] - expected) > 0.000001f) return NO;
    return YES;
}

static void renderData(Output *output, UInt32 frames, AudioBufferList *data) {
    AudioTimeStamp stamp = {0};
    AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PreRender;
    rendered(output, &flags, &stamp, 0, frames, data);
    flags = kAudioUnitRenderAction_PostRender;
    rendered(output, &flags, &stamp, 0, frames, data);
}

static BOOL boost(float *left, float *right, UInt32 frames, double sampleRate) {
    for (UInt32 i = 0; i < frames; ++i) {
        left[i] *= 2;
        right[i] *= 2;
    }
    return YES;
}

static void headroomAndBypass(Output *output) {
    float warmLeft[1024], warmRight[1024];
    SGPlayerSetGain(1);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, warmLeft, warmRight, YES);
    SGPlayerSetOutputControl(YES, -12.041199826559248, 0, 60); // amplitude 0.25
    renderConstant(output, warmLeft, warmRight, YES);
    SGPlayerSetOutputProcessing(boost, NULL);
    // More than one scratch chunk, including peaks that exceed integer full
    // scale inside the effect but fit after the compensating post gain.
    enum { frames = 5003 };
    static float left[frames], right[frames];
    static int16_t pcm[frames * 2];
    const int16_t wave[] = {8192, 16384, 24576, 16384, 8192, -8192, -16384, -24576};
    for (UInt32 i = 0; i < frames; ++i) {
        int16_t sample = wave[i % 8];
        left[i] = right[i] = sample / 32768.0f;
        pcm[i * 2] = pcm[i * 2 + 1] = sample;
    }
    struct { AudioBufferList list; AudioBuffer second; } floats =
        {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
    renderData(output, frames, &floats.list);
    atomic_store(&output->hardware.bytes, 2);
    atomic_store(&output->hardware.flags, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
    AudioBufferList integers = {1, {{2, sizeof pcm, pcm}}};
    renderData(output, frames, &integers);
    BOOL agrees = YES;
    for (UInt32 i = 0; i < frames; ++i) {
        float expected = wave[i % 8] / 65536.0f; // input * 2 * 0.25
        agrees &= fabsf(left[i] - expected) < 0.000001f && fabsf(right[i] - expected) < 0.000001f;
        agrees &= fabsf(pcm[i * 2] / 32768.0f - expected) <= 1.0f / 32768
            && fabsf(pcm[i * 2 + 1] / 32768.0f - expected) <= 1.0f / 32768;
    }
    expect(agrees, "float and s16 preserve boosted peaks through compensating post gain before quantization");
    for (UInt32 i = 0; i < frames * 2; ++i) pcm[i] = 24576;
    closeProcessing();
    renderData(output, frames, &integers);
    openProcessing();
    BOOL attenuated = YES;
    for (UInt32 i = 0; i < frames * 2; ++i) attenuated &= pcm[i] == 6144;
    expect(attenuated, "s16 refusal skips only the boost, never mandatory post gain");

    SGPlayerSetOutputProcessing(NULL, NULL);
    SGPlayerSetOutputControl(NO, 0, 0, 60);
    formatAt(&output->hardware, 48000);
    renderConstant(output, warmLeft, warmRight, YES);
    atomic_store(&output->hardware.flags, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked);
    int32_t words[] = {INT32_MIN, INT32_MAX, 16777217, -16777217, 1, -1, 123456789, -123456789};
    int32_t original[8];
    memcpy(original, words, sizeof words);
    AudioBufferList exact = {1, {{2, sizeof words, words}}};
    renderData(output, 4, &exact);
    expect(!memcmp(words, original, sizeof words), "settled disabled output control preserves every s32 bit");
    formatAt(&output->hardware, 48000);
    SGPlayerSetOutputControl(YES, 0, -12, 60);
    renderConstant(output, warmLeft, warmRight, YES);
    expect(samplesEqual(warmLeft, warmRight, 0.25118864f), "enabling the limiter leaves unity bypass immediately");
    SGPlayerSetOutputControl(NO, 0, 0, 60);
    renderConstant(output, warmLeft, warmRight, YES);
    expect(samplesEqual(warmLeft, warmRight, 1), "disabling limiting releases its envelope to exact unity");
    SGPlayerSetGain(0.25);
    renderConstant(output, warmLeft, warmRight, YES);
    expect(fabsf(warmLeft[0] - 0.99995833f) < 0.000001f && fabsf(warmLeft[1023] - 0.95733333f) < 0.000001f,
           "starting a fade leaves unity bypass on the next buffer");
    SGPlayerSetGain(1);
    renderConstant(output, warmLeft, warmRight, YES);
    expect(fabsf(warmLeft[0] - 0.957375f) < 0.000001f && fabsf(warmLeft[1023] - 1) < 0.000001f,
           "cancelling a fade reverses the envelope on the next buffer");
}

static atomic_bool stopNonowner, nonownerStarted;
static void *nonowner(void *context) {
    AudioUnit unit = context;
    atomic_store(&nonownerStarted, true);
    while (!atomic_load(&stopNonowner)) {
        if (SGPlayerBeginProcessing(unit)) SGPlayerEndProcessing();
    }
    return NULL;
}

static atomic_bool readerLoaded, replacementFinished, renderSucceeded;
static dispatch_semaphore_t releaseReader;
static void *retainedReader(void *context) {
    AudioUnit output = context;
    if (!SGPlayerBeginProcessing(output)) return NULL;
    SGTimePitch *unit = atomic_load(&sg_inPlace);
    atomic_store(&readerLoaded, true);
    HARNESS_CHECK(!dispatch_semaphore_wait(releaseReader, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC)));
    float left[1024] = {0}, right[1024] = {0};
    float *lanes[] = {left, right};
    atomic_store(&renderSucceeded, SGTimePitchProcess(unit, lanes, 1024));
    SGPlayerEndProcessing();
    return NULL;
}
static void *replaceUnit(void *context) {
    harnessRetiring = YES;
    SGTimePitch *unit = unitForFormat();
    atomic_store(&replacementFinished, unit && SGTimePitchSampleRate(unit) == 44100);
    return NULL;
}

static void runTests(void) {
    Output *output = outputFor((AudioUnit)(uintptr_t)1);
    formatAt(&output->hardware, 48000);
    atomic_store(&sg_music, output);
    float left[1024], right[1024];
    SGPlayerSetOutputControl(YES, -12, 0, 60);
    renderConstant(output, left, right, YES); // settle gain ramp
    closeProcessing();
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "closed admission still applies -12 dB output gain");
    SGPlayerSetGain(0.25);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.06279716f), "closed admission still applies sleep attenuation after output gain");
    SGPlayerSetGain(1);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    SGPlayerSetOutputControl(YES, 0, -12, 60);
    renderConstant(output, left, right, YES);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "closed admission still applies standalone limiter");
    // A buffer started as music must retain control even if handoff finishes
    // between its feed and post-render.
    output->musicBuffer = YES;
    atomic_store(&sg_music, NULL);
    renderConstant(output, left, right, NO);
    expect(samplesEqual(left, right, 0.25118864f), "old output's in-flight music buffer retains limiter after handoff");
    SGPlayerSetOutputControl(YES, -12, 0, 60);
    renderConstant(output, left, right, YES); // a complete nonmusic buffer
    atomic_store(&sg_music, output);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.25118864f), "newly selected output starts at configured gain on its first buffer");
    openProcessing();

    pthread_t noise;
    pthread_create(&noise, NULL, nonowner, (void *)(uintptr_t)2);
    HARNESS_AWAIT(atomic_load(&nonownerStarted));
    unsigned refused = 0;
    for (unsigned i = 0; i < 1000000; ++i) {
        if (SGPlayerBeginProcessing(atomic_load(&output->unit))) SGPlayerEndProcessing();
        else ++refused;
    }
    atomic_store(&stopNonowner, true);
    pthread_join(noise, NULL);
    expect(refused == 0, "nonowner callbacks never refuse concurrent music admission");

    // B was last rendered at unity, then stopped while A completed a fade.
    Output *second = outputFor((AudioUnit)(uintptr_t)2);
    formatAt(&second->hardware, 48000);
    SGPlayerSetOutputControl(NO, 0, 0, 60);
    atomic_store(&output->running, true);
    renderConstant(second, left, right, YES);
    SGPlayerSetGain(0.25);
    for (unsigned i = 0; i < 30; ++i) renderConstant(output, left, right, YES);
    atomic_store(&second->running, true);
    markEvent(second);
    reselect(NO, nil);
    // Repeated selection, with no render on B between any of these changes.
    markEvent(output);
    reselect(NO, nil);
    markEvent(second);
    reselect(NO, nil);
    renderConstant(second, left, right, YES);
    expect(samplesEqual(left, right, 0.25f), "repeated handoffs before B's first render cannot restore its stale unity level");
    // Starts carry no saved gain. The timer can advance again before render.
    atomic_store(&second->sleepStarting, true); // startOutput's notification
    atomic_store(&second->sleepStarting, true); // another start before rendering
    SGPlayerSetGain(0.125);
    renderConstant(second, left, right, YES);
    expect(samplesEqual(left, right, 0.125f), "repeated starts use the latest global fade level, not a pending transfer");
    SGPlayerSetGain(0.0625);
    markEvent(output);
    reselect(NO, nil);
    renderConstant(output, left, right, YES);
    expect(samplesEqual(left, right, 0.0625f), "selection starts directly at the current global fade level");
    SGPlayerSetGain(1);
    atomic_store(&second->running, false);
    atomic_store(&second->unit, NULL);
    atomic_store(&output->running, false);

    headroomAndBypass(output);

    SGTimePitch *initial = unitForFormat();
    expect(initial != NULL, "initial pitch unit created");
    if (initial) {
        atomic_store(&sg_engaged, true);
        pthread_t reader, writer;
        HarnessStartHandoff();
        releaseReader = dispatch_semaphore_create(0);
        pthread_create(&reader, NULL, retainedReader, (void *)(uintptr_t)1);
        HARNESS_AWAIT(atomic_load(&readerLoaded));
        formatAt(&output->hardware, 44100);
        pthread_create(&writer, NULL, replaceUnit, NULL);
        HarnessWaitForHeldReader();
        expect(!atomic_load(&replacementFinished), "production format retirement waits for loaded render reader");
        dispatch_semaphore_signal(releaseReader);
        pthread_join(reader, NULL);
        dispatch_semaphore_signal(harnessResumeWriter);
        pthread_join(writer, NULL);
        expect(atomic_load(&renderSucceeded) && atomic_load(&replacementFinished),
               "old unit renders safely before replacement completes");
        disengage();
        SGTimePitchFree(atomic_exchange(&sg_inPlace, NULL));
    }
    atomic_store(&sg_music, NULL);
    atomic_store(&output->unit, NULL);
    printf("RESULT failures=%d\n", testFailures);
    fflush(stdout);
    exit(testFailures ? 1 : 0);
}

@interface OutputHarness : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation OutputHarness
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_async(dispatch_get_main_queue(), ^{ runTests(); });
    return YES;
}
@end
int main(int argc, char **argv) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, @"OutputHarness"); }
}
