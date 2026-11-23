// Audio effects on Spotify's sound (AudioEffects.h): every buffer Spotify's output unit finishes runs
// through SGDSPEngine before it reaches the speaker.
//
// Spotify plays through Core Audio units of its own (AudioUnitDriver2 in the binary: converter, EQ, mixer
// and a RemoteIO output unit, started with AudioOutputUnitStart), with no Objective-C method between it and
// the unit, and it can run two such chains at once, one per sample rate. Shared/Player keeps them apart and
// names the music's output (SGPlayerMusicOutput); that one gets a render notify. After each render the notify
// reads the buffer bound for the speaker into float lanes, runs the engine over them and writes them back, in
// place: the way the first version of Pitch worked on the phone. A notify stays on a unit that was the music's
// once and does nothing there, so one engine never runs on two render threads. Speed and pitch feeds the
// unit's input, so its sound reaches the notify changed. After the engine, with the switch on or off, the notify
// hands the music's buffer mixed to mono to one reader (SGAudioSetOutputReader), the player's Visualizer, which
// only reads it.
//
// The engine is made the first time the output starts with the master switch on, at the output's rate,
// and lives as long as Spotify: the render thread may be holding it at any time. With the switch off the
// notify returns straight away, and Spotify's sound is untouched. Silence goes through the engine too, so a
// reverb or a convolver rings out after a track stops.
//
// Settings apply as they change: SGDSPApply marks the effect, and a serial queue reads its keys a moment
// later and sets them, so a slider dragged across comes down to the last few values. The queue also makes
// the engine, follows the output to a new sample rate, and once a second frees what the effects replaced.
//
// Threading: the notify runs on the render thread and touches only atomics, its scratch lanes and the
// engine's render side. Spotify starts its output on a thread of its own. The effects are set on the queue;
// SGDSPApply and the curves are main thread; SGDSPStatus and SGDSPError any thread.
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <os/lock.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Core/SGLocalize.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SGPCMRead.h"
#import "Shared/Player/SGAudioFormat.h"
#import "AudioEffects.h"
#import "AudioEffectsApply.h"
#import "AudioEffectsPresets.h"
#import "SGDSPEngine.h"

// A burst of changes to a setting is gathered this long before it applies.
static const double kApplyAfter = 0.03;
// How often a summary of the engine's work goes to the log while it runs.
static const double kSummaryEvery = 60;

enum { kScratchFrames = 4096 };

#pragma mark - shared between the threads

typedef enum { SGOutputUnseen, SGOutputPCM, SGOutputUnsupported } SGOutputState;

static _Atomic(SGDSPEngine *) sg_engine;       // made once on the queue, never freed
static atomic_bool sg_running;                 // the switch on and the engine set up for the output
static atomic_int sg_outputState;
static BOOL sg_reachable;                      // Shared/Player reaches Spotify's output
// The format of the buffers the notify gets: the rate, and the layout packed into one word so the render
// thread never reads half of a change (flags in the low 32 bits, then channels, then bytes per sample).
static atomic_uint_fast64_t sg_rateBits;
static atomic_uint_fast64_t sg_layout;

static os_unfair_lock sg_errorLock = OS_UNFAIR_LOCK_INIT;
static NSMutableDictionary<NSString *, NSString *> *sg_errors;

static void storeDouble(atomic_uint_fast64_t *slot, double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    atomic_store(slot, bits);
}

