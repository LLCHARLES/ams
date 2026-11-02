// Player redesign: the cover sits on the field with continuous corners and a soft shadow, and shrinks
// back while playback is paused, the way the Music app's does. Spotify's lyric preview under it, and the cover's size
// beside it, are Spotify's, as its own lyrics setting has them.
//
// The player's cover is drawn where the Music app draws it, as measured off its player (402 x 874pt): square,
// the screen's width less 23pt either side, its top 94.8pt down the screen, just under the header row.
// Spotify centers its tilt view in a taller artwork band, which stands the cover 72pt lower; the tilt view is
// moved on up by a transform (a transform survives the cell laying its views out again), so the cover, its
// corners, plate, image and touches go together, and the field behind it -- not the cover at all -- does not move.
//
// Tree (trees/clean/player/01.txt:36-43): CoverArtCellImpl > ... > CoverArtTiltView 354x354 > an
// ElementView the same size > ImageViewProxy > Encore.ImageView (clips) > UIImageView, with
// Lyrics_NPVContainerKit.LyricsContainerView under the tilt view. The ElementView is what gets the
// corners and the scale: the tilt view's own transform is left to the tilt Spotify gives it when the
// cover is inspected. The image clips, so the shadow is a plate of the Kit's behind it.
//
// A paused cover keeps its shrink while the player opens and closes: the morph flies the bar's cover to
// the frame the cover is drawn at, transform included (SGRPlayerCoverFrameIn), so it lands at the size it
// stays at. Holding it at full size through the transition made it land large and spring down after, or
// grow before a close.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"

static const CGFloat kPausedScale = 0.84;
// The bar's 40pt cover lives in a tilt view of its own; the player's is 354.
static const CGFloat kCoverMinWidth = 200;
// The Music app's cover, measured off its player on the iPhone 16 Pro the layouts were compared on
// (402 x 874pt, 3x): 356pt square, 23pt in from either side of the screen and its top 94.8pt down it, just
// under the header row. Spotify centers its 354pt tilt view in a taller artwork band, which draws the cover
// 72pt lower there (167pt down). The cover may be this much wider than Spotify's tilt view, whose margins are
// its own, and no more.
static const CGFloat kArtworkInset = 23, kArtworkWider = 2.2;
// The cover's top as a share of the screen's height (94.8 of 874), and the least room the header row's buttons
// are left under the safe area's top on a shorter screen.
static const CGFloat kArtworkTopShare = 0.1085, kArtworkTopGap = 33;

static char kPlateKey, kGeoKey;
static NSHashTable<UIView *> *sg_tilts;
// The cover of each tilt view once found. A frame Spotify sets on a scaled view becomes its scaled
// size, leaving bounds that no longer match the tilt view's, so the cover is not looked for by size again.
static NSMapTable<UIView *, UIView *> *sg_covers;

static CGFloat currentScale(void) {
    SPTPlayerState *state = SGPlayerState();
    if (!state.isPaused) return 1;
    return SGRReduceMotion() ? 1 : kPausedScale;
}

// The child of the tilt view the size of the cover.
static UIView *coverIn(UIView *tilt) {
    UIView *cover = [sg_covers objectForKey:tilt];
    if (cover.superview == tilt) return cover;
    UIView *best = nil;
    for (UIView *sub in tilt.subviews) {
        if ([sub isKindOfClass:SGRShadowPlate.class]) continue;
        if (CGSizeEqualToSize(sub.bounds.size, tilt.bounds.size)) {
            [sg_covers setObject:sub forKey:tilt];
            return sub;
        }
        // A cover the tilt was sized for a pass ago, or one a frame set off its center: still the square view
        // the tilt draws, the largest of them. A cell reused for the next track can come with one of these,
        // and the pass that could not find it left the cover where Spotify had it until the next one.
        CGSize size = sub.bounds.size;
        if (size.width >= kCoverMinWidth && fabs(size.width - size.height) < 1 && (!best || size.width > best.bounds.size.width)) best = sub;
    }
    if (best) [sg_covers setObject:best forKey:tilt];
    return best;
}

static BOOL inCoverCell(UIView *tilt) {
    static Class cell;
    if (!cell) cell = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl");
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell]) return YES;
    }
    return NO;
}

