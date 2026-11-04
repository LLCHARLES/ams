// Player redesign: the cover is a view of the redesign's own, drawn where the Music app draws it.
//
// It used to be Spotify's own cover, moved up out of the taller band Spotify centers its tilt view in by
// a transform on that tilt view. A transform is a correction worked out from where the band stands at the
// moment of a layout pass, and it goes stale the moment the band moves without one: the queue taking its
// place on the first open, a page scrolling, a cell reused for the next track. Every fix added another
// pass that re-read the band and re-wrote the transform, and every pass landed a frame later than the
// first one the eye saw -- the cover that dropped into place, appeared out of nothing, or jumped to the
// top when the next track came in paused.
//
// So the cover is no longer Spotify's. This file draws one view of its own, in the player's view, at a
// frame worked out only from that view's own bounds: square, the screen's width less the Music app's
// margins, its top a share of the screen's height down. No window measurement, no tilt view, no cell, no
// transform that has to be kept in step, and no pass that has to run before the first frame. It is in the
// right place on the first open and stays there through a track change; only the picture inside it fades.
//
// Spotify's list of covers is left in place and hidden by a mask (not by alpha: a mask still takes the
// swipe that changes track, and PlayerField.x still reads the picture off its image views to publish it).
// The picture here is the Kit's SGRNowPlayingArtwork, the same one the bar's card, the field, the lyrics'
// thumbnail and the open's flown cover read, so the cover and the stand-in that flies into it are the
// same picture and the hand-over is not seen.
//
// Tree (trees/clean/player/01.txt:26-43): SPTNowPlayingView holds the content layers (the sideways list
// of covers, one per cell), the header row, and the bottom stack with the title, controls and footer. The
// cover's own view sits in that player view, between the header row and the title. The paused shrink is
// one transform on that view, and nothing else writes to it.
#import "Core/SGCore.h"
#import "Core/SGViewTree.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"

static const CGFloat kPausedScale = 0.84;
// The Music app's cover, measured off its player on the iPhone 16 Pro the layouts were compared on
// (402 x 874pt, 3x): 356pt square, 23pt in from either side of the screen and its top 94.8pt down it, just
// under the header row.
static const CGFloat kArtworkInset = 23;
// The cover's top as a share of the screen's height (94.8 of 874), and the least room the header row's
// buttons are left under the safe area's top on a shorter screen.
static const CGFloat kArtworkTopShare = 0.1085, kArtworkTopGap = 33;
// The most of the player's height the cover may take, so the title row is never covered on a short screen.
// A share, not a measurement of Spotify's row: a share is there on the very first frame and never changes.
static const CGFloat kCoverBottomShare = 0.66;
static const CGFloat kCoverMinWidth = 200, kPlayerMinHeight = 400;

static char kCoverKey, kStackKey, kHoldKey, kBadgeGlassKey, kHideMaskKey, kListKey;
static __weak UIView *sg_cover;
static BOOL sg_coverKeptHidden;

static CGFloat currentScale(void) {
    SPTPlayerState *state = SGPlayerState();
    if (!state.isPaused) return 1;
    return SGRReduceMotion() ? 1 : kPausedScale;
}

// One place decides whether the drawn cover is on screen. A stand-in flies in its place while the player
// opens (PlayerMorph.x), and the lyrics take its place while they are open (PlayerLyrics.x, by alpha);
// neither state may be undone by a later pass of the other. Reduce Motion dims a paused cover instead of
// shrinking it, so that dimming is kept here too.
static CGFloat coverAlpha(void) {
    if (sg_coverKeptHidden || SGRPlayerLyricsOpen()) return 0;
    return (SGRReduceMotion() && SGPlayerState().isPaused) ? 0.75 : 1;
}

#pragma mark - the drawn cover

@interface SGRPlayerCoverView : UIView
@property (nonatomic) UIImageView *picture;
@property (nonatomic) SGRShadowPlate *plate;
@end

