// Speed and Pitch (SpeedPitchMenu.x draws them), both done on Spotify's audio, under either look, and the
// record of Spotify's outputs that every processor of its sound follows (SpeedPitch.h).
//
// Spotify's player takes a speed only for podcasts: for songs its restrictions refuse it (device test,
// 2026-09-18: the slider read "Unavailable here"), its own music speed being a per track setting kept on
// playlist items. So speed, like pitch, is done to the sound, by SGTimePitch between Spotify's mixer and
// its speaker unit.
//
// Spotify's audio (AudioUnitDriver2 in the binary) is a chain of units it wires with MakeConnection:
// converter (fed by its decoder through a render callback), EQ, mixer, RemoteIO. Its import of
// AudioUnitSetProperty is rebound (Core/SGRebind.h), and the call connecting a mixer to a RemoteIO unit's
// input is answered by a render callback of this file's instead, which pulls the mixer itself. At normal
// speed and pitch the callback passes the mixer's sound straight through. Otherwise it renders the time and
// pitch unit, which pulls the mixer for rate times the frames it hands back, so Spotify's decoder is drained
// that much faster: the song plays faster or slower, at its own pitch unless Pitch moves it. Switching the
// unit in or out skips or repeats its 93 ms, so it stays in for a moment after both return to normal, and a
// finger dragging across normal does not switch it back and forth.
//
// Spotify keeps a chain per sample rate: a local file at another rate gets a second one, and both can be
// alive and running at once. So every RemoteIO unit has its own record (Output): the mixer and bus feeding
// it, that mixer's largest slice, a sample time of its own, and its two formats. Each unit's callback pulls
// only its own mixer; one pulling another's would drain it twice as fast, and the song would speed up. The
// processors (this file's unit, Sing's stage, the audio effects, Music Haptics) are on one output only, the
// music's: the one Spotify started or connected last, since a new chain is started for the song about to
// play. A unit Spotify never connected (one it feeds with a callback of its own, such as voice search) gets
// them only when no connected one runs. And an output that has had no sound for a second gives them up to
// a connected one that has: a chain left running and fed again without a new start (going back to a
// streamed song after a local file, or the end of a crossfade) is still found. AudioOutputUnitStop and
// AudioComponentInstanceDispose are rebound too: a stopped unit gives the processors up, and a disposed one
// is forgotten, after its render in progress is over, so nothing ever pulls a disposed mixer.
//
// The callback stands in for Spotify's connection only when it can: Spotify's side of the unit float, a
// buffer per channel, 32-bit, one or two channels, and the mixer's output the same rate, layout and
// channels. Otherwise Spotify's own connection is put back and its sound passes untouched (a mixer at
// another rate than the unit would play fast or slow through the callback, where Spotify's own connection
// refuses it). This is checked when Spotify connects, starts and changes a format, and the callback takes
// over again once the formats agree.
//
// Spotify's clock keeps running at its own speed between the player's reports: -[SPTPlayerState position]
// is positionAsOfTimestamp minus timeIntervalSinceNow times [self playbackSpeed] (disassembly,
// 0x1057735ec), so playbackSpeed is hooked to include this speed. From the moment the speed leaves 1x,
// -position counts its own clock: Spotify's position then, plus the song the mixer has handed over since
// (sg_clock). A seek, skip, stop, new track or stall (SGSpeedObserver) hands the clock back to Spotify's, and
// away from 1x takes Spotify's next report as the new start.
//
// When the music's output was never connected, pitch falls back to the way it first shipped: a render notify
// on the RemoteIO unit runs each finished buffer through a unit working in place; speed is then unavailable.
// Those buffers are in the unit's output format, the hardware's, not the one Spotify hands the unit
// (harness/audio-effects/sim), so the fallback's unit is made for that one.
//
// Speed and pitch last until Spotify quits.
//
// The music's render notify also scales each finished buffer by the gain SGPlayerSetGain asks for (the sleep
// timer's fade), in the chain or not.
//
// Threading: the render callbacks and the notify run on each unit's render thread and touch only atomics,
// their own output's record and the units. Spotify connects, starts, stops and disposes on its audio thread;
// the record changes under sg_outputsLock, there and on sg_outputsQueue (format changes, the silence check).
// A change waits for a render in progress to end; a render never waits. Everything else is main thread.
#import <AudioToolbox/AudioToolbox.h>
#import <mach/mach_time.h>
#import <os/lock.h>
#import <pthread.h>
#import <stdatomic.h>
#import "Core/SGCore.h"
#import "Core/SGAudioInline.h"
#import "Headers/SPTPlayer.h"
#import "PlayerState.h"
#import "SpeedPitch.h"
#import "SpeedPitchSongs.h"
#import "SGTimePitch.h"
#import "SGRenderGate.h"
#import "SGOutputControl.h"
#import "SGPCMRead.h"
#import "Shared/Lossless/SGAnchor.h"

// The unit stays in this long after speed and pitch both came back to normal.
static const double kOffAfter = 1.5;
// An output silent this long gives the processors up to a connected one that is not; one started or connected
// this recently counts as having sound.
static const double kSilentFor = 1;
// How often the outputs are checked for that while two or more run.
static const double kCheckEvery = 0.5;

enum { kMaxOutputs = 8, kMaxWatchers = 4 };

#pragma mark - shared between the threads

static float sg_speed = 1, sg_semitones;     // main thread
NSNotificationName const SGPlayerSpeedDidChangeNotification = @"spotifyglass.player.speedChanged";
static atomic_uint sg_speedBits;             // sg_speed for SPTPlayerState, read on any thread
static atomic_uint sg_semitoneBits;          // sg_semitones, for resetUnit() on whichever thread seeks

typedef struct {
    atomic_uint_fast64_t rateBits;
    atomic_uint flags, channels, bytes;
} Format;

// A RemoteIO unit of Spotify's. A slot whose unit is NULL is free; slots are used again, never freed, since a
// render thread may hold one.
typedef struct {
    _Atomic(AudioUnit) unit;
    // What Spotify connected to it, NULL when nothing is; `taken` while this file's callback stands in for that
    // connection, pulling it in chunks no larger than its own largest slice.
    _Atomic(AudioUnit) source;
    UInt32 sourceBus;
    atomic_bool taken;
    atomic_uint chunk;
    #if SG_DRIVER
    SGAnchorRing anchor;
    #endif
    Float64 sourceTime;                      // its render thread only
    // Spotify's side (input scope, element 0), which the callback fills, and the hardware's (output scope),
    // which render notifies get.
    Format client, hardware;
    atomic_bool running, busy;
    SGOutputPublication outputPublication;
    SGOutputSettings outputSettings;         // last complete snapshot, render-owned
    SGOutputEnvelope outputEnvelope;         // render-owned, never shared between units
    float sleepGain;                        // render-owned slew toward the global sleep level
    atomic_bool sleepStarting;              // next render starts at the global level, not a saved level
    BOOL musicBuffer;                       // ownership at this buffer's pre-render
    BOOL controlledMusic;                   // previous buffer's output-control ownership
    atomic_uint_fast64_t loudAt;             // host time of its last rendered buffer with sound
    // Under sg_outputsLock: when Spotify last started or connected it, as an order and as a host time,
    // and whether its notify and listener are on.
    uint64_t order, eventAt;
    BOOL listened;
} Output;

static Output sg_outputs[kMaxOutputs];
static _Atomic(Output *) sg_music;           // the output carrying the processors
static SGRenderGate sg_processing;
static pthread_mutex_t sg_processingChanges = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t sg_outputsLock = PTHREAD_RECURSIVE_MUTEX_INITIALIZER;
static dispatch_queue_t sg_outputsQueue;
static SGPlayerOutputWatcher sg_watchers[kMaxWatchers];
static BOOL sg_reachable;                    // Spotify's AudioOutputUnitStart could be rebound or hooked
static _Atomic(SGPlayerOutputEffects) sg_outputEffects;
static _Atomic(SGPlayerOutputProcessor) sg_outputReader;
// Under sg_outputsLock. Coefficients are made off render for each hardware rate.
static double sg_outputGain = 1, sg_outputThreshold = INFINITY, sg_outputReleaseMS = 100;
// The timer publishes the process-wide fade level through SGPlayerSetGain.
// Outputs only read it; no output can overwrite it during a start or handoff.
static atomic_uint sg_sleepLevelBits;

// The unit in use and whether the render thread runs it: in the music's chain (pull), else in place (pitch only).
static _Atomic(SGTimePitch *) sg_pull, sg_inPlace;
static atomic_bool sg_engaged;
static pthread_mutex_t sg_buildLock = PTHREAD_MUTEX_INITIALIZER;
static _Atomic(SGPlayerStage) sg_stage;
static _Atomic(SGPlayerSourceSelector) sg_sourceSelector;
static atomic_uint_fast64_t sg_sourceEpoch = 1;

uint64_t SGPlayerSourceEpoch(void) { return atomic_load(&sg_sourceEpoch); }
void SGPlayerInvalidateSource(void) { atomic_fetch_add(&sg_sourceEpoch, 1); }
void SGPlayerSetSourceSelector(SGPlayerSourceSelector selector) {
    SGPlayerInvalidateSource();
    atomic_store(&sg_sourceSelector, selector);
}

static double sg_secondsPerTick;
static OSStatus (*sg_setProperty)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);

static Output *music(void) {
    return atomic_load(&sg_music);
}

BOOL SGPlayerBeginProcessing(AudioUnit unit) {
    Output *output = music();
    if (!output || atomic_load(&output->unit) != unit) return NO;
    if (!SGRenderGateEnter(&sg_processing)) return NO;
    output = music();
    if (output && atomic_load(&output->unit) == unit) return YES;
    SGRenderGateLeave(&sg_processing);
    return NO;
}

