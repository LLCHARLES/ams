// SGDSPEngine.h says what this is; SGDSPEffects.h lists the effects.
#import "SGDSPEngine.h"
#import <mach/mach_time.h>
#import <math.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <dispatch/dispatch.h>
#import "Shared/Player/SGRenderGate.h"
#import "Shared/Player/SGOutputControl.h"
#import "SGDSPConvolver.h"
#import "SGDSPEffects.h"
#import "SGDSPFilters.h"

extern bool SGDSPLiveprogTripped(const SGDSPLiveprog *liveprog);

_Static_assert(kSGDSPEngineBlock == kSGDSPConvolverBlock && kSGDSPEngineBlock == kSGDSPEffectMaxFrames, "one block size throughout");

// The FIFO the processed blocks wait in: a power of two holding the primed block, the one being handed out
// and the one just made, with room to spare.
enum { kRing = 4 * kSGDSPEngineBlock };

// The order a block goes through the effects: tone, then dynamics and color, the script, the stereo image,
// and the rooms last.
typedef enum {
    SlotBass, SlotEqualizer, SlotGraphicEq, SlotDDC, SlotCompander, SlotTube, SlotLiveprog, SlotWide, SlotCrossfeed,
    SlotConvolver, SlotReverb, SlotCount,
} Slot;

static void runConvolver(void *state, float *left, float *right, uint32_t frames) {
    SGDSPConvolverProcess(state, left, right);
}

static void freeConvolver(void *state) {
    SGDSPConvolverFree(state);
}

static const struct {
    SGDSPRun run;
    SGDSPFree free;
} kKinds[SlotCount] = {
    [SlotBass] = {SGDSPBassRun, free},
    [SlotEqualizer] = {SGDSPEqualizerRun, free},
    [SlotGraphicEq] = {runConvolver, freeConvolver},
    [SlotDDC] = {SGDSPCascadeRun, SGDSPCascadeFree},
    [SlotCompander] = {SGDSPCompanderRun, free},
    [SlotTube] = {SGDSPTubeRun, free},
    [SlotLiveprog] = {SGDSPLiveprogRun, SGDSPLiveprogFree},
    [SlotWide] = {SGDSPWideRun, free},
    [SlotCrossfeed] = {SGDSPCrossfeedRun, free},
    [SlotConvolver] = {runConvolver, freeConvolver},
    [SlotReverb] = {SGDSPReverbRun, SGDSPReverbFree},
};

typedef struct {
    void *state;      // running; NULL while off
    void *leaving;    // what `state` replaced: faded out over the next block, then the config side's to free
    bool fade;        // the next block crossfades from `leaving` to `state`, NULL being the dry sound
} Effect;

struct SGDSPEngine {
    pthread_mutex_t lock;             // config writers only
    SGRenderGate effectsGate;         // bounded render admission; config waits for the old block
    atomic_uint_fast64_t rateBits;
    atomic_bool restart;
    double rate, releaseMS;           // the config side's

    // Under the lock.
    Effect effects[SlotCount];
    SGOutputSettings configuredOutput;
    bool resetOutput;

    // The render thread's alone.
    SGOutputSettings outputSettings;
    SGOutputEnvelope outputEnvelope;
    uint32_t fill;                    // frames in the block being gathered
    uint64_t written, read;           // frames into and out of the ring, the written ones a block ahead
    float blockLeft[kSGDSPEngineBlock], blockRight[kSGDSPEngineBlock];
    float fromLeft[kSGDSPEngineBlock], fromRight[kSGDSPEngineBlock];
    float ringLeft[kRing], ringRight[kRing];

    atomic_uint_fast64_t blocks, dry, faults;
    atomic_uint_fast64_t averageBits, peakNanos;
    atomic_bool liveprogTripped;
    atomic_bool collectPending;  // a fade finished with an old state, or the VM newly tripped
    unsigned liveprogOverBudget;
    bool liveprogTailPending;
    float liveprogTailLeft, liveprogTailRight;
};