static void scaleCover(UIView *tilt, CGFloat scale) {
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    cover.transform = transform;
    plate.transform = transform;
}

#pragma mark - the Music app's cover geometry

// Where the cover's top belongs, in the window: kArtworkTopShare of the screen down, and no higher than the
// header row's buttons are left on a shorter screen. NAN for the 3D cover, drawn full screen (twice the bar's
// cover's least), whose tilt view is left where Spotify has it.
static CGFloat coverTargetInWindow(UIView *tilt) {
    UIWindow *window = tilt.window;
    if (!window || tilt.bounds.size.height > kCoverMinWidth * 2) return NAN;
    return MAX(CGRectGetHeight(window.bounds) * kArtworkTopShare, window.safeAreaInsets.top + kArtworkTopGap);
}

// The side the player's cover is drawn at: the screen's width less the Music app's margins, and never much wider
// than the tilt view Spotify sized for it (its own 24pt margins, 354 at this player's width). The bar's small
// cover is not this one (kCoverMinWidth). It is also no taller than the room the ordinary player's title row
// leaves under it: the row settles kInfoLift above where Spotify draws it (PlayerLyrics.x), and sizing the cover
// to that keeps the two apart on a short screen instead of drawing the row under the cover.
static CGFloat coverSide(UIView *tilt, CGSize tiltSize) {
    CGFloat screen = tilt.window ? CGRectGetWidth(tilt.window.bounds) : 0;
    if (screen <= 0) return tiltSize.width;
    CGFloat side = MAX(kCoverMinWidth, MIN(screen - 2 * kArtworkInset, tiltSize.width + kArtworkWider));
    // Only room worth taking is taken: a room under kCoverMinWidth says the screen is too short for either
    // layout's numbers, and a cover shrunk to it would be no better than Spotify's place kept.
    CGFloat target = coverTargetInWindow(tilt), lowest = SGRPlayerCoverMaxBottomInWindow();
    if (!isnan(target) && !isnan(lowest) && lowest - target > kCoverMinWidth) side = MIN(side, lowest - target);
    return side;
}

// Moves the tilt view so that the cover, centered in it, is drawn with its top at that place. The move is read
// off where the cover is drawn now -- the tilt's transform included -- and put on as a translation, so a pass
// that runs before the cell's band has laid out lands the cover anyway; the next pass reads the new place and
// keeps it. Waiting until the band was measurable was what left a fresh or reused cell's cover at Spotify's own
// place for a pass, 70pt under the lifted title row, and then jumped it up (PlayerLyrics.x measures the row from
// a settled cover now, so neither follows the other's pass).
static void pinCover(UIView *tilt, CGFloat side) {
    UIView *band = tilt.superview;
    CGFloat target = coverTargetInWindow(tilt);
    if (!band || isnan(target)) return;
    // Both places in the band's own coordinates, so the distance is the translation the move is made in even
    // while a pass runs inside an animation that scales the player.
    CGPoint coverTop = [band convertPoint:CGPointMake(0, (tilt.bounds.size.height - side) / 2) fromView:tilt];
    CGFloat targetInBand = [band convertPoint:CGPointMake(0, target) fromView:nil].y;
    CGAffineTransform lift = tilt.transform;
    lift.ty -= coverTop.y - targetInBand;
    if (!CGAffineTransformEqualToTransform(tilt.transform, lift)) tilt.transform = lift;
}

#pragma mark - where the cover is

// The tilt view of the cover on screen: the queue is a cover per cell and the cells out of view are
// kept hidden (player/02.txt:521), so the one showing is the one in a window with nothing hidden over it. On the first
// open the cells off to the side are not hidden yet, so it must also sit across the screen, not a page off it.
static UIView *showingTilt(void) {
    for (UIView *tilt in sg_tilts) {
        UIWindow *window = tilt.window;
        if (!window) continue;
        if (!SGShownUnder(tilt, nil)) continue;
        CGFloat middle = CGRectGetMidX([tilt convertRect:tilt.bounds toView:nil]);
        if (middle >= 0 && middle <= CGRectGetWidth(window.bounds)) return tilt;
    }
    return nil;
}

UIView *SGRPlayerCoverList(void) {
    for (UIView *v = showingTilt(); v; v = v.superview) {
        if ([v isKindOfClass:UICollectionView.class]) return v;
    }
    return nil;
}