void SGPlayerEndProcessing(void) {
    SGRenderGateLeave(&sg_processing);
}

void SGPlayerSetOutputProcessing(SGPlayerOutputEffects effects, SGPlayerOutputProcessor reader) {
    atomic_store(&sg_outputEffects, effects);
    atomic_store(&sg_outputReader, reader);
}

// Control side only. There is no deadline: a returned barrier proves that the
// last reader, including a post-render notify, has actually left.
static void closeProcessing(void) {
    pthread_mutex_lock(&sg_processingChanges);
    SGRenderGateClose(&sg_processing);
    while (!SGRenderGateIdle(&sg_processing)) usleep(100);
}

static void openProcessing(void) {
    SGRenderGateOpen(&sg_processing);
    pthread_mutex_unlock(&sg_processingChanges);
}

// Microseconds of song the music's mixer has handed over with sound, the own clock's (sg_clock).
static _Atomic uint64_t sg_playedMicros;

static double playedSeconds(void) {
    return atomic_load_explicit(&sg_playedMicros, memory_order_relaxed) / 1e6;
}

// Whether the music's output is fed through this file's callback.
static BOOL tapped(void) {
    Output *output = music();
    return output && atomic_load(&output->taken);
}

static double rateOf(Format *format) {
    uint64_t bits = atomic_load_explicit(&format->rateBits, memory_order_relaxed);
    double rate;
    memcpy(&rate, &bits, sizeof rate);
    return rate;
}

static float loadFloat(atomic_uint *slot) {
    uint32_t bits = atomic_load(slot);
    float value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static double seconds(uint64_t ticks) {
    return ticks * sg_secondsPerTick;
}

#pragma mark - the render thread: the chain

static void silence(AudioBufferList *data) {
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) if (data->mBuffers[b].mData) memset(data->mBuffers[b].mData, 0, data->mBuffers[b].mDataByteSize);
}

#if SG_DRIVER
// Runs of silence from the music's mixer (speed-rebuffer test): written on the render thread only, read by
// SGSpeedProbeSilence on main. A run is reported once it ends.
static _Atomic uint64_t sg_runStart, sg_runFrames, sg_lastRunHost, sg_lastRunFrames, sg_runs;
static _Atomic uint64_t sg_runRateBits;

static void noteSilence(bool silent, UInt32 frames, double rate, uint64_t host) {
    uint64_t start = atomic_load_explicit(&sg_runStart, memory_order_relaxed);
    if (silent) {
        if (!start) atomic_store_explicit(&sg_runStart, host, memory_order_relaxed);
        atomic_fetch_add_explicit(&sg_runFrames, frames, memory_order_relaxed);
    } else if (start) {
        uint64_t bits;
        memcpy(&bits, &rate, sizeof bits);
        atomic_store_explicit(&sg_runRateBits, bits, memory_order_relaxed);
        atomic_store_explicit(&sg_lastRunHost, start, memory_order_relaxed);
        atomic_store_explicit(&sg_lastRunFrames, atomic_load_explicit(&sg_runFrames, memory_order_relaxed), memory_order_relaxed);
        atomic_fetch_add_explicit(&sg_runs, 1, memory_order_release);
        atomic_store_explicit(&sg_runStart, 0, memory_order_relaxed);
        atomic_store_explicit(&sg_runFrames, 0, memory_order_relaxed);
    }
}

uint64_t SGSpeedProbeSilence(uint64_t *host, double *ms, bool *silentNow) {
    uint64_t runs = atomic_load_explicit(&sg_runs, memory_order_acquire);
    uint64_t bits = atomic_load_explicit(&sg_runRateBits, memory_order_relaxed);
    double rate;
    memcpy(&rate, &bits, sizeof rate);
    *host = atomic_load_explicit(&sg_lastRunHost, memory_order_relaxed);
    *ms = rate > 0 ? atomic_load_explicit(&sg_lastRunFrames, memory_order_relaxed) * 1000.0 / rate : 0;
    *silentNow = atomic_load_explicit(&sg_runStart, memory_order_relaxed) != 0;
    return runs;
}
#endif

// The output's mixer's next `frames` frames into `data`, in chunks of at most its largest slice, each with a
// sample time of the output's own, so Spotify's units never see a time twice (an AU renders a time it has
// seen from cache). With `sounding`, it stops at the first chunk marked silent (SGPlayerPull).
static OSStatus pullSource(Output *output, AudioUnit source, const AudioTimeStamp *outputTime, UInt32 frames, AudioBufferList *data, UInt32 *sounding, BOOL processing) {
    enum { kMaxBuffers = 8 };
    UInt32 chunk = atomic_load_explicit(&output->chunk, memory_order_relaxed);
    if (data->mNumberBuffers > kMaxBuffers) chunk = frames;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) if (!data->mBuffers[b].mData) chunk = frames;
    UInt32 bytesPerFrame[kMaxBuffers];
    for (UInt32 b = 0; b < data->mNumberBuffers && b < kMaxBuffers; b++) bytesPerFrame[b] = data->mBuffers[b].mDataByteSize / frames;
    if (sounding) *sounding = frames;

    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(chunk, frames - done);
        struct { AudioBufferList list; AudioBuffer more[kMaxBuffers - 1]; } part;
        AudioBufferList *target = data;
        if (count != frames) {
            part.list.mNumberBuffers = data->mNumberBuffers;
            for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
                part.list.mBuffers[b] = (AudioBuffer){data->mBuffers[b].mNumberChannels, count * bytesPerFrame[b],
                                                      (char *)data->mBuffers[b].mData + done * bytesPerFrame[b]};
            }
            target = &part.list;
        }
        AudioTimeStamp time = outputTime ? *outputTime : (AudioTimeStamp){0};
        time.mSampleTime = output->sourceTime;
        time.mFlags |= kAudioTimeStampSampleTimeValid;
        AudioUnitRenderActionFlags flags = 0;
        uint64_t epoch = SGPlayerSourceEpoch();
        double sourceFrame = output->sourceTime;
        #if SG_DRIVER
        uint64_t anchorHost = mach_absolute_time();
        #endif
        OSStatus status = AudioUnitRender(source, &flags, &time, output->sourceBus, count, target);
        output->sourceTime += count;
        // This counter advances through silent/error pulls, whereas the recording may not. Once a
        // native stall occurs, a future playback owner must establish a fresh recording/frame anchor.
        // Conservatively invalidate even natural silence; never resume an external cursor by guessing.
        BOOL observesSource = atomic_load(&sg_sourceSelector) != NULL;
        #if SG_DRIVER
        observesSource = YES;
        #endif
        if ((status != noErr || (flags & kAudioUnitRenderAction_OutputIsSilence))
            && observesSource && output == music()) SGPlayerInvalidateSource();
        #if SG_DRIVER
        if (processing) {
            // Silent as flagged, or as heard: every sample of the first channel under -80 dBFS.
            bool quiet = status == noErr && !(flags & kAudioUnitRenderAction_OutputIsSilence) && target->mBuffers[0].mData;
            const float *samples = target->mBuffers[0].mData;
            for (UInt32 i = 0; quiet && i < count; i++) if (fabsf(samples[i]) > 1e-4f) quiet = false;
            noteSilence((flags & kAudioUnitRenderAction_OutputIsSilence) || status != noErr || quiet, count, rateOf(&output->client), anchorHost);
        }
        if (processing) {
            double rate = rateOf(&output->client);
            // About ten samples per second at the current speed. Sing's refill may burst.
            double speed = MAX(0.25, loadFloat(&sg_speedBits));
            unsigned every = (unsigned)MAX(1, round(rate * speed / (10.0 * count)));
            SGAnchorRing *ring = &output->anchor;
            if (++ring->pulls >= every || ring->lastEpoch != epoch) {
                SGAnchorSample sample = {sourceFrame, rate, anchorHost, epoch,
                    (uint64_t)(uintptr_t)atomic_load(&output->unit), count, status,
                    (flags & kAudioUnitRenderAction_OutputIsSilence) != 0};
                if (SGAnchorPush(ring, sample)) {
                    ring->pulls = 0;
                    ring->lastEpoch = epoch;
                }
            }
        }
        #endif
        if (status != noErr) return status;
        // Asked to stop at silence: Spotify has none of its sound from here on yet, so the rest is not rendered.
        if ((flags & kAudioUnitRenderAction_OutputIsSilence) && sounding) {
            *sounding = done;
            for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
                UInt32 per = data->mBuffers[b].mDataByteSize / frames;
                if (data->mBuffers[b].mData) memset((char *)data->mBuffers[b].mData + done * per, 0, (frames - done) * per);
            }
            return noErr;
        }
        // A buffer marked silent may still hold what was in it before; nothing after this reads the mark.
        if (flags & kAudioUnitRenderAction_OutputIsSilence) {
            silence(target);
        } else if (output == music()) {
            double rate = rateOf(&output->client);
            if (rate > 0) atomic_fetch_add_explicit(&sg_playedMicros, (uint64_t)(count * 1e6 / rate), memory_order_relaxed);
        }
        SGPlayerSourceSelector selector = atomic_load(&sg_sourceSelector);
        if (selector && processing) {
            // Keep output ownership based on Spotify's original samples, not the replacement's sound.
            BOOL audible = NO;
            for (UInt32 b = 0; !audible && b < target->mNumberBuffers; ++b) {
                const float *samples = target->mBuffers[b].mData;
                for (UInt32 i = 0; samples && i < target->mBuffers[b].mDataByteSize / sizeof(float); ++i) {
                    if (fabsf(samples[i]) > 1e-4f) { audible = YES; break; }
                }
            }
            if (audible) atomic_store_explicit(&output->loudAt, mach_absolute_time(), memory_order_relaxed);
            if (!(flags & kAudioUnitRenderAction_OutputIsSilence))
                selector(atomic_load(&output->unit), epoch, sourceFrame, rateOf(&output->client), count, target);
        }
        done += count;
    }
    return noErr;
}

