// The redesign's now playing bar: the album-colored card becomes a glass card with round (or rounded square)
// artwork and the progress line under the text, and a Next button after play on request; on an iPad of regular width
// a capsule with shuffle, repeat, lyrics and queue too ("the iPad capsule"). Spotify's own labels, buttons and
// gestures stay in place.
//
// The full screen player morphs the bar's own card and artwork into the cover art. The bar was
// written to hand itself back to Spotify for that animation, from NowPlaying_ViewPageImpl's
// Show/CloseFullscreenAnimatedTransitioning, but Spotify 9.1.78 never runs the player through those,
// so the handback never happened and is gone; if the morph ever reads as a cut, the place to start is
// Shared/Player/PlayerEvents.h, which does fire. What does move with the player is a stand-in of the
// bar, which BarTransition.x keeps glass behind.
//
// Tree (trees/home.txt): NowPlayingBarContainerViewController.view 402x56 > NowPlayingBarViewController.view
//   at {8,0} 386x56 > UIView 386x56 (the painted card) > artwork 40x40 r=4, title stack,
//   progress line 370x2 at the bottom. The glass pane goes on the container's view.
// On an iPad of regular width (9.1.90) the bar stands beside the tab bar at the window's trailing foot:
//   CompactNowPlayingViewController's TouchPassthroughView 368x92 > the container's view 368x76 > the bar's view at
//   {8,0} 352x76, a 60x60 cover, the row {68,16} 276x44 of the information and the buttons (device, add, play).
//
// In a Jam Spotify puts a "Jam by ..." strip on the bar, a SwiftUI _UIHostingView of
// Jam_AttachmentsImpl.JamHatElement as wide as the card and 44pt high, and grows the bar by its height
// (386x100, the track card at y = 44). It paints the strip, or a view around the strip and the track, as
// well, so the card is the painted view that holds the track and has no strip in it. The strip stays out
// of the card's glass and gets a pane of its own above it, since its own paint goes clear with the rest.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRRepaint.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRPress.h"
#import "Settings/SGMarquee.h"
#import "NowPlayingBar.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Redesigned/Kit/SGRAccent.h"
#import "Redesigned/Kit/SGRRestyle.h"
#import "Redesigned/Player/Player.h"
#import "Redesigned/Player/PlayerQueue.h"
#import "Settings/SGModPage.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Player/PlayerState.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

static const CGFloat kCardRadius = 24;
// The strip's pane is this much smaller than the strip at each end, so a gap parts it from the card's glass.
static const CGFloat kStripInset = 4;
// Pressed, the card sinks to this and a veil this dark goes over it, as the Music app's mini player does.
static const CGFloat kCardPressScale = 0.97, kCardPressDim = 0.22;
// Rounded square's corners on the 40pt cover. The cover stands 8pt in from the card's 24pt corner, so a corner of
// any radius stays inside the card's curve; 8pt is the Music app's mini player's.
static const CGFloat kArtworkSquareRadius = 8;
// The cover's largest side: the phone's card's is 40 pt, the iPad's 60 pt.
static const CGFloat kCardArtworkMax = 48, kCapsuleArtworkMax = 64;
// kRoundedKey marks the cover's views this file rounded, so a change of shape rounds them again.
static char kGlassKey, kStripGlassKey, kDimKey, kRoundedKey;
static __weak UIView *sg_card;
static CGRect sg_stripFrame;
static __weak UIVisualEffectView *sg_cardGlass;
static __weak UIView *sg_cardArtwork;
// The view a music video plays in, masked to the cover's shape in its middle with these corners (maskVideoCover).
static __weak UIView *sg_videoCover;
static CGFloat sg_videoRadius;
static __weak UIView *sg_progress;
static __weak UIViewController *sg_container;
// The container's view while it stands in the minimized tab bar's row, below the page that holds it.
static __weak UIView *sg_inline;
// The card is the iPad capsule (SGRPlayerIPadRegular; "the iPad capsule" below).
static BOOL sg_capsule;

#pragma mark - the press

// The card sinks by a sublayerTransform of the container's view about the card's middle: its transform is
// the row's move (placeInline) and its children's frames are Spotify's, and this touches neither. The veil
// sits over the card in the same view, so it sinks with it; the glass itself never fades (SGRGlass.h).
static BOOL sg_cardPressed;

static void pressCard(BOOL pressed, BOOL animated) {
    UIView *host = sg_container.viewIfLoaded;
    UIVisualEffectView *glass = sg_cardGlass;
    if (!host) return;
    sg_cardPressed = pressed;
    CATransform3D sink = CATransform3DIdentity;
    if (pressed && glass.superview == host && !SGRReduceMotion()) {
        CGRect bounds = host.bounds, card = glass.frame;
        CGFloat dx = CGRectGetMidX(card) - CGRectGetMidX(bounds), dy = CGRectGetMidY(card) - CGRectGetMidY(bounds);
        // Applied right to left: to the card's middle, scaled, back.
        sink = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), kCardPressScale, kCardPressScale, 1), -dx, -dy, 0);
    }
    SGRPressAnimateLayer(host.layer, @"sublayerTransform", [NSValue valueWithCATransform3D:sink], animated);
    UIView *dim = objc_getAssociatedObject(host, &kDimKey);
    if (!dim) return;
    if (!animated) {
        [dim.layer removeAllAnimations];
        dim.alpha = 0;
        return;
    }
    SGRAnimate(pressed ? SGRMotionRespond : SGRMotionFade, ^{ dim.alpha = pressed ? 1 : 0; }, nil);
}

// The card at rest at once, pressed or springing back: the player grows from the card at rest.
static void settleCard(void) {
    UIView *host = sg_container.viewIfLoaded;
    if (!host || (!sg_cardPressed && ![host.layer animationForKey:@"sublayerTransform"])) return;
    pressCard(NO, NO);
}

// Touches on the card press it; the card's own buttons (play, devices, add) and the Jam strip do not. Spotify's
// tap still opens the player and its swipes still turn the page: the watcher takes nothing from them.
static void watchCard(UIView *host, CGRect card, CGFloat radius) {
    UIView *dim = objc_getAssociatedObject(host, &kDimKey);
    if (!dim) {
        dim = [UIView new];
        dim.userInteractionEnabled = NO;
        dim.isAccessibilityElement = NO;
        dim.accessibilityElementsHidden = YES;
        dim.alpha = 0;
        dim.backgroundColor = [UIColor colorWithWhite:0 alpha:kCardPressDim];
        dim.layer.zPosition = 1;
        dim.layer.cornerCurve = kCACornerCurveContinuous;
        objc_setAssociatedObject(host, &kDimKey, dim, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHost = host;
        SGRPressWatch(host, SGRPressKindScrolling, ^BOOL(UITouch *touch) {
            UIView *view = weakHost;
            UIVisualEffectView *glass = sg_cardGlass;
            if (!view || glass.superview != view || !glass.window) return NO;
            return CGRectContainsPoint(glass.frame, [touch locationInView:view]) && !SGRPressOnSmallControl(touch, view);
        }, ^(BOOL pressed, BOOL tapped) {
            pressCard(pressed, YES);
        });
        SGLog(@"now playing card: pressed under the finger");
    }
    if (dim.superview != host) [host addSubview:dim];
    [UIView performWithoutAnimation:^{
        dim.frame = card;
        dim.layer.cornerRadius = radius;
    }];
}

CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius) {
    settleCard();
    UIVisualEffectView *glass = sg_cardGlass;
    if (!glass.superview || !glass.window || !host) return CGRectNull;
    if (radius) *radius = sg_capsule ? glass.bounds.size.height / 2 : MIN(kCardRadius, glass.bounds.size.height / 2);
    return [host convertRect:glass.bounds fromView:glass];
}

// The square in the middle of `video`'s bounds, the cover's side.
static CGRect videoSquare(UIView *video) {
    CGSize size = video.bounds.size;
    CGFloat side = MIN(size.width, size.height);
    return CGRectMake((size.width - side) / 2, (size.height - side) / 2, side, side);
}

CGRect SGRNowPlayingArtworkFrameIn(UIView *host, CGFloat *radius) {
    settleCard();
    UIView *artwork = sg_cardArtwork;
    if (!artwork.window || !host) return CGRectNull;
    // A video's view shows only the square its mask leaves (maskVideoCover).
    BOOL video = artwork == sg_videoCover;
    if (radius) *radius = video ? sg_videoRadius : artwork.layer.cornerRadius;
    return [host convertRect:video ? videoSquare(artwork) : artwork.bounds fromView:artwork];
}

// The Jam strip. The height keeps out a view of the same module that can hold the track card too.
static BOOL isStrip(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return view.bounds.size.height <= 60 && [name containsString:@"AttachmentsImpl"] && [name containsString:@"Hat"];
}

static BOOL inStrip(UIView *view, UIView *root) {
    for (UIView *v = view; v && v != root; v = v.superview) if (isStrip(v)) return YES;
    return NO;
}

static UIView *stripIn(UIView *root) {
    __block UIView *strip = nil;
    SGForEachView(root, ^(UIView *v) { if (!strip && isStrip(v)) strip = v; });
    return strip;
}