CGRect SGRPlayerCoverFrameIn(UIView *host) {
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    // The cover's own transform is the paused shrink, which is what the eye sees it at.
    return cover && host ? [host convertRect:cover.bounds fromView:cover] : CGRectNull;
}

CGFloat SGRPlayerCoverScale(void) {
    return currentScale();
}

// The tilt view drawing the cover on screen, and the cover it draws in `host`'s coordinates, paused shrink
// included (PlayerGestures.x asks before it lets a tap through). CGRectNull when there is none.
UIView *SGRPlayerCoverTilt(void) {
    return showingTilt();
}

CGRect SGRPlayerCoverRectIn(UIView *tilt, UIView *host) {
    UIView *cover = coverIn(tilt);
    return cover && host ? [host convertRect:cover.bounds fromView:cover] : CGRectNull;
}

// The cover at the place it settles at, in `host`: square, its top where the Music app draws it, its middle the
// tilt view's, and the paused shrink left out. The title row measures its gap from this, not from the frame a
// pass happens to draw (SGRPlayerCoverFrameIn follows the tilt's transform and a cell reused for the next track
// can still be at Spotify's place for a pass), so the row stays put through a track change. The tilt view's own
// transform is not in it: its center is where Spotify centered it, and the cover is placed from there.
CGRect SGRPlayerCoverRestFrameIn(UIView *host) {
    UIView *tilt = showingTilt();
    CGFloat target = tilt ? coverTargetInWindow(tilt) : NAN;
    if (!tilt || !host || isnan(target)) return SGRPlayerCoverFrameIn(host);
    UIView *band = tilt.superview ?: tilt;
    CGPoint middle = [band convertPoint:tilt.center toView:nil];
    CGFloat side = coverSide(tilt, tilt.bounds.size);
    return [host convertRect:CGRectMake(middle.x - side / 2, target, side, side) fromView:nil];
}

CGRect SGRPlayerArtworkAreaIn(UIView *host) {
    UIView *tilt = showingTilt();
    if (!tilt || !host) return CGRectNull;
    // The band is the first view over the cover as wide as the player: the cover sits inset inside it
    // (01.txt:33-36, CoverArtCellImpl > UIView {0, 110, 402, 466.67} > UIView {24, 8, ...} > the tilt view).
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if (v == host) break;
        if (v.bounds.size.width >= host.bounds.size.width - 1) return [host convertRect:v.bounds fromView:v];
    }
    return CGRectNull;
}

// The cover hidden for a stand-in, so the same one comes back if the list moved on meanwhile.
static __weak UIView *sg_hiddenCover, *sg_hiddenPlate;
// Asked for while no cover was laid out yet (the first open): the cover is hidden in the layout pass that makes it,
// so its first frame on screen is already hidden.
static BOOL sg_coverKeptHidden;

void SGRPlayerSetCoverHidden(BOOL hidden) {
    sg_hiddenCover.alpha = SGRReduceMotion() && SGPlayerState().isPaused ? 0.75 : 1;
    sg_hiddenPlate.alpha = 1;
    sg_hiddenCover = sg_hiddenPlate = nil;
    sg_coverKeptHidden = hidden;
    if (!hidden) return;
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    UIView *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    cover.alpha = 0;
    plate.alpha = 0;
    sg_hiddenCover = cover;
    sg_hiddenPlate = plate;
}

#pragma mark - the paused shrink

static void scaleEveryCover(BOOL animated) {
    CGFloat scale = currentScale();
    NSArray<UIView *> *tilts = sg_tilts.allObjects;
    void (^apply)(void) = ^{
        for (UIView *tilt in tilts) {
            scaleCover(tilt, scale);
            UIView *cover = coverIn(tilt);
            if (cover != sg_hiddenCover) cover.alpha = SGRReduceMotion() && SGPlayerState().isPaused ? 0.75 : 1;
        }
    };
    if (animated) SGRAnimate(SGRReduceMotion() ? SGRMotionRespond : SGRMotionLayout, apply, nil);
    else apply();
}

#pragma mark - hold to play faster