void SGPlayerSetStage(SGPlayerStage stage) {
    atomic_store(&sg_stage, stage);
}

typedef struct {
    Output *output;
    AudioUnit source;
    const AudioTimeStamp *time;
} MixerPull;

static OSStatus pullMixer(void *context, UInt32 frames, AudioBufferList *data, UInt32 *sounding) {
    MixerPull *mixer = context;
    return pullSource(mixer->output, mixer->source, mixer->time, frames, data, sounding, YES);
}

// The music's mixer's sound, through the stage when one is set.
static OSStatus pullChain(Output *output, AudioUnit source, const AudioTimeStamp *time, UInt32 frames, AudioBufferList *data) {
    SGPlayerStage stage = atomic_load_explicit(&sg_stage, memory_order_acquire);
    if (!stage) return pullSource(output, source, time, frames, data, NULL, YES);
    MixerPull mixer = {output, source, time};
    return stage(frames, data, pullMixer, &mixer);
}

// Whether the time and pitch unit pulled the mixer during the render under way. The music's render thread only.
static bool sg_unitPulled;

// The time and pitch unit's input. It renders only on the music's output, and a change of music takes the
// unit out first (disengage), so the music here is the output rendering it.
static OSStatus pullForUnit(void *context, UInt32 frames, AudioBufferList *data) {
    sg_unitPulled = true;
    Output *output = music();
    AudioUnit source = output ? atomic_load(&output->source) : NULL;
    if (!source) {
        silence(data);
        return noErr;
    }
    return pullChain(output, source, NULL, frames, data);
}

static BOOL fitsUnit(const AudioBufferList *data, UInt32 frames, SGTimePitch *unit) {
    if (data->mNumberBuffers != SGTimePitchChannels(unit) || frames > kSGTimePitchMaxFrames) return NO;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * sizeof(float)) return NO;
    }
    return YES;
}

// A RemoteIO unit's input, in place of Spotify's connection from its mixer. `refCon` is its Output.
static OSStatus feed(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                     UInt32 frames, AudioBufferList *data) {
    Output *output = refCon;
    atomic_store(&output->busy, true);
    AudioUnit source = atomic_load(&output->source);
    OSStatus status = noErr;
    if (!source) {
        silence(data);
        *flags |= kAudioUnitRenderAction_OutputIsSilence;
    } else if (!SGPlayerBeginProcessing(atomic_load(&output->unit))) {
        // Another chain, or a control-side handoff: native sound, no shared stage.
        status = pullSource(output, source, timestamp, frames, data, NULL, NO);
    } else {
        // Read engagement before the pointer: disengage drains admitted users,
        // and a replacement is published before engagement is enabled again.
        BOOL engaged = atomic_load(&sg_engaged);
        SGTimePitch *unit = engaged ? atomic_load(&sg_pull) : NULL;
        // A unit made for another rate passes the sound as it is, until the main thread makes one for the new rate.
        BOOL tried = unit && fitsUnit(data, frames, unit) && SGTimePitchSampleRate(unit) == rateOf(&output->client);
        sg_unitPulled = false;
        status = tried ? SGTimePitchRender(unit, frames, data) : -1;
        if (status != noErr && tried && sg_unitPulled) {
            // The failed render took the mixer's sound already: a second pull would skip a buffer of the song,
            // so this one is silent instead.
            silence(data);
            *flags |= kAudioUnitRenderAction_OutputIsSilence;
            status = noErr;
        } else if (status != noErr) {
            status = pullChain(output, source, timestamp, frames, data);
        }
        SGPlayerEndProcessing();
    }
    atomic_store(&output->busy, false);
    return status;
}

#pragma mark - the render thread: in place, the fallback

static float sg_scratch[kSGTimePitchMaxChannels][kSGTimePitchMaxFrames];

static inline void writeSample(void *data, UInt32 index, float value, UInt32 bytes, BOOL isFloat, UInt32 fraction) {
    if (bytes == 4 && isFloat) {
        ((float *)data)[index] = value;
        return;
    }
    if (bytes == 4) {
        double scale = fraction ? (double)(1u << fraction) : 2147483648.0;
        ((int32_t *)data)[index] = (int32_t)llrint(fmax(-2147483648.0, fmin(value * scale, 2147483647.0)));
    } else {
        ((int16_t *)data)[index] = (int16_t)lrintf(fmaxf(-32768, fminf(value * 32768, 32767)));
    }
}

static void shiftInPlace(SGTimePitch *unit, Format *hardware, AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *data) {
    UInt32 formatFlags = atomic_load_explicit(&hardware->flags, memory_order_relaxed);
    UInt32 bytes = atomic_load_explicit(&hardware->bytes, memory_order_relaxed);
    UInt32 channels = SGTimePitchChannels(unit);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    if (frames > kSGTimePitchMaxFrames || (bytes != 2 && bytes != 4)) return;
    if (split ? data->mNumberBuffers != channels : data->mNumberBuffers != 1 || data->mBuffers[0].mNumberChannels != channels) return;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < frames * bytes * (split ? 1 : channels)) return;
    }
    // Silence still goes through, so the sound the unit holds plays out rather than coming back later.
    BOOL silent = (*flags & kAudioUnitRenderAction_OutputIsSilence) != 0;

    float *lanes[kSGTimePitchMaxChannels];
    BOOL direct = split && isFloat && bytes == 4 && !silent;
    for (UInt32 c = 0; c < channels; c++) {
        if (direct) {
            lanes[c] = data->mBuffers[c].mData;
            continue;
        }
        lanes[c] = sg_scratch[c];
        const void *source = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) {
            lanes[c][i] = silent ? 0 : SGPCMReadSample(source, split ? i : i * channels + c, bytes, isFloat, fraction);
        }
    }
    if (!SGTimePitchProcess(unit, lanes, frames) || direct) return;
    for (UInt32 c = 0; c < channels; c++) {
        void *target = data->mBuffers[split ? c : 0].mData;
        for (UInt32 i = 0; i < frames; i++) writeSample(target, split ? i : i * channels + c, lanes[c][i], bytes, isFloat, fraction);
    }
    *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
}

// Whether a buffer in `format` holds sound: float over -80 dB, so a mixer's noise floor is not taken for
// music, and in any other format anything but zeros.
static BOOL hasSound(Format *format, AudioUnitRenderActionFlags flags, const AudioBufferList *data) {
    if (flags & kAudioUnitRenderAction_OutputIsSilence) return NO;
    BOOL floats = (atomic_load_explicit(&format->flags, memory_order_relaxed) & kAudioFormatFlagIsFloat)
                  && atomic_load_explicit(&format->bytes, memory_order_relaxed) == 4;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        const uint32_t *words = data->mBuffers[b].mData;
        UInt32 count = words ? data->mBuffers[b].mDataByteSize / sizeof *words : 0;
        for (UInt32 i = 0; i < count; i++) {
            if (floats ? fabsf(((const float *)words)[i]) > 1e-4f : words[i] != 0) return YES;
        }
    }
    return NO;
}

#pragma mark - the render thread: the gain

// Each continuing output slews toward the timer's global fade level. A new
// stream starts at that level directly; no output transfers an envelope.
static const double kGainSlew = 0.5;

static void scaleSample(void *data, UInt32 at, UInt32 bytes, BOOL isFloat, float scale) {
    if (scale == 1) return;
    if (bytes == 4 && isFloat) ((float *)data)[at] *= scale;
    else if (bytes == 4) ((int32_t *)data)[at] = (int32_t)llrint(fmax(-2147483648.0, fmin(2147483647.0, ((int32_t *)data)[at] * (double)scale)));
    else ((int16_t *)data)[at] = (int16_t)lrintf(fmaxf(-32768, fminf(32767, ((int16_t *)data)[at] * scale)));
}