// What holds the track on the bar: the title and artist block, else the artwork (a 36 to 48pt square that
// is not a button), never anything in the strip. Nil when neither is there.
static UIView *trackMarker(UIView *bar) {
    __block UIView *info = nil, *artwork = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (info || inStrip(v, bar)) return;
        if ([NSStringFromClass(v.class) containsString:@"InformationContainer"]) info = v;
        CGSize size = v.bounds.size;
        BOOL square = size.width >= 36 && size.width <= 48 && fabs(size.width - size.height) < 1;
        if (!artwork && square && ![v isKindOfClass:UIControl.class]) artwork = v;
    });
    return info ?: artwork;
}

// A card holds the track and has no strip in it; one with the strip in it only when there is no other.
// Among equals the largest, which outside a Jam is the card it always was.
static BOOL isGoodCard(UIView *card, UIView *bar, UIView *marker) {
    return SGIsInside(card, bar) && !inStrip(card, bar) && (!marker || [marker isDescendantOfView:card]);
}

static UIView *chooseCard(UIView *bar, UIView *marker) {
    UIView *best = nil;
    BOOL bestHasStrip = NO;
    CGFloat bestArea = 0;
    for (UIView *v in sgr_nowPlayingPainted) {
        // Card sized: the paint itself has gone clear by now.
        if (!SGLooksLikeCard(v, UIColor.whiteColor.CGColor) || !isGoodCard(v, bar, marker)) continue;
        BOOL hasStrip = stripIn(v) != nil;
        CGFloat area = v.bounds.size.width * v.bounds.size.height;
        BOOL better = !best || (hasStrip != bestHasStrip ? !hasStrip : area > bestArea);
        if (!better) continue;
        best = v;
        bestHasStrip = hasStrip;
        bestArea = area;
    }
    return best;
}

// Fallback when nothing is painted: the box around artwork, text and the small buttons.
static CGRect contentBounds(UIView *bar, UIView *target) {
    __block CGRect box = CGRectNull;
    SGForEachView(bar, ^(UIView *v) {
        if (v.hidden || v.alpha == 0 || inStrip(v, bar)) return;
        CGFloat width = v.bounds.size.width;
        BOOL content = ([v isKindOfClass:UIImageView.class] && width >= 20 && width <= 120)
            || [v isKindOfClass:UILabel.class]
            || ([v isKindOfClass:UIControl.class] && width <= 100);
        if (content) box = CGRectUnion(box, SGFrameIn(v, target));
    });
    return CGRectIsNull(box) ? box : CGRectInset(box, -10, -8);
}

static void roundView(UIView *view, CGFloat radius) {
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
}

// A rounded square cover's corners in the iPad capsule: standing `inset` in from the capsule's ends of `radius`, a corner
// of r stays inside their curve while √2·(radius − inset − r) + r ≤ radius. The iPad's 60 pt cover in its 76 pt capsule
// needs 11 pt; the phone's card's corner leaves room for kArtworkSquareRadius.
static CGFloat capsuleSquareRadius(CGFloat radius, CGFloat inset) {
    return MAX(kArtworkSquareRadius, ceil((M_SQRT2 * (radius - inset) - radius) / (M_SQRT2 - 1)));
}

// The cover's corners for the Player page's Artwork shape (SGRKeyBarArtworkShape), on a card `cardHeight` high.
static CGFloat artworkRadius(CGFloat width, CGFloat cardHeight) {
    if (SGInt(SGRKeyBarArtworkShape, SGRBarArtworkShapeCircle) != SGRBarArtworkShapeRoundedSquare) return width / 2;
    return sg_capsule ? capsuleSquareRadius(cardHeight / 2, (cardHeight - width) / 2) : kArtworkSquareRadius;
}

// A music video can play in the cover's place in a view that is not square (Eevee issue #193), which the square cover
// below never takes. With no shown square cover in the card, the view the video plays in -- not square, at least
// kVideoMin each way and no more than twice the card's height either way, starting in the leading third of the card,
// with no text or control in it and in nothing that is one or is the track's title block -- is masked to the square in
// its middle with the cover's corners, so it shows as the cover's shape.
static const CGFloat kVideoMin = 24;
static char kVideoMaskKey;

static BOOL isTextOrControl(UIView *view) {
    return [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIControl.class];
}

// Whether `view` holds text or a control, or sits under one, or under the title block (trackMarker), below `card`.
static BOOL touchesTextOrControl(UIView *view, UIView *card) {
    for (UIView *u = view.superview; u && u != card; u = u.superview) {
        if (isTextOrControl(u) || [NSStringFromClass(u.class) containsString:@"InformationContainer"]) return YES;
    }
    __block BOOL holds = NO;
    SGForEachView(view, ^(UIView *v) { if (isTextOrControl(v)) holds = YES; });
    return holds;
}

static UIView *videoCoverIn(UIView *card) {
    CGSize cardSize = card.bounds.size;
    BOOL rtl = card.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    __block UIView *found = nil;
    __block CGFloat nearest = CGFLOAT_MAX;
    SGForEachView(card, ^(UIView *v) {
        if (v == card || inStrip(v, card)) return;
        CGSize size = v.bounds.size;
        if (size.width < kVideoMin || size.height < kVideoMin || size.width > 2 * cardSize.height || size.height > 2 * cardSize.height) return;
        // A square one is a cover, rounded or not, never a video to mask.
        if (fabs(size.width - size.height) < 1) return;
        CGRect frame = [v convertRect:v.bounds toView:card];
        CGFloat lead = rtl ? cardSize.width - CGRectGetMaxX(frame) : CGRectGetMinX(frame);
        if (lead >= cardSize.width / 3 || lead >= nearest || !SGShownUnder(v, card) || touchesTextOrControl(v, card)) return;
        nearest = lead;
        found = v;
    });
    return found;
}

