// Core Haptics stood in for, since the simulator has no Taptic Engine: the classes MusicHaptics.x uses, which
// record what it schedules instead of playing it. The harness links this rather than CoreHaptics.framework.
#import <CoreHaptics/CoreHaptics.h>
#import <QuartzCore/QuartzCore.h>
#import <os/lock.h>
#import "fakehaptics.h"
#import "Core/SGLog.h"

// Only what MusicHaptics.x calls is stood in for.
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"

CHHapticEventParameterID CHHapticEventParameterIDHapticIntensity = @"HapticIntensity";
CHHapticEventParameterID CHHapticEventParameterIDHapticSharpness = @"HapticSharpness";
CHHapticDynamicParameterID CHHapticDynamicParameterIDHapticIntensityControl = @"HapticIntensityControl";
CHHapticDynamicParameterID CHHapticDynamicParameterIDHapticSharpnessControl = @"HapticSharpnessControl";
CHHapticEventType CHHapticEventTypeHapticTransient = @"HapticTransient";
CHHapticEventType CHHapticEventTypeHapticContinuous = @"HapticContinuous";

static os_unfair_lock sg_lock = OS_UNFAIR_LOCK_INIT;
static FakeHaptics sg_counts;
static BOOL sg_running, sg_recovery;
static unsigned sg_epoch, sg_faults, sg_deadCalls, sg_stalePlayers;
static BOOL sg_recovered;
static unsigned sg_starts, sg_startBaseline, sg_operationCalls, sg_repeatedFailures;
static BOOL sg_operation, sg_operationFailed, sg_repeat;
static uint64_t sg_logBaseline;
static BOOL sg_deferStop, sg_stopPending, sg_asyncScenario, sg_asyncResumed;
static unsigned sg_startsDuringStop, sg_playsDuringStop, sg_startsBeforeLateHandler;
static CHHapticCompletionHandler sg_pendingCompletion;
static CHHapticEngine *sg_pendingEngine, *sg_stoppedEngine;
static void (^sg_stopRequested)(void);
static BOOL sg_teardownCase, sg_teardownFaulted, sg_stopFailureDelivered, sg_teardownStopped, sg_teardownResumed;
static unsigned sg_teardownAttempts, sg_pendingRumbleCalls;

void FakeHapticsBeginTeardownFailure(void) {
    os_unfair_lock_lock(&sg_lock);
    sg_teardownCase = YES;
    sg_teardownFaulted = sg_stopFailureDelivered = sg_teardownStopped = sg_teardownResumed = NO;
    sg_teardownAttempts = sg_pendingRumbleCalls = 0;
    os_unfair_lock_unlock(&sg_lock);
}

BOOL FakeHapticsTeardownRecovered(void) {
    os_unfair_lock_lock(&sg_lock);
    BOOL ok = sg_stopFailureDelivered && sg_teardownStopped && sg_teardownResumed && sg_pendingRumbleCalls == 0;
    NSLog(@"[harness] failed teardown: error delivered %d, %u stop attempts, stopped %d, resumed %d, %u pending rumble calls",
          sg_stopFailureDelivered, sg_teardownAttempts, sg_teardownStopped, sg_teardownResumed, sg_pendingRumbleCalls);
    sg_teardownCase = NO;
    os_unfair_lock_unlock(&sg_lock);
    return ok;
}

static BOOL failRumbleTeardown(NSError **outError) {
    os_unfair_lock_lock(&sg_lock);
    BOOL fail = sg_teardownCase && sg_teardownFaulted && !sg_teardownStopped;
    if (fail && sg_stopFailureDelivered) sg_pendingRumbleCalls++;
    os_unfair_lock_unlock(&sg_lock);
    if (fail && outError) *outError = [NSError errorWithDomain:@"FakeTeardown" code:CHHapticErrorCodeResourceNotAvailable userInfo:nil];
    return fail;
}

void FakeHapticsBeginOperationFailure(void) {
    os_unfair_lock_lock(&sg_lock);
    sg_operation = YES;
    sg_operationFailed = NO;
    sg_operationCalls = 0;
    sg_startBaseline = sg_starts;
    os_unfair_lock_unlock(&sg_lock);
}