static double loadDouble(atomic_uint_fast64_t *slot) {
    uint64_t bits = atomic_load_explicit(slot, memory_order_relaxed);
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

#pragma mark - the render thread

#pragma mark - the output's sound, read (AudioEffects.h)

static _Atomic(SGAudioOutputReader) sg_reader;
static float sg_mono[kScratchFrames];

void SGAudioSetOutputReader(SGAudioOutputReader reader) {
    atomic_store_explicit(&sg_reader, reader, memory_order_release);
}

// The buffer, as the effects left it, mixed to mono for the reader: its first two channels, or its one.
static void readOut(SGAudioOutputReader reader, AudioUnitRenderActionFlags flags, UInt32 frames, const AudioBufferList *data) {
    uint64_t layout = atomic_load_explicit(&sg_layout, memory_order_relaxed);
    UInt32 formatFlags = (UInt32)layout, channels = (UInt32)(layout >> 32) & 0xffff, bytes = (UInt32)(layout >> 48);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0, split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if ((bytes != 2 && bytes != 4) || channels < 1 || !SGPCMLayoutFits(data, frames, channels, bytes, split)) return;
    BOOL silent = (flags & kAudioUnitRenderAction_OutputIsSilence) != 0;
    double rate = loadDouble(&sg_rateBits);
    const void *first = data->mBuffers[0].mData, *second = split && channels > 1 ? data->mBuffers[1].mData : first;
    UInt32 stride = split ? 1 : channels, secondOffset = !split && channels > 1 ? 1 : 0;
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(frames - done, (UInt32)kScratchFrames);
        for (UInt32 i = 0; i < count; i++) {
            UInt32 at = (done + i) * stride;
            sg_mono[i] = silent ? 0 : 0.5f * (SGPCMReadSample(first, at, bytes, isFloat, fraction) + SGPCMReadSample(second, at + secondOffset, bytes, isFloat, fraction));
        }
        reader(sg_mono, count, rate);
        done += count;
    }
}

// Shared/Player admits these callbacks, with its always-run per-output control
// between the effects and the reader. Refusal bypasses effects, never attenuation.
static BOOL renderEffects(float *left, float *right, UInt32 frames, double rate) {
    if (atomic_load_explicit(&sg_running, memory_order_acquire)) {
        SGDSPEngine *engine = atomic_load_explicit(&sg_engine, memory_order_acquire);
        // A new rate is being set up on the queue: until then the sound passes as it is.
        if (engine && SGDSPEngineSampleRate(engine) == rate) {
            SGDSPEngineProcessEffects(engine, left, right, frames);
            return YES;
        }
    }
    return NO;
}

static void readOutput(AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *data) {
    SGAudioOutputReader reader = atomic_load_explicit(&sg_reader, memory_order_acquire);
    if (reader) readOut(reader, *flags, frames, data);
}

#pragma mark - Spotify's audio thread

// The format the notify's buffers are in, which is the RemoteIO unit's output side (element 0, output scope):
// the hardware's, not the one Spotify hands the unit (the input scope). In the simulator a 44.1 kHz client
// comes out at 48 kHz, and a 16-bit interleaved one as float, a buffer per channel (harness/audio-effects/sim).
// Answers whether the engine can take it.
static BOOL readFormat(AudioUnit unit) {
    AudioStreamBasicDescription format = {0}, client = {0};
    UInt32 size = sizeof format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, &size);
    size = sizeof client;
    AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &client, &size);
    UInt32 bytes = format.mBitsPerChannel / 8;
    BOOL takes = status == noErr && format.mFormatID == kAudioFormatLinearPCM && format.mSampleRate > 0 && format.mChannelsPerFrame >= 1
                 && (bytes == 2 || bytes == 4) && ((format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsSignedInteger));
    // Spotify starts its output again after every pause; the format is logged when it is not the last one.
    // Spotify's thread and a format change's may both be here.
    static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
    static NSString *logged;
    NSString *text = [NSString stringWithFormat:@"dsp: Spotify's output renders %@, from %@ Spotify hands it%@", SGAudioFormatText(format),
                      SGAudioFormatText(client), takes ? @"" : [NSString stringWithFormat:@"; not a format the engine takes (status %d), its sound passes as it is", (int)status]];
    os_unfair_lock_lock(&lock);
    BOOL changed = ![text isEqualToString:logged];
    logged = text;
    os_unfair_lock_unlock(&lock);
    if (changed) SGLog(@"%@", text);
    if (!takes) {
        atomic_store(&sg_layout, 0);
        atomic_store(&sg_outputState, SGOutputUnsupported);
        return NO;
    }
    storeDouble(&sg_rateBits, format.mSampleRate);
    atomic_store(&sg_layout, (uint64_t)format.mFormatFlags | (uint64_t)(format.mChannelsPerFrame & 0xffff) << 32 | (uint64_t)bytes << 48);
    atomic_store(&sg_outputState, SGOutputPCM);
    // The engine is made, or follows a new rate, when the switch is on.
    dispatch_async(dispatch_get_main_queue(), ^{
        SGDSPApply(SGKeyDSP);
    });
    return YES;
}