static void maskVideoCover(UIView *video, CGFloat cardHeight) {
    CGRect square = videoSquare(video);
    sg_videoRadius = artworkRadius(square.size.width, cardHeight);
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:square cornerRadius:sg_videoRadius];
    CAShapeLayer *mask = objc_getAssociatedObject(video, &kVideoMaskKey);
    if (!mask) {
        mask = [CAShapeLayer layer];
        objc_setAssociatedObject(video, &kVideoMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (video.layer.mask == mask && CGRectEqualToRect(mask.frame, video.bounds) && CGPathEqualToPath(mask.path, path.CGPath)) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    mask.frame = video.bounds;
    mask.path = path.CGPath;
    video.layer.mask = mask;
    [CATransaction commit];
}

static void unmaskVideoCover(UIView *video) {
    CAShapeLayer *mask = objc_getAssociatedObject(video, &kVideoMaskKey);
    if (mask && video.layer.mask == mask) video.layer.mask = nil;
}

static void restyleCardContent(UIView *card) {
    // The video is looked for again on every pass, and only while there is no square cover.
    if (sg_cardArtwork && sg_cardArtwork == sg_videoCover) sg_cardArtwork = nil;
    __block BOOL squareCover = NO;
    SGForEachView(card, ^(UIView *v) {
        if (inStrip(v, card)) return;
        CGSize size = v.bounds.size;
        // 40 pt on the phone's card, 60 pt on the iPad's capsule (the iPad's bar, 9.1.90).
        BOOL square = size.width >= 36 && size.width <= (sg_capsule ? kCapsuleArtworkMax : kCardArtworkMax) && fabs(size.width - size.height) < 1;
        if (!square || v.layer.cornerRadius <= 0) return;
        // A hidden cover is still shaped for when it shows again, but only a shown one is the cover the bar shows.
        BOOL shown = SGShownUnder(v, card);
        if (shown) squareCover = YES;
        // The shape asked for is there already: nothing to change, as on every layout after the first.
        CGFloat radius = artworkRadius(size.width, card.bounds.size.height);
        if (v.layer.cornerRadius == radius) {
            if (!sg_cardArtwork && shown) sg_cardArtwork = v;
            return;
        }
        // Round already, and not by this file: Spotify's own round cover is left as it is.
        if (!objc_getAssociatedObject(v, &kRoundedKey) && v.layer.cornerRadius >= size.width / 2) {
            if (!sg_cardArtwork && shown) sg_cardArtwork = v;
            return;
        }
        UIView *outer = v;
        for (UIView *u = v; u && u != card && CGSizeEqualToSize(u.bounds.size, size); u = u.superview) {
            if (u.layer.cornerRadius != radius) roundView(u, radius);
            if (!u.clipsToBounds) u.clipsToBounds = YES;
            if (!objc_getAssociatedObject(u, &kRoundedKey)) objc_setAssociatedObject(u, &kRoundedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            outer = u;
        }
        if (shown) sg_cardArtwork = outer;
    });
    UIView *video = squareCover ? nil : videoCoverIn(card);
    if (sg_videoCover && sg_videoCover != video) unmaskVideoCover(sg_videoCover);
    sg_videoCover = video;
    if (video) {
        maskVideoCover(video, card.bounds.size.height);
        sg_cardArtwork = video;
    }
    __block UIView *progress = sg_progress;
    if (![progress isDescendantOfView:card]) {
        progress = nil;
        SGForEachView(card, ^(UIView *v) {
            CGRect f = v.frame;
            if (!progress && !inStrip(v, card) && f.size.height <= 3 && f.size.width >= 200 && v.superview.bounds.size.height >= 40) progress = v;
        });
        sg_progress = progress;
    }
    // Under the text, 226pt on a full width card, shorter on the one in the minimized tab bar. On the capsule it keeps
    // off the round ends, a capsule's height in from each side.
    CGSize cardSize = card.bounds.size;
    CGRect target = sg_capsule ? CGRectMake(cardSize.height, cardSize.height - 6, MAX(0, cardSize.width - 2 * cardSize.height), 2)
                               : CGRectMake(52, cardSize.height - 6, MAX(0, cardSize.width - 160), 2);
    if (progress && !CGRectEqualToRect(progress.frame, target)) {
        progress.frame = target;
        [progress setNeedsLayout];
        [progress layoutIfNeeded];
    }
}

// The strip's own pane, a strip high less the gaps, on the card's side the strip is on. It is measured from
// the card's settled frame and the strip's height, not from the strip's frame: Spotify animates the strip
// in, and a pane taken from it mid-way sat about 12pt off and cut its ⋯ button. The glass comes in and goes
// by its effect, never by alpha (SGRGlass.h).
static void placeStripGlass(UIView *host, UIView *strip, CGRect card, BOOL above) {
    UIVisualEffectView *pane = objc_getAssociatedObject(host, &kStripGlassKey);
    if (!strip) {
        if (pane.effect) SGRAnimate(SGRMotionExit, ^{ SGRShowGlass(pane, NO); }, nil);
        return;
    }
    BOOL made = pane != nil;
    pane = SGGlassFor(host, &kStripGlassKey);
    if (!made) {
        pane.effect = nil;
        pane.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    CGFloat height = strip.bounds.size.height;
    CGRect frame = CGRectMake(card.origin.x, above ? CGRectGetMinY(card) - height : CGRectGetMaxY(card), card.size.width, height);
    pane.frame = CGRectInset(frame, 0, kStripInset);
    SGShapeGlass(pane, MIN(kCardRadius, pane.bounds.size.height / 2), NO);
    if (!pane.effect) SGRAnimate(SGRMotionRespond, ^{ SGRShowGlass(pane, YES); }, nil);
}

// The bar's left and right edges in its superview, set through the constants of the constraints that hold
// them there (their constants as Spotify set them kept to go back to), or through its frame when it is laid
// out by frame. A frame alone does not move a view laid out by constraints, nor what is constrained inside
// it (harness/tabbar). NO, with nothing changed, when its edges are held some other way, or right to left
// unless `mirrored` (the iPad capsule's), whose leading and trailing constants count from the right.
static NSMapTable<NSLayoutConstraint *, NSNumber *> *sg_constants;
static CGRect sg_fullFrame, sg_narrowFrame;

static void restoreEdges(UIView *bar) {
    for (NSLayoutConstraint *constraint in sg_constants) constraint.constant = [[sg_constants objectForKey:constraint] doubleValue];
    [sg_constants removeAllObjects];
    if (bar.translatesAutoresizingMaskIntoConstraints && CGRectEqualToRect(bar.frame, sg_narrowFrame)) bar.frame = sg_fullFrame;
    sg_narrowFrame = CGRectNull;
}

// Each constraint of the superview's that holds one of the bar's sides to the same side of the superview: whether it is
// the left side, whether the bar is its first item, the sign its constant has (-1 for leading and trailing right to left)
// and that side's x in the superview. A constant is `sign` times the first item's side less the second's.
static void eachEdgeConstraint(UIView *bar, void (^each)(NSLayoutConstraint *constraint, BOOL isLeft, BOOL barFirst, CGFloat sign, CGFloat edge)) {
    UIView *superview = bar.superview;
    BOOL rtl = superview.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    for (NSLayoutConstraint *constraint in superview.constraints) {
        NSLayoutAttribute attribute = constraint.firstAttribute;
        BOOL barFirst = constraint.firstItem == bar && constraint.secondItem == superview;
        if (!constraint.active || constraint.relation != NSLayoutRelationEqual || constraint.multiplier != 1 || attribute != constraint.secondAttribute
            || (!barFirst && !(constraint.secondItem == bar && constraint.firstItem == superview))) continue;
        BOOL directional = attribute == NSLayoutAttributeLeading || attribute == NSLayoutAttributeTrailing;
        if (!directional && attribute != NSLayoutAttributeLeft && attribute != NSLayoutAttributeRight) continue;
        BOOL isLeft = attribute == NSLayoutAttributeLeft || (attribute == NSLayoutAttributeLeading && !rtl)
            || (attribute == NSLayoutAttributeTrailing && rtl);
        each(constraint, isLeft, barFirst, directional && rtl ? -1 : 1, isLeft ? 0 : superview.bounds.size.width);
    }
}

static BOOL setEdges(UIView *bar, CGFloat left, CGFloat right, BOOL mirrored) {
    UIView *superview = bar.superview;
    if (bar.translatesAutoresizingMaskIntoConstraints) {
        CGRect frame = CGRectMake(left, bar.frame.origin.y, right - left, bar.frame.size.height);
        if (!CGRectEqualToRect(bar.frame, sg_narrowFrame)) sg_fullFrame = bar.frame;
        sg_narrowFrame = frame;
        if (!CGRectEqualToRect(bar.frame, frame)) bar.frame = frame;
        return YES;
    }
    if (!mirrored && superview.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft) return NO;
    if (!sg_constants) sg_constants = [NSMapTable weakToStrongObjectsMapTable];
    __block NSUInteger held = 0;
    eachEdgeConstraint(bar, ^(NSLayoutConstraint *constraint, BOOL isLeft, BOOL barFirst, CGFloat sign, CGFloat edge) {
        if (![sg_constants objectForKey:constraint]) [sg_constants setObject:@(constraint.constant) forKey:constraint];
        CGFloat value = isLeft ? left : right;
        CGFloat constant = sign * (barFirst ? value - edge : edge - value);
        if (constraint.constant != constant) constraint.constant = constant;
        held |= isLeft ? 1 : 2;
    });
    if (held == 3) return YES;
    restoreEdges(bar);
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"now playing bar: its edges are not held by its superview's constraints, so it keeps Spotify's"); });
    return NO;
}

// The bar's sides where Spotify puts them, whatever this file has set: its frame or the constants Spotify gave the
// constraints that hold them. NO when its sides are held some other way.
static BOOL spotifyEdges(UIView *bar, CGFloat *left, CGFloat *right) {
    if (bar.translatesAutoresizingMaskIntoConstraints) {
        CGRect frame = CGRectEqualToRect(bar.frame, sg_narrowFrame) ? sg_fullFrame : bar.frame;
        *left = CGRectGetMinX(frame);
        *right = CGRectGetMaxX(frame);
        return YES;
    }
    __block NSUInteger held = 0;
    eachEdgeConstraint(bar, ^(NSLayoutConstraint *constraint, BOOL isLeft, BOOL barFirst, CGFloat sign, CGFloat edge) {
        NSNumber *kept = [sg_constants objectForKey:constraint];
        CGFloat constant = kept ? kept.doubleValue : constraint.constant;
        CGFloat x = barFirst ? edge + sign * constant : edge - sign * constant;
        if (isLeft) *left = x;
        else *right = x;
        held |= isLeft ? 1 : 2;
    });
    return held == 3;
}

// The bar's edges set to `r`'s sides, `r` in the coordinates of the container's view's superview and the view standing
// at `origin` in them. NO, with nothing changed, for a null `r`.
static BOOL edgesTo(UIView *bar, CGRect r, CGPoint origin) {
    return !CGRectIsNull(r) && setEdges(bar, CGRectGetMinX(r) - origin.x, CGRectGetMaxX(r) - origin.x, NO);
}

#pragma mark - the Next button

// The Player page's Next button (SGRKeyBarNextButton): Spotify's bar ends in play, the Music app's mini player in play
// and Next. Spotify's row is a stack of the track's information and a stack of the buttons, play's item last; Next is
// an item of the row's own after the buttons, as large as play's item, so the row makes room for it and the title gives
// the room up. Not one of the buttons' stack: Spotify moves its items there by index, and Next among them put the add
// button after play (9.1.90). It asks the player for the next track as the Live Activity's Next does.
static NSString *const kPlayId = @"SPTNowPlayingPlayButton";
static NSString *const kNextId = @"retrine.nowplayingbar.next";
static char kNextKey;

// The smallest touch target a control may have, in points (Apple's Human Interface Guidelines). Play's item, which the
// button is laid out as, is 44x40 pt in 9.1.90's bar.
static const CGFloat kMinTouchTarget = 44;

@interface SGRBarNextButton : UIButton
// Play's item's size, which the stack lays the button out at.
@property (nonatomic) CGSize itemSize;
@end

// The Next button last placed, for the hit test of the bar's page (the passthrough view's hook).
static __weak UIView *sg_nextButton;

@implementation SGRBarNextButton
- (CGSize)intrinsicContentSize {
    return self.itemSize;
}

// At least kMinTouchTarget each way about its middle, whatever its laid out size; the bar's page's hit test hands it
// the touches its row's bounds keep from it (nextButtonHit).
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect bounds = self.bounds;
    CGFloat dx = MIN(0, (bounds.size.width - kMinTouchTarget) / 2), dy = MIN(0, (bounds.size.height - kMinTouchTarget) / 2);
    return CGRectContainsPoint(CGRectInset(bounds, dx, dy), point);
}

- (void)setItemSize:(CGSize)size {
    if (CGSizeEqualToSize(size, _itemSize)) return;
    _itemSize = size;
    [self invalidateIntrinsicContentSize];
}