// Always runs, including when shared effects are unavailable during handoff.
// Envelopes are per-output. Only admitted effects use the shared scratch lanes;
// their float headroom survives mandatory control and is quantized at the end.
static void applyOutputControl(Output *output, AudioUnitRenderActionFlags *flags, UInt32 frames, AudioBufferList *data,
                               BOOL musicBuffer, SGPlayerOutputEffects effects) {
    Format *hardware = &output->hardware;
    UInt32 bytes = atomic_load_explicit(&hardware->bytes, memory_order_relaxed);
    double rate = rateOf(hardware);
    if ((bytes != 2 && bytes != 4) || rate <= 0) return;
    UInt32 formatFlags = atomic_load_explicit(&hardware->flags, memory_order_relaxed);
    BOOL isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    BOOL split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 channels = atomic_load_explicit(&hardware->channels, memory_order_relaxed);
    if (!channels || (split ? data->mNumberBuffers != channels
        : data->mNumberBuffers != 1 || data->mBuffers[0].mNumberChannels != channels)) return;
    for (UInt32 b = 0; b < data->mNumberBuffers; b++) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize / bytes / (split ? 1 : channels) < frames) return;
    }
    SGOutputRead(&output->outputPublication, &output->outputSettings);
    SGOutputSettings settings = musicBuffer ? output->outputSettings : (SGOutputSettings){1, INFINITY, 0};
    // A newly selected output starts at the configured gain, not at its former
    // nonmusic unity level. Setting changes within one stream still ramp.
    BOOL beginsMusic = musicBuffer && !output->controlledMusic;
    if (beginsMusic)
        output->outputEnvelope = (SGOutputEnvelope){settings.gain, 1};
    if (settings.threshold == INFINITY) output->outputEnvelope.limiter = 1;
    output->controlledMusic = musicBuffer;
    float from = output->outputEnvelope.gain, step = (settings.gain - from) / frames;
    BOOL starting = atomic_exchange(&output->sleepStarting, false);
    float target = loadFloat(&sg_sleepLevelBits);
    float sleepFrom = starting || beginsMusic ? target : output->sleepGain;
    float most = (float)(frames / (kGainSlew * rate));
    float sleepTo = sleepFrom + fmaxf(-most, fminf(target - sleepFrom, most));
    output->sleepGain = sleepTo;
    BOOL neutral = from == 1 && settings.gain == 1 && settings.threshold == INFINITY
        && output->outputEnvelope.limiter == 1 && sleepFrom == 1 && sleepTo == 1;
    // State adoption above is mandatory even on bypass. No samples are read or
    // rewritten while output control is settled and no effects are admitted.
    if (neutral && !effects) return;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    BOOL silent = (*flags & kAudioUnitRenderAction_OutputIsSilence) != 0;
    BOOL loud = !silent;
    for (UInt32 done = 0; done < frames;) {
        UInt32 count = MIN(frames - done, (UInt32)kSGTimePitchMaxFrames);
        BOOL direct = split && isFloat && bytes == 4 && channels >= 2;
        float *left = NULL, *right = NULL;
        BOOL processed = NO;
        if (effects) {
            // Only an admitted callback uses the shared scratch lanes. The
            // in-place pitch stage has finished with them before this stage.
            left = direct ? (float *)data->mBuffers[0].mData + done : sg_scratch[0];
            right = direct ? (float *)data->mBuffers[1].mData + done : sg_scratch[1];
            if (!direct || silent) for (UInt32 j = 0; j < count; ++j) {
                UInt32 at = split ? done + j : (done + j) * channels;
                left[j] = silent ? 0 : SGPCMReadSample(data->mBuffers[0].mData, at, bytes, isFloat, fraction);
                right[j] = channels < 2 ? left[j] : silent ? 0
                    : SGPCMReadSample(data->mBuffers[split ? 1 : 0].mData, split ? done + j : at + 1, bytes, isFloat, fraction);
            }
            processed = effects(left, right, count, rate);
        }
        if (neutral && (!processed || (direct && !silent))) {
            done += count;
            continue;
        }
        for (UInt32 j = 0; j < count; ++j) {
            UInt32 i = done + j, at = split ? i : i * channels;
            float l = processed ? left[j] : silent ? 0 : SGPCMReadSample(data->mBuffers[0].mData, at, bytes, isFloat, fraction);
            float r = processed ? right[j] : channels < 2 ? l : silent ? 0
                : SGPCMReadSample(data->mBuffers[split ? 1 : 0].mData, split ? i : at + 1, bytes, isFloat, fraction);
            if (processed && channels == 1) l = r = 0.5f * (l + r);
            float gain = from == settings.gain ? from : from + step * (i + 1);
            float scale = neutral ? 1 : SGOutputFrameScale(&output->outputEnvelope, settings, gain, l, r);
            float sleep = sleepFrom + (sleepTo - sleepFrom) * (i + 1) / frames;
            if (processed) {
                l *= scale * sleep;
                r *= scale * sleep;
                writeSample(data->mBuffers[0].mData, at, l, bytes, isFloat, fraction);
                if (channels > 1) writeSample(data->mBuffers[split ? 1 : 0].mData, split ? i : at + 1, r, bytes, isFloat, fraction);
                loud = loud || l != 0 || r != 0;
            }
            if (!silent) for (UInt32 c = processed ? 2 : 0; c < channels; ++c)
                scaleSample(data->mBuffers[split ? c : 0].mData, split ? i : at + c, bytes, isFloat, (c < 2 ? scale : 1) * sleep);
        }
        done += count;
    }
    if (loud) *flags &= ~kAudioUnitRenderAction_OutputIsSilence;
    output->outputEnvelope.gain = settings.gain;
}

// On every started output, `refCon` its Output: notes when it has sound, and shifts the pitch on the music's
// when it is not fed by the callback.
static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    Output *output = refCon;
    if (bus != 0) return noErr;
    if (*flags & kAudioUnitRenderAction_PreRender) output->musicBuffer = output == music();
    if (!(*flags & kAudioUnitRenderAction_PostRender) || !data || !data->mNumberBuffers || !frames) return noErr;
    BOOL sourceMetered = atomic_load(&sg_sourceSelector) && atomic_load(&output->taken) && output == music();
    if (!sourceMetered && hasSound(&output->hardware, *flags, data)) atomic_store_explicit(&output->loudAt, mach_absolute_time(), memory_order_relaxed);
    BOOL admitted = SGPlayerBeginProcessing(atomic_load(&output->unit));
    BOOL musicBuffer = output->musicBuffer || output == music() || admitted;
    if (admitted && !atomic_load(&output->taken) && atomic_load(&sg_engaged)) {
        SGTimePitch *unit = atomic_load(&sg_inPlace);
        if (unit && SGTimePitchSampleRate(unit) == rateOf(&output->hardware))
            shiftInPlace(unit, &output->hardware, flags, frames, data);
    }
    SGPlayerOutputEffects effects = admitted ? atomic_load(&sg_outputEffects) : NULL;
    SGPlayerOutputProcessor reader = atomic_load(&sg_outputReader);
    applyOutputControl(output, flags, frames, data, musicBuffer, effects);
    if (admitted && reader) reader(flags, frames, data);
    if (admitted) SGPlayerEndProcessing();
    return noErr;
}

#pragma mark - the outputs (sg_outputsLock)

static BOOL isRemoteIO(AudioUnit unit) {
    AudioComponentDescription description = {0};
    if (!unit || AudioComponentGetDescription(AudioComponentInstanceGetComponent(unit), &description) != noErr) return NO;
    return description.componentType == kAudioUnitType_Output && description.componentSubType == kAudioUnitSubType_RemoteIO;
}

static Output *outputOf(AudioUnit unit) {
    for (int i = 0; unit && i < kMaxOutputs; i++) if (atomic_load(&sg_outputs[i].unit) == unit) return &sg_outputs[i];
    return NULL;
}

static Output *outputFor(AudioUnit unit) {
    Output *output = outputOf(unit);
    for (int i = 0; !output && i < kMaxOutputs; i++) {
        if (atomic_load(&sg_outputs[i].unit)) continue;
        output = &sg_outputs[i];
        atomic_store(&output->source, NULL);
        atomic_store(&output->taken, false);
        atomic_store(&output->running, false);
        atomic_store(&output->chunk, 1024);
        atomic_store(&output->loudAt, 0);
        output->sourceTime = 0;
        output->outputSettings = (SGOutputSettings){1, INFINITY, 0};
        output->outputEnvelope = (SGOutputEnvelope){1, 1};
        output->sleepGain = 1;
        atomic_store(&output->sleepStarting, true);
        output->musicBuffer = NO;
        output->controlledMusic = NO;
        SGOutputPublish(&output->outputPublication, output->outputSettings);
        output->order = output->eventAt = 0;
        output->listened = NO;
        atomic_store(&output->unit, unit);
    }
    if (!output) {
        static int logged;
        if (logged++ < 3) SGLog(@"audio: more than %d outputs at once, %p is left as Spotify made it", kMaxOutputs, unit);
    }
    return output;
}

// Waits for the output's render in progress, if any, to end.
static void waitFor(Output *output) {
    for (int i = 0; i < 400 && atomic_load(&output->busy); i++) usleep(250);
}

// Stops the render threads using the unit, and returns once none is.
static void disengage(void) {
    atomic_store(&sg_engaged, false);
    closeProcessing();
    openProcessing();
}

static void readScope(AudioUnit unit, AudioUnitScope scope, Format *into, AudioStreamBasicDescription *format) {
    UInt32 size = sizeof *format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, scope, 0, format, &size);
    if (status != noErr || format->mFormatID != kAudioFormatLinearPCM || format->mSampleRate <= 0) {
        *format = (AudioStreamBasicDescription){0};
    }
    uint64_t bits;
    memcpy(&bits, &format->mSampleRate, sizeof bits);
    atomic_store(&into->rateBits, bits);
    atomic_store(&into->flags, format->mFormatFlags);
    atomic_store(&into->channels, format->mChannelsPerFrame);
    atomic_store(&into->bytes, format->mBitsPerChannel / 8);
}

static void publishOutput(Output *output) {
    double rate = rateOf(&output->hardware);
    SGOutputSettings settings = {(float)sg_outputGain, (float)sg_outputThreshold,
        rate > 0 ? (float)exp(-1000 / (sg_outputReleaseMS * rate)) : 0};
    SGOutputPublish(&output->outputPublication, settings);
}

void SGPlayerSetOutputControl(BOOL on, double gainDB, double thresholdDB, double releaseMS) {
    pthread_mutex_lock(&sg_outputsLock);
    sg_outputGain = on ? pow(10, gainDB / 20) : 1;
    sg_outputThreshold = on ? pow(10, fmin(thresholdDB, 0) / 20) : INFINITY;
    sg_outputReleaseMS = fmax(releaseMS, 0.1);
    for (int i = 0; i < kMaxOutputs; ++i)
        if (atomic_load(&sg_outputs[i].unit)) publishOutput(&sg_outputs[i]);
    pthread_mutex_unlock(&sg_outputsLock);
}