// The music's output started, changed or changed format (Shared/Player): its format read, the notify on it.
static void listenTo(AudioUnit unit) {
    if (!unit || !SGPlayerMusicOutputRunning()) {
        dispatch_async(dispatch_get_main_queue(), ^{ SGDSPApply(SGKeyDSP); });
        return;
    }
    if (!readFormat(unit)) return;
    // The sound held from before the output stopped, or from another output, would play first; the stream
    // starts over instead.
    SGDSPEngine *engine = atomic_load(&sg_engine);
    if (engine) SGDSPEngineRestart(engine);
}

#pragma mark - errors

// An effect's name in the log, by its switch key.
static NSString *effectName(NSString *effect) {
    NSDictionary<NSString *, NSString *> *names = @{
        SGKeyDSPCompander: @"compander", SGKeyDSPBass: @"bass boost", SGKeyDSPEqualizer: @"equalizer", SGKeyDSPGraphicEq: @"graphic EQ",
        SGKeyDSPConvolver: @"convolver", SGKeyDSPDDC: @"DDC", SGKeyDSPLiveprog: @"Liveprog", SGKeyDSPReverb: @"reverb",
        SGKeyDSPStereoWide: @"stereo widening", SGKeyDSPCrossfeed: @"crossfeed", SGKeyDSPTube: @"analog modeling",
    };
    return names[effect] ?: effect;
}

static NSString *liveprogRunawayMessage(void) {
    return SGL(@"settings.audioeffects.liveprog.runaway", @"This script took too long and was turned off.");
}

static void setError(NSString *effect, NSString *message) {
    if ([effect isEqualToString:SGKeyDSPLiveprog] &&
        [message isEqualToString:@"This script took too long to start."]) {
        message = SGL(@"settings.audioeffects.liveprog.starttimeout", @"This script took too long to start.");
    }
    if ([effect isEqualToString:SGKeyDSPLiveprog] &&
        [message isEqualToString:@"This script took too long and was turned off."]) message = liveprogRunawayMessage();
    os_unfair_lock_lock(&sg_errorLock);
    if (!sg_errors) sg_errors = [NSMutableDictionary dictionary];
    sg_errors[effect] = message;
    os_unfair_lock_unlock(&sg_errorLock);
    if (message) SGLog(@"dsp: %@ did not take: %@", effectName(effect), message);
}

NSString *SGDSPError(NSString *switchKey) {
    if (!switchKey) return nil;
    os_unfair_lock_lock(&sg_errorLock);
    NSString *message = sg_errors[switchKey];
    os_unfair_lock_unlock(&sg_errorLock);
    // Error readers are off the render thread. The engine only publishes an
    // atomic trip there; its config timer collects the bypassed VM as usual.
    // A failed load takes precedence over the previous VM's retained trip.
    if (!message && [switchKey isEqualToString:SGKeyDSPLiveprog]) {
        SGDSPEngine *engine = atomic_load_explicit(&sg_engine, memory_order_acquire);
        if (SGDSPEngineLiveprogError(engine)) return liveprogRunawayMessage();
    }
    return message;
}

#pragma mark - the queue: setting the effects

static NSString *onOff(BOOL on) {
    return on ? @"on" : @"off";
}

static NSString *gainsText(NSArray<NSNumber *> *gains) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:gains.count];
    for (NSNumber *gain in gains) [parts addObject:[NSString stringWithFormat:@"%g", gain.doubleValue]];
    return [parts componentsJoinedByString:@" "];
}

static NSString *choice(NSArray<NSString *> *names, NSString *key) {
    NSInteger index = (NSInteger)SGDSPNumber(key);
    return index >= 0 && index < (NSInteger)names.count ? names[index] : @(index).stringValue;
}

// A file effect's file, from its library by name: its path, nil and an error when there is none to read.
static NSString *libraryFile(SGDSPFileKind kind, NSString *effect, BOOL on) {
    NSString *name = SGDSPString(SGDSPFileKey(kind));
    if (!on) return nil;
    if (!name.length) {
        setError(effect, @"No file is chosen");
        return nil;
    }
    NSString *path = [SGDSPLibraryDirectory(kind) stringByAppendingPathComponent:name.lastPathComponent];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        setError(effect, [NSString stringWithFormat:@"%@ is not in the library any more", name]);
        return nil;
    }
    return path;
}