enum { kLiveprogConsecutiveBlocks = 8, kLiveprogStartSeconds = 2 };
static const char kLiveprogRunError[] = "This script took too long and was turned off.";
static const char kLiveprogStartError[] = "This script took too long to start.";
// The host has one selected script. Rebuilding its engine must not retry a
// quarantined script; only its explicit switch/file action clears this latch.
static atomic_bool sg_liveprogQuarantined;

static double sg_nanosPerTick;
static float sg_ramp[kSGDSPEngineBlock];   // a crossfade's, half a cosine from 0 to 1

static void startOnce(void) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    sg_nanosPerTick = (double)timebase.numer / timebase.denom;
    for (int i = 0; i < kSGDSPEngineBlock; i++) sg_ramp[i] = (float)(0.5 - 0.5 * cos(M_PI * (i + 1) / kSGDSPEngineBlock));
}

static void storeDouble(atomic_uint_fast64_t *slot, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store_explicit(slot, bits, memory_order_relaxed);
}

static double loadDouble(const atomic_uint_fast64_t *slot) {
    uint64_t bits = atomic_load_explicit((atomic_uint_fast64_t *)slot, memory_order_relaxed);
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static void copyError(char *error, size_t errorSize, const char *text) {
    if (error && errorSize) snprintf(error, errorSize, "%s", text);
}

static bool validRate(double rate) {
    return rate >= 8000 && rate <= 384000;
}

static void beginConfig(SGDSPEngine *engine) {
    pthread_mutex_lock(&engine->lock);
    SGRenderGateClose(&engine->effectsGate);
    while (!SGRenderGateIdle(&engine->effectsGate)) usleep(100);
}

static void endConfig(SGDSPEngine *engine) {
    SGRenderGateOpen(&engine->effectsGate);
    pthread_mutex_unlock(&engine->lock);
}

// Copied only on admitted blocks. On a missed adoption the render thread keeps
// its previous complete configuration, including gain and limiting.
static void adoptOutput(SGDSPEngine *engine) {
    engine->outputSettings = engine->configuredOutput;
    if (engine->resetOutput) {
        engine->outputEnvelope = (SGOutputEnvelope){engine->outputSettings.gain, 1};
        engine->resetOutput = false;
    }
}

#pragma mark - making one

// The FIFO back to one block of silence ahead of the first frame in.
static void startOver(SGDSPEngine *engine) {
    engine->fill = 0;
    engine->read = 0;
    engine->written = kSGDSPEngineBlock;
    memset(engine->ringLeft, 0, kSGDSPEngineBlock * sizeof(float));
    memset(engine->ringRight, 0, kSGDSPEngineBlock * sizeof(float));
}

SGDSPEngine *SGDSPEngineCreate(double sampleRate) {
    static pthread_once_t once = PTHREAD_ONCE_INIT;
    if (!validRate(sampleRate)) return NULL;
    pthread_once(&once, startOnce);
    SGDSPEngine *engine = calloc(1, sizeof *engine);
    if (!engine || pthread_mutex_init(&engine->lock, NULL) != 0) {
        free(engine);
        return NULL;
    }
    engine->rate = sampleRate;
    storeDouble(&engine->rateBits, sampleRate);
    engine->outputEnvelope = (SGOutputEnvelope){1, 1};
    SGDSPEngineSetOutput(engine, 0, -0.1, 60);
    adoptOutput(engine);
    startOver(engine);
    return engine;
}

// Every effect off at once, with nothing to fade: what was running is freed.
static void dropAll(SGDSPEngine *engine, double rate) {
    void *dropped[SlotCount][2];
    beginConfig(engine);
    for (int s = 0; s < SlotCount; s++) {
        Effect *effect = &engine->effects[s];
        dropped[s][0] = effect->state;
        dropped[s][1] = effect->leaving;
        *effect = (Effect){0};
    }
    engine->rate = rate;
    storeDouble(&engine->rateBits, rate);
    engine->configuredOutput.release = (float)exp(-1000 / (engine->releaseMS * rate));
    atomic_store_explicit(&engine->collectPending, false, memory_order_relaxed);
    engine->resetOutput = true;
    endConfig(engine);
    for (int s = 0; s < SlotCount; s++) {
        for (int i = 0; i < 2; i++) {
            if (dropped[s][i]) kKinds[s].free(dropped[s][i]);
        }
    }
}

void SGDSPEngineFree(SGDSPEngine *engine) {
    if (!engine) return;
    dropAll(engine, engine->rate);
    pthread_mutex_destroy(&engine->lock);
    free(engine);
}

double SGDSPEngineSampleRate(const SGDSPEngine *engine) {
    return loadDouble(&engine->rateBits);
}

void SGDSPEngineSetSampleRate(SGDSPEngine *engine, double sampleRate) {
    if (validRate(sampleRate) && sampleRate != engine->rate) dropAll(engine, sampleRate);
}

void SGDSPEngineReset(SGDSPEngine *engine) {
    dropAll(engine, engine->rate);
}

void SGDSPEngineCollect(SGDSPEngine *engine) {
    if (!atomic_load_explicit(&engine->collectPending, memory_order_acquire)) return;
    void *done[SlotCount] = {0};
    void *tripped = NULL;
    beginConfig(engine);
    // Only an admitted render can set this. A later fade or trip will request the next collection.
    atomic_store_explicit(&engine->collectPending, false, memory_order_relaxed);
    for (int s = 0; s < SlotCount; s++) {
        Effect *effect = &engine->effects[s];
        if (s == SlotLiveprog && atomic_load_explicit(&engine->liveprogTripped, memory_order_relaxed)) {
            tripped = effect->state;
            done[s] = effect->leaving;
            *effect = (Effect){0};
            continue;
        }
        if (effect->fade || !effect->leaving) continue;
        done[s] = effect->leaving;
        effect->leaving = NULL;
    }
    endConfig(engine);
    if (tripped) SGDSPLiveprogFree(tripped);
    for (int s = 0; s < SlotCount; s++) {
        if (done[s]) kKinds[s].free(done[s]);
    }
}

#pragma mark - the render thread

static bool allFinite(const float *left, const float *right) {
    // Anything times zero is zero, but for NaN and infinity: the sum is NaN when one of them is.
    float sum = 0;
    for (uint32_t i = 0; i < kSGDSPEngineBlock; i++) sum += left[i] * 0.0f + right[i] * 0.0f;
    return sum == sum;
}

static void crossfade(SGDSPEngine *engine, Slot slot, float *left, float *right, bool heldTail) {
    Effect *effect = &engine->effects[slot];
    if (heldTail) {
        // Never execute a runaway VM again, even to fade it out. Continue from
        // its last finite output sample through the same cosine leaving ramp.
        for (uint32_t i = 0; i < kSGDSPEngineBlock; i++) {
            engine->fromLeft[i] = engine->liveprogTailLeft;
            engine->fromRight[i] = engine->liveprogTailRight;
        }
    } else {
        memcpy(engine->fromLeft, left, sizeof engine->fromLeft);
        memcpy(engine->fromRight, right, sizeof engine->fromRight);
        if (effect->leaving) kKinds[slot].run(effect->leaving, engine->fromLeft, engine->fromRight, kSGDSPEngineBlock);
        if (effect->state) kKinds[slot].run(effect->state, left, right, kSGDSPEngineBlock);
    }
    for (uint32_t i = 0; i < kSGDSPEngineBlock; i++) {
        left[i] = engine->fromLeft[i] + (left[i] - engine->fromLeft[i]) * sg_ramp[i];
        right[i] = engine->fromRight[i] + (right[i] - engine->fromRight[i]) * sg_ramp[i];
    }
    if (!heldTail) {
        effect->fade = false;
        if (effect->leaving) atomic_store_explicit(&engine->collectPending, true, memory_order_release);
    }
}

// The gain, moving to a new one over the block, then a limiter with no lookahead: it clamps a peak the
// sample it comes, stereo linked, and lets go at the release's pace.
static void output(SGDSPEngine *engine, float *left, float *right) {
    SGOutputProcess(&engine->outputEnvelope, engine->outputSettings, left, right, kSGDSPEngineBlock);
}

// The block through what is on; answers whether anything touched it.
static bool process(SGDSPEngine *engine, float *left, float *right) {
    bool active = false;
    for (int s = 0; s < SlotCount; s++) {
        Effect *effect = &engine->effects[s];
        if (s == SlotLiveprog) {
            if (engine->liveprogTailPending) {
                crossfade(engine, SlotLiveprog, left, right, true);
                engine->liveprogTailPending = false;
                active = true;
                continue;
            }
            if (atomic_load_explicit(&engine->liveprogTripped, memory_order_relaxed)) continue;
        }
        uint64_t start = s == SlotLiveprog ? mach_absolute_time() : 0;
        if (effect->fade) crossfade(engine, (Slot)s, left, right, false);
        else if (effect->state) kKinds[s].run(effect->state, left, right, kSGDSPEngineBlock);
        else continue;
        if (s == SlotLiveprog) {
            double nanos = (mach_absolute_time() - start) * sg_nanosPerTick;
            double durationNanos = kSGDSPEngineBlock / engine->rate * 1e9;
            engine->liveprogOverBudget = nanos > durationNanos * 0.5 ? engine->liveprogOverBudget + 1 : 0;
            if (isfinite(left[kSGDSPEngineBlock - 1]) && isfinite(right[kSGDSPEngineBlock - 1])) {
                engine->liveprogTailLeft = left[kSGDSPEngineBlock - 1];
                engine->liveprogTailRight = right[kSGDSPEngineBlock - 1];
            }
            if (nanos > durationNanos || engine->liveprogOverBudget >= kLiveprogConsecutiveBlocks ||
                SGDSPLiveprogTripped(effect->state) || SGDSPLiveprogTripped(effect->leaving)) {
                engine->liveprogTailPending = true;
                atomic_store_explicit(&engine->liveprogTripped, true, memory_order_release);
                atomic_store_explicit(&engine->collectPending, true, memory_order_release);
                atomic_store_explicit(&sg_liveprogQuarantined, true, memory_order_release);
            }
            // Let runBlock silence and count the fault, before it enters a stateful effect.
            if (!allFinite(left, right)) return true;
        }
        active = true;
    }
    return active;
}

// The gathered block through admitted effects, then output control, into the ring. The ring is a
// whole number of blocks and blocks are written whole, so a block never wraps.
static void runBlock(SGDSPEngine *engine, bool outputControl) {
    uint64_t at = engine->written & (kRing - 1);
    float *left = engine->ringLeft + at, *right = engine->ringRight + at;
    memcpy(left, engine->blockLeft, sizeof engine->blockLeft);
    memcpy(right, engine->blockRight, sizeof engine->blockRight);
    if (!SGRenderGateEnter(&engine->effectsGate)) {
        atomic_fetch_add_explicit(&engine->dry, 1, memory_order_relaxed);
    } else {
        uint64_t start = mach_absolute_time();
        adoptOutput(engine);
        bool active = process(engine, left, right);
        SGRenderGateLeave(&engine->effectsGate);
        uint64_t nanos = (uint64_t)((mach_absolute_time() - start) * sg_nanosPerTick);
        double average = loadDouble(&engine->averageBits);
        storeDouble(&engine->averageBits, average ? average + (nanos - average) * 0.05 : nanos);
        if (nanos > atomic_load_explicit(&engine->peakNanos, memory_order_relaxed)) {
            atomic_store_explicit(&engine->peakNanos, nanos, memory_order_relaxed);
        }
        atomic_fetch_add_explicit(&engine->blocks, 1, memory_order_relaxed);
        // An effect gone unstable would put NaN into its own state and every block after; silence rather
        // than noise, and the config side resets the engine when it sees the count move.
        if (active && !allFinite(left, right)) {
            memset(left, 0, sizeof engine->blockLeft);
            memset(right, 0, sizeof engine->blockRight);
            atomic_fetch_add_explicit(&engine->faults, 1, memory_order_relaxed);
        }
    }
    // Output control never passes dry, even when an effect configuration is busy
    // or every optional effect is off.
    if (outputControl) output(engine, left, right);
    engine->written += kSGDSPEngineBlock;
}

static void processFrames(SGDSPEngine *engine, float *left, float *right, uint32_t frames, bool outputControl) {
    if (atomic_exchange_explicit(&engine->restart, false, memory_order_acquire)) startOver(engine);
    uint32_t in = 0, out = 0;
    while (in < frames) {
        uint32_t take = kSGDSPEngineBlock - engine->fill;
        if (take > frames - in) take = frames - in;
        memcpy(engine->blockLeft + engine->fill, left + in, take * sizeof(float));
        memcpy(engine->blockRight + engine->fill, right + in, take * sizeof(float));
        engine->fill += take;
        in += take;
        if (engine->fill == kSGDSPEngineBlock) {
            runBlock(engine, outputControl);
            engine->fill = 0;
        }
        // As many frames out as came in: the ring is always a block ahead, so it has them, and the frames
        // overwritten were copied into the block already.
        while (out < in) {
            uint32_t at = (uint32_t)(engine->read & (kRing - 1));
            uint32_t count = in - out;
            if (count > kRing - at) count = kRing - at;
            memcpy(left + out, engine->ringLeft + at, count * sizeof(float));
            memcpy(right + out, engine->ringRight + at, count * sizeof(float));
            engine->read += count;
            out += count;
        }
    }
}

void SGDSPEngineRestart(SGDSPEngine *engine) {
    atomic_store_explicit(&engine->restart, true, memory_order_release);
}

void SGDSPEngineProcess(SGDSPEngine *engine, float *left, float *right, uint32_t frames) {
    processFrames(engine, left, right, frames, true);
}

void SGDSPEngineProcessEffects(SGDSPEngine *engine, float *left, float *right, uint32_t frames) {
    processFrames(engine, left, right, frames, false);
}

SGDSPEngineStats SGDSPEngineReadStats(SGDSPEngine *engine, bool takePeak) {
    SGDSPEngineStats stats = {
        .blocks = atomic_load_explicit(&engine->blocks, memory_order_relaxed),
        .dry = atomic_load_explicit(&engine->dry, memory_order_relaxed),
        .faults = atomic_load_explicit(&engine->faults, memory_order_relaxed),
        .averageMS = loadDouble(&engine->averageBits) / 1e6,
        .peakMS = (takePeak ? atomic_exchange_explicit(&engine->peakNanos, 0, memory_order_relaxed)
                            : atomic_load_explicit(&engine->peakNanos, memory_order_relaxed)) / 1e6,
    };
    double blockMS = kSGDSPEngineBlock / SGDSPEngineSampleRate(engine) * 1000;
    stats.load = stats.averageMS / blockMS;
    return stats;
}

#pragma mark - setting the effects

// A new state for the slot (NULL: off), crossfaded in over the next block. A fade still to be heard keeps
// what is heard now as its start, and the state it was going to drops.
static bool install(SGDSPEngine *engine, Slot slot, void *state) {
    Effect *effect = &engine->effects[slot];
    void *dropped;
    beginConfig(engine);
    if (slot == SlotLiveprog) {
        // Recheck under admission: the old VM can trip while its replacement
        // compiles or while a disable waits for the last render to finish.
        if (atomic_load_explicit(&sg_liveprogQuarantined, memory_order_acquire) ||
            atomic_load_explicit(&engine->liveprogTripped, memory_order_relaxed)) {
            Effect retired = *effect;
            *effect = (Effect){0};
            endConfig(engine);
            SGDSPLiveprogFree(retired.state);
            SGDSPLiveprogFree(retired.leaving);
            SGDSPLiveprogFree(state);
            return state == NULL;
        }
        engine->liveprogOverBudget = 0;
    }
    if (effect->fade) {
        dropped = effect->state;
    } else {
        dropped = effect->leaving;
        effect->leaving = effect->state;
    }
    effect->state = state;
    effect->fade = effect->leaving || state;
    endConfig(engine);
    if (dropped) kKinds[slot].free(dropped);
    SGDSPEngineCollect(engine);
    return true;
}

// The running state, under the lock, for a setter to change in place; NULL (and the lock released) when off.
static void *running(SGDSPEngine *engine, Slot slot) {
    beginConfig(engine);
    void *state = engine->effects[slot].state;
    if (!state) endConfig(engine);
    return state;
}

void SGDSPEngineSetOutput(SGDSPEngine *engine, double postGainDB, double limiterThresholdDB, double limiterReleaseMS) {
    beginConfig(engine);
    engine->releaseMS = fmax(limiterReleaseMS, 0.1);
    engine->configuredOutput.gain = (float)pow(10, postGainDB / 20);
    engine->configuredOutput.threshold = (float)pow(10, fmin(limiterThresholdDB, 0) / 20);
    engine->configuredOutput.release = (float)exp(-1000 / (engine->releaseMS * engine->rate));
    endConfig(engine);
}

void SGDSPEngineSetCompander(SGDSPEngine *engine, bool on, double timeConstant, const double frequencies[7], const double gains[7]) {
    if (!on) {
        install(engine, SlotCompander, NULL);
        return;
    }
    SGDSPCompander *compander = running(engine, SlotCompander);
    if (compander) {
        SGDSPCompanderSet(compander, timeConstant, gains);
        endConfig(engine);
        return;
    }
    install(engine, SlotCompander, SGDSPCompanderCreate(engine->rate, timeConstant, frequencies, gains));
}

void SGDSPEngineSetBassBoost(SGDSPEngine *engine, bool on, double maxGainDB) {
    if (!on) {
        install(engine, SlotBass, NULL);
        return;
    }
    SGDSPBass *bass = running(engine, SlotBass);
    if (bass) {
        SGDSPBassSet(bass, maxGainDB);
        endConfig(engine);
        return;
    }
    install(engine, SlotBass, SGDSPBassCreate(engine->rate, maxGainDB));
}

void SGDSPEngineSetEqualizer(SGDSPEngine *engine, bool on, const double frequencies[15], const double gains[15]) {
    if (!on) {
        install(engine, SlotEqualizer, NULL);
        return;
    }
    SGBiquad bands[15];
    SGDSPDesignEqualizer(engine->rate, frequencies, gains, bands);
    SGDSPEqualizer *equalizer = running(engine, SlotEqualizer);
    if (equalizer) {
        SGDSPEqualizerSet(equalizer, bands);
        endConfig(engine);
        return;
    }
    install(engine, SlotEqualizer, SGDSPEqualizerCreate(bands));
}

void SGDSPEngineSetReverb(SGDSPEngine *engine, bool on, int preset, float amount) {
    if (!on) {
        install(engine, SlotReverb, NULL);
        return;
    }
    SGDSPReverb *reverb = running(engine, SlotReverb);
    if (reverb) {
        SGDSPReverbSet(reverb, preset, amount);
        endConfig(engine);
        return;
    }
    install(engine, SlotReverb, SGDSPReverbCreate(engine->rate, preset, amount));
}

void SGDSPEngineSetStereoWide(SGDSPEngine *engine, bool on, double levelPercent) {
    if (!on) {
        install(engine, SlotWide, NULL);
        return;
    }
    SGDSPWide *wide = running(engine, SlotWide);
    if (wide) {
        SGDSPWideSet(wide, levelPercent);
        endConfig(engine);
        return;
    }
    install(engine, SlotWide, SGDSPWideCreate(engine->rate, levelPercent));
}

void SGDSPEngineSetCrossfeed(SGDSPEngine *engine, bool on, int preset) {
    if (!on) {
        install(engine, SlotCrossfeed, NULL);
        return;
    }
    SGDSPCrossfeed *crossfeed = running(engine, SlotCrossfeed);
    if (crossfeed) {
        SGDSPCrossfeedSet(crossfeed, preset);
        endConfig(engine);
        return;
    }
    install(engine, SlotCrossfeed, SGDSPCrossfeedCreate(engine->rate, preset));
}

void SGDSPEngineSetTube(SGDSPEngine *engine, bool on, double driveDB) {
    if (!on) {
        install(engine, SlotTube, NULL);
        return;
    }
    SGDSPTube *tube = running(engine, SlotTube);
    if (tube) {
        SGDSPTubeSet(tube, driveDB);
        endConfig(engine);
        return;
    }
    install(engine, SlotTube, SGDSPTubeCreate(engine->rate, driveDB));
}

#pragma mark - effects that read something

bool SGDSPEngineSetGraphicEq(SGDSPEngine *engine, bool on, const char *nodes, char *error, size_t errorSize) {
    if (!on) {
        install(engine, SlotGraphicEq, NULL);
        return true;
    }
    SGDSPGraphicCurve curve;
    if (!SGDSPParseGraphicEq(nodes, &curve)) {
        install(engine, SlotGraphicEq, NULL);
        copyError(error, errorSize, "Not in AutoEq's GraphicEQ format (\"GraphicEQ: 20 -1.2; 21 -1.1; ...\")");
        return false;
    }
    int taps = 0;
    float *impulse = SGDSPDesignGraphicEq(&curve, engine->rate, &taps);
    SGDSPFreeGraphicEq(&curve);
    const float *responses[1] = {impulse};
    SGDSPConvolver *convolver = impulse ? SGDSPConvolverCreate(responses, 1, (size_t)taps) : NULL;
    free(impulse);
    install(engine, SlotGraphicEq, convolver);
    if (!convolver) copyError(error, errorSize, "Not enough memory for the curve");
    return convolver != NULL;
}

bool SGDSPEngineSetConvolver(SGDSPEngine *engine, bool on, const char *path, int mode, char *error, size_t errorSize) {
    if (!on) {
        install(engine, SlotConvolver, NULL);
        return true;
    }
    SGDSPImpulse impulse;
    SGDSPImpulseMode kind = mode == 1 ? SGDSPImpulseTrimmed : mode == 2 ? SGDSPImpulseMinimumPhase : SGDSPImpulseOriginal;
    if (!SGDSPReadImpulse(path, engine->rate, kind, &impulse, error, errorSize)) {
        install(engine, SlotConvolver, NULL);
        return false;
    }
    SGDSPConvolver *convolver = SGDSPConvolverCreate((const float *const *)impulse.responses, impulse.paths, impulse.length);
    SGDSPFreeImpulse(&impulse);
    install(engine, SlotConvolver, convolver);
    if (!convolver) copyError(error, errorSize, "Not enough memory for the impulse response");
    return convolver != NULL;
}

bool SGDSPEngineSetDDC(SGDSPEngine *engine, bool on, const char *text, char *error, size_t errorSize) {
    if (!on) {
        install(engine, SlotDDC, NULL);
        return true;
    }
    SGDSPDDC ddc;
    if (!text || !SGDSPParseDDC(text, &ddc, error, errorSize)) {
        if (!text) copyError(error, errorSize, "The DDC file could not be read");
        install(engine, SlotDDC, NULL);
        return false;
    }
    int count = 0;
    SGBiquad *sections = SGDSPDDCFor(&ddc, engine->rate, &count);
    SGDSPFreeDDC(&ddc);
    SGDSPCascade *cascade = sections ? SGDSPCascadeCreate(sections, count) : NULL;
    install(engine, SlotDDC, cascade);
    if (!cascade) copyError(error, errorSize, "Not enough memory for the DDC file");
    return cascade != NULL;
}

// A load job owns its script and VM, never the engine. After abandonment only
// the worker may dispose of it, including when the engine has already gone away.
typedef enum { LoadWaiting, LoadComplete, LoadAbandoned } LoadPhase;
typedef struct {
    atomic_int phase;
    char *script;
    double rate;
    uint64_t started;
    bool expired;
    bool slow;
    SGDSPLiveprog *result;
    char error[300];
} LiveprogLoad;
static atomic_bool sg_liveprogLoading;

const char *SGDSPEngineLiveprogError(const SGDSPEngine *engine) {
    return (atomic_load_explicit(&sg_liveprogQuarantined, memory_order_acquire) ||
            (engine && atomic_load_explicit(&engine->liveprogTripped, memory_order_acquire))) ? kLiveprogRunError : NULL;
}

void SGDSPEngineLiveprogUserChange(SGDSPEngine *engine) {
    Effect retired = {0};
    if (engine) {
        beginConfig(engine);
        if (atomic_exchange_explicit(&engine->liveprogTripped, false, memory_order_acq_rel)) {
            retired = engine->effects[SlotLiveprog];
            engine->effects[SlotLiveprog] = (Effect){0};
        }
        engine->liveprogOverBudget = 0;
    }
    atomic_store_explicit(&sg_liveprogQuarantined, false, memory_order_release);
    if (engine) endConfig(engine);
    // The cached-tail transition is independent of VM lifetime and quarantine.
    SGDSPLiveprogFree(retired.state);
    SGDSPLiveprogFree(retired.leaving);
}

bool SGDSPEngineSetLiveprog(SGDSPEngine *engine, bool on, const char *script, char *error, size_t errorSize) {
    if (!on) {
        install(engine, SlotLiveprog, NULL);
        return true;
    }
    if (SGDSPEngineLiveprogError(engine)) {
        install(engine, SlotLiveprog, NULL);
        copyError(error, errorSize, kLiveprogRunError);
        return false;
    }
    if (atomic_exchange_explicit(&sg_liveprogLoading, true, memory_order_acq_rel)) {
        copyError(error, errorSize, kLiveprogStartError);
        return false;
    }
    LiveprogLoad *job = calloc(1, sizeof *job);
    if (!job || (script && !(job->script = strdup(script)))) {
        free(job);
        atomic_store(&sg_liveprogLoading, false);
        copyError(error, errorSize, "Not enough memory for the script");
        return false;
    }
    job->rate = engine->rate;
    job->started = mach_absolute_time();
    dispatch_semaphore_t finished = dispatch_semaphore_create(0);
    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, kLiveprogStartSeconds * NSEC_PER_SEC);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        job->result = SGDSPLiveprogCreate(job->script, job->rate, &job->slow, job->error, sizeof job->error);
        free(job->script);
        // The waiting thread may itself be descheduled at its deadline. A late
        // worker must not publish its VM just because it won that wake-up race.
        job->expired = (mach_absolute_time() - job->started) * sg_nanosPerTick > kLiveprogStartSeconds * 1e9;
        int waiting = LoadWaiting;
        if (!atomic_compare_exchange_strong_explicit(&job->phase, &waiting, LoadComplete,
                                                     memory_order_release, memory_order_relaxed)) {
            SGDSPLiveprogFree(job->result);
            free(job);
        }
        atomic_store_explicit(&sg_liveprogLoading, false, memory_order_release);
        dispatch_semaphore_signal(finished);
    });
    if (dispatch_semaphore_wait(finished, deadline)) {
        int waiting = LoadWaiting;
        if (atomic_compare_exchange_strong_explicit(&job->phase, &waiting, LoadAbandoned,
                                                    memory_order_acq_rel, memory_order_acquire)) {
            copyError(error, errorSize, kLiveprogStartError);
            return false;
        }
    }
    SGDSPLiveprog *liveprog = job->result;
    // Running out of startup work is the same refusal as the deadline: the previous script stays.
    if (job->expired || job->slow) {
        SGDSPLiveprogFree(liveprog);
        free(job);
        copyError(error, errorSize, kLiveprogStartError);
        return false;
    }
    if (!liveprog) copyError(error, errorSize, job->error);
    free(job);
    bool installed = install(engine, SlotLiveprog, liveprog);
    if (!installed) copyError(error, errorSize, kLiveprogRunError);
    return liveprog != NULL && installed;
}

#pragma mark - curves

void SGDSPEngineEqualizerCurve(const double bandFrequencies[15], const double gains[15], int count, double *frequencies, double *decibels) {
    if (count <= 0) return;
    SGDSPLogFrequencies(count, frequencies);
    SGBiquad bands[15];
    SGDSPDesignEqualizer(48000, bandFrequencies, gains, bands);
    for (int i = 0; i < count; i++) decibels[i] = SGBiquadGainDB(bands, 15, 48000, frequencies[i]);
}

void SGDSPEngineCompanderCurve(const double bandFrequencies[7], const double gains[7], int count, double *frequencies, double *values) {
    if (count <= 0) return;
    SGDSPLogFrequencies(count, frequencies);
    for (int i = 0; i < count; i++) values[i] = SGDSPSmoothCurve(bandFrequencies, gains, 7, frequencies[i]);
}