static NSString *formatText(const AudioStreamBasicDescription *format) {
    if (format->mFormatID != kAudioFormatLinearPCM) return @"not linear PCM";
    return [NSString stringWithFormat:@"%.0f Hz, %u ch, %u-bit %@%@", format->mSampleRate, (unsigned)format->mChannelsPerFrame,
            (unsigned)format->mBitsPerChannel, (format->mFormatFlags & kAudioFormatFlagIsFloat) ? @"float" : @"integer",
            (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? @" split" : @" interleaved"];
}

// Why the callback cannot stand in for the connection to the client format `client`, nil when it can.
static NSString *refusal(Output *output, const AudioStreamBasicDescription *client) {
    BOOL canonical = client->mFormatID == kAudioFormatLinearPCM && (client->mFormatFlags & kAudioFormatFlagIsFloat)
                     && (client->mFormatFlags & kAudioFormatFlagIsNonInterleaved) && client->mBitsPerChannel == 32
                     && client->mChannelsPerFrame >= 1 && client->mChannelsPerFrame <= kSGTimePitchMaxChannels;
    if (!canonical) return [NSString stringWithFormat:@"Spotify's side is %@, not float split 1 or 2 ch", formatText(client)];
    AudioStreamBasicDescription mixer = {0};
    UInt32 size = sizeof mixer;
    AudioUnit source = atomic_load(&output->source);
    if (AudioUnitGetProperty(source, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, output->sourceBus, &mixer, &size) != noErr) return nil;
    UInt32 layout = kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved;
    if (mixer.mSampleRate != client->mSampleRate || (mixer.mFormatFlags & layout) != (client->mFormatFlags & layout)
        || mixer.mChannelsPerFrame != client->mChannelsPerFrame || mixer.mBitsPerChannel != client->mBitsPerChannel) {
        return [NSString stringWithFormat:@"its mixer gives %@ for %@", formatText(&mixer), formatText(client)];
    }
    return nil;
}

// Reads both formats and the mixer's slice, and puts in the callback or Spotify's own connection, whichever
// the formats allow. Answers why Spotify's connection is kept, nil when the callback feeds the output.
static NSString *settle(Output *output, AudioStreamBasicDescription *client, AudioStreamBasicDescription *hardware) {
    AudioUnit unit = atomic_load(&output->unit);
    readScope(unit, kAudioUnitScope_Input, &output->client, client);
    readScope(unit, kAudioUnitScope_Output, &output->hardware, hardware);
    publishOutput(output);
    AudioUnit source = atomic_load(&output->source);
    if (!source) return @"not connected";
    UInt32 slice = 0, size = sizeof slice;
    if (AudioUnitGetProperty(source, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &slice, &size) == noErr && slice >= 256) {
        atomic_store(&output->chunk, slice);
    }
    NSString *why = refusal(output, client);
    BOOL take = !why;
    if (take == atomic_load(&output->taken)) return why;
    OSStatus status;
    if (take) {
        AURenderCallbackStruct callback = {feed, output};
        status = sg_setProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof callback);
    } else {
        // Its sound passes as Spotify made it; the callback's render in progress, if any, ends first.
        AudioUnitConnection connection = {source, output->sourceBus, 0};
        status = sg_setProperty(unit, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &connection, sizeof connection);
        waitFor(output);
    }
    if (status == noErr) atomic_store(&output->taken, take);
    SGLog(@"audio: output %p %@ (status %d)%@", unit, take ? @"fed through the mod's callback" : @"given Spotify's own connection back",
          (int)status, why ? [@": " stringByAppendingString:why] : @"");
    return atomic_load(&output->taken) ? nil : why ?: @"the callback could not be set";
}

static void markEvent(Output *output) {
    static uint64_t order;
    output->order = ++order;
    output->eventAt = mach_absolute_time();
}

static NSString *describe(Output *output) {
    if (!output) return @"none";
    return [NSString stringWithFormat:@"%p (%.0f Hz)", atomic_load(&output->unit), rateOf(&output->client)];
}

static void tellWatchers(void) {
    Output *output = music();
    AudioUnit unit = output ? atomic_load(&output->unit) : NULL;
    for (int i = 0; i < kMaxWatchers && sg_watchers[i]; i++) sg_watchers[i](unit);
}

static void applyToFormat(void);

// The output that should carry the processors, Spotify's newest of the best kind: running and connected
// with sound in the last second, then running and connected, then running and fed by Spotify itself, then
// connected but not started, so speed can be chosen before Spotify starts it.
static Output *choose(void) {
    uint64_t now = mach_absolute_time();
    Output *best = NULL;
    int bestRank = -1;
    for (int i = 0; i < kMaxOutputs; i++) {
        Output *output = &sg_outputs[i];
        if (!atomic_load(&output->unit)) continue;
        BOOL connected = atomic_load(&output->source) != NULL, running = atomic_load(&output->running);
        if (!running && !connected) continue;
        BOOL sounds = seconds(now - MAX(atomic_load(&output->loudAt), output->eventAt)) < kSilentFor;
        int rank = running * 4 + connected * 2 + (running && connected && sounds);
        if (rank > bestRank || (rank == bestRank && output->order > best->order)) {
            best = output;
            bestRank = rank;
        }
    }
    return best;
}

// Hands the processors to the output that should have them; the watchers are told when they moved, or when
// `always` (a start of the music's output, a format change on it).
static void reselect(BOOL always, NSString *why) {
    Output *previous = music(), *next = choose();
    if (next == previous && !always) return;
    closeProcessing();
    if (next != previous) {
        atomic_store(&sg_engaged, false);
        // The newest now, so it keeps the processors through a tie with the one it took them from.
        if (next) markEvent(next);
        if (next) atomic_store(&next->sleepStarting, true);
        atomic_store(&sg_music, next);
        SGLog(@"audio: the processors move from %@ to %@%@", describe(previous), describe(next), why ? [@", " stringByAppendingString:why] : @"");
    }
    if (next != previous || always) {
        SGPlayerInvalidateSource();
        tellWatchers();
        applyToFormat();
    }
    openProcessing();
}

static void checkSilence(void) {
    pthread_mutex_lock(&sg_outputsLock);
    int running = 0;
    for (int i = 0; i < kMaxOutputs; i++) running += atomic_load(&sg_outputs[i].unit) && atomic_load(&sg_outputs[i].running);
    if (running > 1) reselect(NO, [NSString stringWithFormat:@"its output silent for %.0f s while another has sound", kSilentFor]);
    pthread_mutex_unlock(&sg_outputsLock);
}

static void formatChanged(void *refCon, AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element) {
    if (property != kAudioUnitProperty_StreamFormat || element != 0) return;
    if (scope != kAudioUnitScope_Input && scope != kAudioUnitScope_Output) return;
    // Off the thread setting it: settling may set the unit's connection, which is not done from inside its own listener.
    Output *output = refCon;
    if (output == music()) SGPlayerInvalidateSource();
    dispatch_async(sg_outputsQueue, ^{
        pthread_mutex_lock(&sg_outputsLock);
        if (atomic_load(&output->unit) == unit) {
            AudioStreamBasicDescription client, hardware;
            settle(output, &client, &hardware);
            SGLog(@"audio: output %p's format changed: Spotify's side %@, the hardware's %@", unit, formatText(&client), formatText(&hardware));
            reselect(output == music(), nil);
        }
        pthread_mutex_unlock(&sg_outputsLock);
    });
}

#pragma mark - Spotify's audio thread

// A format or slice Spotify sets on a mixer feeding an output: settled again, the output's own listener
// covering its side.
static void sourceChanged(AudioUnit unit) {
    pthread_mutex_lock(&sg_outputsLock);
    for (int i = 0; i < kMaxOutputs; i++) {
        Output *output = &sg_outputs[i];
        AudioUnit outputUnit = atomic_load(&output->unit);
        if (!outputUnit || atomic_load(&output->source) != unit) continue;
        if (output == music()) SGPlayerInvalidateSource();
        dispatch_async(sg_outputsQueue, ^{
            pthread_mutex_lock(&sg_outputsLock);
            AudioStreamBasicDescription client, hardware;
            if (atomic_load(&output->unit) == outputUnit && atomic_load(&output->source) == unit) {
                settle(output, &client, &hardware);
                if (output == music()) applyToFormat();
            }
            pthread_mutex_unlock(&sg_outputsLock);
        });
    }
    pthread_mutex_unlock(&sg_outputsLock);
}

