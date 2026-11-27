// build-sim.sh battery: real player-state handler, worker, ring and motion registration;
// no download, model prediction, hardware, or instrumentation on the render thread.
#import <unistd.h>
#import <stdatomic.h>
#import <pthread.h>
#import "../../harness-fail.h"
static atomic_uint polls;
static atomic_bool observePark;
static dispatch_semaphore_t workerParked;
static int workerWait(pthread_cond_t *cond, pthread_mutex_t *lock) {
    if (atomic_exchange(&observePark, false)) dispatch_semaphore_signal(workerParked);
    return pthread_cond_wait(cond, lock);
}
static int workerSleep(useconds_t delay) {
    atomic_fetch_add(&polls, 1);
    return usleep(delay);
}
#define usleep workerSleep
#define pthread_cond_wait workerWait
#import "SGSingEngine.m"
#undef pthread_cond_wait
#undef usleep

#import "Sing.h"
#import "SGSingLoader.h"
static SGSingSeparator *loaded;
static SGSingSeparator *harnessSeparator(void) { return loaded ?: SGSingLoaderSeparator(); }
#define SGSingModelCurrentState() SGSingModelReady
#define SGSingModelURL() [NSURL fileURLWithPath:@"/mock/separator-light.mlmodelc"]
#define SGSingLoaderSeparator() harnessSeparator()
#import "Sing.m"

static OSStatus tone(void *unused, UInt32 frames, float *l, float *r, UInt32 *sounding) {
    for (UInt32 i = 0; i < frames; ++i) l[i] = r[i] = 0.25f;
    if (sounding) *sounding = frames;
    return noErr;
}

@interface HalfVocal : SGSingSeparator
@end
@implementation HalfVocal
- (BOOL)separateLeft:(const float *)left right:(const float *)right vocalsLeft:(float *)vl vocalsRight:(float *)vr error:(NSError **)error {
    for (unsigned i = 0; i < kSGSingWindowFrames; ++i) {
        vl[i] = 0.5f * left[i];
        vr[i] = 0.5f * right[i];
    }
    return YES;
}
@end

static bool mixed(const float *l, const float *r) {
    for (unsigned i = 0; i < 1024; ++i)
        if (!(fabsf(l[i] - 0.125f) < 1e-6f && fabsf(r[i] - 0.125f) < 1e-6f)) return false;
    return true;
}

// Identity prediction with a switchable ANE error. Only the Core ML file reader is replaced;
// tick(), apply(), the loader and the separator all see the actual failed prediction.
@interface TickModel : MLModel
@property BOOL fails;
@end
@implementation TickModel
- (id<MLFeatureProvider>)predictionFromFeatures:(id<MLFeatureProvider>)input error:(NSError **)error {
    if (self.fails) {
        if (error) *error = [NSError errorWithDomain:@"TickHarness" code:1 userInfo:nil];
        return nil;
    }
    return [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"vocals_spectrum":[input featureValueForName:@"spectrum"]} error:error];
}
@end

static void waitUntil(CFAbsoluteTime deadline, BOOL (^done)(void), void (^next)(void)) {
    if (done()) { next(); return; }
    if (CFAbsoluteTimeGetCurrent() >= deadline)
        HARNESS_FAIL(@"loader state %ld, fast %ld, error %@", (long)SGSingLoaderCurrentState(), (long)SGSingLoaderFastState(), SGSingLoaderError());
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 50), dispatch_get_main_queue(), ^{ waitUntil(deadline, done, next); });
}

static void checkBackgroundTick(int windows) {
    loaded = nil;
    sg_active = NO;
    SGSingLoaderPurge(@"start tick case");
    __block TickModel *ane;
    Method reader = class_getClassMethod(MLModel.class, @selector(modelWithContentsOfURL:configuration:error:));
    IMP stub = imp_implementationWithBlock(^MLModel *(id cls, NSURL *url, MLModelConfiguration *config, NSError **error) {
        TickModel *model = [TickModel alloc];
        if (config.computeUnits != MLComputeUnitsCPUOnly) ane = model;
        return model;
    });
    IMP original = method_setImplementation(reader, stub);
    NSURL *url = SGSingModelURL();
    float *silence = calloc(kSGSingWindowFrames, sizeof(float)), *out = calloc(kSGSingWindowFrames, sizeof(float));
    BOOL (^window)(void) = ^BOOL {
        @autoreleasepool { return [SGSingLoaderSeparator() separateLeft:silence right:silence vocalsLeft:out vocalsRight:out error:nil]; }
    };
    SGSingLoaderSetForeground(YES);
    SGSingLoaderWant(url, YES);
    waitUntil(CFAbsoluteTimeGetCurrent() + 60, ^BOOL { return SGSingLoaderFastState() == SGSingFastReady; }, ^{
        SGSingLoaderSetForeground(NO);
        sg_active = NO;
        for (int i = 0; i < windows; i++) HARNESS_CHECK(window());
        ane.fails = YES;
        HARNESS_CHECK(window() == (windows == 0));
        unsigned attempts = SGSingLoaderAttempts();
        tick();
        HARNESS_CHECK(sg_neuralFailed && SGSingLoaderFastState() == SGSingFastNone);
        HARNESS_CHECK(SGSingLoaderCurrentState() == (windows ? SGSingLoaderLoading : SGSingLoaderReady));
        waitUntil(CFAbsoluteTimeGetCurrent() + 60, ^BOOL { return SGSingLoaderCurrentState() == SGSingLoaderReady; }, ^{
            SGSingLoaderSetForeground(YES);
            HARNESS_CHECK(SGSingLoaderAttempts() == attempts + (windows != 0) && window() && !SGSingLoaderSeparator().stats.fast);
            SGSingLoaderPurge(@"end tick case");
            sg_neuralFailed = nil;
            method_setImplementation(reader, original);
            imp_removeBlock(stub);
            free(silence); free(out);
            if (!windows) checkBackgroundTick(20);
            else {
                puts("PASS background tick handles probation and proven failures; foreground does not re-request ANE");
                exit(0);
            }
        });
    });
}