BOOL FakeHapticsOperationRecovered(void) {
    os_unfair_lock_lock(&sg_lock);
    BOOL ok = sg_operationFailed && sg_running && !sg_counts.rumbling &&
              sg_starts == sg_startBaseline && sg_operationCalls == 0;
    NSLog(@"[harness] operation failure: injected %d, running %d, rumbling %d, restarts %u, playback calls %u",
          sg_operationFailed, sg_running, sg_counts.rumbling, sg_starts - sg_startBaseline, sg_operationCalls);
    sg_operation = NO;
    os_unfair_lock_unlock(&sg_lock);
    return ok;
}

void FakeHapticsBeginRepeatedFailures(void) {
    os_unfair_lock_lock(&sg_lock);
    sg_repeat = YES;
    sg_repeatedFailures = 0;
    sg_startBaseline = sg_starts;
    sg_logBaseline = SGLogLastSeq();
    os_unfair_lock_unlock(&sg_lock);
}

BOOL FakeHapticsEndRepeatedFailures(void) {
    os_unfair_lock_lock(&sg_lock);
    sg_repeat = NO;
    unsigned starts = sg_starts - sg_startBaseline, failures = sg_repeatedFailures;
    os_unfair_lock_unlock(&sg_lock);
    unsigned logs = 0;
    for (NSDictionary *entry in SGLogRecent(sg_logBaseline)) {
        if ([entry[@"text"] hasPrefix:@"music haptics:"] && [entry[@"text"] containsString:@"FakeRepeated"]) logs++;
    }
    NSLog(@"[harness] repeated failures over 5s: %u failures, %u restarts, %u error logs", failures, starts, logs);
    return failures >= 2 && starts <= 3 && logs == 1;
}

void FakeHapticsDeferStop(void (^requested)(void)) {
    os_unfair_lock_lock(&sg_lock);
    sg_deferStop = sg_asyncScenario = YES;
    sg_asyncResumed = NO;
    sg_startsDuringStop = sg_playsDuringStop = 0;
    sg_stopRequested = [requested copy];
    os_unfair_lock_unlock(&sg_lock);
}

BOOL FakeHapticsCompleteStop(void) {
    os_unfair_lock_lock(&sg_lock);
    BOOL ok = sg_stopPending && sg_startsDuringStop == 0 && sg_playsDuringStop == 0;
    NSLog(@"[harness] deferred stop: pending %d, %u premature starts, %u playback calls",
          sg_stopPending, sg_startsDuringStop, sg_playsDuringStop);
    CHHapticCompletionHandler completion = sg_pendingCompletion;
    sg_stoppedEngine = sg_pendingEngine;
    sg_pendingEngine = nil;
    sg_pendingCompletion = nil;
    sg_deferStop = sg_stopPending = NO;
    sg_running = NO;
    sg_counts.rumbling = NO;
    sg_epoch++;
    os_unfair_lock_unlock(&sg_lock);
    if (completion) completion(nil);
    return ok;
}

void FakeHapticsDeliverStoppedHandler(void) {
    os_unfair_lock_lock(&sg_lock);
    CHHapticEngine *engine = sg_stoppedEngine;
    sg_stoppedEngine = nil;
    sg_startsBeforeLateHandler = sg_starts;
    os_unfair_lock_unlock(&sg_lock);
    if (engine.stoppedHandler) engine.stoppedHandler(CHHapticEngineStoppedReasonAudioSessionInterrupt);
}

BOOL FakeHapticsAsyncStopRecovered(void) {
    os_unfair_lock_lock(&sg_lock);
    BOOL ok = sg_asyncResumed && sg_running && sg_starts == sg_startsBeforeLateHandler;
    NSLog(@"[harness] deferred callback: resumed %d, running %d, %u redundant restarts",
          sg_asyncResumed, sg_running, sg_starts - sg_startsBeforeLateHandler);
    sg_asyncScenario = NO;
    os_unfair_lock_unlock(&sg_lock);
    return ok;
}