static OSStatus setProperty(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope, AudioUnitElement element,
                            const void *data, UInt32 size) {
    if (property != kAudioUnitProperty_MakeConnection || scope != kAudioUnitScope_Input || element != 0 || !data
        || size < sizeof(AudioUnitConnection) || !isRemoteIO(unit)) {
        // Invalidate before applying a format change: Core Audio's listener may arrive later. Even
        // setting the same format conservatively invalidates a prepared source's negotiated contract.
        Output *current = music();
        if (property == kAudioUnitProperty_StreamFormat && current
            && (unit == atomic_load(&current->unit) || unit == atomic_load(&current->source))) SGPlayerInvalidateSource();
        OSStatus status = sg_setProperty(unit, property, scope, element, data, size);
        if (status == noErr && (property == kAudioUnitProperty_StreamFormat || property == kAudioUnitProperty_MaximumFramesPerSlice)) sourceChanged(unit);
        return status;
    }
    const AudioUnitConnection *connection = data;
    SGPlayerInvalidateSource();
    pthread_mutex_lock(&sg_outputsLock);
    Output *output = outputFor(unit);
    if (!output) {
        pthread_mutex_unlock(&sg_outputsLock);
        return sg_setProperty(unit, property, scope, element, data, size);
    }
    if (!connection->sourceAudioUnit) {
        BOOL wasTaken = atomic_exchange(&output->taken, false);
        atomic_store(&output->source, NULL);
        waitFor(output);
        if (wasTaken) {
            AURenderCallbackStruct none = {0};
            sg_setProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &none, sizeof none);
        }
        SGLog(@"audio: Spotify disconnected output %p", unit);
        OSStatus status = sg_setProperty(unit, property, scope, element, data, size);
        reselect(NO, @"its output disconnected");
        pthread_mutex_unlock(&sg_outputsLock);
        return status;
    }
    // A new mixer: the old one's render, if any, ends first, and the new one's time starts at 0.
    atomic_store(&output->taken, false);
    atomic_store(&output->source, NULL);
    waitFor(output);
    output->sourceBus = connection->sourceOutputNumber;
    output->sourceTime = 0;
    atomic_store(&output->source, connection->sourceAudioUnit);
    markEvent(output);
    AudioStreamBasicDescription client, hardware;
    // Spotify's connection is made too only when the callback cannot stand in for it.
    NSString *why = settle(output, &client, &hardware);
    OSStatus status = why ? sg_setProperty(unit, property, scope, element, data, size) : noErr;
    SGLog(@"audio: Spotify connects mixer %p (bus %u) to output %p, %@%@", connection->sourceAudioUnit, (unsigned)connection->sourceOutputNumber,
          unit, formatText(&client), why ? [@"; its own connection kept: " stringByAppendingString:why] : @"; fed through the mod's callback");
    reselect(NO, @"Spotify connected it last");
    pthread_mutex_unlock(&sg_outputsLock);
    return status;
}

static OSStatus (*sg_startOutput)(AudioUnit unit);

// The silence check, a couple of times a second while two outputs run, as it does nothing with fewer. Under
// sg_outputsLock, after any output starts, stops or goes.
static void updateChecking(void) {
    static dispatch_source_t timer;   // kept for good: a source must not be released while suspended
    static BOOL checking;
    if (!timer) {
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, sg_outputsQueue);
        dispatch_source_set_event_handler(timer, ^{
            checkSilence();
        });
    }
    int running = 0;
    for (int i = 0; i < kMaxOutputs; i++) running += atomic_load(&sg_outputs[i].unit) && atomic_load(&sg_outputs[i].running);
    if ((running > 1) == checking) return;
    checking = running > 1;
    if (!checking) {
        dispatch_suspend(timer);
        return;
    }
    uint64_t every = (uint64_t)(kCheckEvery * NSEC_PER_SEC);
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, (int64_t)every), every, NSEC_PER_SEC / 10);
    dispatch_resume(timer);
}

static OSStatus startOutput(AudioUnit unit) {
    if (!isRemoteIO(unit)) return sg_startOutput(unit);
    pthread_mutex_lock(&sg_outputsLock);
    Output *output = outputFor(unit);
    if (output) {
        AudioStreamBasicDescription client, hardware;
        NSString *why = settle(output, &client, &hardware);
        markEvent(output);
        atomic_store(&output->sleepStarting, true);
        atomic_store(&output->running, true);
        updateChecking();
        if (!output->listened) {
            output->listened = YES;
            AudioUnitAddRenderNotify(unit, rendered, output);
            AudioUnitAddPropertyListener(unit, kAudioUnitProperty_StreamFormat, formatChanged, output);
        }
        // Every start of the music's output is told, so what holds sound from before the pause starts over.
        reselect(music() == output, @"Spotify started it last");
        AudioUnit source = atomic_load(&output->source);
        SGLog(@"audio: output %p started: Spotify's side %@, the hardware's %@, %@; the processors are on %@", unit, formatText(&client),
              formatText(&hardware), !source ? @"fed by Spotify itself" : why ? [NSString stringWithFormat:@"mixer %p through Spotify's connection (%@)", source, why]
              : [NSString stringWithFormat:@"mixer %p through the mod's callback", source], music() == output ? @"this one" : describe(music()));
    }
    pthread_mutex_unlock(&sg_outputsLock);
    return sg_startOutput(unit);
}

static OSStatus (*sg_stopOutput)(AudioUnit unit);

static OSStatus stopOutput(AudioUnit unit) {
    if (unit == SGPlayerMusicOutput()) SGPlayerInvalidateSource();
    OSStatus status = sg_stopOutput(unit);
    pthread_mutex_lock(&sg_outputsLock);
    Output *output = outputOf(unit);
    if (output && atomic_exchange(&output->running, false)) {
        updateChecking();
        reselect(music() == output, @"its output stopped");
        SGLog(@"audio: output %p stopped (Spotify's side %.0f Hz); the processors are on %@", unit, rateOf(&output->client), describe(music()));
    }
    pthread_mutex_unlock(&sg_outputsLock);
    return status;
}

static OSStatus (*sg_dispose)(AudioComponentInstance unit);

// Every output fed by the unit loses it, and the unit's own output is forgotten, before it goes; renders in
// progress end first.
static OSStatus disposeUnit(AudioComponentInstance unit) {
    SGPlayerInvalidateSource();
    pthread_mutex_lock(&sg_outputsLock);
    BOOL changed = NO;
    for (int i = 0; i < kMaxOutputs; i++) {
        Output *output = &sg_outputs[i];
        AudioUnit outputUnit = atomic_load(&output->unit);
        if (!outputUnit) continue;
        if (outputUnit == unit) {
            if (output == music()) disengage();
            atomic_store(&output->running, false);
            atomic_store(&output->source, NULL);
            waitFor(output);
            atomic_store(&output->unit, NULL);
            SGLog(@"audio: output %p disposed (Spotify's side %.0f Hz)", unit, rateOf(&output->client));
            changed = YES;
        } else if (atomic_load(&output->source) == unit) {
            atomic_store(&output->source, NULL);
            waitFor(output);
            SGLog(@"audio: mixer %p disposed, output %p plays silence until Spotify connects another", unit, outputUnit);
            changed = YES;
        }
    }
    if (changed) {
        updateChecking();
        reselect(NO, @"a unit disposed");
    }
    // Under the lock, so its slot is not used again while its last render may still be running.
    OSStatus status = sg_dispose(unit);
    pthread_mutex_unlock(&sg_outputsLock);
    return status;
}

#pragma mark - engaging the unit

// The unit for the music's format and the way in use, made when there is none or the format changed. A
// replaced one retires after disengage's admission barrier, never after waitFor's timeout.
static SGTimePitch *unitForFormat(void) {
    Output *output = music();
    if (!output) return NULL;
    BOOL pull = atomic_load(&output->taken);
    Format *format = pull ? &output->client : &output->hardware;
    double rate = rateOf(format);
    UInt32 channels = atomic_load(&format->channels);
    if (rate <= 0 || channels < 1 || channels > kSGTimePitchMaxChannels) return NULL;
    _Atomic(SGTimePitch *) *slot = pull ? &sg_pull : &sg_inPlace;
    pthread_mutex_lock(&sg_buildLock);
    SGTimePitch *unit = atomic_load(slot);
    if (!unit || SGTimePitchSampleRate(unit) != rate || SGTimePitchChannels(unit) != channels) {
        BOOL wasEngaged = atomic_load(&sg_engaged);
        disengage();
        SGTimePitch *retired = unit;
        unit = SGTimePitchCreate(rate, channels, pull ? pullForUnit : NULL, NULL);
        if (unit) {
            SGTimePitchSetFollows(unit, SGPlayerPitchFollowsSpeed());
            SGTimePitchSetRate(unit, pull ? sg_speed : 1);
            SGTimePitchSetSemitones(unit, sg_semitones);
            SGTimePitchReset(unit);
        }
        atomic_store(slot, unit);
        SGTimePitchFree(retired);
        SGLog(@"redesign speed: %@ %@ for %.0f Hz, %u channels", unit ? @"a unit" : @"no unit", pull ? @"in the chain" : @"in place", rate, (unsigned)channels);
        if (unit && wasEngaged) atomic_store(&sg_engaged, true);
    }
    pthread_mutex_unlock(&sg_buildLock);
    return unit;
}

static void report(void) {
    SGTimePitch *unit = atomic_load(tapped() ? &sg_pull : &sg_inPlace);
    if (!unit) return;
    SGLog(@"redesign speed: %.2fx, %+.0f st, %u underruns, %u failures, largest pull %u, %.1f s of input", sg_speed, sg_semitones,
          SGTimePitchUnderruns(unit), SGTimePitchFailures(unit), SGTimePitchLargestPull(unit),
          SGTimePitchConsumed(unit) / SGTimePitchSampleRate(unit));
}

// Hands the render thread to the unit's other half, reset, when the speed, the pitch or Pitch follows speed
// now call for it. That costs the unit's delay once (93 ms going to the stretch), the same as putting it in,
// where rendering the other half as it was left would play what it held from last time. Under sg_buildLock.
static void switchIfAsked(SGTimePitch *unit) {
    if (!atomic_load(&sg_engaged) || !SGTimePitchSwitchPending(unit)) return;
    disengage();
    SGTimePitchReset(unit);
    atomic_store(&sg_engaged, true);
}

