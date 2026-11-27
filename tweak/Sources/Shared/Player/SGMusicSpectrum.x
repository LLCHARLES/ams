// The music's spectrum in three bands (SGMusicSpectrum.h).
#import <Accelerate/Accelerate.h>
#import <AudioToolbox/AudioToolbox.h>
#import <stdatomic.h>
#import <os/lock.h>
#import "Core/SGCore.h"
#import "Shared/Player/SpeedPitch.h"
#import "Shared/Player/SGPCMRead.h"
#import "SGMusicSpectrum.h"

// The buffers are taken whole, unwindowed, mono, at 48 kHz: 30 readings a second asked for, 48000 / 30 rounded up
// to a power of two, gives 2048 frames, 23.4 readings a second. Spotify's output at another rate is resampled to 48 kHz first.
enum { kLog2N = 11, kN = 1 << kLog2N, kHalf = kN / 2, kBands = 3 };
static const double kTapRate = 48000;
// Each level is scaled by this intensity after being held to 0 to 1, which matched the Music app's backdrop.
static const float kIntensity = 0.2f;
// The Music app's bands, in hertz: each a lower and an upper edge (a bin counts when lower < its frequency <= upper).
static const float kBandEdge[kBands][2] = {{20, 300}, {300, 3500}, {3500, 24000}};
// The readings kept for a reader that has fallen behind: it takes each one, as the Music app's backdrop takes each
// report its main queue is handed.
enum { kKept = 16 };

static atomic_bool sg_wanted;
static atomic_bool sg_fresh;                     // the next buffer starts a new frame, as a tap started anew does
static _Atomic uint64_t sg_layout;              // format flags | channels << 32 | bytes << 48, 0 for none
static _Atomic uint64_t sg_sampleRateBits;
static _Atomic uint32_t sg_levelBits[kKept][kBands];
static _Atomic uint64_t sg_readings;            // how many readings there have been; bumped after each is stored

// Render-thread state: only the notify touches it, under the output's admission.
static FFTSetup sg_fft;
static float sg_frame[kN], sg_real[kHalf], sg_imag[kHalf], sg_power[kHalf];
static UInt32 sg_fill;

// The resampler to 48 kHz: windowed sinc, kTaps a side, its kernel tabled in kPhases steps between samples for the
// rate it was made for.
enum { kTaps = 16, kPhases = 256, kHeld = 64 };
static float sg_kernel[kPhases + 1][2 * kTaps];
static double sg_kernelRate;
static os_unfair_lock sg_kernelLock = OS_UNFAIR_LOCK_INIT;
static dispatch_queue_t sg_kernelQueue;
static float sg_held[kHeld];                    // the latest input samples, a ring
static uint64_t sg_heard;                       // input samples heard since the frame began
static double sg_next;                          // where the next 48 kHz sample falls, in input samples

static double besselI0(double x) {
    double sum = 1, term = 1;
    for (int k = 1; k < 32; k++) {
        term *= (x / (2 * k)) * (x / (2 * k));
        sum += term;
    }
    return sum;
}

static void makeKernel(double rate) {
    // Only this serial queue writes the kernel. Publish the complete table; a
    // render racing publication drops analysis, never waits for preparation.
    if (rate == sg_kernelRate || !atomic_load(&sg_wanted)) return;
    float kernel[kPhases + 1][2 * kTaps];
    double cutoff = MIN(1.0, kTapRate / rate) * 0.97, beta = 8;
    for (int p = 0; p <= kPhases; p++) {
        double fraction = (double)p / kPhases;
        for (int k = 0; k < 2 * kTaps; k++) {
            double d = (k - (kTaps - 1)) - fraction;   // tap k is input sample floor(position) - (kTaps - 1) + k
            double x = M_PI * cutoff * d;
            double sinc = fabs(d) < 1e-9 ? 1 : sin(x) / x;
            double r = d / kTaps;
            double window = fabs(r) >= 1 ? 0 : besselI0(beta * sqrt(1 - r * r)) / besselI0(beta);
            kernel[p][k] = (float)(cutoff * sinc * window);
        }
    }
    os_unfair_lock_lock(&sg_kernelLock);
    memcpy(sg_kernel, kernel, sizeof kernel);
    sg_kernelRate = rate;
    os_unfair_lock_unlock(&sg_kernelLock);
}

static double loadDouble(_Atomic uint64_t *bits) {
    uint64_t raw = atomic_load_explicit(bits, memory_order_relaxed);
    double value;
    memcpy(&value, &raw, sizeof value);
    return value;
}

