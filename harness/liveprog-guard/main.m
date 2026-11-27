#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <mach/thread_policy.h>
#import <math.h>
#import <pthread.h>
#import <stdatomic.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import "SGDSPEngine.h"
#import "SGDSPEffects.h"
#import "AudioEffects.h"
#import "Core/SGLocalize.h"
#import "Core/SGLog.h"
#import <os/lock.h>

static _Atomic(SGDSPEngine *) sg_engine;
static os_unfair_lock sg_errorLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSString *> *sg_errors;
// The runner copies this complete section verbatim from AudioEffects.x. Only
// the iOS audio hook is omitted; SGDSPError and its config writer are production.
#include "AudioEffectsErrors.m"

static bool synthetic;
static uint64_t ticks, runTicks;
static double nanosPerTick;
static float left[kSGDSPEngineBlock], right[kSGDSPEngineBlock];
static const char *gain = "@sample\nspl0 *= 0.5; spl1 *= 0.5;\n";
static const char *startError = "This script took too long to start.";
static dispatch_semaphore_t loadEntered, renderedDuringLoad;
static unsigned deadlineRequests;
static _Atomic(pthread_t) renderThread;
static atomic_bool inRender;
static atomic_uint renderAllocations;

typedef void(malloc_logger_t)(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t);
extern malloc_logger_t *malloc_logger;
static dispatch_semaphore_t releaseLoad, freedLoad;
static dispatch_semaphore_t workerReturned;
static atomic_bool observeWorkerReturn;
static _Atomic(SGDSPLiveprog *) heldVM;

static void countAllocation(uint32_t type, uintptr_t a, uintptr_t b, uintptr_t c, uintptr_t result, uint32_t skip) {
    if (atomic_load_explicit(&inRender, memory_order_relaxed) &&
        pthread_equal(pthread_self(), atomic_load_explicit(&renderThread, memory_order_relaxed)))
        atomic_fetch_add_explicit(&renderAllocations, 1, memory_order_relaxed);
}