- (void)skip {
    [(id<SPTPlayer>)SGPlayer() skipToNextTrackWithOptions:nil];
}
@end

// forward.fill's point size, matched by eye to the pause glyph Spotify draws in the bar (9.1.90): at 17 it read heavier.
static const CGFloat kNextGlyphSize = 15;

// Next when `point`, in `host`'s coordinates, is within its touch target and it is showing in `host`; nil otherwise.
// Spotify's row is 40 pt high, so a hit test that reaches Next only through the row never sees the target's top and
// bottom 2 pt.
static UIView *nextButtonHit(UIView *host, CGPoint point, UIEvent *event) {
    UIView *next = sg_nextButton;
    if (!next.window || ![next isDescendantOfView:host]) return nil;
    // As UIKit's own hit test would: nothing hidden, faded out or closed to touches between Next and the host.
    for (UIView *v = next; v; v = v == host ? nil : v.superview) {
        if (v.hidden || v.alpha < 0.01 || !v.userInteractionEnabled) return nil;
    }
    return [next pointInside:[host convertPoint:point toView:next] withEvent:event] ? next : nil;
}

static SGRBarNextButton *makeNextButton(void) {
    SGRBarNextButton *next = [SGRBarNextButton buttonWithType:UIButtonTypeSystem];
    UIImageSymbolConfiguration *glyph = [UIImageSymbolConfiguration configurationWithPointSize:kNextGlyphSize weight:UIImageSymbolWeightRegular];
    [next setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:glyph] forState:UIControlStateNormal];
    next.tintColor = SGRPrimary();
    next.accessibilityIdentifier = kNextId;
    next.accessibilityLabel = SGL(@"settings.gestures.action.next", @"Next track");
    [next setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [next setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [next addTarget:next action:@selector(skip) forControlEvents:UIControlEventTouchUpInside];
    return next;
}

// Spotify's row: the stack of the track's information and the stack of the buttons, play's item among them; nil, and
// `buttons` and `playItem` too, when the bar is not built that way.
static UIStackView *buttonRow(UIView *bar, UIStackView **buttons, UIView **playItem) {
    __block UIView *play = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!play && [v.accessibilityIdentifier isEqualToString:kPlayId] && !inStrip(v, bar)) play = v;
    });
    UIView *item = play;
    while (item.superview && item.superview != bar && ![item.superview isKindOfClass:UIStackView.class]) item = item.superview;
    UIStackView *stack = (UIStackView *)item.superview;
    UIStackView *row = (UIStackView *)stack.superview;
    BOOL found = [stack isKindOfClass:UIStackView.class] && [stack.arrangedSubviews containsObject:item]
        && [row isKindOfClass:UIStackView.class] && [row.arrangedSubviews containsObject:stack];
    if (buttons) *buttons = found ? stack : nil;
    if (playItem) *playItem = found ? item : nil;
    if (found) return row;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"now playing bar: play's button stack is not in a row stack (%@)", play.class); });
    return nil;
}

// The button right after Spotify's buttons, last in the row, while the switch is on, out of it while it is off; the iPad
// capsule's buttons come after it. In the minimized row tuckExtras hides it with the device and add buttons.
static void placeNextButton(UIView *bar) {
    SGRBarNextButton *next = objc_getAssociatedObject(bar, &kNextKey);
    if (!SGEnabled(SGRKeyBarNextButton)) {
        [next removeFromSuperview];
        return;
    }
    UIStackView *buttons = nil;
    UIView *item = nil;
    UIStackView *row = buttonRow(bar, &buttons, &item);
    if (!row) {
        // A Next placed before Spotify changed its bar goes with it, so no button is left where it no longer belongs.
        [next removeFromSuperview];
        return;
    }
    if (!next) {
        next = makeNextButton();
        objc_setAssociatedObject(bar, &kNextKey, next, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    sg_nextButton = next;
    if (item.bounds.size.width >= 1) next.itemSize = item.bounds.size;
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    NSUInteger at = [arranged indexOfObject:buttons] + 1;
    if (at < arranged.count && arranged[at] == next) return;
    [UIView performWithoutAnimation:^{
        next.hidden = NO;
        next.alpha = 1;
        [row insertArrangedSubview:next atIndex:at];
        [row setCustomSpacing:0 afterView:buttons];
    }];
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"now playing bar: Next after the buttons in %@", row.class); });
}

// In the row the card keeps the cover, the title and play, as the Music app's does: the device, add and Next
// buttons stand aside while it is there and come back with the full card, the device button staying when the
// Player page's Device button asks for it (SGRKeyBarInlineConnect). The iPad capsule keeps Next and its own buttons,
// and the device and add buttons stand aside for them. Only what this hid is shown again.
typedef NS_ENUM(NSInteger, SGRBarTuck) { SGRBarTuckNone, SGRBarTuckRow, SGRBarTuckCapsule };
static NSHashTable<UIView *> *sg_tucked;
static SGRBarTuck sg_tuck;

BOOL SGRBarRowKeepsConnect(void) {
    return sg_tuck == SGRBarTuckRow && SGHidden(SGRKeyBarInlineConnect);
}

// The device button the full card hides (BarConnect.x) is placed again for the new state in the same pass.
static void tuckExtras(UIView *bar, SGRBarTuck tuck) {
    if (!sg_tucked) sg_tucked = [NSHashTable weakObjectsHashTable];
    // A stack hides an item only once the animation it was hidden in ends, so the buttons also fade on
    // their own, out as the card heads for the row and back in after it leaves.
    if (tuck != sg_tuck) {
        NSArray<UIView *> *items = sg_tucked.allObjects;
        [sg_tucked removeAllObjects];
        for (UIView *item in items) item.hidden = NO;
        SGRAnimate(SGRMotionRespond, ^{ for (UIView *item in items) item.alpha = 1; }, nil);
        sg_tuck = tuck;
    }
    SGRBarPlaceConnect(bar);
    if (tuck == SGRBarTuckNone) return;
    BOOL keepConnect = SGRBarRowKeepsConnect(), keepNext = tuck == SGRBarTuckCapsule;
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = v.accessibilityIdentifier;
        BOOL connect = [name isEqualToString:@"Components.ConnectButtonOutputSwitcher"];
        BOOL next = [name isEqualToString:kNextId];
        if ((!connect || keepConnect) && ![name isEqualToString:@"Components.UI.AddToButton"] && (!next || keepNext)) return;
        // The stack's own item, so the stack closes the gap.
        UIView *item = v;
        while (item.superview && item.superview != bar && ![item.superview isKindOfClass:UIStackView.class]) item = item.superview;
        if (![item.superview isKindOfClass:UIStackView.class] || item.hidden) return;
        item.hidden = YES;
        SGRAnimate(SGRMotionExit, ^{ item.alpha = 0; }, nil);
        [sg_tucked addObject:item];
    });
}

#pragma mark - the iPad capsule

// On an iPad of regular width (SGRPlayerIPadRegular) the card is a capsule, as the Music app's mini player on iPad is,
// and besides the cover, the title and play (and Next, when it is switched on) it holds shuffle, repeat, lyrics and
// queue: buttons of the mod's in Spotify's row after its own, the way Next is, while the device and add buttons stand
// aside (tuckExtras). Shuffle and repeat send the player's own commands, the ones the Live Activity's controls send
// (setShufflingContext:, SGPlayerAdvanceRepeat), and show what the player reports, lit in the accent while on; lyrics
// opens the player, through spotify:now-playing on Spotify's link dispatcher, on its lyrics (SGRPlayerShowLyricsOnOpen);
// queue opens Playing Next over the app (PlayerQueue.m). For their room the capsule grows from Spotify's card toward
// the glass tab bar beside it, keeping its other side where Spotify put it, and stops short of the tab bar's glass.
static NSString *const kShuffleId = @"retrine.nowplayingbar.shuffle", *const kRepeatId = @"retrine.nowplayingbar.repeat";
static NSString *const kLyricsId = @"retrine.nowplayingbar.lyrics", *const kQueueId = @"retrine.nowplayingbar.queue";
static NSString *const kRepeatSymbol = @"repeat", *const kRepeatOneSymbol = @"repeat.1";
// The four glyphs' point size, drawn as heavy as play's and Next's glyphs read beside them.
static const CGFloat kCapsuleGlyphSize = 17;
// The room the capsule grows to give the title, and how far it keeps from the tab bar's glass.
static const CGFloat kCapsuleTextWidth = 200, kCapsuleTabGap = 16;
static char kCapsuleKey, kTabsKey;

// A system button, as Next is: Spotify's tap on the card, which opens the player, lets a button's own tap through, where
// it takes one from a control of another kind. Laid out a touch target square in the row, the large content viewer
// showing its title at accessibility text sizes.
@interface SGRBarCapsuleButton : UIButton
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) void (^onTap)(UIView *button);
@end

@implementation SGRBarCapsuleButton
- (CGSize)intrinsicContentSize {
    return CGSizeMake(kMinTouchTarget, kMinTouchTarget);
}

- (void)setSymbol:(NSString *)symbol {
    if ([symbol isEqualToString:_symbol]) return;
    _symbol = [symbol copy];
    UIImageSymbolConfiguration *glyph = [UIImageSymbolConfiguration configurationWithPointSize:kCapsuleGlyphSize weight:UIImageSymbolWeightRegular];
    UIImage *image = [UIImage systemImageNamed:symbol withConfiguration:glyph];
    [self setImage:image forState:UIControlStateNormal];
    self.largeContentImage = image;
}