static void storeDouble(_Atomic uint64_t *bits, double value) {
    uint64_t raw;
    memcpy(&raw, &value, sizeof raw);
    atomic_store_explicit(bits, raw, memory_order_relaxed);
}

// One full frame, as the Music app's analyzer reads it: the power of each bin (unscaled, the first holding the DC and
// Nyquist terms) as a share of the whole, summed over each band, then scaled by the whole's loudness, 20 log10 of it
// over 120, held to 0 to 1, and scaled by the backdrop's intensity.
static void analyze(void) {
    DSPSplitComplex split = {sg_real, sg_imag};
    vDSP_ctoz((const DSPComplex *)sg_frame, 2, &split, 1, kHalf);
    vDSP_fft_zrip(sg_fft, &split, 1, kLog2N, kFFTDirection_Forward);
    vDSP_zvmags(&split, 1, sg_power, 1, kHalf);
    float total = 0;
    vDSP_sve(sg_power, 1, &total, kHalf);
    if (!(total > 0)) return;
    float loudness = 20 * log10f(total) / 120;
    float shares[kBands] = {0};
    for (int k = 0; k < kHalf; k++) {
        float frequency = (float)(k * kTapRate / kN);
        for (int b = 0; b < kBands; b++) {
            if (frequency > kBandEdge[b][0] && frequency <= kBandEdge[b][1]) shares[b] += sg_power[k] / total;
        }
    }
    uint64_t reading = atomic_load_explicit(&sg_readings, memory_order_relaxed);
    for (int b = 0; b < kBands; b++) {
        uint32_t bits;
        float level = MIN(1.0f, MAX(0.0f, shares[b] * loudness)) * kIntensity;
        memcpy(&bits, &level, sizeof bits);
        atomic_store_explicit(&sg_levelBits[reading % kKept][b], bits, memory_order_relaxed);
    }
    atomic_store_explicit(&sg_readings, reading + 1, memory_order_release);
}

// A 48 kHz sample into the frame, analyzed when it fills.
static void hear(float sample) {
    sg_frame[sg_fill++] = sample;
    if (sg_fill == kN) {
        analyze();
        sg_fill = 0;
    }
}

// An input sample at `rate`, resampled to 48 kHz unless it is that already.
static void take(float sample, double rate) {
    if (rate == kTapRate) {
        hear(sample);
        return;
    }
    if (sg_heard == 0) sg_next = kTaps - 1;
    sg_held[sg_heard % kHeld] = sample;
    sg_heard++;
    double step = rate / kTapRate;
    while (sg_next + kTaps < (double)sg_heard) {
        uint64_t whole = (uint64_t)sg_next;
        double fraction = (sg_next - whole) * kPhases;
        int phase = (int)fraction;
        float mix = (float)(fraction - phase), out = 0;
        const float *a = sg_kernel[phase], *b = sg_kernel[phase + 1];
        for (int k = 0; k < 2 * kTaps; k++) {
            float x = sg_held[(whole - (kTaps - 1) + k) % kHeld];
            out += x * (a[k] + mix * (b[k] - a[k]));
        }
        hear(out);
        sg_next += step;
    }
}

