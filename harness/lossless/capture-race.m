// SGLosslessEngine.m's capture against a recording that changes under it: a render call that saw the last
// recording armed must not carry its fill into a shorter one, nor write past the buffer. The engine file is
// included whole so its static capture state can be set up exactly; run under AddressSanitizer by capture-race.sh.
#ifndef ONLY_GUARD
static void interleaveSkip(void);
#define SG_RING_READ_INTERLEAVE interleaveSkip
#endif
#import "../../tweak/Sources/Shared/Lossless/SGLosslessEngine.m"
#import <pthread.h>

void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) {}
static _Atomic uint64_t sourceEpoch = 1;
uint64_t SGPlayerSourceEpoch(void) { return atomic_load(&sourceEpoch); }

static int failures;
#define CHECK(ok, ...) do { BOOL _ok = (ok); printf("%s ", _ok ? "  ok  " : "  FAIL"); printf(__VA_ARGS__); printf("\n"); if (!_ok) failures++; } while (0)

static AudioUnit const kUnit = (AudioUnit)0x1;
static float left[512], right[512];

#ifndef ONLY_GUARD
static NSString *skipPath;
static void interleaveSkip(void) {
    if (!skipPath) return;
    // Run the actual writer between the two bound loads. The read is near EOF,
    // so the seek succeeds and fill returns without waiting for ring space.
    atomic_store(&sg_writers, 1);
    fill(skipPath, 44100, 0, 0, 1, malloc(kChunk * sizeof(float)), malloc(kChunk * sizeof(float)));
    skipPath = nil;
}
#endif

static void renderOnce(double sourceFrame) {
    struct { AudioBufferList list; AudioBuffer second; } buffers = {{2, {{1, sizeof left, left}}}, {1, sizeof right, right}};
    selector(kUnit, 1, sourceFrame, 44100, 512, &buffers.list);
}

static void *recordOneSecond(void *ok) {
    NSString *error;
    *(BOOL *)ok = record(kCheckSeconds, &error);
    return NULL;
}

int main(int argc, char **argv) {
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

        NSString *path = @(argv[1]);
        releaseCapture();
        sg_ring = calloc(2, sizeof *sg_ring);
        NSString *error;
        if (!load(path, 44100, &error)) { NSLog(@"fixture: %@", error); return 1; }
        uint64_t gap = sg_reader.frames - 44100 / 2;
        skipPath = path;
        bool replacedGap = ringRead(gap, 512, left, right);
        CHECK(!replacedGap && atomic_load(&sg_ringStart) > gap && atomic_load(&sg_ringEnd) > sg_ringStart,
              "a writer skip between the bound loads leaves the gap dry");
        atomic_store(&sg_readAt, 0);
        atomic_store(&sg_ringStart, 0);
        atomic_store(&sg_ringEnd, 0);
        atomic_store(&sg_writers, 1);
        NSThread *writer = [[NSThread alloc] initWithBlock:^{
            fill(path, 44100, 0, 0, 1, malloc(kChunk * sizeof(float)), malloc(kChunk * sizeof(float)));
        }];
        [writer start];
        for (int i = 0; i < 200 && atomic_load(&sg_ringEnd) + 2*kChunk <= kRing; ++i) usleep(5000);
        CHECK(atomic_load(&sg_ringEnd) + 2*kChunk > kRing && atomic_load(&sg_writers), "writer is blocked on a full ring before EOF");
        // A warning can discard the search copy, but not the live replacement's samples.
        uint64_t bufferedEnd = atomic_load(&sg_ringEnd);
        float unity = 1;
        uint32_t bits;
        memcpy(&bits, &unity, sizeof bits);
        atomic_store(&sg_gainBits, bits);
        sg_playEpoch = 1; sg_playUnit = kUnit; sg_playRate = 44100;
        atomic_store(&sg_anchorEpoch, 1);
        atomic_store(&sg_live, true);
        (void)queue();
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        dispatch_sync(queue(), ^{});
        // Free two chunks of space; require a block past the old end, not a
        // successful read from already-buffered audio after a stopped writer.
        renderOnce(2 * kChunk);
        uint64_t next = bufferedEnd + kChunk;
        for (int i = 0; i < 200 && atomic_load(&sg_ringEnd) < next + 512; ++i) usleep(5000);
        memset(left, 0, sizeof left);
        memset(right, 0, sizeof right);
        uint64_t before = atomic_load(&sg_replaced);
        renderOnce(next);
        BOOL matches = YES;
        for (int i = 0; i < 512; ++i) matches &= left[i] == 0.25f && right[i] == -0.25f;
        CHECK(!sg_coarse && matches && atomic_load(&sg_replaced) == before + 512,
              "memory warning releases search memory and newly decoded stereo samples still replace playback");
        atomic_fetch_add(&sourceEpoch, 1); // pause, without stopPlaying() changing generation
        for (int i = 0; i < 200 && atomic_load(&sg_writers); ++i) usleep(5000);
        CHECK(!atomic_load(&sg_writers), "epoch change alone releases the full-ring writer");
        stopPlaying();
#endif
        printf("\n%s: %d failed\n", failures ? "FAILED" : "all passed", failures);
        return failures ? 1 : 0;
    }
}