- (void)tapped {
    if (self.onTap) self.onTap(self);
}
@end

static __weak SGRBarCapsuleButton *sg_shuffle, *sg_repeat;

static SGRBarCapsuleButton *capsuleButton(NSString *symbol, NSString *title, NSString *identifier, void (^tap)(UIView *button)) {
    SGRBarCapsuleButton *button = [SGRBarCapsuleButton buttonWithType:UIButtonTypeSystem];
    button.symbol = symbol;
    button.tintColor = SGRPrimary();
    button.accessibilityIdentifier = identifier;
    button.accessibilityLabel = title;
    button.showsLargeContentViewer = YES;
    button.largeContentTitle = title;
    [button addInteraction:[UILargeContentViewerInteraction new]];
    [button setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [button setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    button.onTap = tap;
    [button addTarget:button action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

static NSArray<SGRBarCapsuleButton *> *makeCapsuleButtons(void) {
    SGRBarCapsuleButton *shuffle = capsuleButton(@"shuffle", SGL(@"settings.player.ipad.shuffle", @"Shuffle"), kShuffleId, ^(UIView *button) {
        SPTPlayerState *state = SGPlayerState();
        [(id<SPTPlayer>)SGPlayer() setShufflingContext:!state.options.shufflingContext];
    });
    SGRBarCapsuleButton *repeat = capsuleButton(kRepeatSymbol, SGL(@"settings.player.ipad.repeat", @"Repeat"), kRepeatId, ^(UIView *button) {
        SGPlayerAdvanceRepeat((id<SPTPlayer>)SGPlayer(), SGPlayerState().options);
    });
    SGRBarCapsuleButton *lyrics = capsuleButton(@"quote.bubble", SGL(@"settings.main.lyrics.title", @"Lyrics"), kLyricsId, ^(UIView *button) {
        SGRPlayerShowLyricsOnOpen();
        if (!SGOpenSpotifyURI([NSURL URLWithString:@"spotify:now-playing"])) SGLog(@"now playing bar: the player could not be opened for its lyrics");
    });
    SGRBarCapsuleButton *queue = capsuleButton(@"list.bullet", SGL(@"settings.player.ipad.queue", @"Queue"), kQueueId, ^(UIView *button) {
        SGRPlayerShowQueue(button);
    });
    sg_shuffle = shuffle;
    sg_repeat = repeat;
    return @[shuffle, repeat, lyrics, queue];
}

// Shuffle and repeat as the player reports them: lit in the accent while on, repeat's glyph with its 1 while it
// repeats the track, and VoiceOver told which. Dimmed with nothing to play.
static void showPlayerOptions(void) {
    SGRBarCapsuleButton *shuffle = sg_shuffle, *repeat = sg_repeat;
    if (!shuffle.window && !repeat.window) return;
    SPTPlayerState *state = SGPlayerState();
    SPTPlayerOptions *options = state.options;
    BOOL shuffling = options.shufflingContext, track = options.repeatingTrack, context = options.repeatingContext;
    UIColor *lit = SGRAccentColor() ?: SGColorRGB(SGRAccentRGB());
    BOOL playable = state.track != nil;
    NSString *on = SGL(@"common.on", @"On"), *off = SGL(@"common.off", @"Off");
    UIColor *shuffleTint = shuffling ? lit : SGRPrimary(), *repeatTint = track || context ? lit : SGRPrimary();
    if (![shuffle.tintColor isEqual:shuffleTint]) shuffle.tintColor = shuffleTint;
    if (![repeat.tintColor isEqual:repeatTint]) repeat.tintColor = repeatTint;
    repeat.symbol = track ? kRepeatOneSymbol : kRepeatSymbol;
    shuffle.accessibilityValue = shuffling ? on : off;
    repeat.accessibilityValue = track ? SGL(@"settings.player.ipad.repeat.one", @"One")
        : context ? SGL(@"settings.player.ipad.repeat.all", @"All") : off;
    if (shuffle.enabled != playable) shuffle.enabled = playable;
    if (repeat.enabled != playable) repeat.enabled = playable;
}

@interface SGRBarOptionsWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRBarOptionsWatcher
- (void)playerStateDidChange:(SPTPlayerState *)state {
    showPlayerOptions();
}
// Repeat is not among what a change is reported for: every report is looked at.
- (void)playerStateDidReport:(SPTPlayerState *)state {
    showPlayerOptions();
}
@end

// The four after Spotify's buttons and Next while the card is the capsule, out of the row while it is not.
static void placeCapsuleButtons(UIView *bar, BOOL capsule) {
    NSArray<SGRBarCapsuleButton *> *buttons = objc_getAssociatedObject(bar, &kCapsuleKey);
    UIStackView *spotify = nil;
    UIView *playItem = nil;
    UIStackView *row = capsule ? buttonRow(bar, &spotify, &playItem) : nil;
    if (!row) {
        for (UIView *button in buttons) [button removeFromSuperview];
        return;
    }
    SGForEachView(playItem, ^(UIView *view) {
        if ([view.accessibilityIdentifier isEqualToString:kPlayId]) view.tintColor = SGRPrimary();
    });
    if (!buttons) {
        buttons = makeCapsuleButtons();
        objc_setAssociatedObject(bar, &kCapsuleKey, buttons, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSArray<UIView *> *arranged = row.arrangedSubviews;
    UIView *next = sg_nextButton;
    UIView *before = [arranged containsObject:next] ? next : spotify;
    NSUInteger at = [arranged indexOfObject:before] + 1;
    BOOL placed = NO;
    for (SGRBarCapsuleButton *button in buttons) {
        if (at >= row.arrangedSubviews.count || row.arrangedSubviews[at] != button) {
            [UIView performWithoutAnimation:^{ [row insertArrangedSubview:button atIndex:at]; }];
            placed = YES;
        }
        at++;
    }
    showPlayerOptions();
    if (!placed) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"now playing bar: the capsule's shuffle, repeat, lyrics and queue in %@", row.class); });
}

// UIKit moves the tab bar's platter as its bar settles (at launch it is laid out across a wider bar first), with no
// pass of the now playing bar to follow, and the tab bar tells the card only of a compact width's row (TabBar.x). The
// platter's frame setters are watched instead, and a move lays the capsule out again, once a turn of the run loop.
@interface SGRTabGlassWatcher : NSObject
@end

@implementation SGRTabGlassWatcher {
    BOOL _pending;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    // KVO reports setters, not movement. UIKit assigns the same platter geometry during layout;
    // turning those assignments into another synchronous layout feeds the next notification.
    if ([change[NSKeyValueChangeOldKey] isEqual:change[NSKeyValueChangeNewKey]]) return;
    if (_pending) return;
    _pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_pending = NO;
        if (sg_capsule) SGRNowPlayingBarFollowTabBar();
    });
}
@end

static void watchTabGlass(UIView *platter) {
    static SGRTabGlassWatcher *watcher;
    static __weak UIView *watched;
    UIView *previous = watched;
    if (previous == platter) return;
    if (!watcher) watcher = [SGRTabGlassWatcher new];
    for (NSString *key in @[@"frame", @"center", @"bounds"]) {
        [previous removeObserver:watcher forKeyPath:key];
        [platter addObserver:watcher forKeyPath:key options:NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew context:NULL];
    }
    watched = platter;
}

// The glass tab bar's platter on the bar's row nearest the bar, in the bar's superview's coordinates: UIKit's floating tab
// bar draws its glass in a view of its own, narrower than the bar (Redesigned/Navbar/TabBar.x reads it the same way),
// inside Spotify's tab bar view, and a split tab stands on a platter of its own between the main one and the bar. The
// nearest is the one whose side toward the bar is furthest that way: the rightmost right side, right to left the
// leftmost left side. Only a platter that is seen counts: TabBar.x hides the split bar that has lost its last tab and
// leaves it, platter and all, where it stood. CGRectNull when there is none beside the bar.
static BOOL platterSeen(UIView *platter) {
    for (UIView *v = platter; v; v = v.superview) {
        if (v.hidden || v.alpha < 0.01) return NO;
    }
    return YES;
}

static CGRect tabGlassBeside(UIView *bar) {
    UIView *tabs = bar.window ? SGRFindByIdentifier(bar.window, @"elements-tabs-view-identifier", &kTabsKey) : nil;
    BOOL rtl = bar.superview.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    __block UIView *platter = nil;
    __block CGRect glass = CGRectNull;
    if (tabs) SGForEachView(tabs, ^(UIView *v) {
        if (![NSStringFromClass(v.class) hasSuffix:@"PlatterView"] || !platterSeen(v)) return;
        CGRect frame = [v convertRect:v.bounds toView:bar.superview];
        if (CGRectGetMaxY(frame) <= CGRectGetMinY(bar.frame) || CGRectGetMinY(frame) >= CGRectGetMaxY(bar.frame)) return;
        BOOL nearer = rtl ? CGRectGetMinX(frame) < CGRectGetMinX(glass) : CGRectGetMaxX(frame) > CGRectGetMaxX(glass);
        if (platter && !nearer) return;
        platter = v;
        glass = frame;
    });
    if (!platter) return CGRectNull;
    watchTabGlass(platter);
    return glass;
}

// What the row's views after the title take, at their own widths, with the row's spacing before each.
static CGFloat rowButtonsWidth(UIStackView *row) {
    CGFloat width = 0;
    for (UIView *view in row.arrangedSubviews) {
        if (view == row.arrangedSubviews.firstObject || view.hidden) continue;
        CGFloat own = view.intrinsicContentSize.width;
        if (own == UIViewNoIntrinsicMetric) own = [view systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].width;
        width += own + row.spacing;
    }
    return width;
}

// The capsule's sides: Spotify's, the side toward the tab bar moved out until the title has kCapsuleTextWidth, but never
// nearer the tab bar's glass than kCapsuleTabGap. Spotify's own when it has room, nothing beside it to grow toward, or its
// sides cannot be read.
static BOOL widenCapsule(UIView *bar) {
    CGFloat left = 0, right = 0;
    UIStackView *row = buttonRow(bar, NULL, NULL);
    if (!row) return NO;
    if (!spotifyEdges(bar, &left, &right)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"now playing bar: the capsule's sides are not held by its superview's constraints, so it keeps Spotify's"); });
        return NO;
    }
    // Fit both trees from their constraints: the bar's frame can already have our new width while
    // the row still has the old one. Subtracting those frames feeds our own widening into the next pass.
    CGSize fittedBar = [bar systemLayoutSizeFittingSize:CGSizeMake(0, bar.bounds.size.height)
                        withHorizontalFittingPriority:UILayoutPriorityFittingSizeLevel
                              verticalFittingPriority:UILayoutPriorityRequired];
    CGSize fittedRow = [row systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGFloat wanted = fittedBar.width - fittedRow.width + rowButtonsWidth(row) + kCapsuleTextWidth;
    if (wanted <= right - left) return NO;
    CGRect glass = tabGlassBeside(bar);
    if (CGRectIsNull(glass)) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"now playing bar: no tab bar glass beside the capsule, so it keeps Spotify's width"); });
        return NO;
    }
    BOOL rtl = bar.superview.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat grown = rtl ? MIN(left + wanted, CGRectGetMinX(glass) - kCapsuleTabGap) : MAX(right - wanted, CGRectGetMaxX(glass) + kCapsuleTabGap);
    BOOL set = rtl ? grown > right && setEdges(bar, left, grown, YES) : grown < left && setEdges(bar, grown, right, YES);
    static dispatch_once_t once;
    if (set) dispatch_once(&once, ^{
        SGLog(@"now playing bar: the capsule grows from %.0f-%.0f to %.0f for a %.0f pt card", left, right, grown, wanted);
    });
    return set;
}