// `refCon` is the unit; only the music's output is heard, mixed to mono.
static OSStatus rendered(void *refCon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *timestamp, UInt32 bus,
                         UInt32 frames, AudioBufferList *data) {
    if (!(*flags & kAudioUnitRenderAction_PostRender) || bus != 0 || !data || !data->mNumberBuffers || !frames) return noErr;
    if (!atomic_load_explicit(&sg_wanted, memory_order_relaxed) || !sg_fft) return noErr;
    if (*flags & kAudioUnitRenderAction_OutputIsSilence) return noErr;
    if (!SGPlayerBeginProcessing((AudioUnit)refCon)) return noErr;
    uint64_t layout = atomic_load_explicit(&sg_layout, memory_order_relaxed);
    UInt32 formatFlags = (UInt32)layout, channels = (UInt32)(layout >> 32) & 0xffff, bytes = (UInt32)(layout >> 48);
    bool isFloat = (formatFlags & kAudioFormatFlagIsFloat) != 0;
    bool split = (formatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    UInt32 fraction = (formatFlags & kLinearPCMFormatFlagsSampleFractionMask) >> kLinearPCMFormatFlagsSampleFractionShift;
    double sampleRate = loadDouble(&sg_sampleRateBits);
    if ((bytes != 2 && bytes != 4) || channels < 1 || sampleRate <= 0 || !SGPCMLayoutFits(data, frames, channels, bytes, split)) {
        SGPlayerEndProcessing();
        return noErr;
    }
    if (atomic_exchange_explicit(&sg_fresh, false, memory_order_relaxed)) {
        sg_fill = 0;
        sg_heard = 0;
    }
    BOOL resample = sampleRate != kTapRate;
    if (resample) {
        BOOL locked = os_unfair_lock_trylock(&sg_kernelLock);
        if (!locked || sg_kernelRate != sampleRate) {
            if (locked) os_unfair_lock_unlock(&sg_kernelLock);
            sg_fill = 0;
            sg_heard = 0;
            SGPlayerEndProcessing();
            return noErr;
        }
    }
    const void *left = data->mBuffers[0].mData, *right = split && channels > 1 ? data->mBuffers[1].mData : left;
    UInt32 stride = split ? 1 : channels, rightOffset = !split && channels > 1 ? 1 : 0;
    for (UInt32 i = 0; i < frames; i++) {
        UInt32 at = i * stride;
        take(0.5f * (SGPCMReadSample(left, at, bytes, isFloat, fraction) + SGPCMReadSample(right, at + rightOffset, bytes, isFloat, fraction)), sampleRate);
    }
    if (resample) os_unfair_lock_unlock(&sg_kernelLock);
    SGPlayerEndProcessing();
    return noErr;
}

// The output's format, the hardware side the notify's buffers are in; a format it cannot read leaves them alone.
static void readFormat(AudioUnit unit) {
    AudioStreamBasicDescription format = {0};
    UInt32 size = sizeof format;
    OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, &size);
    UInt32 bytes = format.mBitsPerChannel / 8;
    BOOL takes = status == noErr && format.mFormatID == kAudioFormatLinearPCM && format.mSampleRate > 0 && format.mChannelsPerFrame >= 1
                 && (bytes == 2 || bytes == 4) && ((format.mFormatFlags & kAudioFormatFlagIsFloat) || (format.mFormatFlags & kAudioFormatFlagIsSignedInteger));
    if (!takes) {
        atomic_store(&sg_layout, 0);
        return;
    }
    storeDouble(&sg_sampleRateBits, format.mSampleRate);
    double rate = format.mSampleRate;
    if (rate != kTapRate) dispatch_async(sg_kernelQueue, ^{ makeKernel(rate); });
    atomic_store(&sg_layout, (uint64_t)format.mFormatFlags | (uint64_t)(format.mChannelsPerFrame & 0xffff) << 32 | (uint64_t)bytes << 48);
}

static void listenTo(AudioUnit unit) {
    // Watchers are serialized by the output lock, before disposal of the old unit.
    static AudioUnit attached;
    if (attached) AudioUnitRemoveRenderNotify(attached, rendered, attached);
    attached = NULL;
    atomic_store(&sg_fresh, true);
    if (!unit || !SGPlayerMusicOutputRunning()) return;
    readFormat(unit);
    OSStatus status = AudioUnitAddRenderNotify(unit, rendered, unit);
    if (status != noErr) SGLog(@"music spectrum: the render notify could not be added (%d)", (int)status);
    else attached = unit;
}

static NSUInteger sg_readers;
static BOOL sg_registered;

void SGMusicSpectrumAddReader(void) {
    if (sg_readers++ != 0) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sg_fft = vDSP_create_fftsetup(kLog2N, kFFTRadix2);
        sg_kernelQueue = dispatch_queue_create("spotifyglass.fluid.kernel", DISPATCH_QUEUE_SERIAL);
    });
    atomic_store(&sg_wanted, true);
    sg_registered = sg_fft && SGPlayerSetDemandWatcher(listenTo, YES);
    if (!sg_registered) {
        atomic_store(&sg_wanted, false);
        SGLog(@"music spectrum: analyzer or disposal-safe output watcher unavailable");
    }
}

void SGMusicSpectrumRemoveReader(void) {
    if (--sg_readers != 0) return;
    atomic_store(&sg_wanted, false);
    if (sg_registered) SGPlayerSetDemandWatcher(listenTo, NO);
}

uint64_t SGMusicSpectrumReadings(void) {
    return atomic_load_explicit(&sg_readings, memory_order_acquire);
}

BOOL SGMusicSpectrumReading(uint64_t index, float levels[3]) {
    uint64_t readings = atomic_load_explicit(&sg_readings, memory_order_acquire);
    if (index >= readings || readings - index > kKept / 2) return NO;
    for (int b = 0; b < kBands; b++) {
        uint32_t bits = atomic_load_explicit(&sg_levelBits[index % kKept][b], memory_order_relaxed);
        memcpy(&levels[b], &bits, sizeof bits);
    }
    return YES;
}
