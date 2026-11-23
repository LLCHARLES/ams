// Player redesign: AutoMix's transitions shown in the player, from the Shared facts about the coming blend
// (Shared/AutoMix/SGTransitionFacts.h), each under its option on the AutoMix page (Shared/AutoMix/AutoMixPreview.h):
//
//     the progress bar  the outgoing window as a lighter band at the end of the song, and once the next song has
//                       come, its incoming window at its start until playback passes it (PlayerControls.x hands
//                       over the slider)
//     the queue         the kind of the next blend over Playing Next's first row (PlayerQueue.m)
//     the cover         both songs on one stage during the overlap, then the cover back (PlayerArtwork.x lends it)
//
// The band and the stage need the windows' times (`timesKnown`); the queue shows the kind whenever facts exist.
// Only the playing -> next pair has facts, so only the first row is annotated.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Player/PlayerState.h"

// Whether `track` is the facts' song `uri`: the same URI and, where both carry one, the same queue UID.
BOOL SGRMixTrackIs(SPTPlayerTrack *track, NSString *uri, NSString *uid);
// Transitions in the queue, as the AutoMix page last stored it.
BOOL SGRMixShowsQueue(void);
// A progress bar's slider laid out (PlayerControls.x): its own bands, put into it once, follow the facts and its
// bounds and are placed again only when either changed; a hidden slider does nothing.
void SGRPlayerMixSliderLaidOut(UISlider *slider);
// A cover became ready after the field; resume a stage waiting without an arm timer.
void SGRPlayerMixCoverLaidOut(void);

// The cover `track`'s metadata names, fetched (cached by the URL session) and decoded for display off main: the largest
// for AutoMix's stage, a thumbnail's (Playing Next's rows, PlayerQueue.m) when `small`. `done` runs on main with the
// image, nil when the metadata names none (then at once, and nothing is returned) or it did not come. Cancelling the
// returned progress stops the download and the decoding where they are, and `done` is then never called.
NSProgress *SGRPlayerTrackCover(SPTPlayerTrack *track, BOOL small, void (^done)(UIImage *image));

#pragma mark - the cover's stage (PlayerArtwork.x)

// Puts `stage` over the cover on screen, at its place and scale, and hides the cover while its shadow stays; nil
// takes the stage away and hands the cover back. NO, with nothing changed, when no cover is on screen. A cover the
// morph also hides (SGRPlayerSetCoverHidden) comes back only once neither holds it.
BOOL SGRPlayerStageCover(UIView *stage);
