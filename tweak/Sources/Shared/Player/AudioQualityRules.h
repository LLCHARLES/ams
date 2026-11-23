// The audio quality badge's rules, Foundation only so harness/player can run them on the Mac
// (upcoming-tracks-check.sh, audio-quality-check.m): what Spotify's playback quality says, put in its own names.
//
// SPTPlaybackQuality (SPTPlayerState's playbackQuality, Spotify 9.1.90) reports bitrateLevel 0 unknown, 1 low,
// 2 normal, 3 high, 4 very_high, 5 hifi, 6 hifi_24 and 7 petrel, whose meaning is unknown, and strategy 1
// best_matching, 2 backend_advised, 3 offlined_file, 4 cached_file and 5 local_file.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SGAudioTier) {
    SGAudioTierNone,
    SGAudioTierLow,
    SGAudioTierNormal,
    SGAudioTierHigh,
    SGAudioTierVeryHigh,
    SGAudioTierLossless,
    SGAudioTierLossless24,
};

typedef NS_ENUM(NSInteger, SGAudioSource) {
    SGAudioSourceUnknown,
    SGAudioSourceStreamed,
    SGAudioSourceDownloaded,
    SGAudioSourceCached,
    SGAudioSourceLocalFile,
};

// The tier of the file playing, from bitrateLevel; None for unknown, petrel and anything newer.
SGAudioTier SGAudioTierForBitrateLevel(long long bitrateLevel);
SGAudioSource SGAudioSourceForStrategy(long long strategy);
// What the badge shows: None while the switch is off, while another device plays, for anything but a Spotify
// song (a podcast, an ad, a local file) and for a level that names no tier.
SGAudioTier SGAudioTierShown(BOOL on, BOOL playingLocally, NSString *trackURI, long long bitrateLevel);
// Lossless tiers draw the lossless glyph; the lossy ones are their name alone.
BOOL SGAudioTierIsLossless(SGAudioTier tier);
// Spotify's own names (HiFi_DevicePickerIntegrationImpl's sLosslessStreamingQualityLabel,
// sLossless24StreamingQualityLabel, sVeryHighStreamingQualityLabel and on), nil for None.
NSString *SGAudioTierName(SGAudioTier tier);
// The redesign's badge words, the Music app's way: "High Quality", and Very high "Highest Quality" (Spotify's lossy
// 320 kbps, not lossless); the lossless tiers keep their names. nil for None.
NSString *SGAudioTierBadgeName(SGAudioTier tier);
// The redesign's details. The rate: "About 160 kbps" at Spotify's published rate for a lossy tier, a lossless one's bit
// depth over `playingHz` (44.1 kHz, Spotify's lossless rate, while it is not reported); nil for None.
NSString *SGAudioTierRateText(SGAudioTier tier, long long playingHz);
// What the tier is, in a sentence; nil for None.
NSString *SGAudioTierSummary(SGAudioTier tier);
// The footnote under it: the song playing and Spotify's own name of the tier; nil for None.
NSString *SGAudioTierFootnote(SGAudioTier tier);
// nil for Unknown.
NSString *SGAudioSourceName(SGAudioSource source);
// "44.1 kHz"; nil for a rate that is not positive.
NSString *SGAudioSampleRateText(long long hertz);

// Whether the details opened for `openedFor` still describe what plays: the same track, still a tier to show, and the
// badge they point at still shown. A skip, another device, the switch off or the badge going (the player closing, the
// times hidden) dismiss them.
BOOL SGAudioQualityDetailsStay(NSString *openedFor, NSString *playing, SGAudioTier tier, BOOL badgeShown);

// The part of UIView the visibility rule reads, so the Mac can check it without UIKit.
@protocol SGAudioQualityViewChain
- (id)superview;
- (BOOL)isHidden;
- (CGFloat)alpha;
@end
// Whether `view` draws: neither it nor any view above it is hidden or faded out (the lyrics page fades the times'
// unit, not the badge). A badge that does not draw takes no taps and leaves tap to seek alone.
BOOL SGAudioQualityViewDrawn(id<SGAudioQualityViewChain> view);
