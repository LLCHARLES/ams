// The redesigned player's hookup of the gestures (Shared/Gestures): the double tap goes on the player's artwork list.
//
// Tree (trees/now-playing.txt): the artwork sits in AccessibleCollectionView, a full screen list of
// the queue scrolled sideways, so the recognizer goes on that and the grid is the screen. Spotify's
// controls are sibling units rather than children of it, so a tap on a button never reaches it.
#import "Core/SGCore.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Player/PlayerSettings.h"
#import "Player.h"

// The title row is lifted to the Music app's place, above the bottom stack it is arranged in. UIKit
// stops looking at a view whose bounds the touch is not in, so a tap on the title, the star or the ...
// fell through to the cover's cell behind it and opened the full screen cover -- whatever the switch
// said, that being the cell's own tap and not the tilt view's handleTap. Asked by the list and the tilt
// view before either takes a touch, the row answers for where it is drawn (PlayerLyrics.x): its own
// buttons take the tap, and the cover never opens from there. A tap past the row is left to Spotify.
//
// A single tap on the cover is Spotify's way into the tilt mode, the artwork alone in 3D. That is
// the half of a double tap that misses, so while the zones are on it would open on the way to every
// gesture; the tap goes back to Spotify with the switch. Full screen cover hidden keeps it from Spotify too.
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {
    if (SGFlag(SGKeyGestures, NO) || SGHidden(SGKeyHideFullScreenCover)) return;
    %orig;
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