// A text file with a NUL after it, for the parsers.
static NSData *textFile(NSString *path) {
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path];
    [data appendBytes:"" length:1];
    return data;
}

static void applyOutput(SGDSPEngine *engine) {
    double gain = SGDSPNumber(SGKeyDSPPostGain), threshold = SGDSPNumber(SGKeyDSPLimiterThreshold), release = SGDSPNumber(SGKeyDSPLimiterRelease);
    SGPlayerSetOutputControl(SGDSPSwitch(SGKeyDSP), gain, threshold, release);
    // Set again on every start of Spotify's output; logged when it changed.
    static NSString *logged;
    NSString *text = [NSString stringWithFormat:@"dsp: output gain %+.1f dB, limiter at %.1f dB releasing in %.1f ms", gain, threshold, release];
    if (![text isEqualToString:logged]) SGLog(@"%@", text);
    logged = text;
}

static void applyEffect(SGDSPEngine *engine, NSString *effect) {
    BOOL on = SGDSPSwitch(effect);
    char error[300] = "";
    BOOL ok = YES;
    NSString *what = @"";
    if ([effect isEqualToString:SGKeyDSPCompander]) {
        NSArray<NSNumber *> *gains = SGDSPGains(SGKeyDSPCompanderGains);
        double values[7];
        for (int i = 0; i < 7; i++) values[i] = gains[i].doubleValue;
        double time = SGDSPNumber(SGKeyDSPCompanderTime);
        SGDSPEngineSetCompander(engine, on, time, SGDSPCompanderFrequencies, values);
        what = [NSString stringWithFormat:@"compander %@, %.2f s, amounts %@", onOff(on), time, gainsText(gains)];
    } else if ([effect isEqualToString:SGKeyDSPBass]) {
        double gain = SGDSPNumber(SGKeyDSPBassGain);
        SGDSPEngineSetBassBoost(engine, on, gain);
        what = [NSString stringWithFormat:@"bass boost %@, %.1f dB", onOff(on), gain];
    } else if ([effect isEqualToString:SGKeyDSPEqualizer]) {
        NSArray<NSNumber *> *gains = SGDSPGains(SGKeyDSPEqualizerGains);
        double values[15];
        for (int i = 0; i < 15; i++) values[i] = gains[i].doubleValue;
        SGDSPEngineSetEqualizer(engine, on, SGDSPEqualizerFrequencies, values);
        what = [NSString stringWithFormat:@"equalizer %@, gains %@", onOff(on), gainsText(gains)];
    } else if ([effect isEqualToString:SGKeyDSPGraphicEq]) {
        NSString *nodes = SGDSPString(SGKeyDSPGraphicEqNodes);
        ok = SGDSPEngineSetGraphicEq(engine, on, nodes.UTF8String, error, sizeof error);
        NSUInteger count = [nodes componentsSeparatedByString:@";"].count;
        what = [NSString stringWithFormat:@"Graphic EQ %@, about %lu points", onOff(on), (unsigned long)(count > 1 ? count - 1 : count)];
    } else if ([effect isEqualToString:SGKeyDSPConvolver]) {
        NSString *path = libraryFile(SGDSPFileImpulseResponse, effect, on);
        if (on && !path) {
            SGDSPEngineSetConvolver(engine, false, NULL, 0, error, sizeof error);
            return;
        }
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        ok = SGDSPEngineSetConvolver(engine, on, path.fileSystemRepresentation, (int)SGDSPNumber(SGKeyDSPConvolverMode), error, sizeof error);
        what = [NSString stringWithFormat:@"convolver %@%@%@", onOff(on), on ? @", " : @"", on ? [NSString stringWithFormat:@"%@ (%@) read in %.0f ms",
                path.lastPathComponent, choice(SGDSPConvolverModeNames(), SGKeyDSPConvolverMode), (CFAbsoluteTimeGetCurrent() - start) * 1000] : @""];
    } else if ([effect isEqualToString:SGKeyDSPDDC]) {
        NSString *path = libraryFile(SGDSPFileDDC, effect, on);
        if (on && !path) {
            SGDSPEngineSetDDC(engine, false, NULL, error, sizeof error);
            return;
        }
        NSData *text = on ? textFile(path) : nil;
        ok = SGDSPEngineSetDDC(engine, on, text.bytes, error, sizeof error);
        what = [NSString stringWithFormat:@"DDC %@%@%@", onOff(on), on ? @", " : @"", on ? path.lastPathComponent : @""];
    } else if ([effect isEqualToString:SGKeyDSPLiveprog]) {
        NSString *path = libraryFile(SGDSPFileLiveprog, effect, on);
        if (on && !path) {
            SGDSPEngineSetLiveprog(engine, false, NULL, error, sizeof error);
            return;
        }
        NSData *script = on ? textFile(path) : nil;
        CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
        ok = SGDSPEngineSetLiveprog(engine, on, script.bytes, error, sizeof error);
        what = [NSString stringWithFormat:@"Liveprog %@%@%@", onOff(on), on ? @", " : @"", on ? [NSString stringWithFormat:@"%@ compiled in %.0f ms",
                path.lastPathComponent, (CFAbsoluteTimeGetCurrent() - start) * 1000] : @""];
    } else if ([effect isEqualToString:SGKeyDSPReverb]) {
        SGDSPEngineSetReverb(engine, on, (int)SGDSPNumber(SGKeyDSPReverbPreset), (float)SGDSPNumber(SGKeyDSPReverbAmount));
        what = [NSString stringWithFormat:@"reverb %@, %@", onOff(on), choice(SGDSPReverbPresetNames(), SGKeyDSPReverbPreset)];
    } else if ([effect isEqualToString:SGKeyDSPStereoWide]) {
        double level = SGDSPNumber(SGKeyDSPStereoWideLevel);
        SGDSPEngineSetStereoWide(engine, on, level);
        what = [NSString stringWithFormat:@"stereo widening %@, %.0f%%", onOff(on), level];
    } else if ([effect isEqualToString:SGKeyDSPCrossfeed]) {
        SGDSPEngineSetCrossfeed(engine, on, (int)SGDSPNumber(SGKeyDSPCrossfeedMode));
        what = [NSString stringWithFormat:@"crossfeed %@, %@", onOff(on), choice(SGDSPCrossfeedModeNames(), SGKeyDSPCrossfeedMode)];
    } else if ([effect isEqualToString:SGKeyDSPTube]) {
        double drive = SGDSPNumber(SGKeyDSPTubeDrive);
        SGDSPEngineSetTube(engine, on, drive);
        what = [NSString stringWithFormat:@"analog modeling %@, %.1f dB", onOff(on), drive];
    } else {
        return;
    }
    setError(effect, ok ? nil : @(error));
    if (ok) SGLog(@"dsp: %@", what);
}