void FakeHapticsBeginRecovery(void) {
    os_unfair_lock_lock(&sg_lock);
    sg_recovery = YES;
    sg_faults = sg_deadCalls = sg_stalePlayers = 0;
    sg_recovered = NO;
    os_unfair_lock_unlock(&sg_lock);
}

BOOL FakeHapticsRecovered(void) {
    os_unfair_lock_lock(&sg_lock);
    BOOL ok = sg_faults == 3 && sg_recovered && !sg_deadCalls && !sg_stalePlayers;
    NSLog(@"[harness] recovery: %u faults, resumed %d, %u calls into stopped engine, %u stale players",
          sg_faults, sg_recovered, sg_deadCalls, sg_stalePlayers);
    sg_recovery = NO;
    os_unfair_lock_unlock(&sg_lock);
    return ok;
}

FakeHaptics FakeHapticsTake(void) {
    os_unfair_lock_lock(&sg_lock);
    FakeHaptics counts = sg_counts;
    counts.running = sg_running;
    sg_counts = (FakeHaptics){0};
    sg_counts.rumbling = counts.rumbling;
    os_unfair_lock_unlock(&sg_lock);
    return counts;
}

static void record(void (^change)(FakeHaptics *counts)) {
    os_unfair_lock_lock(&sg_lock);
    change(&sg_counts);
    os_unfair_lock_unlock(&sg_lock);
}

// An event's parameters or a player's dynamic ones: both classes answer parameterID and value.
static float valueOf(NSArray *parameters, NSString *identifier) {
    for (CHHapticEventParameter *parameter in parameters) {
        if ([parameter.parameterID isEqualToString:identifier]) return parameter.value;
    }
    return -1;
}

@interface FakeCapability : NSObject <CHHapticDeviceCapability> @end
@implementation FakeCapability
- (BOOL)supportsHaptics { return YES; }
- (BOOL)supportsAudio { return NO; }
- (id<CHHapticParameterAttributes>)attributesForEventParameter:(CHHapticEventParameterID)p eventType:(CHHapticEventType)t error:(NSError **)e { return nil; }
- (id<CHHapticParameterAttributes>)attributesForDynamicParameter:(CHHapticDynamicParameterID)p error:(NSError **)e { return nil; }
@end

@implementation CHHapticEventParameter
- (instancetype)initWithParameterID:(CHHapticEventParameterID)parameterID value:(float)value { if ((self = [super init])) { _parameterID = parameterID; _value = value; } return self; }
@end
@implementation CHHapticDynamicParameter
- (instancetype)initWithParameterID:(CHHapticDynamicParameterID)parameterID value:(float)value relativeTime:(NSTimeInterval)time { if ((self = [super init])) { _parameterID = parameterID; _value = value; _relativeTime = time; } return self; }
@end
@implementation CHHapticEvent
- (instancetype)initWithEventType:(CHHapticEventType)type parameters:(NSArray *)parameters relativeTime:(NSTimeInterval)time { if ((self = [super init])) { _type = type; _eventParameters = parameters; _relativeTime = time; } return self; }
- (instancetype)initWithEventType:(CHHapticEventType)type parameters:(NSArray *)parameters relativeTime:(NSTimeInterval)time duration:(NSTimeInterval)duration { if ((self = [self initWithEventType:type parameters:parameters relativeTime:time])) { _duration = duration; } return self; }
@end
@interface CHHapticPattern ()
@property NSArray<CHHapticEvent *> *fakeEvents;
@end
@implementation CHHapticPattern
- (instancetype)initWithEvents:(NSArray<CHHapticEvent *> *)events parameters:(NSArray *)parameters error:(NSError **)error { if ((self = [super init])) { _fakeEvents = events; } return self; }
@end

@interface FakePlayer : NSObject <CHHapticAdvancedPatternPlayer>
@property CHHapticPattern *pattern;
@property CHHapticEngine *engine;
@property unsigned epoch;
@end