// Holding either side of the cover plays at kHoldSpeed until the finger lifts, and the speed set before
// comes back. The middle third is left alone, and a hold that starts to move is a swipe to the next track.
// It is a speed like the menu's, so with Pitch follows speed on (until switched off) it also plays an
// octave higher, the way a record does. The native look's copy is in Native/Player/PlayerGestures.x.
static const double kHoldSpeed = 2;
static char kHoldKey, kBadgeGlassKey;

@interface SGRCoverHold : UILongPressGestureRecognizer
@end

@implementation SGRCoverHold {
    double _before;
    UIView *_badge;
    UILabel *_badgeLabel;
    BOOL _badgeShown;
}

- (void)sgr_held {
    UIView *cover = self.view;
    if (self.state == UIGestureRecognizerStateBegan) {
        CGFloat x = [self locationInView:cover].x, third = cover.bounds.size.width / 3;
        if ((x > third && x < 2 * third) || !SGPlayerSpeedAllowed()) {
            self.enabled = NO;
            self.enabled = YES;   // cancels this hold
            return;
        }
        _before = SGPlayerSpeed();
        SGSetPlayerSpeed(kHoldSpeed);
        SGPlayFeedback(SGFeedbackGrab);
        [self showBadge:YES on:cover];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, @"Playing at 2 times speed");
    } else if (self.state == UIGestureRecognizerStateEnded || self.state == UIGestureRecognizerStateCancelled
               || self.state == UIGestureRecognizerStateFailed) {
        if (_before > 0) SGSetPlayerSpeed(_before);
        _before = 0;
        [self showBadge:NO on:cover];
    }
}

// "2×" and a forward glyph on the Kit's glass capsule at the top of the cover while it is held. What fades
// is the glass's effect (SGRShowGlass), never an alpha over it; the capsule grows in from 0.9 with the Kit's
// press spring and goes with its exit, quicker than it came: the finger is already off the cover.
- (void)showBadge:(BOOL)shown on:(UIView *)cover {
    if (shown && !_badge) {
        _badgeLabel = [UILabel new];
        UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        NSTextAttachment *arrows = [NSTextAttachment textAttachmentWithImage:[[UIImage systemImageNamed:@"forward.fill"
            withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font]] imageWithTintColor:UIColor.whiteColor
            renderingMode:UIImageRenderingModeAlwaysOriginal]];
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithString:@"2×  "
            attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor}];
        [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:arrows]];
        _badgeLabel.attributedText = text;
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 92, 34)];
        _badge.userInteractionEnabled = NO;
        _badgeLabel.frame = _badge.bounds;
        _badgeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_badge addSubview:_badgeLabel];
    }
    if (!_badge) return;
    _badgeShown = shown;
    UIView *badge = _badge, *label = _badgeLabel;
    // Made again by the Kit if Reduce Transparency changed: then it is a solid fill, which fades by alpha.
    UIView *shape = SGRGlassCapsuleInside(badge, &kBadgeGlassKey, badge.bounds.size, NO);
    void (^state)(BOOL) = ^(BOOL on) {
        SGRShowGlass(shape, on);
        label.alpha = on ? 1 : 0;
    };
    if (shown) {
        if (badge.superview != cover) {
            badge.center = CGPointMake(CGRectGetMidX(cover.bounds), 30);
            state(NO);
            badge.transform = SGRReduceMotion() ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.9, 0.9);
            [cover addSubview:badge];
        }
        // A fade alone under Reduce Motion, where the Kit's spring would be no animation at all.
        SGRAnimate(SGRReduceMotion() ? SGRMotionFade : SGRMotionPress, ^{
            state(YES);
            badge.transform = CGAffineTransformIdentity;
        }, nil);
    } else {
        SGRAnimate(SGRMotionExit, ^{ state(NO); }, ^(BOOL finished) {
            if (finished && !self->_badgeShown) [badge removeFromSuperview];
        });
    }
}

@end

static void watchHold(UIView *tilt) {
    if (objc_getAssociatedObject(tilt, &kHoldKey)) return;
    SGRCoverHold *hold = [[SGRCoverHold alloc] initWithTarget:nil action:nil];
    [hold addTarget:hold action:@selector(sgr_held)];
    hold.minimumPressDuration = 0.35;
    [tilt addGestureRecognizer:hold];
    objc_setAssociatedObject(tilt, &kHoldKey, hold, OBJC_ASSOCIATION_ASSIGN);
}