// Grown past its page's bounds, the capsule takes the touches there through the page's hit test: the glass's frame in
// `page`, or CGRectNull when the card is not a capsule.
static CGRect capsuleIn(UIView *page) {
    UIVisualEffectView *glass = sg_cardGlass;
    if (!sg_capsule || !glass.window || ![glass isDescendantOfView:page]) return CGRectNull;
    return [page convertRect:glass.bounds fromView:glass];
}

// The Music app's two lines, the title over the artists, in place of Spotify's "title • artists" and the
// device line under it; the title alone in the minimized row, the artists too when the Player page asks for
// them and both lines fit. Each swipe page holds its own track's labels,
// so the text is read from them and drawn over them page by page. The page reads its own VoiceOver label.
static NSString *const kPageId = @"now-playing-bar-page";
static NSString *const kUnitId = @"Components.UI.PageInformationUnitNowPlayingBar";
static NSString *const kDeviceLineId = @"now-plaging-bar-connect-content";   // Spotify's spelling
static NSString *const kBullet = @" • ";
static char kTextKey;
// In the row the two lines are this far apart, and need this much of the bar's height beyond their own.
static const CGFloat kRowLinesGap = 1, kRowLinesMargin = 6;

@interface SGRBarText : UIView
@property (nonatomic, readonly) SGMarqueeLabel *title, *artists;
@property (nonatomic) BOOL inRow;
// The Player page's Artist under the title when minimized (SGRKeyBarInlineArtist), as placeText read it.
@property (nonatomic) BOOL artistInRow;
@end

@implementation SGRBarText
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _title = [SGMarqueeLabel new];
    _title.textColor = SGRPrimary();
    _artists = [SGMarqueeLabel new];
    _artists.textColor = SGRSecondary();
    [self applyFonts];
    [self addSubview:_title];
    [self addSubview:_artists];
    __weak SGRBarText *weakSelf = self;
    SGRObserveVisibility(self, ^{ [weakSelf updateScrolling]; });
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateScrolling)
                                               name:SGRPlayerVisibilityDidChangeNotification object:nil];
    return self;
}

- (void)updateScrolling {
    UIWindow *window = self.window;
    // A pager changes its offset without laying the neighbouring title out again.
    // Coverage belongs to the bar, not to a page's momentary clipped rect.
    BOOL paused = !window || SGRPlayerLandscapeCovers(window);
    for (UIView *v = self; !paused && v; v = v.superview) {
        paused = v.hidden || v.alpha <= 0;
        if (!paused && v == sgr_nowPlayingRoot)
            paused = CGRectContainsRect(SGRSettledPlayerRect(window), [v convertRect:v.bounds toView:window]);
    }
    _title.scrollingPaused = paused;
    _artists.scrollingPaused = paused || _artists.alpha == 0;
}