@implementation SGRPlayerCoverView

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;   // the swipe that changes track still reaches the list underneath
    self.backgroundColor = UIColor.clearColor;
    _plate = [[SGRShadowPlate alloc] initWithFrame:self.bounds];
    _plate.cornerRadius = SGRRadiusArtwork;
    [self addSubview:_plate];
    _picture = [[UIImageView alloc] initWithFrame:self.bounds];
    _picture.contentMode = UIViewContentModeScaleAspectFill;
    _picture.clipsToBounds = YES;
    _picture.layer.cornerRadius = SGRRadiusArtwork;
    _picture.layer.cornerCurve = kCACornerCurveContinuous;
    _picture.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];  // a placeholder, never a blank frame
    _picture.userInteractionEnabled = NO;
    [self addSubview:_picture];
    return self;
}

// The picture is the Kit's, the same one the stand-in flies in with. Only a new picture fades; the same
// image published again at a better quality is left alone. A first open draws whatever is already in,
// or the placeholder until the notification comes, and never a cover that appears out of nothing.
- (void)setArtwork:(UIImage *)image animated:(BOOL)animated {
    if (!image || image == _picture.image) return;
    if (!animated || SGRReduceMotion()) {
        _picture.image = image;
        return;
    }
    [UIView transitionWithView:_picture duration:0.28
                       options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ _picture.image = image; } completion:nil];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (!CGRectEqualToRect(_picture.frame, bounds)) _picture.frame = bounds;
    if (!CGRectEqualToRect(_plate.frame, bounds)) _plate.frame = bounds;
}

@end

#pragma mark - the geometry, worked out from the player's own bounds

// The one place the cover is drawn. It reads only the player view's bounds and its safe area, so it is
// the same on the first frame, after a rotation, through a track change and while the player opens or
// closes -- and there is nothing to correct later.
static CGRect coverFrameIn(UIView *host) {
    CGRect b = host.bounds;
    CGFloat top = MAX(CGRectGetHeight(b) * kArtworkTopShare, host.safeAreaInsets.top + kArtworkTopGap);
    CGFloat side = MAX(kCoverMinWidth, CGRectGetWidth(b) - 2 * kArtworkInset);
    side = MIN(side, MAX(kCoverMinWidth, CGRectGetHeight(b) * kCoverBottomShare - top));
    return CGRectMake(round((CGRectGetWidth(b) - side) / 2), round(top), side, side);
}

static void placeCover(UIView *host) {
    SGRPlayerCoverView *cover = (SGRPlayerCoverView *)sg_cover;
    if (!cover || cover.superview != host) return;
    CGRect frame = coverFrameIn(host);
    // Bounds and center, not frame: they hold under the paused shrink's transform, and setting them is
    // idempotent -- a pass that runs again changes nothing and cuts no animation short.
    CGSize size = frame.size;
    if (!CGSizeEqualToSize(cover.bounds.size, size)) cover.bounds = (CGRect){CGPointZero, size};
    CGPoint middle = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (!CGPointEqualToPoint(cover.center, middle)) cover.center = middle;
    [cover setNeedsLayout];
    [cover layoutIfNeeded];
}

// Spotify's own covers are still there for their gestures and for PlayerField.x to read the picture
// from. A mask hides them without turning off hit testing (an alpha of 0 would drop the swipe that
// changes track), and without changing the image views' own alpha that the read asks about. A mask with
// an empty frame hides everything and never needs updating as the list's bounds change.
static UIView *nativeCoverList(UIView *host) {
    return SGFindRemembered(host, &kListKey, ^BOOL(UIView *v) {
        return [v isKindOfClass:UICollectionView.class] && SGClassNamed(v.class, @"AccessibleCollectionView")
            && v.bounds.size.width >= kCoverMinWidth;
    });
}

