// The redesigned player's hookup of the gestures (Shared/Gestures): the double tap goes on the player's artwork list.
//
// Tree (trees/now-playing.txt): the artwork sits in AccessibleCollectionView, a full screen list of the
// queue scrolled sideways, so the recognizer goes on that and the grid is the screen. Spotify's controls
// are sibling units rather than children of it, so a tap on a button never reaches it.
//
// The redesign draws its own cover (PlayerArtwork.x) and hides Spotify's list of covers under a mask.
// A mask leaves hit testing alone, so the list still takes the swipe that changes track and the double
// tap still lands on it. But the tilt view's frame is Spotify's own, from a band the redesign no longer
// draws its cover in, so a tap in the middle of the drawn cover need not reach a tilt view at all while
// the empty room beside it does: the middle opened nothing, the room beside it opened the full screen
// cover. The drawn cover's own rect answers instead, in this list's coordinates -- a rect of pure
// geometry, which cannot stand a pass behind what the eye sees. A tap on it is handed to a tilt view so
// its recognizer opens Spotify's full screen cover; a tap past it is answered by the view the tilt sits
// in, which opens nothing. No frame is moved here.
#import "Core/SGCore.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Player/PlayerSettings.h"
#import "Player.h"

static Class sg_tiltClass;
static char kTiltKey;

static Class tiltClass(void) {
    if (!sg_tiltClass) sg_tiltClass = NSClassFromString(@"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView");
    return sg_tiltClass;
}

static UIView *tiltOf(UIView *view) {
    Class cls = tiltClass();
    if (!cls) return nil;
    for (UIView *v = view; v; v = v.superview) if ([v isKindOfClass:cls]) return v;
    return nil;
}

// A tilt to answer a tap on the drawn cover with when the list's own hit test came back with none: the
// cover is drawn higher than Spotify's band, so its top can lie outside every tilt's frame. Remembered
// weakly on the list and looked for again once it leaves, so a reused cell is not kept and every touch
// does not walk the whole tree.
static UIView *tiltIn(UIView *list) {
    Class cls = tiltClass();
    if (!cls) return nil;
    return SGFindRemembered(list, &kTiltKey, ^BOOL(UIView *v) { return [v isKindOfClass:cls]; });
}

// A single tap on the cover is Spotify's way into the full screen cover, the artwork alone in 3D, where
// it turns a little with the phone. The switch hides it, and the zones take the tap while they are on so
// a double tap does not open it on the way. Under either look this is the only thing that opens it.
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
    UIView *hit = %orig;
    UIView *cover = SGRPlayerCoverList();
    // Hidden for a flying stand-in or for the lyrics, the cover is not what the eye sees either, so the
    // list's own answer stands. Otherwise its rect, with the paused shrink taken in, is the cover on
    // screen: read in this list's coordinates, the same ones the point came in.
    if (!cover || !cover.window || cover.alpha < 0.01) return hit;
    CGRect drawn = [cover convertRect:cover.bounds toView:(UIView *)self];
    if (CGRectIsNull(drawn) || CGRectIsEmpty(drawn)) return hit;
    UIView *hitTilt = tiltOf(hit);
    if (CGRectContainsPoint(CGRectInset(drawn, -1, -1), point)) {
        // Answered with the tilt view whole, whatever lies inside it: the tap that opens the inspection
        // is the tilt's own, and a touch handed deeper to the cover's image view did not open it on the
        // phone. A point on the corner's drawn edge is on the cover: the rect is whole points, a touch is not.
        UIView *answer = hitTilt ?: tiltIn((UIView *)self);
        return answer ?: hit;
    }
    // The tilt's frame reaches past the drawn cover: the view it sits in answers, and no recognizer of
    // the tilt's runs, so the room beside the cover does not open the full screen cover.
    if (hitTilt) return hitTilt.superview ?: hit;
    return hit;
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