// Capped at Large, so a bar made at one text size and shown at another needs them made again.
- (void)applyFonts {
    _title.font = SGCategoryCappedFont(UIFontTextStyleSubheadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    _artists.font = SGCategoryCappedFont(UIFontTextStyleFootnote, UIFontWeightRegular, UIContentSizeCategoryLarge);
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    if ([previous.preferredContentSizeCategory isEqualToString:self.traitCollection.preferredContentSizeCategory]) return;
    [self applyFonts];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat titleHeight = ceil(_title.font.lineHeight), artistsHeight = ceil(_artists.font.lineHeight);
    BOOL has = _artists.text.length > 0;
    // In the row the artists come under the title only when both lines fit the bar's height with room to spare.
    BOOL two = _inRow ? has && _artistInRow && titleHeight + artistsHeight + kRowLinesMargin <= size.height : has;
    // The full card's lines share 2pt of their leading, set as close as the Music app sets its card's; the row's
    // are parted by a point.
    CGFloat overlap = _inRow ? -kRowLinesGap : 2;
    CGFloat top = round((size.height - titleHeight - (two ? artistsHeight - overlap : 0)) / 2);
    _title.frame = CGRectMake(0, top, size.width, titleHeight);
    _artists.frame = CGRectMake(0, top + titleHeight - overlap, size.width, artistsHeight);
    _artists.alpha = two ? 1 : 0;
    [self updateScrolling];
}
@end

static NSString *marqueeText(UIView *marquee) {
    for (UIView *sub in marquee.subviews) if ([sub isKindOfClass:UILabel.class]) return ((UILabel *)sub).text;
    return nil;
}

// Not hidden or faded by Spotify between the view and the unit; the unit's own children are faded by this file.
static BOOL inSight(UIView *view, UIView *unit) {
    for (UIView *v = view; v && v != unit; v = v.superview) {
        if (v.hidden || (v.alpha < 0.01 && v.superview != unit)) return NO;
    }
    return YES;
}

// The title the player knows that the page's first line is: the line is the title alone, or the title, the
// bullet and the artists, whose first the track names. A title can hold the bullet itself, which the line alone
// cannot tell from the one that parts it. Every track the player knows is a candidate, since a page of the
// pager may show a neighbor: a title equal to the line wins, else the longest title the line starts with that
// the track's artist follows, so a short title ("Rock" by "Roll") never takes the line of a longer one
// ("Rock • Roll" by "The Band"). Nil when none matches.
static NSString *scanKnownTitle(SPTPlayerState *state, NSString *line, NSString *visibleArtist, SPTPlayerTrack **match) {
    NSMutableArray *tracks = [NSMutableArray array];
    if (state.track) [tracks addObject:state.track];
    if ([state.future isKindOfClass:NSArray.class]) [tracks addObjectsFromArray:state.future];
    if ([state.reverse isKindOfClass:NSArray.class]) [tracks addObjectsFromArray:state.reverse];
    NSString *best = nil;
    NSUInteger bestArtistLength = 0;
    for (id item in tracks) {
        if (![item isKindOfClass:NSClassFromString(@"SPTPlayerTrack")]) continue;
        SPTPlayerTrack *track = item;
        NSString *title = track.trackTitle, *artist = track.artistName;
        if (![title isKindOfClass:NSString.class] || !title.length) continue;
        if (title.length < best.length) continue;
        BOOL exact = [line isEqualToString:title];
        NSString *pageArtist = visibleArtist;
        if (!exact) {
            NSString *head = [title stringByAppendingString:kBullet];
            if (![line hasPrefix:head] || line.length == head.length) continue;
            pageArtist = [line substringFromIndex:head.length];
        }
        BOOL hasArtist = [artist isKindOfClass:NSString.class] && artist.length;
        NSUInteger artistLength = hasArtist && [pageArtist hasPrefix:artist] ? artist.length : 0;
        if (!exact && hasArtist && !artistLength) continue;
        if (exact && (!pageArtist.length || [pageArtist isEqualToString:artist])) {
            *match = track;
            return title;
        }
        // For equal titles the longest matching artist prefix wins; otherwise keep the first.
        if (title.length > best.length || artistLength > bestArtistLength) {
            best = title;
            bestArtistLength = artistLength;
            *match = track;
        }
    }
    return best;
}

// The scan's answers kept for the state object they were made for, keyed by the lines used to match, since the pager's pages each
// hold their own: the cells lay out far more often than either changes, and the player reports a new state
// object whenever it does. The state is held so that its address cannot be reused by another while the answers
// are kept.
static SPTPlayerState *sg_knownState;
static NSMutableDictionary *sg_knownTitles;

// With either title setting on, cache the track instead of just the split point's title.
static BOOL sg_showTitles;
static BOOL showTitlesEnabled(void) {
    return SGFlag(SGKeyLyricsSimplifyTitles, NO) || SGFlag(SGKeyLyricsTranslateTitles, NO);
}
static NSString *knownTitleOf(NSString *line, NSString *visibleArtist, SPTPlayerTrack **match) {
    SPTPlayerState *state = SGPlayerState();
    if (!sg_knownTitles || state != sg_knownState) {
        sg_knownTitles = [NSMutableDictionary dictionary];
        sg_knownState = state;
    }
    id key = visibleArtist.length ? (id)@[line, visibleArtist] : line;
    id known = sg_knownTitles[key];
    if (!known) {
        SPTPlayerTrack *track = nil;
        NSString *title = scanKnownTitle(state, line, visibleArtist, &track);
        known = (sg_showTitles ? (id)track : title) ?: NSNull.null;
        sg_knownTitles[key] = known;
    }
    if (known == NSNull.null) return nil;
    if (!sg_showTitles) return known;
    *match = known;
    return (*match).trackTitle;
}

static void placeText(UIView *page) {
    // The cell lays itself out before its content view places Spotify's text, so the text is placed first.
    [page layoutIfNeeded];
    __block UIView *unit = nil;
    SGForEachView(page, ^(UIView *v) {
        if (!unit && [v.accessibilityIdentifier isEqualToString:kUnitId]) unit = v;
    });
    // Spotify lays a page out two ways. With a device line under it, the unit's first marquee is "title • artists"
    // and a later one, hidden, holds the artists alone. Without one, the first is the title and the next one in
    // sight is the artists. A promotional line, held at no alpha, is never the artists.
    __block NSString *line = nil, *artists = nil, *shown = nil;
    if (unit) SGForEachView(unit, ^(UIView *v) {
        if (![v.accessibilityIdentifier isEqualToString:@"Encore.MarqueeLabel"]) return;
        NSString *text = marqueeText(v);
        if (!line) {
            line = text;
            return;
        }
        if (!text.length) return;
        if (!artists && [line hasSuffix:[kBullet stringByAppendingString:text]]) artists = text;
        if (!shown && inSight(v, unit)) shown = text;
    });
    if (!line.length) return;
    NSString *title = line;
    SPTPlayerTrack *track = nil;
    NSString *known = knownTitleOf(line, sg_showTitles ? shown : nil, &track);
    if (known) {
        title = known;
        artists = line.length > known.length ? [line substringFromIndex:known.length + kBullet.length] : shown;
        if (track) {
            id uri = track.URI;
            NSString *text = [uri isKindOfClass:NSURL.class] ? ((NSURL *)uri).absoluteString : [uri description];
            NSString *trackID = [text hasPrefix:@"spotify:track:"] ? [text substringFromIndex:@"spotify:track:".length] : nil;
            if (trackID || [text hasPrefix:@"spotify:local:"]) {
                NSString *artist = track.artistName, *translated = nil;
                title = SGRShownTitle(trackID, known, artist, &translated);
                if (translated.length && ![translated isEqualToString:artist] && [artists isEqualToString:artist])
                    artists = translated;
            }
        }
    } else if (artists) {
        title = [line substringToIndex:line.length - artists.length - kBullet.length];
    } else {
        NSRange bullet = [line rangeOfString:kBullet];
        if (bullet.location != NSNotFound) {
            title = [line substringToIndex:bullet.location];
            artists = [line substringFromIndex:NSMaxRange(bullet)];
        } else {
            artists = shown;
        }
    }

    SGRBarText *text = objc_getAssociatedObject(page, &kTextKey);
    BOOL made = !text;
    if (made) {
        text = [SGRBarText new];
        objc_setAssociatedObject(page, &kTextKey, text, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Inside Spotify's unit, so the text moves and fades with it as Spotify slides a page's in and out: the page's
    // height, which the card shows whole, and a line of text wide.
    CGRect frame = CGRectMake(0, -SGFrameIn(unit, page).origin.y, unit.bounds.size.width, page.bounds.size.height);
    BOOL inRow = sg_inline != nil;
    void (^place)(void) = ^{
        if (text.superview != unit) [unit addSubview:text];
        else if (unit.subviews.lastObject != text) [unit bringSubviewToFront:text];
        if (!CGRectEqualToRect(text.frame, frame)) text.frame = frame;
        text.title.text = title;
        text.artists.text = artists ?: @"";
        // Every pass: the artists can come in after the title.
        text.inRow = inRow;
        text.artistInRow = SGHidden(SGRKeyBarInlineArtist);
        [text setNeedsLayout];
        [text layoutIfNeeded];
    };
    // A new page's text is placed where it belongs, never grown from nothing inside the bar's animation.
    if (made) [UIView performWithoutAnimation:place];
    else place();
    for (UIView *sub in unit.subviews) if (sub != text && sub.alpha > 0) sub.alpha = 0;
}

static void placeTexts(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        NSString *name = v.accessibilityIdentifier;
        if ([name isEqualToString:kPageId]) placeText(v);
        else if ([name isEqualToString:kDeviceLineId] && v.alpha > 0) v.alpha = 0;
    });
}

// In the minimized tab bar's row (TabBar.x): the bar narrowed to the slot by its edges, so Spotify's content
// lays itself out to the width, and moved down by a transform on the container's view, which Spotify's
// layout leaves alone. Outside a Jam only: its strip has no room in the row. Above the bar the card takes the
// expanded glass row's edges (SGRTabBarGlassRow) the same way, as the Music app's mini player stands as wide as its
// tab bar, and Spotify's own edges where there is no row (a regular width) or its edges cannot be set (right to left).
static void placeInline(UIViewController *container) {
    UIView *view = container.view;
    UIView *bar = container.childViewControllers.firstObject.viewIfLoaded;
    UIView *strip = bar ? stripIn(bar) : nil;
    BOOL jam = strip && !strip.hidden && strip.alpha >= 0.01 && strip.window && strip.bounds.size.height >= 1;
    CGRect slot = !bar || bar.superview != view || jam ? CGRectNull : SGRTabBarInlineSlot(view.superview, bar.bounds.size.height);
    // Where the view stands untransformed, in the slot's coordinates.
    CGPoint origin = CGPointMake(view.center.x - view.bounds.size.width / 2, view.center.y - view.bounds.size.height / 2);
    if (!edgesTo(bar, slot, origin)) {
        sg_inline = nil;
        if (bar) tuckExtras(bar, sg_capsule ? SGRBarTuckCapsule : SGRBarTuckNone);
        if (!CGAffineTransformIsIdentity(view.transform)) view.transform = CGAffineTransformIdentity;
        CGRect row = bar && bar.superview == view ? SGRTabBarGlassRow(view.superview) : CGRectNull;
        if (!edgesTo(bar, row, origin) && !(sg_capsule && bar.superview == view && widenCapsule(bar))) restoreEdges(bar);
        if (bar) placeTexts(bar);
        return;
    }
    CGAffineTransform move = CGAffineTransformMakeTranslation(0, CGRectGetMidY(slot) - origin.y - CGRectGetMidY(bar.frame));
    if (!CGAffineTransformEqualToTransform(view.transform, move)) view.transform = move;
    tuckExtras(bar, SGRBarTuckRow);
    sg_inline = view;
    placeTexts(bar);
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableString *clips = [NSMutableString string];
        for (UIView *v = view.superview; v; v = v.superview) if (v.clipsToBounds) [clips appendFormat:@" %@", v.class];
        SGLog(@"now playing bar in the tab bar's row at %@, clipped by:%@", NSStringFromCGRect(slot), clips.length ? clips : @" nothing");
    });
}

void SGRNowPlayingBarFollowTabBar(void) {
    UIViewController *container = sg_container;
    if (!container.isViewLoaded) return;
    placeInline(container);
    [container.view setNeedsLayout];
    [container.view layoutIfNeeded];
}

// The same bar class also stands at the top of Spotify's sheets (the DJ request one: Up next, device, play).
// It is not the tab bar's card there: the sheet has its own blue ground and corners, and a dark 24pt pane of
// the bar's full width on it reads as a frame round the track. It is left as Spotify draws it, its device button
// too (BarConnect.x), and it must not become the bar this file tracks (sg_container, sg_cardGlass,
// sgr_nowPlayingRoot): the player takes its card frame from those.
BOOL SGRBarInSheet(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:@"sheet-view"] || [NSStringFromClass(v.class) containsString:@"SheetImpl"]) return YES;
    }
    return NO;
}

