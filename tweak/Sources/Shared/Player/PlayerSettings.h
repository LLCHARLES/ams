// Settings of the player that hold for either look.
#import <UIKit/UIKit.h>
#import "Core/SGPrefs.h"
#import "Core/SGUIMode.h"

UIViewController *SGLockScreenWidgetPage(void);
@class SGModRow, SGModSection;
SGModSection *SGPlaybackRulesSection(SGModRow *blockedArtists, SGModRow *blockedSongs);

// YES hides Spotify's chip. With no override, only the redesigned player hides it.
#define SGKeyHideVideoSwitch @"spotifyglass.hide.videoSwitch"
#define SGVideoSwitchIdentifier @"nowplaying-npv-musicvideos-switch"
SGModRow *SGNativeVideoSwitchRow(void);
static inline BOOL SGVideoSwitchHiddenForLook(BOOL redesigned) { return SGFlag(SGKeyHideVideoSwitch, redesigned); }
static inline BOOL SGVideoSwitchHidden(void) { return SGVideoSwitchHiddenForLook(SGRedesignedUI()); }

// A tap on the player's cover opens Spotify's full screen cover unless this is on, under either look: each look's
// handleTap hook on CoverArtTiltView (PlayerGestures.x) returns before Spotify's, as it does while Gestures is on.
// Spotify's flag (cover_art_tilt_enabled) is left alone: with it off the cover has no CoverArtTiltView, which the
// redesign's cover rounding and the native look's hold to play faster hang on. Off until switched on.
#define SGKeyHideFullScreenCover @"spotifyglass.hide.fullScreenCover"
