// Shared/Haptics/ControlHaptics.x: the artist hold's feedback, which the harness does not play.
#import "Shared/Haptics/Haptics.h"
#import "../album/motion-player-double.h"
void SGPlayFeedback(SGFeedback feedback) {}

// Redesigned/Kit/SGRAccentContext.m: the accent in effect, which main.m changes while the add button stays saved; nil is
// Spotify's green (SGRTokens.m).
UIColor *harnessAccent;
UIColor *SGRAccentColor(void) { return harnessAccent; }

// The rest of the page harnesses' stubs (../shared/redesigned-page-stubs.m, ../playlist/stubs.m), without their fixed
// accent: no repaint hooks, player transitions, album queue menu, or presenter above the window's root.
__weak UIView *sgr_nowPlayingRoot = nil;
NSHashTable<UIView *> *sgr_nowPlayingPainted = nil;
__weak UIView *sgr_lyricsCardRoot = nil;
__weak UIView *sgr_lyricsPageRoot = nil;
__weak UIView *sgr_playlistRoot = nil;
__weak UIView *sgr_albumRoot = nil;
__weak UIView *sgr_artistRoot = nil;
BOOL SGRPlayerIsTransitioning(void) { return NO; }
void SGRObservePlayerTransition(id owner, void (^changed)(id owner)) {}
void SGAlbumQueueMarkSource(UIView *view) {}
UIViewController *SGTopController(void) {
    UIWindowScene *scene = (UIWindowScene *)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIViewController *top = scene.windows.firstObject.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}
