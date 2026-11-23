// SGLosslessEngine.m's capture against a recording that changes under it: a render call that saw the last
// recording armed must not carry its fill into a shorter one, nor write past the buffer. The engine file is
// included whole so its static capture state can be set up exactly; run under AddressSanitizer by capture-race.sh.
#import "../../tweak/Sources/Shared/Lossless/SGLosslessEngine.m"
#import <pthread.h>

void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) {}
uint64_t SGPlayerSourceEpoch(void) { return 1; }

static int failures;
#define CHECK(ok, ...) do { BOOL _ok = (ok); printf("%s ", _ok ? "  ok  " : "  FAIL"); printf(__VA_ARGS__); printf("\n"); if (!_ok) failures++; } while (0)

static AudioUnit const kUnit = (AudioUnit)0x1;
static float left[512], right[512];

static void renderOnce(double sourceFrame) {
    struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
    selector(kUnit, 1, sourceFrame, 44100, 512, &buffers.list);
}

static void *recordOneSecond(void *ok) {
    NSString *error;
    *(BOOL *)ok = record(kCheckSeconds, &error);
    return NULL;
}

int main(void) {
    @autoreleasepool {
        // A render call left a fill from a 4 s recording behind a 1 s one: the next call must not write on.
        uint32_t length = 44100;
        sg_cap = malloc(length * sizeof(float));
        sg_capLength = length;
        atomic_store(&sg_capFill, length + 1000);
        sg_capNext = 1000; sg_capEpoch = 1; sg_capUnit = kUnit;
        atomic_store(&sg_capState, kArmed);
        renderOnce(1000);
        CHECK(atomic_load(&sg_capFill) == length + 1000, "a fill past the length writes nothing and stays put");
        free(sg_cap);
        sg_cap = NULL;
#ifndef ONLY_GUARD
        // A new recording waits for a render call still inside capture before it sets the length.
        // The last recording's length and fill differ from what record() sets, so a reset before the wait shows.
        uint32_t oldLength = 4 * 44100, oldFill = 5000;
        atomic_store(&sg_capLength, oldLength);
        atomic_store(&sg_capFill, oldFill);
        atomic_store(&sg_capState, kArmed);
        sg_capRate = 44100;
        atomic_store(&sg_capturing, 1);
        BOOL recorded = NO;
        pthread_t thread;
        pthread_create(&thread, NULL, recordOneSecond, &recorded);
        // record() stands the capture down first, then waits; nothing else may move while the render call is in.
        for (int i = 0; i < 200 && atomic_load(&sg_capState) != kIdle; i++) usleep(5000);
        usleep(200000);
        CHECK(atomic_load(&sg_capState) == kIdle && atomic_load(&sg_capLength) == oldLength && atomic_load(&sg_capFill) == oldFill,
              "the length and fill are not changed while a render call captures (%u, %u)",
              atomic_load(&sg_capLength), atomic_load(&sg_capFill));
        atomic_store(&sg_capturing, 0);
        for (int i = 0; i < 200 && atomic_load(&sg_capState) != kArmed; i++) usleep(5000);
        double frame = 0;
        while (atomic_load(&sg_capState) == kArmed) { renderOnce(frame); frame += 512; }
        pthread_join(thread, NULL);
        CHECK(recorded && atomic_load(&sg_capFill) == atomic_load(&sg_capLength),
              "then records the whole second (%u of %u frames)", atomic_load(&sg_capFill), atomic_load(&sg_capLength));
#endif
        printf("\n%s: %d failed\n", failures ? "FAILED" : "all passed", failures);
        return failures ? 1 : 0;
    }
}