// The tilt and the cover as the phone has them, logged when the state changes (and on a track change, beside
// the cover's own passes): the frame, bounds, center and transform through a track change are what a cover
// that jumps up is read from.
static void logGeometry(UIView *tilt, UIView *cover, NSString *when) {
    if (!tilt) return;
    NSString *state = [NSString stringWithFormat:@"%@|%.1f,%.1f|%@|%@|%@|%@", when,
                       tilt.center.x, tilt.center.y, NSStringFromCGAffineTransform(tilt.transform),
                       cover ? NSStringFromCGRect(cover.frame) : @"-",
                       cover ? NSStringFromCGAffineTransform(cover.transform) : @"-",
                       cover ? NSStringFromCGSize(cover.bounds.size) : @"-"];
    if ([state isEqualToString:objc_getAssociatedObject(tilt, &kGeoKey)]) return;
    objc_setAssociatedObject(tilt, &kGeoKey, state, OBJC_ASSOCIATION_COPY_NONATOMIC);
    SGLog(@"redesign player: artwork %@: tilt frame %@ bounds %@ center %@ transform %@; cover %@ frame %@ bounds %@ transform %@; window %@",
          when, NSStringFromCGRect(tilt.frame), NSStringFromCGRect(tilt.bounds), NSStringFromCGPoint(tilt.center),
          NSStringFromCGAffineTransform(tilt.transform), cover ? NSStringFromClass(cover.class) : @"none",
          cover ? NSStringFromCGRect(cover.frame) : @"-", cover ? NSStringFromCGRect(cover.bounds) : @"-",
          cover ? NSStringFromCGAffineTransform(cover.transform) : @"-",
          tilt.window ? NSStringFromCGSize(tilt.window.bounds.size) : @"none");
}

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
- (void)layoutSubviews {
    UIView *tilt = (UIView *)self;
    %orig;
    // The width first: the bar's and the pages' small tilt views skip the walk up to the cell.
    if (tilt.bounds.size.width < kCoverMinWidth || !inCoverCell(tilt)) return;
    [sg_tilts addObject:tilt];
    // Kept hidden, it is whichever cover is showing: the first open can lay out a second cell in its place. Not animated,
    // though this pass may run inside Spotify's transition.
    if (sg_coverKeptHidden && showingTilt() == tilt) {
        UIView *kept = coverIn(tilt);
        if (kept && kept != sg_hiddenCover) [UIView performWithoutAnimation:^{ SGRPlayerSetCoverHidden(YES); }];
    }
    watchHold(tilt);
    SGRPlayerMotionCoverLaidOut();
    // The cover fills the tilt view (01.txt:37) and is drawn where the Music app draws it: square, the screen's
    // width less its margins, its top just under the header row rather than centered in Spotify's taller band.
    // The move is the tilt view's, as a transform: the cell writes its frame again on every pass and a transform
    // survives that, and the cover's image, corners, shadow plate and its touches all move with it. The frames the
    // lyrics' thumbnail and the open's flown cover read (SGRPlayerCoverFrameIn) take the transform in.
    // Bounds and center, unlike a frame, hold under the scale.
    CGRect bounds = tilt.bounds;
    CGPoint middle = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGFloat side = coverSide(tilt, bounds.size);
    CGSize size = CGSizeMake(side, side);
    // Every write below is written without animation: a pass that runs inside Spotify's track change would
    // otherwise animate the tilt from the old place (or from Spotify's own) to the new one, which is the cover
    // seen jumping. Spotify's crossfade of the artwork itself is its own and is not touched by this.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // The cover is placed before it is looked for: a cell reused for the next track lays its cover out a pass
    // later, and waiting for it left the tilt at Spotify's place, to jump up when the next pass moved it.
    pinCover(tilt, side);
    UIView *cover = coverIn(tilt);
    if (!cover) {
        [CATransaction commit];
        logGeometry(tilt, nil, @"laid out, no cover");
        return;
    }
    if (!CGSizeEqualToSize(cover.bounds.size, size)) cover.bounds = (CGRect){cover.bounds.origin, size};
    if (!CGPointEqualToPoint(cover.center, middle)) cover.center = middle;
    // Its image is placed again for the new size (the ImageViewProxy hook below makes it fill the cover).
    for (UIView *image in cover.subviews) {
        if (!CGRectEqualToRect(image.frame, cover.bounds)) image.bounds = image.bounds, image.center = image.center;
    }

    cover.layer.cornerRadius = SGRRadiusArtwork;
    cover.layer.cornerCurve = kCACornerCurveContinuous;
    cover.clipsToBounds = YES;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    plate.bounds = cover.bounds;
    plate.center = cover.center;
    // The same value an animation in flight is heading to, so a layout pass never cuts one short.
    scaleCover(tilt, currentScale());
    [CATransaction commit];
    logGeometry(tilt, cover, @"laid out");

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: cover %@ rounded %.0f with a shadow plate, scale %.2f", NSStringFromClass(cover.class), SGRRadiusArtwork, currentScale()); });
}
%end