void HarnessSingBattery(NSSet *listeners) {
    loaded = [[HalfVocal alloc] initWithModel:nil];
    SGSetEnabled(SGKeySingSpatial, YES);
    SGSetSingLevel(0);
    SGSetSingOn(YES);
    SGSingEngine *engine = atomic_load(&sg_engine);
    SGSingTrackWatcher *watcher = [SGSingTrackWatcher new];
    SPTPlayerState *state = SGPlayerState();
    NSSet *both = [NSSet setWithArray:@[@"gestures", @"sing"]], *gestures = [NSSet setWithObject:@"gestures"];
    HARNESS_CHECK([listeners isEqual:both]);
    float l[1024], r[1024];
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 60;
    do {
        SGSingEngineRender(engine, 1024, l, r, tone, NULL);
        if (mixed(l, r)) break;
        usleep(2000); // let the real worker consume the windows as we feed them
    } while (CFAbsoluteTimeGetCurrent() < deadline);
    HARNESS_CHECK(mixed(l, r));
    double lead = SGSingHeldLead();
    HARNESS_CHECK(lead > 0.05);
    deadline = CFAbsoluteTimeGetCurrent() + 60;
    while (!atomic_load(&polls) && CFAbsoluteTimeGetCurrent() < deadline) usleep(5000);
    HARNESS_CHECK(atomic_load(&polls));
    workerParked = dispatch_semaphore_create(0);
    atomic_store(&observePark, true);
    [state setValue:@YES forKey:@"isPaused"];
    [watcher playerStateDidChange:state];
    unsigned before = atomic_load(&polls);
    HARNESS_CHECK(!dispatch_semaphore_wait(workerParked, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC)));
    HARNESS_CHECK(atomic_load(&polls) - before <= 1 && SGSingHeldLead() == lead);
    HARNESS_CHECK([listeners isEqual:gestures]);
    [state setValue:@NO forKey:@"isPaused"];
    [watcher playerStateDidChange:state];
    before = atomic_load(&polls);
    deadline = CFAbsoluteTimeGetCurrent() + 60;
    while (atomic_load(&polls) == before && CFAbsoluteTimeGetCurrent() < deadline) usleep(5000);
    HARNESS_CHECK(atomic_load(&polls) > before && SGSingHeldLead() == lead);
    SGSingEngineRender(engine, 1024, l, r, tone, NULL);
    HARNESS_CHECK(mixed(l, r));
    HARNESS_CHECK([listeners isEqual:both]);
    sg_hot = YES;
    apply();
    HARNESS_CHECK([listeners isEqual:gestures]);
    sg_hot = NO;
    apply();
    HARNESS_CHECK([listeners isEqual:both]);
    sg_elsewhere = YES;
    [watcher playerStateDidChange:state];
    HARNESS_CHECK([listeners isEqual:gestures]);
    sg_elsewhere = NO;
    [watcher playerStateDidChange:state];
    HARNESS_CHECK([listeners isEqual:both]);
    puts("PASS engaged pause parks the worker and preserves buffered output; heat and remote withdraw only Sing motion");
    // Run after launch, with main free to receive the loader's completions. Don't let the worker
    // process a window at the same time as the test, which drives the separator directly.
    [state setValue:@YES forKey:@"isPaused"];
    [watcher playerStateDidChange:state];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) {
            // Let Sing's foreground observer apply the simulator's CPU-only capability first.
            dispatch_async(dispatch_get_main_queue(), ^{ checkBackgroundTick(0); });
        }];
}