@implementation CHHapticEngine
@synthesize stoppedHandler = _stoppedHandler, resetHandler = _resetHandler, playsHapticsOnly = _playsHapticsOnly, autoShutdownEnabled = _autoShutdownEnabled;
+ (id<CHHapticDeviceCapability>)capabilitiesForHardware { return [FakeCapability new]; }
- (instancetype)initAndReturnError:(NSError **)error { return [super init]; }
- (instancetype)initWithAudioSession:(AVAudioSession *)audioSession error:(NSError **)error { return [super init]; }
- (NSTimeInterval)currentTime { return CACurrentMediaTime(); }
- (BOOL)startAndReturnError:(NSError **)outError {
    os_unfair_lock_lock(&sg_lock);
    sg_starts++;
    if (sg_asyncScenario && sg_stopPending) sg_startsDuringStop++;
    sg_running = YES;
    os_unfair_lock_unlock(&sg_lock);
    return YES;
}
- (void)stopWithCompletionHandler:(CHHapticCompletionHandler)handler {
    os_unfair_lock_lock(&sg_lock);
    BOOL failStop = sg_teardownCase && sg_teardownAttempts++ == 0;
    if (sg_deferStop) {
        sg_stopPending = YES;
        sg_pendingCompletion = [handler copy];
        sg_pendingEngine = self;
        void (^requested)(void) = sg_stopRequested;
        sg_stopRequested = nil;
        os_unfair_lock_unlock(&sg_lock);
        if (requested) dispatch_async(dispatch_get_main_queue(), requested);
        return;
    }
    os_unfair_lock_unlock(&sg_lock);
    dispatch_async(dispatch_get_main_queue(), ^{
        os_unfair_lock_lock(&sg_lock);
        if (failStop) {
            sg_stopFailureDelivered = YES;
            os_unfair_lock_unlock(&sg_lock);
            if (handler) handler([NSError errorWithDomain:@"FakeTeardown" code:CHHapticErrorCodeResourceNotAvailable userInfo:nil]);
            return;
        }
        if (sg_teardownCase) sg_teardownStopped = YES;
        sg_running = NO;
        sg_counts.rumbling = NO;
        sg_epoch++;
        os_unfair_lock_unlock(&sg_lock);
        if (handler) handler(nil);
        if (self.stoppedHandler) self.stoppedHandler(CHHapticEngineStoppedReasonAudioSessionInterrupt);
    });
}
- (id<CHHapticPatternPlayer>)createPlayerWithPattern:(CHHapticPattern *)pattern error:(NSError **)outError {
    FakePlayer *p = [FakePlayer new];
    p.pattern = pattern;
    p.engine = self;
    os_unfair_lock_lock(&sg_lock);
    p.epoch = sg_epoch;
    os_unfair_lock_unlock(&sg_lock);
    return p;
}
- (id<CHHapticAdvancedPatternPlayer>)createAdvancedPlayerWithPattern:(CHHapticPattern *)pattern error:(NSError **)outError {
    return (id<CHHapticAdvancedPatternPlayer>)[self createPlayerWithPattern:pattern error:outError];
}
@end