// The cover's image (ImageViewProxy > Encore.ImageView) keeps the size Spotify gave it for a cell with the preview,
// 317 in a 345 box on a track with lyrics, at the box's top left: the image sat off center with a blank band right
// and under it (issue #21). In the player's cover it fills the box the cover now is, whatever size it is given.
// Auto Layout places it through its bounds and center, a frame set by hand through its frame.
static UIView *coverOfImage(UIView *image) {
    UIView *box = image.superview;
    return box && coverIn(box.superview) == box ? box : nil;
}

%hook _TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy
- (void)setFrame:(CGRect)frame {
    UIView *box = coverOfImage((UIView *)self);
    %orig(box ? box.bounds : frame);
}
- (void)setBounds:(CGRect)bounds {
    UIView *box = coverOfImage((UIView *)self);
    %orig(box ? (CGRect){bounds.origin, box.bounds.size} : bounds);
}
- (void)setCenter:(CGPoint)center {
    UIView *box = coverOfImage((UIView *)self);
    %orig(box ? CGPointMake(CGRectGetMidX(box.bounds), CGRectGetMidY(box.bounds)) : center);
}
// What it holds keeps its own 317 unless it is laid out to this view's size again: the Encore image view here,
// and the image and placeholder in that (below).
- (void)layoutSubviews {
    %orig;
    UIView *proxy = (UIView *)self;
    if (!coverOfImage(proxy)) return;
    for (UIView *image in proxy.subviews) {
        if (!CGRectEqualToRect(image.frame, proxy.bounds)) image.frame = proxy.bounds;
    }
}
%end

%hook _TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    static Class proxyClass;
    if (!proxyClass) proxyClass = NSClassFromString(@"_TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy");
    if (![view.superview isKindOfClass:proxyClass] || !coverOfImage(view.superview)) return;
    for (UIView *part in view.subviews) {
        if (!CGRectEqualToRect(part.frame, view.bounds)) part.frame = view.bounds;
    }
}
%end


@interface SGRPlayerArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerArtworkWatcher {
    NSInteger _paused;
    NSString *_track;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _paused = -1;
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    // The artwork through a track change, read before the covers have laid out and again while the next
    // one's picture comes in: the frame and transform at each point say where a cover that jumped was.
    NSString *track = SGURIString(state.track.URI);
    if (![track isEqualToString:_track]) {
        _track = track;
        for (NSNumber *delay in @[@0.05, @0.4, @1.5]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *tilt = showingTilt();
                logGeometry(tilt, coverIn(tilt), [NSString stringWithFormat:@"track %.2fs after the change", delay.doubleValue]);
            });
        }
    }
    NSInteger paused = state.isPaused ? 1 : 0;
    if (paused == _paused) return;
    _paused = paused;
    scaleEveryCover(YES);
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"redesign player: state paused=%d loading=%d, %lu covers scaled", state.isPaused, state.isLoading, (unsigned long)sg_tilts.count);
}

@end

static SGRPlayerArtworkWatcher *sg_artworkWatcher;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_tilts = [NSHashTable weakObjectsHashTable];
    sg_covers = [NSMapTable weakToWeakObjectsMapTable];
    sg_artworkWatcher = [SGRPlayerArtworkWatcher new];
    SGAddPlayerStateObserver(sg_artworkWatcher);
    SGRequireClasses(@[
        @"_TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView",
        @"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl",
    ]);
}
