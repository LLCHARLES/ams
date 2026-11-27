// The audio quality badge, under either look: the quality of the song playing, the way the Music app's Lossless
// badge sits centered under the progress bar, between the two times, and a tap on it shows the details in a popover
// (AudioQuality.x; the rules are AudioQualityRules.m).
//
// What it says is Spotify's own report for the file it plays (SPTPlayerState's playbackQuality, bitrateLevel),
// read from every player report (SGPlayerStateObserver's playerStateDidReport:), since a quality that changes
// within a song does not change the state's track. Never the quality the user asked for or the highest available.
// Lossless files of the mod's own (Shared/Lossless) are not claimed: the badge says what Spotify streams.
//
// Each look places it from its DurationElementUnit's layout (Native/Player/Player.x through SGAudioQualityPlaceBadge,
// Redesigned/Player/PlayerControls.x through SGAudioQualityPlaceRedesignedBadge). The badge is a subview of the unit's
// view, so the unit's alpha, transforms and hiding carry over, and it takes no part in Spotify's layout, so the times
// and the slider stay where they are.
//
// The two looks word and place it differently. The native look's: Spotify's names of the tiers, a glyph before the
// lossless ones only, centered on the times' middle, and details of rows (tier, sample rates, resampled, source). The
// redesign's, as the Music app draws its own: a waveform before every tier, the Music app's words ("High Quality",
// SGAudioTierBadgeName), its text on the times' baseline, and details as one summary (SGAudioTierRateText,
// SGAudioTierSummary, SGAudioTierFootnote) under the glyph and the tier.
#import <UIKit/UIKit.h>
#import "AudioQualityRules.h"

// Audio quality on the Player page, under either look: off until switched on, followed at once.
#define SGKeyPlayerAudioQuality @"spotifyglass.player.audioQuality"
// After the Player page's switch has stored the key: the open player follows.
void SGAudioQualitySettingChanged(void);

// Main thread. Centers the badge between `unitView`'s two times, on their middle, while the switch is on and Spotify
// reports a tier for a song playing here; hides it while the scene is landscape, while the times are hidden and where
// it does not fit between them. Returns at once while the switch is off; nothing is added to a unit while there is
// nothing to show.
void SGAudioQualityPlaceBadge(UIView *unitView);
// The same for the redesign's badge, whose text stands on the times' baseline, and which an iPad shows in landscape
// too. `timesDrop` is how far the redesign lowers the times at rest by a translation of theirs, which the badge
// follows; a scrub's further drop it does not.
void SGAudioQualityPlaceRedesignedBadge(UIView *unitView, CGFloat timesDrop);
// The badge in `unitView` while it draws (shown, and neither it nor any view above it hidden or faded out), else nil:
// a tap there is the badge's, not a seek.
// The redesign's ink and fill alphas for the badge's text, glyph and capsule, and whether plusL carries them (NO: they
// are plain whites already worked out for what is behind). Redrawn when they change; no badge, no effect.
void SGAudioQualitySetRedesignedInk(UIView *unitView, CGFloat ink, CGFloat fill, BOOL plusL);
// The ink and fill the redesign's badge has over a dark backdrop, which a light one raises.
CGFloat SGAudioQualityStandardInk(void);
CGFloat SGAudioQualityStandardFill(void);
UIView *SGAudioQualityShownBadge(UIView *unitView);