@implementation FakePlayer
@synthesize loopEnabled, loopEnd, playbackRate, isMuted, completionHandler;
- (BOOL)failPlayback:(NSError **)outError {
    os_unfair_lock_lock(&sg_lock);
    if (sg_operation && sg_operationFailed) sg_operationCalls++;
    if (sg_asyncScenario && sg_stopPending) sg_playsDuringStop++;
    BOOL operation = sg_operation && !sg_operationFailed && sg_counts.rumbling;
    BOOL repeated = sg_repeat;
    BOOL teardown = sg_teardownCase && !sg_teardownFaulted && sg_counts.rumbling;
    if (teardown) sg_teardownFaulted = YES;
    if (operation) sg_operationFailed = YES;
    if (repeated) {
        sg_repeatedFailures++;
        sg_running = NO;
        sg_counts.rumbling = NO;
        sg_epoch++;
    }
    os_unfair_lock_unlock(&sg_lock);
    if (!operation && !repeated && !teardown) return NO;
    if (outError) *outError = [NSError errorWithDomain:repeated ? @"FakeRepeated" : @"FakeOperation"
        code:repeated ? CHHapticErrorCodeEngineNotRunning : CHHapticErrorCodeResourceNotAvailable userInfo:nil];
    return YES;
}
- (BOOL)ready:(NSError **)outError {
    os_unfair_lock_lock(&sg_lock);
    BOOL running = sg_running, current = self.epoch == sg_epoch;
    if (sg_recovery) {
        if (!running) sg_deadCalls++;
        else if (!current) sg_stalePlayers++;
    }
    os_unfair_lock_unlock(&sg_lock);
    if (running && current) return YES;
    if (outError) *outError = [NSError errorWithDomain:@"FakeHaptics" code:CHHapticErrorCodeEngineNotRunning userInfo:nil];
    return NO;
}
- (BOOL)startAtTime:(NSTimeInterval)time error:(NSError **)outError {
    if ([self failPlayback:outError]) return NO;
    if (![self ready:outError]) return NO;
    os_unfair_lock_lock(&sg_lock);
    if (sg_asyncScenario && !sg_deferStop && !sg_stopPending) sg_asyncResumed = YES;
    if (sg_teardownCase && sg_teardownStopped) sg_teardownResumed = YES;
    os_unfair_lock_unlock(&sg_lock);
    CHHapticEvent *event = self.pattern.fakeEvents.firstObject;
    if ([event.type isEqualToString:CHHapticEventTypeHapticTransient]) {
        float intensity = valueOf(event.eventParameters, CHHapticEventParameterIDHapticIntensity);
        float sharpness = valueOf(event.eventParameters, CHHapticEventParameterIDHapticSharpness);
        record(^(FakeHaptics *counts) {
            // The analyzer's kicks are 0.15 to 0.45 sharp, its snares 0.55 to 0.95.
            if (sharpness < 0.5f) counts->kicks++;
            else counts->snares++;
            counts->tapIntensity += intensity;
        });
    } else {
        record(^(FakeHaptics *counts) {
            counts->rumbleStarts++;
            counts->rumbling = YES;
        });
    }
    return YES;
}
- (BOOL)stopAtTime:(NSTimeInterval)time error:(NSError **)outError {
    if (failRumbleTeardown(outError)) return NO;
    if (![self ready:outError]) return NO;
    record(^(FakeHaptics *counts) {
        counts->rumbleStops++;
        counts->rumbling = NO;
    });
    return YES;
}
- (BOOL)sendParameters:(NSArray *)parameters atTime:(NSTimeInterval)time error:(NSError **)outError {
    if ([self failPlayback:outError]) return NO;
    if (![self ready:outError]) return NO;
    os_unfair_lock_lock(&sg_lock);
    unsigned fault = 0;
    if (sg_recovery && sg_faults < 3) {
        fault = ++sg_faults;
        sg_running = NO;
        sg_epoch++;
        sg_counts.rumbling = NO;
    } else if (sg_recovery) {
        sg_recovered = YES;
    }
    os_unfair_lock_unlock(&sg_lock);
    if (fault == 1) {
        if (outError) *outError = [NSError errorWithDomain:@"FakeHaptics" code:CHHapticErrorCodeServerInterrupted userInfo:nil];
        return NO;
    }
    if (fault == 2) self.engine.stoppedHandler(CHHapticEngineStoppedReasonAudioSessionInterrupt);
    if (fault == 3) self.engine.resetHandler();
    if (fault) return YES;
    float level = valueOf(parameters, CHHapticDynamicParameterIDHapticIntensityControl);
    record(^(FakeHaptics *counts) {
        counts->levels++;
        counts->levelSum += level;
        counts->levelMax = MAX(counts->levelMax, level);
    });
    return YES;
}
- (BOOL)scheduleParameterCurve:(CHHapticParameterCurve *)parameterCurve atTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)cancelAndReturnError:(NSError **)outError {
    if (failRumbleTeardown(outError)) return NO;
    if (![self ready:outError]) return NO;
    if ([self.pattern.fakeEvents.firstObject.type isEqualToString:CHHapticEventTypeHapticContinuous]) {
        record(^(FakeHaptics *counts) { counts->rumbling = NO; });
    }
    return YES;
}
- (BOOL)pauseAtTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)resumeAtTime:(NSTimeInterval)time error:(NSError **)outError { return YES; }
- (BOOL)seekToOffset:(NSTimeInterval)offsetTime error:(NSError **)outError { return YES; }
@end