// Puts the unit in or takes it out for the current speed and pitch.
static void apply(void) {
    BOOL normal = sg_speed == 1 && sg_semitones == 0;
    static NSUInteger change;
    NSUInteger thisChange = ++change;
    if (normal) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kOffAfter * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (thisChange != change || sg_speed != 1 || sg_semitones != 0 || !atomic_load(&sg_engaged)) return;
            report();
            pthread_mutex_lock(&sg_buildLock);
            disengage();
            pthread_mutex_unlock(&sg_buildLock);
        });
    }
    SGTimePitch *unit = unitForFormat();
    if (!unit) {
        static int logged;
        if (!normal && logged++ < 3) SGLog(@"redesign speed: Spotify's output has not started, or is in a format the unit does not take; nothing to change yet");
        return;
    }
    // A seek's resetUnit() may run on Spotify's own thread: the unit is reset and engaged by one side at a time.
    pthread_mutex_lock(&sg_buildLock);
    SGTimePitchSetRate(unit, tapped() ? sg_speed : 1);
    SGTimePitchSetSemitones(unit, sg_semitones);
    if (!normal && !atomic_load(&sg_engaged)) {
        disengage();
        SGTimePitchReset(unit);
        atomic_store(&sg_engaged, true);
    }
    switchIfAsked(unit);
    pthread_mutex_unlock(&sg_buildLock);
}

// A speed or pitch chosen before the output started, or kept across a new format or another output, applies
// now: apply() makes the unit again when the rate or the channels changed, and puts it back in, reset, after
// a change of output took it out.
static void applyToFormat(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sg_speed != 1 || sg_semitones != 0) apply();
    });
}

#pragma mark - the calls

double SGPlayerSpeed(void) {
    return sg_speed;
}

BOOL SGPlayerSpeedAllowed(void) {
    return tapped();
}

// The position Spotify counted in the last -position on this thread, before the own clock and before Sing's lead.
static _Thread_local double sg_spotifyPosition;

// The own clock (see the top), in what is heard: `on` while it counts, from `position` song seconds heard when
// `played` was playedSeconds() and Sing held `lead` ahead, for `track`. `armed` takes the first report stamped at or
// after `notBefore` as its start. What it hands back is in Spotify's terms, a report's own lead on top, which Sing's
// -position (outside this one) takes off again: a report after the lead was built carries all of it, one before it none.
static struct {
    BOOL on, armed;
    CFAbsoluteTime notBefore;
    double position, played, lead;
} sg_clock;

// Sing's -position asks [self position] again for the raw one, and its readers below may too, so this hook may run
// inside itself; only the outer one corrects.
static _Thread_local BOOL sg_correcting;

// Sing's lead (Shared/Sing): what it holds ahead now, and a report's correction. 0 without Sing.
static SGPlayerHeldLead sg_heldLead;
static SGPlayerLeadOf sg_leadOf;

void SGPlayerSetLeadReaders(SGPlayerHeldLead held, SGPlayerLeadOf of) {
    sg_heldLead = held;
    sg_leadOf = of;
}

static double heldLeadNow(void) {
    return sg_heldLead ? sg_heldLead() : 0;
}

static double leadOfState(SPTPlayerState *state) {
    if (!sg_leadOf || !state) return 0;
    BOOL was = sg_correcting;
    sg_correcting = YES;
    double lead = sg_leadOf(state);
    sg_correcting = was;
    return lead;
}
// The newest report seen, to tell a seek from elsewhere (another device over Connect) by its position: one
// further than kSeekGap from where the report before would be by then, both made since the speed last changed
// (sg_speedChangedAt). A false stall moves it 1.2 s at most.
static struct {
    CFAbsoluteTime stamp;
    double asOf, speed;
} sg_lastReport;
static CFAbsoluteTime sg_speedChangedAt;
static const double kSeekGap = 3;
static NSString *sg_clockTrack;
static os_unfair_lock sg_clockLock = OS_UNFAIR_LOCK_INIT;

static NSString *trackOf(SPTPlayerState *state) {
    return [state.track.URI description];
}

// Away from 1x, Spotify's next report from now starts the own clock over.
static void rearmClock(void) {
    os_unfair_lock_lock(&sg_clockLock);
    sg_clock = (typeof(sg_clock)){.armed = loadFloat(&sg_speedBits) != 1, .notBefore = CFAbsoluteTimeGetCurrent()};
    os_unfair_lock_unlock(&sg_clockLock);
}

// Drops what the unit holds from before (93 ms when it is in).
static void resetUnit(void) {
    pthread_mutex_lock(&sg_buildLock);
    SGTimePitch *unit = atomic_load(tapped() ? &sg_pull : &sg_inPlace);
    if (unit) {
        disengage();
        SGTimePitchReset(unit);
        if (loadFloat(&sg_speedBits) != 1 || loadFloat(&sg_semitoneBits) != 0) atomic_store(&sg_engaged, true);
    }
    pthread_mutex_unlock(&sg_buildLock);
}

// Spotify's clock again from here, and the unit starts clean at the new place.
static void handBack(void) {
    rearmClock();
    resetUnit();
}

void SGSetPlayerSpeed(double speed) {
    if (!tapped()) return;
    // Spotify's clock is right until the speed leaves 1x, so it is read before, as Spotify counts it: Sing's
    // -position, outside this file's, takes its lead off what this one returns.
    SPTPlayerState *state = SGPlayerState();
    sg_spotifyPosition = -1;
    [state position];
    double position = sg_spotifyPosition, lead = leadOfState(state), held = heldLeadNow();
    os_unfair_lock_lock(&sg_clockLock);
    if (!sg_clock.on && !sg_clock.armed && speed != 1 && state && position >= 0) {
        sg_clock = (typeof(sg_clock)){.on = YES, .position = position - lead, .played = playedSeconds(), .lead = held};
        sg_clockTrack = trackOf(state);
    }
    BOOL changed = (float)speed != sg_speed;
    if (changed) sg_speedChangedAt = CFAbsoluteTimeGetCurrent();
    os_unfair_lock_unlock(&sg_clockLock);
    sg_speed = (float)speed;
    storeFloat(&sg_speedBits, sg_speed);
    apply();
    SGSpeedPitchSongValuesChanged(@"speed");
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:SGPlayerSpeedDidChangeNotification object:nil];
}

float SGPlayerPitch(void) {
    return sg_semitones;
}

void SGSetPlayerPitch(float semitones) {
    if (!sg_reachable && !tapped()) return;
    sg_semitones = semitones;
    storeFloat(&sg_semitoneBits, semitones);
    apply();
    SGSpeedPitchSongValuesChanged(@"pitch");
}

BOOL SGPlayerPitchFollowsSpeed(void) {
    return SGEnabled(SGKeyPitchFollowsSpeed);
}

void SGSetPlayerPitchFollowsSpeed(BOOL follows) {
    SGSetEnabled(SGKeyPitchFollowsSpeed, follows);
    SGTimePitch *unit = atomic_load(&sg_pull);
    if (unit) SGTimePitchSetFollows(unit, follows);
    apply();
    SGSpeedPitchSongValuesChanged(@"follows");
}

BOOL SGPlayerPitchAvailable(void) {
    return sg_reachable || tapped();
}

void SGPlayerSetGain(float gain) {
    if (!sg_reachable) {
        static int logged;
        if (logged++ < 1) SGLog(@"audio: Spotify's output was not reached, the gain cannot apply");
    }
    storeFloat(&sg_sleepLevelBits, fmaxf(0, fminf(gain, 1)));
}

AudioUnit SGPlayerMusicOutput(void) {
    Output *output = music();
    return output ? atomic_load(&output->unit) : NULL;
}

BOOL SGPlayerMusicOutputRunning(void) {
    Output *output = music();
    return output && atomic_load(&output->running);
}

BOOL SGPlayerMusicClientFormat(AudioStreamBasicDescription *format) {
    pthread_mutex_lock(&sg_outputsLock);
    AudioUnit unit = SGPlayerMusicOutput();
    UInt32 size = sizeof *format;
    BOOL read = unit && AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, format, &size) == noErr;
    pthread_mutex_unlock(&sg_outputsLock);
    return read;
}

// Inline hooks see framework and tweak calls too. Until the complete lifecycle is installed,
// even Spotify calls pass through; a partially installed hook must not acquire an output.
// MSHookFunction may patch before returning its trampoline. During that window the operation
// fails explicitly: no wait, no false success and no call to the now-patched symbol (recursion).
static atomic_bool sg_inlineReady;
#define SG_INLINE_SPOTIFY (atomic_load_explicit(&sg_inlineReady, memory_order_acquire) && \
                          SGCalledFromMainExecutable(__builtin_return_address(0)))

static OSStatus inlineSetProperty(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32);
static OSStatus inlineStartOutput(AudioUnit);
static OSStatus inlineStopOutput(AudioUnit);
static OSStatus inlineDisposeUnit(AudioComponentInstance);
enum { kInlineStop, kInlineDispose, kInlineStart, kInlineProperty };
static SGInlineHook sg_inlineHooks[] = {
    {.function = (void *)AudioOutputUnitStop, .replacement = (void *)inlineStopOutput, .original = (void **)&sg_stopOutput},
    {.function = (void *)AudioComponentInstanceDispose, .replacement = (void *)inlineDisposeUnit, .original = (void **)&sg_dispose},
    {.function = (void *)AudioOutputUnitStart, .replacement = (void *)inlineStartOutput, .original = (void **)&sg_startOutput},
    {.function = (void *)AudioUnitSetProperty, .replacement = (void *)inlineSetProperty, .original = (void **)&sg_setProperty},
};

static OSStatus inlineSetProperty(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope,
                                  AudioUnitElement element, const void *data, UInt32 size) {
    SG_AUDIO_INLINE_ORIGINAL(original, &sg_inlineHooks[kInlineProperty], __typeof__(sg_setProperty));
    return SG_INLINE_SPOTIFY ? setProperty(unit, property, scope, element, data, size)
                            : original(unit, property, scope, element, data, size);
}

static OSStatus inlineStartOutput(AudioUnit unit) {
    SG_AUDIO_INLINE_ORIGINAL(original, &sg_inlineHooks[kInlineStart], __typeof__(sg_startOutput));
    return SG_INLINE_SPOTIFY ? startOutput(unit) : original(unit);
}

