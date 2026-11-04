// The redesigned player's hookup of the gestures (Shared/Gestures): the double tap goes on the player's artwork list.
//
// Tree (trees/now-playing.txt): the artwork sits in AccessibleCollectionView, a full screen list of the
// queue scrolled sideways, so the recognizer goes on that and the grid is the screen. Spotify's controls
// are sibling units rather than children of it, so a tap on a button never reaches it.
//
// The redesign draws its own cover (PlayerArtwork.x) and hides Spotify's list of covers under a mask.
// A mask leaves hit testing alone, so the list still takes the swipe that changes track and the double
// tap still lands on it. What must not reach it is the tap that opens Spotify's 3D inspection: the cover
// that inspection shows is Spotify's, which the player no longer draws, so the tap is swallowed here.
// The title row, lifted above the stack it is arranged in, is answered first (PlayerLyrics.x); every
// other touch is left to the list's own hit test, unchanged.
#import "Core/SGCore.h"
#import "Shared/Gestures/Gestures.h"
#import "Player.h"

// A single tap on the hidden tilt view is Spotify's way into the cover's 3D inspection, and the only
// thing that opens it. Swallowed rather than passed on: it would bring Spotify's own cover up over the
// redesign's, which is drawn from the Kit's artwork instead. Swipes and the double tap are the list's,
// and the drawn cover lets touches through to them.
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = SGRPlayerInfoRowHitIn((UIView *)self, point, event);
    if (row) return row;
    return %orig;
}
%end

%hook _TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView
- (void)layoutSubviews {
    %orig;
    SGGestureAttach((UIView *)self);
}
// No rect is rewritten here. The redesign's cover is a view of its own at a frame worked out from the
// player's bounds, so there is no tilt view standing a pass behind what it draws, and the list's own
// hit test is the right answer for every touch (the title row's lifted bounds aside).
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = SGRPlayerInfoRowHitIn((UIView *)self, point, event);
    if (row) return row;
    return %orig;
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
    ]);
}