static void require(bool good, const char *message) {
    if (!good) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

#include "host.m"

// Only the engine's clock and VM boundary are substituted. The real EEL VM and
// the production render chain execute in both real-time and synthetic-time tests.
uint64_t guard_clock(void) {
    return synthetic ? ticks : mach_absolute_time();
}

void guard_run(void *state, float *l, float *r, uint32_t count) {
    SGDSPLiveprogRun(state, l, r, count);
    if (synthetic) ticks += runTicks;
}

SGDSPLiveprog *guard_create(const char *script, double rate, bool *slow, char *error, size_t errorSize) {
    SGDSPLiveprog *vm = SGDSPLiveprogCreate(script, rate, slow, error, errorSize);
    if (script && !strncmp(script, "desc: held\n", 11)) {
        atomic_store(&heldVM, vm);
        dispatch_semaphore_signal(loadEntered);
        if (renderedDuringLoad) dispatch_semaphore_signal(loadEntered);
        dispatch_semaphore_wait(releaseLoad, DISPATCH_TIME_FOREVER);
    }
    return vm;
}

void guard_free(void *vm) {
    bool held = vm && vm == atomic_load(&heldVM);
    SGDSPLiveprogFree(vm);
    if (held) {
        atomic_store(&heldVM, NULL);
        dispatch_semaphore_signal(freedLoad);
    }
}

long guard_signal(dispatch_semaphore_t semaphore) {
    bool observed = atomic_exchange(&observeWorkerReturn, false);
    long result = dispatch_semaphore_signal(semaphore);
    if (observed)
        dispatch_semaphore_signal(workerReturned);
    return result;
}

dispatch_time_t guard_deadline(dispatch_time_t base, int64_t offset) {
    require(base == DISPATCH_TIME_NOW && offset == 2 * NSEC_PER_SEC, "startup requests a two-second deadline");
    deadlineRequests++;
    return (dispatch_time_t)offset;
}

long guard_wait(dispatch_semaphore_t finished, dispatch_time_t deadline) {
    require(deadline == 2 * NSEC_PER_SEC, "startup waits on its requested deadline");
    if (!loadEntered) {
        require(!dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
                "startup worker did not finish");
        return 0;
    }
    require(!dispatch_semaphore_wait(loadEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
            "worker did not enter held startup");
    if (renderedDuringLoad)
        require(!dispatch_semaphore_wait(renderedDuringLoad, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
                "previous script did not render during startup");
    return 1; // Expire the deadline while the worker is positively held.
}

static void block(SGDSPEngine *engine) {
    for (unsigned i = 0; i < kSGDSPEngineBlock; i++) {
        left[i] = 0.25f;
        right[i] = -0.125f;
    }
    atomic_store_explicit(&renderThread, pthread_self(), memory_order_relaxed);
    atomic_store_explicit(&inRender, true, memory_order_relaxed);
    SGDSPEngineProcessEffects(engine, left, right, kSGDSPEngineBlock);
    atomic_store_explicit(&inRender, false, memory_order_relaxed);
    require(atomic_load(&renderAllocations) == 0, "render never allocates or frees");
    for (unsigned i = 0; i < kSGDSPEngineBlock; i++)
        require(isfinite(left[i]) && isfinite(right[i]), "output remains finite");
}

static void level(float l, float r) {
    for (unsigned i = 0; i < kSGDSPEngineBlock; i++)
        require(fabsf(left[i] - l) < 0.000001f && fabsf(right[i] - r) < 0.000001f,
                "settled output matches the independent channel levels");
}

static void load(SGDSPEngine *engine, const char *script) {
    char error[300] = "";
    SGDSPEngineLiveprogUserChange(engine);
    bool ok = SGDSPEngineSetLiveprog(engine, true, script, error, sizeof error);
    if (!ok) fprintf(stderr, "%s\n", error);
    require(ok, "script loads");
}

static void cost(double fraction, double rate) {
    runTicks = llround((1024.0 / rate * 1e9 * fraction) / nanosPerTick);
}

static void thresholds(double rate) {
    synthetic = true;
    SGDSPEngine *engine = SGDSPEngineCreate(rate);
    load(engine, gain);
    cost(0.75, rate);
    for (int i = 0; i < 7; i++) block(engine);
    require(!SGDSPEngineLiveprogError(engine), "seven over-half blocks do not trip");
    cost(0.25, rate);
    block(engine);
    cost(0.75, rate);
    for (int i = 0; i < 7; i++) block(engine);
    require(!SGDSPEngineLiveprogError(engine), "a cheap block resets the consecutive count");
    block(engine);
    const char *error = SGDSPEngineLiveprogError(engine);
    require(error && !strcmp(error, "This script took too long and was turned off."),
            "eighth consecutive over-half block reports the runaway error");
    // No collect yet: render must bypass without waiting for a config pass.
    block(engine);
    block(engine);
    require(left[0] >= 0.125f && left[0] < 0.12501f && left[1023] == 0.25f,
            "leaving ramp starts at the old tail and ends at dry");
    for (unsigned i = 1; i < kSGDSPEngineBlock; i++)
        require(left[i] >= left[i-1] && left[i] - left[i-1] < 0.001f,
                "runaway leaving crossfade is continuous");
    block(engine);
    level(0.25f, -0.125f);
    SGDSPEngineCollect(engine);
    require(SGDSPEngineLiveprogError(engine) != NULL, "collect preserves the error latch");
    cost(0.1, rate);
    load(engine, gain);
    require(!SGDSPEngineLiveprogError(engine), "re-enable clears the trip");
    for (int i = 0; i < 12; i++) block(engine);
    level(0.125f, -0.0625f);
    cost(1.25, rate);
    block(engine);
    require(SGDSPEngineLiveprogError(engine) != NULL, "one over-full block trips immediately");
    // Collect before the next render must not remove the cached leaving ramp.
    SGDSPEngineCollect(engine);
    block(engine);
    block(engine);
    require(left[0] < 0.12501f && left[1023] == 0.25f, "collect retains the leaving crossfade");
    block(engine);
    level(0.25f, -0.125f);
    SGDSPEngineFree(engine);
}

// Rendered as the audio unit renders: on a time-constraint thread that waits between blocks. An ordinary thread
// rendering back to back can be held off the CPU past a block's length on a busy machine, which the real-clock
// guard rightly counts against the script; the audio thread is not held that way. The wait is an eighth of a
// block, so 64 seconds of audio take 8, and a two-second load spans about 750 blocks.
static uint64_t audioRenderPace(void) {
    uint64_t pace = (uint64_t)llround((double)kSGDSPEngineBlock / 48000 * 1e9 / 8 / nanosPerTick);
    thread_time_constraint_policy_data_t policy = {
        .period = (uint32_t)pace, .computation = (uint32_t)(pace / 2), .constraint = (uint32_t)pace, .preemptible = 1};
    mach_port_t thread = mach_thread_self();
    kern_return_t set = thread_policy_set(thread, THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&policy,
                                          THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    mach_port_deallocate(mach_task_self(), thread);
    require(set == KERN_SUCCESS, "the render thread takes the audio thread's time-constraint policy");
    return pace;
}

static void waitForAudioBlock(uint64_t *next, uint64_t pace) {
    *next += pace;
    mach_wait_until(*next);
}

static void *normalScriptRender(void *unused) {
    uint64_t pace = audioRenderPace();
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    load(engine, gain);
    uint64_t next = mach_absolute_time();
    for (int i = 0; i < 3000; i++) {
        block(engine);
        require(!SGDSPEngineLiveprogError(engine), "normal script never trips in 64 seconds of audio");
        if (i > 1) level(0.125f, -0.0625f);
        waitForAudioBlock(&next, pace);
    }
    SGDSPEngineFree(engine);
    return NULL;
}

static void normalScript(void) {
    pthread_t thread;
    require(pthread_create(&thread, NULL, normalScriptRender, NULL) == 0, "render thread starts");
    require(pthread_join(thread, NULL) == 0, "render thread finishes");
}

static void heavy(void) {
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    load(engine, "@block\nloop(128, loop(16384, x = sin(x + 1);););\n"
                 "@sample\nspl0 *= 0.5; spl1 *= 0.5;\n");
    for (int i = 0; i < 10 && !SGDSPEngineLiveprogError(engine); i++) block(engine);
    require(SGDSPEngineLiveprogError(engine) != NULL, "real finite heavy EEL script trips");
    for (int i = 0; i < 20; i++) {
        block(engine);
        if (i > 1) level(0.25f, -0.125f);
    }
    SGDSPEngineCollect(engine);
    SGDSPEngineFree(engine);
}

static void *renderDuringLoad(void *engine) {
    // Wait for the VM to enter the held loader, not merely for the thread to start.
    require(!dispatch_semaphore_wait(loadEntered, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)),
            "render did not observe held load");
    for (unsigned i = 0; i < 101; ++i) {
        block(engine);
        level(0.125f, -0.0625f);
    }
    dispatch_semaphore_signal(renderedDuringLoad);
    return NULL;
}

static void deadline(void) {
    releaseLoad = dispatch_semaphore_create(0);
    freedLoad = dispatch_semaphore_create(0);
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    load(engine, gain);
    for (int i = 0; i < 3; i++) block(engine);
    pthread_t thread;
    synthetic = true;
    cost(0.1, 48000);
    loadEntered = dispatch_semaphore_create(0);
    renderedDuringLoad = dispatch_semaphore_create(0);
    require(pthread_create(&thread, NULL, renderDuringLoad, engine) == 0, "render thread starts");
    // Hold startup independently of the VM's deterministic work budget.
    char error[300] = "";
    bool ok = SGDSPEngineSetLiveprog(engine, true,
        "desc: held\n@sample\nspl0 = 0; spl1 = 0;\n", error, sizeof error);
    require(!ok && !strcmp(error, startError), "held startup returns the start error");
    unsigned before = deadlineRequests;
    ok = SGDSPEngineSetLiveprog(engine, true, gain, error, sizeof error);
    require(!ok && !strcmp(error, startError) && deadlineRequests == before,
            "a second load is immediately refused while the worker is abandoned");
    dispatch_semaphore_signal(releaseLoad);
    require(dispatch_semaphore_wait(freedLoad, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0,
            "abandoned startup releases the VM");
    require(pthread_join(thread, NULL) == 0, "render thread joins");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    SGDSPEngineFree(engine);
}

static void abandonment(void) {
    loadEntered = dispatch_semaphore_create(0);
    releaseLoad = dispatch_semaphore_create(0);
    freedLoad = dispatch_semaphore_create(0);
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    char error[300] = "";
    bool ok = SGDSPEngineSetLiveprog(engine, true,
        "desc: held\n@sample\nspl0 *= 0.5; spl1 *= 0.5;\n", error, sizeof error);
    require(!ok && !strcmp(error, startError), "a held worker is abandoned at the deadline");
    require(dispatch_semaphore_wait(freedLoad, DISPATCH_TIME_NOW) != 0,
            "an abandoned VM is not freed while its worker owns it");
    SGDSPEngineFree(engine);
    dispatch_semaphore_signal(releaseLoad);
    require(dispatch_semaphore_wait(freedLoad, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0,
            "the worker frees its abandoned VM after returning, even after engine destruction");
}

static void limits(void) {
    bool slow = false;
    char message[128] = "";
    SGDSPLiveprog *vm = SGDSPLiveprogCreate("slider1:1.5\nslider4294967297:8\n@sample\nspl0 = slider1;", 48000, &slow, message, sizeof message);
    require(vm != NULL, "slider fixture loads");
    float l = 0.25f, r = 0.5f;
    SGDSPLiveprogRun(vm, &l, &r, 1);
    require(l == 1.5f && r == 0.5f, "oversized slider number cannot overwrite slider1");
    SGDSPLiveprogFree(vm);
    vm = SGDSPLiveprogCreate("slider1:1e80\n@sample\n"
        "mem_set_values(0,7); x=3; spl0=mem_insert_shuffle(slider1,1,9)+mem_multiply_sum(-slider1,0,1)"
        "+mem_set_values(slider1,8)+mem_get_values(-slider1,x); spl1=x+mem_multiply_sum(-1,0,1);",
        48000, &slow, message, sizeof message);
    require(vm != NULL, "RAM range fixture loads");
    SGDSPLiveprogRun(vm, &l, &r, 1);
    require(l == 0 && r == 52, "invalid RAM operands return zero without changing values or RAM");
    SGDSPLiveprogFree(vm);
    synthetic = true; // the clock guard cannot account for these trips
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    char error[300] = "";
    load(engine, gain);
    cost(0.1, 48000);
    require(!SGDSPEngineSetLiveprog(engine, true,
            "@init\nloop(1000,loop(1000,x+=1));\n@sample\nspl0=x;", error, sizeof error)
            && !strcmp(error,startError), "aggregate init work is refused");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    require(!SGDSPEngineSetLiveprog(engine, true,
            "@init\nloop(1000,memset(0,1,4000000));\n@sample\nspl0=x;", error, sizeof error)
            && !strcmp(error,startError), "bulk memory work in init is metered");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    NSMutableString *straight = [NSMutableString stringWithString:@"@init\n"];
    for (int i = 0; i < 16; i++) [straight appendString:@"memset(0,1,1048576);"];
    [straight appendString:@"\n@sample\nspl0=x;"];
    NSMutableString *values = [NSMutableString stringWithString:@"@init\nloop(300000,mem_set_values(0"];
    for (int i = 0; i < 64; i++) [values appendString:@",x"];
    [values appendString:@"));\n@sample\nspl0=x;"];
    // A refused @init must stop at the refusal: g is a global the running script reads.
    load(engine, "@sample\nspl0*=0.5+_global.g;spl1*=0.5+_global.g;");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    NSMutableString *stops = [straight mutableCopy];
    [stops replaceOccurrencesOfString:@"\n@sample" withString:@"_global.g=1;\n@sample" options:0 range:NSMakeRange(0, stops.length)];
    require(!SGDSPEngineSetLiveprog(engine, true, stops.UTF8String, error, sizeof error) && !strcmp(error,startError),
            "a refused init is refused");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    load(engine, gain);
    NSDictionary<NSString *, NSString *> *refusals = @{
        @"bulk work that runs out without a later loop is refused": straight,
        @"scanning unallocated memory is metered": @"@init\nloop(100,x+=mem_multiply_sum(-1,1048576,130000000));\n@sample\nspl0=x;",
        @"multi-value transfers are metered": values,
    };
    for (NSString *what in refusals) {
        require(!SGDSPEngineSetLiveprog(engine, true, refusals[what].UTF8String, error, sizeof error)
                && !strcmp(error,startError), what.UTF8String);
        for (int i = 0; i < 3; i++) block(engine);
        level(0.125f, -0.0625f);
    }
    // Each iteration is a loop step plus a 16-element memset's step: 999,998 of the 1,000,000 startup
    // steps, and the final 32-element memset spends exactly the last two.
    load(engine, "@init\nloop(499999,memset(0,0,16));memset(0,0,32);\n@sample\nspl0*=0.5;spl1*=0.5;");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    // A spilled operand comes back through the stack-to-FP pop on the portable VM.
    load(engine, "@sample\n//#eel-no-optimize:2\na=2;b=3;spl0*=((a+b)*(a-b))/-10;spl1*=((a*b)-(b-a))/10;");
    for (int i = 0; i < 3; i++) block(engine);
    level(0.125f, -0.0625f);
    for (NSString *body in @[@"loop(320,loop(320,x+=1));", @"while((x+=1)<100100);"]) {
        load(engine, [[@"@sample\n" stringByAppendingString:body] UTF8String]);
        // The previous trip's cached tail plays out in the first block after a reload, before this script runs.
        block(engine);
        if (!SGDSPEngineLiveprogError(engine)) block(engine);
        require(SGDSPEngineLiveprogError(engine) != NULL, "VM budget quarantines the script on its first run");
        SGDSPEngineCollect(engine);
    }
    for (NSString *link in @[@"+a", @"[]"]) {
        NSMutableString *s = [NSMutableString stringWithString:@"@sample\nspl0=a"];
        for (int i=0; i<260; i++) [s appendString:link];
        SGDSPEngineLiveprogUserChange(engine);
        require(!SGDSPEngineSetLiveprog(engine,true,s.UTF8String,error,sizeof error) &&
                !strncmp(error,"Line 2:",7),"overlong chain fails with a compiler error");
    }
    SGDSPEngineFree(engine);
}

static bool applyScript(SGDSPEngine *engine, const char *script) {
    char error[300] = "";
    SGDSPEngineLiveprogUserChange(engine);
    bool ok = SGDSPEngineSetLiveprog(engine, true, script, error, sizeof error);
    setError(SGKeyDSPLiveprog, ok ? nil : @(error));
    return ok;
}

static void messages(void) {
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    atomic_store(&sg_engine, engine);
    require(applyScript(engine, gain), "initial script applies");
    synthetic = true;
    cost(1.25, 48000);
    block(engine);
    require([SGDSPError(SGKeyDSPLiveprog) isEqualToString:@"This script took too long and was turned off."],
            "SGDSPError exposes the runaway message");
    require(SGDSPError(SGKeyDSPDDC) == nil, "Liveprog's trip does not affect other errors");
    SGDSPEngineCollect(engine);
    require([SGDSPError(SGKeyDSPLiveprog) isEqualToString:@"This script took too long and was turned off."],
            "collect does not erase the displayed runaway message");
    cost(0.1, 48000);
    require(applyScript(engine, gain) && SGDSPError(SGKeyDSPLiveprog) == nil,
            "re-enabling clears the displayed runaway message");
    loadEntered = dispatch_semaphore_create(0);
    releaseLoad = dispatch_semaphore_create(0);
    freedLoad = dispatch_semaphore_create(0);
    workerReturned = dispatch_semaphore_create(0);
    atomic_store(&observeWorkerReturn, true);
    require(!applyScript(engine, "desc: held\n@sample\nspl0 *= 0.5;\n"),
            "held startup reaches its deadline");
    require([SGDSPError(SGKeyDSPLiveprog) isEqualToString:@"This script took too long to start."],
            "SGDSPError exposes the startup timeout message");
    dispatch_semaphore_signal(releaseLoad);
    require(dispatch_semaphore_wait(workerReturned, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)) == 0,
            "abandoned worker has returned");
    loadEntered = nil;
    require(applyScript(engine, gain) && SGDSPError(SGKeyDSPLiveprog) == nil,
            "re-enabling clears the displayed startup timeout message");
    atomic_store(&sg_engine, NULL);
    SGDSPEngineFree(engine);
}

static void expectQuarantined(SGDSPEngine *engine) {
    require([SGDSPError(SGKeyDSPLiveprog) isEqualToString:@"This script took too long and was turned off."],
            "automatic reapplication preserves the displayed quarantine");
    for (int i = 0; i < 4; i++) block(engine);
    level(0.25f, -0.125f);
}

static void quarantine(void) {
    synthetic = true;
    SGDSPEngine *engine = SGDSPEngineCreate(48000);
    atomic_store(&sg_engine, engine);
    hostScript(gain);
    hostApply(SGKeyDSPLiveprog);
    cost(1.25, 48000);
    block(engine);
    // Repeating the automatic path also catches an install that silently drops
    // the latch while refusing the first retry, then loads on the next retry.
    cost(0.1, 48000);
    for (int i = 0; i < 2; i++) {
        applyAll(engine);
        expectQuarantined(engine);
    }
    SGDSPEngineSetSampleRate(engine, 96000);
    for (int i = 0; i < 2; i++) {
        hostApply(SGKeyDSP);
        expectQuarantined(engine);
    }
    followRoute();
    hostDrain();
    expectQuarantined(engine);
    atomic_store(&sg_engine, NULL);
    SGDSPEngineFree(engine);
    engine = SGDSPEngineCreate(48000);
    atomic_store(&sg_engine, engine);
    hostApply(SGKeyDSP);
    expectQuarantined(engine);

    hostOn = NO;
    hostApply(SGKeyDSPLiveprog);
    hostOn = YES;
    hostApply(SGKeyDSPLiveprog);
    require(SGDSPError(SGKeyDSPLiveprog) == nil, "explicit off/on clears quarantine");
    for (int i = 0; i < 4; i++) block(engine);
    level(0.125f, -0.0625f);

    // Conversion to Float32 overflows. This reproduces a budget trip and a
    // non-finite fault in the same block, using the real EEL VM.
    hostScript("@sample\nspl0 = 10^100; spl1 = 10^100;\n");
    hostApply(SGKeyDSPLiveprog);
    require(SGDSPError(SGKeyDSPLiveprog) == nil, "non-finite script loads successfully");
    cost(1.25, 48000);
    block(engine);
    require(SGDSPEngineReadStats(engine, false).faults > 0, "script produces a non-finite fault");
    cost(0.1, 48000);
    tend();
    expectQuarantined(engine);
    applyAll(engine);
    expectQuarantined(engine);

    hostScript(gain);
    hostApply(SGKeyDSPLiveprog);
    require(SGDSPError(SGKeyDSPLiveprog) == nil, "explicit script selection clears quarantine");
    for (int i = 0; i < 4; i++) block(engine);
    level(0.125f, -0.0625f);
    atomic_store(&sg_engine, NULL);
    SGDSPEngineFree(engine);
}

static void adjacentDisable(void) {
    synthetic = true;
    for (int replace = 0; replace < 2; replace++) {
        SGDSPEngine *engine = SGDSPEngineCreate(48000);
        load(engine, gain);
        cost(0.1, 48000);
        for (int i = 0; i < 3; i++) block(engine);
        cost(1.25, 48000);
        block(engine);
        require(SGDSPEngineLiveprogError(engine) != NULL, "script trips before adjacent config");
        char error[300] = "";
        require(SGDSPEngineSetLiveprog(engine, false, NULL, error, sizeof error), "adjacent disable applies");
        if (replace) load(engine, "@sample\nspl0 *= 0.25; spl1 *= 0.25;\n");
        cost(0.1, 48000);
        block(engine); // The FIFO still hands out the tripping block.
        float previous = left[1023];
        block(engine); // Pending leaving ramp, not a second runaway execution.
        require(fabsf(left[0] - previous) < 0.001f, "adjacent disable/replacement preserves the boundary");
        require(left[1023] == 0.25f, "pending leaving ramp reaches dry");
        for (unsigned i = 1; i < kSGDSPEngineBlock; i++)
            require(fabsf(left[i] - left[i-1]) < 0.001f, "adjacent transition stays within the crossfade bound");
        for (int i = 0; i < 4; i++) block(engine);
        level(replace ? 0.0625f : 0.25f, replace ? -0.03125f : -0.125f);
        SGDSPEngineFree(engine);
    }
}

int main(int argc, char **argv) {
    @autoreleasepool {
        require(argc == 2, "one case name required");
        hostDirectory = [@(argv[0]) stringByDeletingLastPathComponent];
        mach_timebase_info_data_t info;
        mach_timebase_info(&info);
        nanosPerTick = (double)info.numer / info.denom;
        malloc_logger = countAllocation;
        if (!strcmp(argv[1], "thresholds")) {
            thresholds(48000);
            thresholds(96000);
        } else if (!strcmp(argv[1], "normal")) normalScript();
        else if (!strcmp(argv[1], "heavy")) heavy();
        else if (!strcmp(argv[1], "limits")) limits();
        else if (!strcmp(argv[1], "deadline")) deadline();
        else if (!strcmp(argv[1], "abandonment")) abandonment();
        else if (!strcmp(argv[1], "messages")) messages();
        else if (!strcmp(argv[1], "quarantine")) quarantine();
        else if (!strcmp(argv[1], "adjacent")) adjacentDisable();
        else require(false, "unknown case");
        printf("PASS: %s\n", argv[1]);
    }
    return 0;
}