static OSStatus inlineStopOutput(AudioUnit unit) {
    SG_AUDIO_INLINE_ORIGINAL(original, &sg_inlineHooks[kInlineStop], __typeof__(sg_stopOutput));
    return SG_INLINE_SPOTIFY ? stopOutput(unit) : original(unit);
}

static OSStatus inlineDisposeUnit(AudioComponentInstance unit) {
    SG_AUDIO_INLINE_ORIGINAL(original, &sg_inlineHooks[kInlineDispose], __typeof__(sg_dispose));
    return SG_INLINE_SPOTIFY ? disposeUnit(unit) : original(unit);
}

static BOOL hookInline(void) {
    if (!SGHookFunctionsInline(sg_inlineHooks, kInlineProperty)) return NO;
    SGHookFunctionInline(&sg_inlineHooks[kInlineProperty]);
    atomic_store_explicit(&sg_inlineReady, true, memory_order_release);
    SGLog(@"audio: Spotify's output reached through the jailbreak's hooks (speed %@)", sg_setProperty ? @"too" : @"not");
    return YES;
}

// Synchronous launch installation, not lazy playback work: our unconditional %ctor calls this
// before %init. AudioEffects/Haptics/Sing may get here first from their own %ctors through
// SGPlayerWatchMusicOutput. dispatch_once makes later registrations installation-free.
// Supported launch injection therefore precedes Spotify's output creation/start: there is no
// live Spotify Stop/Dispose to lose during trampoline publication. The error guard is only a
// last resort for foreign callers; late injection into an already-playing process is unsupported.
static void rebind(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mach_timebase_info_data_t timebase;
        mach_timebase_info(&timebase);
        sg_secondsPerTick = (double)timebase.numer / timebase.denom / 1e9;
        sg_outputsQueue = dispatch_queue_create("spotifyglass.outputs", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0));
        // Choose one installation mechanism, so a writable speed slot cannot take over before
        // a read-only lifecycle slot fails. Non-jailbroken installs keep the original rebind path.
        if (SGJailbroken()) {
            sg_reachable = hookInline();
            if (!sg_reachable) SGLog(@"audio: the jailbreak's output hooks did not all take, its output cannot be reached");
            else if (!sg_setProperty) SGLog(@"redesign speed: AudioUnitSetProperty could not be hooked, the menu offers pitch only");
            return;
        }
        if (!SGRebindImport("AudioUnitSetProperty", setProperty, (void **)&sg_setProperty) || !sg_setProperty) {
            sg_setProperty = NULL;
            SGLog(@"redesign speed: Spotify does not import AudioUnitSetProperty, the menu offers pitch only");
        }
        sg_reachable = SGRebindImport("AudioOutputUnitStart", startOutput, (void **)&sg_startOutput) && sg_startOutput;
        if (!sg_reachable) {
            SGLog(@"audio: Spotify does not import AudioOutputUnitStart, its output cannot be reached");
            return;
        }
        if (!SGRebindImport("AudioOutputUnitStop", stopOutput, (void **)&sg_stopOutput) || !sg_stopOutput) sg_stopOutput = AudioOutputUnitStop;
        if (!SGRebindImport("AudioComponentInstanceDispose", disposeUnit, (void **)&sg_dispose) || !sg_dispose) {
            sg_dispose = AudioComponentInstanceDispose;
            SGLog(@"audio: Spotify does not import AudioComponentInstanceDispose, a disposed output is not seen");
        }
    });
}

BOOL SGPlayerWatchMusicOutput(SGPlayerOutputWatcher watcher) {
    rebind();
    pthread_mutex_lock(&sg_outputsLock);
    for (int i = 0; i < kMaxWatchers; i++) {
        if (sg_watchers[i]) continue;
        sg_watchers[i] = watcher;
        break;
    }
    pthread_mutex_unlock(&sg_outputsLock);
    return sg_reachable;
}

#pragma mark - Spotify's clock


%hook SPTPlayerState
- (double)playbackSpeed {
    double speed = %orig;
    float ours = loadFloat(&sg_speedBits);
    return ours > 0 && ours != 1 ? speed * ours : speed;
}

- (double)position {
    if (sg_correcting) return %orig;
    sg_correcting = YES;
    double position = %orig;
    sg_correcting = NO;
    sg_spotifyPosition = position;
    if (position < 0) return position;
    double played = playedSeconds();
    CFAbsoluteTime stamp = self.timestamp.timeIntervalSinceReferenceDate;
    // Spotify's own, from the position it counted: Sing's positionAsOfTimestamp has its lead taken off, which
    // turning Sing on or off would show as a seek.
    double speed = self.isPaused ? 0 : self.playbackSpeed, asOf = position - (CFAbsoluteTimeGetCurrent() - stamp) * speed;
    NSString *track = nil;
    double lead = 0, held = 0;
    os_unfair_lock_lock(&sg_clockLock);
    // Keep the lock on the idle path: a newly started clock must never see an unread track.
    // Only the active path needs Spotify and Sing's readers, which may reenter this hook.
    if (sg_clock.on || sg_clock.armed) {
        os_unfair_lock_unlock(&sg_clockLock);
        track = trackOf(self);
        lead = leadOfState(self);
        held = heldLeadNow();
        os_unfair_lock_lock(&sg_clockLock);
    }
    BOOL seeked = NO;
    if (stamp > sg_lastReport.stamp) {
        if (sg_lastReport.stamp > sg_speedChangedAt) seeked = fabs(asOf - (sg_lastReport.asOf + (stamp - sg_lastReport.stamp) * sg_lastReport.speed)) > kSeekGap;
        sg_lastReport = (typeof(sg_lastReport)){stamp, asOf, speed};
    }
    BOOL seekedAway = sg_clock.on && seeked;
    if (seekedAway || (sg_clock.on && ![track isEqualToString:sg_clockTrack])) {
        sg_clock = (typeof(sg_clock)){.armed = loadFloat(&sg_speedBits) != 1};
    }
    if (!sg_clock.on && sg_clock.armed && stamp >= sg_clock.notBefore) {
        sg_clock = (typeof(sg_clock)){.on = YES, .position = position - lead, .played = played, .lead = held};
        sg_clockTrack = track;
    }
    // Paused too: the paused report is as far behind. Heard is what was pulled less what Sing holds ahead of it.
    if (sg_clock.on) position = sg_clock.position + (played - sg_clock.played) - (held - sg_clock.lead) + lead;
    os_unfair_lock_unlock(&sg_clockLock);
    if (seekedAway) SGLog(@"speed: Spotify moved to %.1f s without a seek here; its clock starts over", asOf);
    return position;
}
%end

%hook SPTEsperantoPlayer
- (id)seekTo:(double)position relative:(long long)relative options:(id)options creatorTimestampPositionMs:(double)creator {
    handBack();
    return %orig;
}
- (id)skipToNextTrackWithOptions:(id)options track:(id)track loggingParams:(id)params {
    handBack();
    return %orig;
}
- (id)skipToPreviousTrackWithOptions:(id)options track:(id)track loggingParams:(id)params {
    handBack();
    return %orig;
}
- (id)stop {
    handBack();
    return %orig;
}
%end

// Away from 1x, Spotify's core cannot keep up and stalls: the driver queue empties, the mixer hands over zeros
// and the core reports speed 0 at the place it stopped, then resumes from there (notes/speed-rebuffer.md). Its
// clock is right and the own one, which counted the zeros, is ahead. Each stall report hands the clock back to
// Spotify's, and the report that resumes starts it over at the right place.
@interface SGSpeedObserver : NSObject <SGPlayerStateObserver>
@end

@implementation SGSpeedObserver
- (void)playerStateDidChange:(SPTPlayerState *)state {}
- (void)playerStateDidReport:(SPTPlayerState *)state {
    if (loadFloat(&sg_speedBits) == 1 || !state.isPlaying || state.isPaused) return;
    BOOL buffering = [state respondsToSelector:NSSelectorFromString(@"isBuffering")] && [[state valueForKey:@"isBuffering"] boolValue];
    if (buffering || state.playbackSpeed == 0) rearmClock();
}
@end

%ctor {
    storeFloat(&sg_speedBits, 1);
    storeFloat(&sg_sleepLevelBits, 1);
    rebind();
    %init;
    SGRequireClasses(@[@"SPTPlayerState"]);
    dispatch_async(dispatch_get_main_queue(), ^{
        static SGSpeedObserver *observer;
        observer = [SGSpeedObserver new];
        SGAddPlayerStateObserver(observer);
    });
}

#if SG_DRIVER
bool SGPlayerAnchorRead(SGAnchorSample *latest, unsigned *dropped) {
    bool found = false;
    *dropped = 0;
    for (unsigned i = 0; i < kMaxOutputs; ++i) {
        SGAnchorSample sample;
        while (SGAnchorPop(&sg_outputs[i].anchor, &sample)) {
            if (!found || sample.host >= latest->host) *latest = sample;
            found = true;
        }
        *dropped += atomic_load_explicit(&sg_outputs[i].anchor.dropped, memory_order_relaxed);
    }
    return found;
}

double SGPlayerAnchorLatency(bool *engaged) {
    pthread_mutex_lock(&sg_buildLock);
    *engaged = atomic_load(&sg_engaged);
    SGTimePitch *unit = atomic_load(tapped() ? &sg_pull : &sg_inPlace);
    double latency = *engaged && unit ? SGTimePitchLatency(unit) : 0;
    pthread_mutex_unlock(&sg_buildLock);
    return latency;
}
#endif
