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
    // The cover drawn under the point answers, whichever tilt draws it. The list keeps one tilt view per cell,
    // and on a first open, a sideways scroll or a cell reused for the next track the tilt the touch lands in is
    // not always the one drawing the visible cover: measured by the other one, a tap in the middle of the cover
    // was "beside it" and was answered with that cell's parent, which no recognizer watches, while the edge --
    // where the list's own hit test came back with no tilt and the showing one was asked -- still opened.
    UIView *hitTilt = tiltOf(hit);
    UIView *shown = SGRPlayerCoverTilt();
    // A hit test answers with a view of the subtree it was asked for, and a second list's tilt (the player
    // opening or closing beside this one) is not one.
    if (shown && ![shown isDescendantOfView:(UIView *)self]) shown = nil;
    CGRect cover = CGRectNull;
    UIView *answer = nil;
    UIView *tilts[2] = {hitTilt, shown};
    for (NSUInteger i = 0; i < 2 && !answer; i++) {
        UIView *tilt = tilts[i];
        if (!tilt) continue;
        CGRect drawn = SGRPlayerCoverRectIn(tilt, (UIView *)self);
        // A point on the corner's drawn edge is on the cover: the rect is whole points and a touch is not.
        if (CGRectIsNull(drawn) || !CGRectContainsPoint(CGRectInset(drawn, -1, -1), point)) continue;
        // Answered with the tilt view whole, whatever lies inside it: the tap that opens the inspection is the
        // tilt's own (PlayerGestures.x's handleTap hook, and Spotify's -[CoverArtTiltView handleTap] the only
        // caller), and a touch handed deeper -- to the cover's image view -- did not open it on the phone,
        // while the same tap on the cover's edge, which the tilt alone answers, did.
        cover = drawn;
        answer = tilt;
    }
    if (answer) {
        if (hit != answer) logTap((UIView *)self, point, answer, cover, hit, answer);
        return answer;
    }
    if (!hitTilt) return hit;
    // The tilt's frame reaches past its cover: the view it sits in answers, and no recognizer of the tilt's runs.
    UIView *elsewhere = hitTilt.superview ?: hit;
    // Every touch that falls on the cover or on what the tilt's frame wrongly reaches is written down, so the
    // phone's log has the workable tap and the broken one side by side; a touch well away from both is left.
    logTap((UIView *)self, point, shown ?: hitTilt, cover, hit, elsewhere);
    return elsewhere;
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