static void hideNativeCovers(UIView *host) {
    UIView *list = nativeCoverList(host);
    if (!list) return;
    CALayer *mask = objc_getAssociatedObject(list, &kHideMaskKey);
    if (!mask) {
        mask = [CALayer layer];
        // A black mask at opacity 0 hides the whole list. The frame is deliberately larger than any
        // list so a bounds change never needs a new one (PlayerMotion.x fades the same shape).
        mask.frame = CGRectMake(0, 0, 4096, 4096);
        mask.backgroundColor = UIColor.blackColor.CGColor;
        mask.opacity = 0;
        objc_setAssociatedObject(list, &kHideMaskKey, mask, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (list.layer.mask != mask) list.layer.mask = mask;
}

#pragma mark - hold to play faster

// Holding either side of the cover plays at kHoldSpeed until the finger lifts, and the speed set before
// comes back. The middle third is left alone, and a hold that starts to move is a swipe to the next track.
// It is a speed like the menu's, so with Pitch follows speed on (until switched off) it also plays an
// octave higher, the way a record does. The recognizer lives on the player's view: the drawn cover lets
// touches through to the list, so its own view cannot watch them. The badge is drawn on the cover.
static const double kHoldSpeed = 2;

@interface SGRCoverHold : UILongPressGestureRecognizer
@end

@implementation SGRCoverHold {
    double _before;
    UIView *_badge;
    UILabel *_badgeLabel;
    BOOL _badgeShown;
}

- (void)sgr_held {
    UIView *host = self.view;
    SGRPlayerCoverView *cover = (SGRPlayerCoverView *)sg_cover;
    if (self.state == UIGestureRecognizerStateBegan) {
        CGRect drawn = SGRPlayerCoverFrameIn(host);
        CGPoint p = [self locationInView:host];
        CGFloat x = p.x - CGRectGetMinX(drawn), third = drawn.size.width / 3;
        if (CGRectIsNull(drawn) || !CGRectContainsPoint(drawn, p)
            || (x > third && x < 2 * third) || !SGPlayerSpeedAllowed()) {
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

// "2x" and a forward glyph on the Kit's glass capsule at the top of the cover while it is held. What fades
// is the glass's effect (SGRShowGlass), never an alpha over it; the capsule grows in from 0.9 with the Kit's
// press spring and goes with its exit, quicker than it came: the finger is already off the cover.
- (void)showBadge:(BOOL)shown on:(UIView *)cover {
    if (shown && !cover) return;
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

static void watchHold(UIView *host) {
    if (objc_getAssociatedObject(host, &kHoldKey)) return;
    SGRCoverHold *hold = [[SGRCoverHold alloc] initWithTarget:nil action:nil];
    [hold addTarget:hold action:@selector(sgr_held)];
    hold.minimumPressDuration = 0.35;
    hold.cancelsTouchesInView = NO;   // a swipe to the next track starts on the cover too
    [host addGestureRecognizer:hold];
    objc_setAssociatedObject(host, &kHoldKey, hold, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

#pragma mark - installing the cover

static void ensureCover(UIView *host) {
    SGRPlayerCoverView *cover = (SGRPlayerCoverView *)objc_getAssociatedObject(host, &kCoverKey);
    if (!cover) {
        cover = [[SGRPlayerCoverView alloc] initWithFrame:CGRectZero];
        objc_setAssociatedObject(host, &kCoverKey, cover, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        sg_cover = cover;
        // Behind the bottom stack (the title, controls and footer), over the artwork field. The cover's
        // own rect ends well above the stack, so wherever it sits in the order nothing else is covered.
        UIView *stack = SGFindIdentifier(host, @"npv.bottomStackView", &kStackKey);
        if (stack && stack.superview == host) [host insertSubview:cover belowSubview:stack];
        else [host addSubview:cover];
        cover.alpha = coverAlpha();
        [cover setArtwork:SGRNowPlayingArtwork(NULL, NULL) animated:NO];
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"redesign player: the cover is drawn in the player's own view"); });
    } else if (cover.superview != host) {
        [host addSubview:cover];
    }
    sg_cover = cover;
    placeCover(host);
    hideNativeCovers(host);
    watchHold(host);
    SGRPlayerMotionCoverLaidOut();
}

%hook _TtC19NowPlaying_ViewImpl24NowPlayingViewController
- (void)viewWillLayoutSubviews {
    %orig;
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kPlayerMinHeight) return;
    ensureCover(host);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig(animated);
    UIView *host = ((UIViewController *)self).viewIfLoaded;
    if (!host || host.bounds.size.height < kPlayerMinHeight) return;
    ensureCover(host);
}
%end

#pragma mark - the cover's public geometry, all read off the drawn view

UIView *SGRPlayerCoverList(void) {
    // The lyrics fade this by alpha and an animated artwork masks its layer, so it stands for "the cover
    // on screen" now that the cover is a view of our own rather than Spotify's list.
    return sg_cover;
}

// The frame from pure geometry, with the paused shrink about the center: an answer before the drawn view
// has been made on a first open, so the morph's stand-in has somewhere to fly to on its very first frame
// instead of being hidden and then appearing. Once the view exists the conversion below takes over, and
// both give the same rect.
static CGRect coverRestIn(UIView *host, BOOL scaled) {
    if (!host) return CGRectNull;
    CGRect frame = coverFrameIn(host);
    if (scaled) {
        CGFloat scale = currentScale();
        frame = CGRectInset(frame, frame.size.width * (1 - scale) / 2, frame.size.height * (1 - scale) / 2);
    }
    return frame;
}

CGRect SGRPlayerCoverFrameIn(UIView *host) {
    UIView *cover = sg_cover;
    if (!host) return CGRectNull;
    // Includes the paused shrink's transform, which is what the eye sees and what the flown cover lands on.
    return cover ? [host convertRect:cover.bounds fromView:cover] : coverRestIn(host, YES);
}

CGFloat SGRPlayerCoverScale(void) {
    return currentScale();
}

CGRect SGRPlayerCoverRestFrameIn(UIView *host) {
    UIView *cover = sg_cover;
    if (!host) return CGRectNull;
    if (!cover || !cover.superview) return coverRestIn(host, NO);
    // The frame without the paused shrink: center and bounds, held in the player's own coordinates.
    CGSize size = cover.bounds.size;
    CGRect rest = CGRectMake(cover.center.x - size.width / 2, cover.center.y - size.height / 2, size.width, size.height);
    return [host convertRect:rest fromView:cover.superview];
}

CGRect SGRPlayerArtworkAreaIn(UIView *host) {
    // Pure geometry again: the lyrics' first layout may run before the cover view has been made, and the
    // room the artwork is given is known from the player's bounds either way.
    if (!host) return CGRectNull;
    CGRect frame = coverFrameIn(host);
    CGFloat bottom = MAX(CGRectGetMaxY(frame), CGRectGetHeight(host.bounds) * kCoverBottomShare);
    return CGRectMake(0, CGRectGetMinY(frame), CGRectGetWidth(host.bounds), bottom - CGRectGetMinY(frame));
}

void SGRPlayerSetCoverHidden(BOOL hidden) {
    sg_coverKeptHidden = hidden;
    UIView *cover = sg_cover;
    if (cover) cover.alpha = coverAlpha();
}

#pragma mark - the paused shrink and the picture

@interface SGRPlayerArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

@implementation SGRPlayerArtworkWatcher {
    NSInteger _paused;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    _paused = -1;
    return self;
}

- (void)playerStateDidChange:(SPTPlayerState *)state {
    NSInteger paused = state.isPaused ? 1 : 0;
    if (paused == _paused) return;
    _paused = paused;
    UIView *cover = sg_cover;
    if (!cover) return;
    CGFloat scale = currentScale();
    SGRAnimate(SGRReduceMotion() ? SGRMotionRespond : SGRMotionLayout, ^{
        cover.transform = CGAffineTransformMakeScale(scale, scale);
    }, nil);
}

@end

static SGRPlayerArtworkWatcher *sg_artworkWatcher;
static id sg_artworkObserver;

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    sg_artworkWatcher = [SGRPlayerArtworkWatcher new];
    SGAddPlayerStateObserver(sg_artworkWatcher);
    sg_artworkObserver = [NSNotificationCenter.defaultCenter
        addObserverForName:SGRNowPlayingArtworkDidChangeNotification object:nil
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            UIImage *image = note.userInfo[@"image"];
            [(SGRPlayerCoverView *)sg_cover setArtwork:image animated:YES];
        }];
    SGRequireClasses(@[
        @"_TtC19NowPlaying_ViewImpl24NowPlayingViewController",
        @"_TtC35NowPlaying_ContentLayerPlatformImpl24AccessibleCollectionView",
    ]);
}