#pragma mark - the queue: the engine

static dispatch_queue_t applyQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("spotifyglass.dsp", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
    });
    return queue;
}

static void applyAll(SGDSPEngine *engine) {
    applyOutput(engine);
    for (NSString *effect in SGDSPEffectSwitches()) applyEffect(engine, effect);
}

// Once a second while the engine lives: what the effects replaced freed, an engine gone non-finite started
// over, and now and then a summary.
static void tend(void) {
    SGDSPEngine *engine = atomic_load(&sg_engine);
    SGDSPEngineCollect(engine);
    static uint64_t faults, blocks;
    static CFAbsoluteTime summarized;
    SGDSPEngineStats stats = SGDSPEngineReadStats(engine, true);
    if (stats.faults != faults) {
        faults = stats.faults;
        SGLog(@"dsp: the output stopped being finite (%llu blocks silenced), the engine starts over", stats.faults);
        SGDSPEngineReset(engine);
        applyAll(engine);
    }
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (stats.blocks != blocks && now - summarized >= kSummaryEvery) {
        summarized = now;
        SGLog(@"dsp: %llu blocks processed, %llu passed dry while settings changed, %.2f ms a block (%.1f%% of its time), %.2f ms at most",
              stats.blocks - blocks, stats.dry, stats.averageMS, stats.load * 100, stats.peakMS);
        blocks = stats.blocks;
    }
}

