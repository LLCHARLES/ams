// The redesigned player's hookup of the gestures (Shared/Gestures): the double tap goes on the player's artwork list.
//
// Tree (trees/now-playing.txt): the artwork sits in AccessibleCollectionView, a full screen list of
// the queue scrolled sideways, so the recognizer goes on that and the grid is the screen. Spotify's
// controls are sibling units rather than children of it, so a tap on a button never reaches it.
//
// A tap opens the cover's tilt mode (Spotify's -[CoverArtTiltView handleTap], the only thing that does), and the
// view it must reach is the cover as the player draws it, not the tilt view's frame: the tilt is moved up by a
// transform to stand where the Music app draws the cover, and a cell reused for the next track can lay its cover
// out a pass after the tilt's own, so the frame and what it draws can stand apart (PlayerArtwork.x). The cover's
// own rect decides, taken in the list's coordinates with its transforms in (SGRPlayerCoverRectIn): a tap on it
// is answered by the tilt view, so its recognizer sees the touch; a tap past it is answered by what lies there,
// never by the tilt, so the room beside the cover does not open it. No frame is moved here.
#import "Core/SGCore.h"
#import "Shared/Gestures/Gestures.h"
#import "Shared/Player/PlayerSettings.h"
#import "Player.h"

static Class sg_tiltClass;

static UIView *tiltOf(UIView *view) {
    if (!sg_tiltClass) sg_tiltClass = NSClassFromString(@"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView");
    for (UIView *v = view; v; v = v.superview) if ([v isKindOfClass:sg_tiltClass]) return v;
    return nil;
}

static NSString *recognizersIn(UIView *view) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) [names addObject:NSStringFromClass(recognizer.class)];
    return names.count ? [names componentsJoinedByString:@", "] : @"none";
}

// What the tap at `point` (in `list`'s coordinates) reached, with the points the hit test is judged by: the
// window's, the tilt's and the cover's, so a phone that opens the tilt from the wrong place says where the
// cover was drawn and which view took the touch.
static void logTap(UIView *list, CGPoint point, UIView *tilt, CGRect cover, UIView *hit, UIView *answer) {
    static NSUInteger taps;
    if (taps++ >= 40) return;
    UIWindow *window = list.window;
    CGPoint windowPoint = window ? [window convertPoint:point fromView:list] : point;
    CGPoint inTilt = [tilt convertPoint:point fromView:list];
    UIView *cell = nil;
    for (UIView *v = tilt; v && !cell; v = v.superview) if ([v isKindOfClass:UICollectionViewCell.class]) cell = v;
    CGPoint inCell = cell ? [cell convertPoint:point fromView:list] : CGPointZero;
    CGRect drawn = window ? [window convertRect:cover fromView:list] : cover;
    CGRect tiltFrame = window ? [window convertRect:tilt.bounds fromView:tilt] : tilt.frame;
    SGLog(@"redesign player: tap %.1f,%.1f (window), %.1f,%.1f (list); cover %@ drawn in the window%@; in the tilt %.1f,%.1f%@; in the cell %.1f,%.1f; tilt %@ at %@ transform %@, recognizers %@; hit %@; answered %@",
          windowPoint.x, windowPoint.y, point.x, point.y, NSStringFromCGRect(drawn),
          CGRectContainsPoint(cover, point) ? @" (on it)" : @" (beside it)",
          inTilt.x, inTilt.y, CGRectContainsPoint(tilt.bounds, inTilt) ? @" (inside)" : @" (outside)",
          inCell.x, inCell.y, NSStringFromClass(tilt.class), NSStringFromCGRect(tiltFrame),
          NSStringFromCGAffineTransform(tilt.transform), recognizersIn(tilt),
          hit ? NSStringFromClass(hit.class) : @"nothing", answer ? NSStringFromClass(answer.class) : @"nothing");
}

// A single tap on the cover is Spotify's way into the tilt mode, the artwork alone in 3D. That is
// the half of a double tap that misses, so while the zones are on it would open on the way to every
// gesture; the tap goes back to Spotify with the switch. Full screen cover hidden keeps it from Spotify too.
%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)handleTap {
    if (SGFlag(SGKeyGestures, NO) || SGHidden(SGKeyHideFullScreenCover)) return;
    %orig;
}

// The title row is lifted to the Music app's place, above the bottom stack it is arranged in, and the cover's
// full screen cell is behind the stack: a tap on the title, the star or the ⋯ was past the stack's bounds and
// the cover took it, opening the tilt mode. The row answers first for where it is drawn (PlayerLyrics.x); the
// cover keeps every other touch, so tapping it still opens its inspection.
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

// The cover's own rect answers, not the tilt view's frame: the tilt is a pass behind what it draws on a cell
// the next track reused, and its frame then stands over the room below the cover, which opened the tilt mode
// from there while the cover itself did not (the phone's report). A tap on the drawn cover is handed to the
// tilt view so Spotify's recognizer sees it; a tap that only the tilt's frame reaches is handed to the view
// the tilt sits in, which opens nothing. Swipes still start inside the list either way.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *row = SGRPlayerInfoRowHitIn((UIView *)self, point, event);
    if (row) return row;
    UIView *hit = %orig;
    UIView *hitTilt = tiltOf(hit);
    UIView *tilt = hitTilt ?: SGRPlayerCoverTilt();
    if (!tilt) return hit;
    CGRect cover = SGRPlayerCoverRectIn(tilt, (UIView *)self);
    if (CGRectIsNull(cover)) return hit;
    // A point on the corner's drawn edge is on the cover: the rect is whole points and a touch is not.
    BOOL onCover = CGRectContainsPoint(CGRectInset(cover, -1, -1), point);
    UIView *answer = hit;
    if (onCover) {
        // Asked of the tilt view's own tree, not answered with the tilt whole: the tap that opens the inspection
        // is a recognizer on the tilt view, which takes a touch its subtree answers, and one on a view inside it
        // would miss a touch answered above it. The point can be inside the tilt but over the cover's edge only.
        CGPoint inTilt = [tilt convertPoint:point fromView:(UIView *)self];
        UIView *inside = CGRectContainsPoint(tilt.bounds, inTilt) ? [tilt hitTest:inTilt withEvent:event] : nil;
        answer = inside ?: tilt;
    } else if (hitTilt) {
        // The tilt's frame reaches past its cover: the view it sits in answers, and no recognizer of the tilt's runs.
        answer = hitTilt.superview ?: hit;
    }
    // Every touch that falls on the cover or on what the tilt's frame wrongly reaches is written down, so the
    // phone's log has the workable tap and the broken one side by side; a touch well away from both is left.
    if (onCover || hitTilt) logTap((UIView *)self, point, tilt, cover, hit, answer);
    return answer;
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
