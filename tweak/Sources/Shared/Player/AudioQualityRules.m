#import "AudioQualityRules.h"
#import "Core/SGLocalize.h"

SGAudioTier SGAudioTierForBitrateLevel(long long bitrateLevel) {
    switch (bitrateLevel) {
        case 1: return SGAudioTierLow;
        case 2: return SGAudioTierNormal;
        case 3: return SGAudioTierHigh;
        case 4: return SGAudioTierVeryHigh;
        case 5: return SGAudioTierLossless;
        case 6: return SGAudioTierLossless24;
        default: return SGAudioTierNone;
    }
}

SGAudioSource SGAudioSourceForStrategy(long long strategy) {
    switch (strategy) {
        case 1: case 2: return SGAudioSourceStreamed;
        case 3: return SGAudioSourceDownloaded;
        case 4: return SGAudioSourceCached;
        case 5: return SGAudioSourceLocalFile;
        default: return SGAudioSourceUnknown;
    }
}

SGAudioTier SGAudioTierShown(BOOL on, BOOL playingLocally, NSString *trackURI, long long bitrateLevel) {
    if (!on || !playingLocally || ![trackURI hasPrefix:@"spotify:track:"]) return SGAudioTierNone;
    return SGAudioTierForBitrateLevel(bitrateLevel);
}

BOOL SGAudioTierIsLossless(SGAudioTier tier) {
    return tier == SGAudioTierLossless || tier == SGAudioTierLossless24;
}

NSString *SGAudioTierName(SGAudioTier tier) {
    switch (tier) {
        case SGAudioTierNone: return nil;
        case SGAudioTierLow: return SGL(@"player.audio_quality.tier.low", @"Low");
        case SGAudioTierNormal: return SGL(@"player.audio_quality.tier.normal", @"Normal");
        case SGAudioTierHigh: return SGL(@"player.audio_quality.tier.high", @"High");
        case SGAudioTierVeryHigh: return SGL(@"player.audio_quality.tier.very_high", @"Very high");
        case SGAudioTierLossless: return SGL(@"player.audio_quality.tier.lossless", @"Lossless");
        case SGAudioTierLossless24: return SGL(@"player.audio_quality.tier.lossless_24", @"Lossless 24-bit");
    }
    return nil;
}

NSString *SGAudioTierBadgeName(SGAudioTier tier) {
    switch (tier) {
        case SGAudioTierNone: return nil;
        case SGAudioTierLow: return SGL(@"player.audio_quality.badge.low", @"Low Quality");
        case SGAudioTierNormal: return SGL(@"player.audio_quality.badge.normal", @"Normal Quality");
        case SGAudioTierHigh: return SGL(@"player.audio_quality.badge.high", @"High Quality");
        case SGAudioTierVeryHigh: return SGL(@"player.audio_quality.badge.very_high", @"Highest Quality");
        case SGAudioTierLossless: case SGAudioTierLossless24: return SGAudioTierName(tier);
    }
    return nil;
}

// Spotify's published rates for its lossy tiers (support.spotify.com, Audio quality), and its lossless sample rate.
static const long kLowKbps = 24, kNormalKbps = 96, kHighKbps = 160, kVeryHighKbps = 320;
static const long long kLosslessHz = 44100;
static const long kLosslessBits = 16, kLossless24Bits = 24;

NSString *SGAudioTierRateText(SGAudioTier tier, long long playingHz) {
    long kbps = 0, bits = 0;
    switch (tier) {
        case SGAudioTierNone: return nil;
        case SGAudioTierLow: kbps = kLowKbps; break;
        case SGAudioTierNormal: kbps = kNormalKbps; break;
        case SGAudioTierHigh: kbps = kHighKbps; break;
        case SGAudioTierVeryHigh: kbps = kVeryHighKbps; break;
        case SGAudioTierLossless: bits = kLosslessBits; break;
        case SGAudioTierLossless24: bits = kLossless24Bits; break;
    }
    if (kbps) return [NSString stringWithFormat:SGL(@"player.audio_quality.about_kbps", @"About %ld kbps"), kbps];
    NSString *rate = SGAudioSampleRateText(playingHz > 0 ? playingHz : kLosslessHz);
    return [NSString stringWithFormat:SGL(@"player.audio_quality.bits_rate", @"%ld-bit/%@"), bits, rate];
}

NSString *SGAudioTierSummary(SGAudioTier tier) {
    switch (tier) {
        case SGAudioTierNone: return nil;
        case SGAudioTierLow: return SGL(@"player.audio_quality.summary.low", @"The lightest stream, made to save data.");
        case SGAudioTierNormal: return SGL(@"player.audio_quality.summary.normal", @"A balance of sound and data for everyday listening.");
        case SGAudioTierHigh: return SGL(@"player.audio_quality.summary.high", @"A higher bitrate that brings out more of the detail.");
        case SGAudioTierVeryHigh: return SGL(@"player.audio_quality.summary.very_high", @"Spotify's best compressed sound, with nearly all of the detail kept.");
        case SGAudioTierLossless: return SGL(@"player.audio_quality.summary.lossless", @"CD quality, with nothing lost to compression.");
        case SGAudioTierLossless24: return SGL(@"player.audio_quality.summary.lossless_24", @"24-bit studio sound, with nothing lost to compression.");
    }
    return nil;
}

NSString *SGAudioTierFootnote(SGAudioTier tier) {
    NSString *name = SGAudioTierName(tier);
    return name ? [NSString stringWithFormat:SGL(@"player.audio_quality.footnote", @"Playing now · Spotify %@"), name] : nil;
}

NSString *SGAudioSourceName(SGAudioSource source) {
    switch (source) {
        case SGAudioSourceUnknown: return nil;
        case SGAudioSourceStreamed: return SGL(@"player.audio_quality.source.streamed", @"Streamed");
        case SGAudioSourceDownloaded: return SGL(@"player.audio_quality.source.downloaded", @"Downloaded");
        case SGAudioSourceCached: return SGL(@"player.audio_quality.source.cached", @"Cached");
        case SGAudioSourceLocalFile: return SGL(@"player.audio_quality.source.local_file", @"Local file");
    }
    return nil;
}

BOOL SGAudioQualityDetailsStay(NSString *openedFor, NSString *playing, SGAudioTier tier, BOOL badgeShown) {
    return openedFor && [openedFor isEqualToString:playing] && tier != SGAudioTierNone && badgeShown;
}

// UIKit's own floor for a view that takes touches.
static const CGFloat kDrawnAlpha = 0.01;

BOOL SGAudioQualityViewDrawn(id<SGAudioQualityViewChain> view) {
    if (!view) return NO;
    for (id<SGAudioQualityViewChain> v = view; v; v = [v superview]) {
        if ([v isHidden] || [v alpha] < kDrawnAlpha) return NO;
    }
    return YES;
}

NSString *SGAudioSampleRateText(long long hertz) {
    if (hertz <= 0) return nil;
    // Spotify writes its own rates with a point in every language ("16-bit/44.1 kHz").
    NSString *kilohertz = hertz % 1000 == 0 ? [NSString stringWithFormat:@"%lld", hertz / 1000]
                                            : [NSString stringWithFormat:@"%.1f", hertz / 1000.0];
    return [NSString stringWithFormat:SGL(@"player.audio_quality.khz", @"%@ kHz"), kilohertz];
}