// The engine is read out once a second while it runs. With the switch off there is nothing in it to
// read, so the source is suspended rather than left ticking for the rest of the app's life: the engine
// is never freed, and a timer tied to its making would outlive every use of it. Only ever touched from
// applyMaster, which is to say on applyQueue().
static dispatch_source_t sg_tendTimer;
static BOOL sg_tending;

static void setTending(BOOL on) {
    if (!sg_tendTimer || on == sg_tending) return;
    sg_tending = on;
    if (on) dispatch_resume(sg_tendTimer);
    else dispatch_suspend(sg_tendTimer);
}

// The switch and the output's format: the engine made or moved to the output's rate, everything set when
// it was, and the notify let in or kept out. Answers whether every effect was set.
static BOOL applyMaster(void) {
    if (!SGPlayerMusicOutputRunning()) {
        setTending(NO);
        SGDSPEngine *engine = atomic_load(&sg_engine);
        if (engine) SGDSPEngineCollect(engine);
    }
    if (!SGDSPSwitch(SGKeyDSP)) {
        SGPlayerSetOutputProcessing(NULL, readOutput);
        SGPlayerSetOutputControl(NO, 0, 0, 100);
        setTending(NO);
        if (atomic_exchange(&sg_running, false)) SGLog(@"dsp: off, Spotify's sound passes as it is");
        return NO;
    }
    double rate = loadDouble(&sg_rateBits);
    if (atomic_load(&sg_outputState) != SGOutputPCM || rate <= 0) {
        SGLog(@"dsp: on, waiting for Spotify to start its output");
        return NO;
    }
    SGDSPEngine *engine = atomic_load(&sg_engine);
    BOOL everything = NO;
    if (!engine) {
        engine = SGDSPEngineCreate(rate);
        if (!engine) {
            SGLog(@"dsp: the engine could not be made at %.0f Hz", rate);
            return NO;
        }
        SGLog(@"dsp: engine made at %.0f Hz, blocks of %d frames, so the sound is %.1f ms later", rate, kSGDSPEngineBlock,
              kSGDSPEngineBlock / rate * 1000);
        atomic_store(&sg_engine, engine);
        // A source comes up suspended; setTending below is what starts it.
        sg_tendTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, applyQueue());
        dispatch_source_set_timer(sg_tendTimer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, NSEC_PER_SEC / 4);
        dispatch_source_set_event_handler(sg_tendTimer, ^{
            tend();
        });
        everything = YES;
    } else if (SGDSPEngineSampleRate(engine) != rate) {
        SGDSPEngineSetSampleRate(engine, rate);
        SGLog(@"dsp: the engine follows the output to %.0f Hz", rate);
        everything = YES;
    }
    if (everything) applyAll(engine);
    else applyOutput(engine);
    if (!atomic_load(&sg_running)) {
        SGDSPEngineRestart(engine);
        atomic_store_explicit(&sg_running, true, memory_order_release);
        SGLog(@"dsp: on");
    }
    setTending(SGPlayerMusicOutputRunning());
    SGPlayerSetOutputProcessing(renderEffects, readOutput);
    return everything;
}

static os_unfair_lock sg_pendingLock = OS_UNFAIR_LOCK_INIT;
static NSMutableOrderedSet<NSString *> *sg_pending;
static BOOL sg_drainScheduled;
static BOOL sg_liveprogUserChange;
static BOOL sg_followingRoute; // main thread: a route preset uses the same setting setters as the page

static void drain(void) {
    os_unfair_lock_lock(&sg_pendingLock);
    NSArray<NSString *> *effects = sg_pending.array;
    BOOL liveprogUserChange = sg_liveprogUserChange;
    sg_liveprogUserChange = NO;
    sg_pending = nil;
    sg_drainScheduled = NO;
    os_unfair_lock_unlock(&sg_pendingLock);
    // Consume explicit intent before a master/rate update can applyAll and return.
    // Output notifications enqueue only SGKeyDSP and never clear quarantine.
    if (liveprogUserChange) SGDSPEngineLiveprogUserChange(atomic_load(&sg_engine));
    if ([effects containsObject:SGKeyDSP] && applyMaster()) return;
    SGDSPEngine *engine = atomic_load(&sg_engine);
    // Without an engine nothing is set: it is set up with every effect when it is made.
    if (!engine) return;
    for (NSString *effect in effects) {
        if (![effect isEqualToString:SGKeyDSP]) applyEffect(engine, effect);
    }
}