static void styleNowPlayingBar(UIViewController *container) {
    if (container.isViewLoaded && SGRBarInSheet(container.view)) {
        UIVisualEffectView *pane = objc_getAssociatedObject(container.view, &kGlassKey);
        if (pane) [pane removeFromSuperview];
        return;
    }
    UIViewController *barVC = container.childViewControllers.firstObject;
    UIView *bar = barVC.viewIfLoaded ?: container.view;
    sg_container = container;
    if (!sgr_nowPlayingPainted) sgr_nowPlayingPainted = [NSHashTable weakObjectsHashTable];
    sgr_nowPlayingRoot = bar;

    // What is painted now, before it goes clear; SGRRepaint.x adds what Spotify paints later. Its size is
    // judged when the card is chosen: in a Jam the card can still be unsized here (harness/tabbar).
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UIVisualEffectView.class] && !SGKeepsColor(v) && SGIsVisibleColor(v.layer.backgroundColor)) [sgr_nowPlayingPainted addObject:v];
    });
    // The card stays while it still holds the track with no strip in it, whatever Spotify paints after.
    UIView *marker = trackMarker(bar);
    UIView *card = sg_card;
    if (!card || !isGoodCard(card, bar, marker) || stripIn(card)) card = sg_card = chooseCard(bar, marker);

    container.view.layer.backgroundColor = NULL;
    SGStripBackgrounds(bar);

    UIView *strip = stripIn(bar);
    if (strip && (strip.hidden || strip.alpha < 0.01 || !strip.window)) strip = nil;
    // Spotify lays the strip out after the bar and moves it in, so the bar is styled again a moment after
    // the strip has moved, until it stays put.
    CGRect stripFrame = strip ? SGFrameIn(strip, container.view) : CGRectZero;
    if (!CGRectEqualToRect(stripFrame, sg_stripFrame)) {
        sg_stripFrame = stripFrame;
        UIView *host = container.view;
        dispatch_async(dispatch_get_main_queue(), ^{ [host setNeedsLayout]; });
    }
    if (strip.bounds.size.height < 1) strip = nil;
    BOOL capsule = SGRPlayerIPadRegular(container.view);
    if (capsule != sg_capsule) {
        sg_capsule = capsule;
        SGLog(@"now playing bar: %@", capsule ? @"the iPad capsule" : @"the card");
    }
    placeNextButton(bar);
    placeCapsuleButtons(bar, capsule);
    placeInline(container);

    CGRect frame = card ? SGFrameIn(card, container.view) : contentBounds(bar, container.view);
    if (CGRectIsNull(frame)) return;
    // The strip comes out of the card's glass from its side: all of it when the card is a view around both,
    // else as much as overlaps.
    BOOL stripAbove = NO;
    if (strip) {
        stripAbove = CGRectGetMidY(stripFrame) < CGRectGetMidY(frame);
        CGFloat cut = card && [strip isDescendantOfView:card] ? strip.bounds.size.height : CGRectIntersection(frame, stripFrame).size.height;
        frame.size.height -= cut;
        if (stripAbove) frame.origin.y += cut;
    }
    frame.size.height = MIN(frame.size.height, 80);
    if (frame.size.height < 30 || frame.size.width < 100) return;

    CGFloat radius = capsule ? frame.size.height / 2 : MIN(kCardRadius, frame.size.height / 2);
    if (card) {
        roundView(card, radius);
        restyleCardContent(card);
    }

    BOOL made = objc_getAssociatedObject(container.view, &kGlassKey) != nil;
    UIVisualEffectView *glass = SGGlassFor(container.view, &kGlassKey);
    if (!made) glass.effect = SGRGlassEffect();
    // Dark whatever the system is set to: the bar is outside the navigation stacks Spotify makes dark, and
    // took the system's light glass on a phone in light mode (TabBar.x).
    if (glass.overrideUserInterfaceStyle != UIUserInterfaceStyleDark) glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    sg_cardGlass = glass;
    glass.frame = frame;
    SGShapeGlass(glass, radius, capsule);
    placeStripGlass(container.view, strip, frame, stripAbove);
    watchCard(container.view, frame, radius);

    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SGLog(@"now playing card %@ at %@ (bar %@, container %@)", card.class, NSStringFromCGRect(frame),
              NSStringFromCGRect(bar.frame), NSStringFromCGRect(container.view.bounds));
    });
    static dispatch_once_t jamOnce;
    if (strip) dispatch_once(&jamOnce, ^{
        SGLog(@"now playing card in a Jam: %@ at %@, strip %@ at %@ (bar %@)", card.class, NSStringFromCGRect(frame), strip.class,
              NSStringFromCGRect(SGFrameIn(strip, container.view)), NSStringFromCGRect(bar.frame));
    });
}

%hook _TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    styleNowPlayingBar((UIViewController *)self);
}
%end

// The page the bar stands in passes touches outside the bar through, and the bar in the tab bar's row is
// below the page's bounds: a touch there reaches the bar only through this. Only the narrowed card takes
// one: the container's view keeps the screen's width, and took the touches meant for the tab bar's circles.
// Only the container's view moves to the row, by a transform; Spotify's layout view above it stays at the
// bar's old place and took every touch there (#70), so a touch on nothing of the moved bar's goes through.
// Next's whole touch target is reached here too (nextButtonHit), and the iPad capsule where it has grown past the
// page's bounds (capsuleIn), which UIKit asks the page about only once its pointInside: says the touch is its.
%group SGRBarTouchHooks
%hook SGRBarTouchView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return %orig || CGRectContainsPoint(capsuleIn((UIView *)self), point);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    UIView *next = nextButtonHit((UIView *)self, point, event);
    if (next) return next;
    UIView *card = sg_container.viewIfLoaded;
    UIView *bar = sg_container.childViewControllers.firstObject.viewIfLoaded;
    if (bar && (!hit || ![hit isDescendantOfView:card]) && CGRectContainsPoint(capsuleIn((UIView *)self), point)) {
        UIView *inside = [bar hitTest:[(UIView *)self convertPoint:point toView:bar] withEvent:event];
        if (inside) return inside;
    }
    UIView *moved = sg_inline;
    if (![moved isDescendantOfView:(UIView *)self] || (hit && [hit isDescendantOfView:moved])) return hit;
    UIView *inside = [moved hitTest:[(UIView *)self convertPoint:point toView:moved] withEvent:event];
    return inside && inside != moved ? inside : nil;
}
%end
%end

// A page lays out again when Spotify moves its text, which it does after the first pass at launch.
%hook _TtC18NowPlaying_BarImpl17InformationCellV2
- (void)layoutSubviews {
    %orig;
    if (sgr_nowPlayingRoot && [(UIView *)self isDescendantOfView:sgr_nowPlayingRoot]) placeText((UIView *)self);
}
%end

%hook _TtC18NowPlaying_BarImpl15InformationCell
- (void)layoutSubviews {
    %orig;
    if (sgr_nowPlayingRoot && [(UIView *)self isDescendantOfView:sgr_nowPlayingRoot]) placeText((UIView *)self);
}
%end

// A page's marquee lays out again when Spotify gives it a new track, which nothing else of the bar's does.
%hook _TtCE14Encore_TextKitO16EncoreFoundation6Encore12MarqueeLabel
- (void)layoutSubviews {
    %orig;
    UIView *root = sgr_nowPlayingRoot;
    if (!root || ![(UIView *)self isDescendantOfView:root]) return;
    for (UIView *v = (UIView *)self; v && v != root; v = v.superview) {
        if ([v.accessibilityIdentifier isEqualToString:kPageId]) {
            placeText(v);
            return;
        }
    }
}
%end

%hook _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLayoutSubviews {
    %orig;
    UIViewController *parent = ((UIViewController *)self).parentViewController;
    if ([NSStringFromClass(parent.class) containsString:@"NowPlayingBarContainer"]) styleNowPlayingBar(parent);
}
%end

static SGRBarOptionsWatcher *sg_optionsWatcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    Class touch = SGFileprivateViewClass("_TtC22NowPlaying_BarPageImplP33_CCC0D2EEA6D4725EECD8965E8C38C86D20TouchPassthroughView", UIView.class);
    if (touch) {
        %init(SGRBarTouchHooks, SGRBarTouchView = touch);
    } else SGLog(@"TouchPassthroughView not found, its hooks are inactive");
    sg_optionsWatcher = [SGRBarOptionsWatcher new];
    SGAddPlayerStateObserver(sg_optionsWatcher);
    sg_showTitles = showTitlesEnabled();
    for (NSString *name in @[SGSimplifyTitlesDidChangeNotification, SGTranslatedTitleDidChangeNotification,
                             SGTitleTranslationSettingsDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
            // The next layout places every page after the player has applied its own settings notification.
            dispatch_async(dispatch_get_main_queue(), ^{
                BOOL enabled = showTitlesEnabled();
                if (!enabled && !sg_showTitles) return;
                if (sg_showTitles != enabled) [sg_knownTitles removeAllObjects];
                sg_showTitles = enabled;
                [sgr_nowPlayingRoot setNeedsLayout];
            });
        }];
    }
    // Posted on the main thread.
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *note) { showPlayerOptions(); }];
    SGRequireClasses(@[
        @"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController",
        @"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController",
        @"_TtCE14Encore_TextKitO16EncoreFoundation6Encore12MarqueeLabel",
        @"_TtC18NowPlaying_BarImpl17InformationCellV2",
    ]);
}