void SGDSPApply(NSString *effect) {
    if (!effect) return;
    os_unfair_lock_lock(&sg_pendingLock);
    if (!sg_pending) sg_pending = [NSMutableOrderedSet orderedSet];
    [sg_pending addObject:effect];
    if ([effect isEqualToString:SGKeyDSPLiveprog] && !sg_followingRoute) sg_liveprogUserChange = YES;
    BOOL schedule = !sg_drainScheduled;
    sg_drainScheduled = YES;
    os_unfair_lock_unlock(&sg_pendingLock);
    if (schedule) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kApplyAfter * NSEC_PER_SEC)), applyQueue(), ^{
        drain();
    });
}

#pragma mark - what the page shows

NSString *SGDSPStatus(void) {
    if (!SGDSPSwitch(SGKeyDSP)) return SGL(@"common.off", @"Off");
    if (atomic_load(&sg_outputState) == SGOutputUnsupported) return SGL(@"settings.audioeffects.status.unsupported_output", @"Spotify's output is in a format the engine does not take");
    SGDSPEngine *engine = atomic_load(&sg_engine);
    if (!sg_reachable) return SGL(@"settings.audioeffects.status.unreachable", @"Unavailable: Spotify's output could not be reached");
    if (!engine || !atomic_load(&sg_running)) return SGL(@"settings.audioeffects.status.waiting_for_playback", @"Waiting for Spotify to play");
    double rate = SGDSPEngineSampleRate(engine);
    double load = SGDSPEngineReadStats(engine, false).load;
    return [NSString stringWithFormat:SGL(@"settings.audioeffects.status.running_format", @"Running at %@ kHz, %.1f%% load"), [NSString stringWithFormat:@"%g", rate / 1000], load * 100];
}

void SGDSPEqualizerResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *decibels) {
    if (count <= 0 || !frequencies || !decibels) return;
    double values[15] = {0};
    for (NSUInteger i = 0; i < 15 && i < gains.count; i++) values[i] = gains[i].doubleValue;
    SGDSPEngineEqualizerCurve(SGDSPEqualizerFrequencies, values, (int)count, frequencies, decibels);
}

void SGDSPCompanderResponse(NSArray<NSNumber *> *gains, NSInteger count, double *frequencies, double *values) {
    if (count <= 0 || !frequencies || !values) return;
    double bands[7] = {0};
    for (NSUInteger i = 0; i < 7 && i < gains.count; i++) bands[i] = gains[i].doubleValue;
    SGDSPEngineCompanderCurve(SGDSPCompanderFrequencies, bands, (int)count, frequencies, values);
}

// The output audio goes to now, for the corrections remembered per output (AutoEq.m).
static void followRoute(void) {
    AVAudioSessionPortDescription *port = AVAudioSession.sharedInstance.currentRoute.outputs.firstObject;
    if (port) {
        sg_followingRoute = YES;
        SGAutoEqOutputChanged(port.UID, port.portName);
        sg_followingRoute = NO;
    }
}

%ctor {
    SGPlayerSetOutputProcessing(NULL, readOutput);
    // Posted on the audio session's thread: handed to main without waiting, so it cannot deadlock against main.
    [NSNotificationCenter.defaultCenter addObserverForName:AVAudioSessionRouteChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) {
        dispatch_async(dispatch_get_main_queue(), ^{ followRoute(); });
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        followRoute();
    });
    sg_reachable = SGPlayerWatchMusicOutput(listenTo);
    if (!sg_reachable) {
        SGLog(@"dsp: Spotify's output cannot be reached, the effects cannot reach its sound");
        return;
    }
    SGLog(@"dsp: listening for Spotify's output unit (%@)", SGDSPSwitch(SGKeyDSP) ? @"on" : @"off");
}
