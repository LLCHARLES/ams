// Player redesign: the cover sits on the field with continuous corners and a soft shadow, and shrinks
// back while playback is paused, the way the Music app's does. Spotify's lyric preview under it, and the cover's size
// beside it, are Spotify's, as its own lyrics setting has them.
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
//
// The cover has two holders besides Spotify: the morph hides it for the cover it flies (SGRPlayerSetCoverHidden), and
// AutoMix's stage stands over it during a mix (SGRPlayerStageCover, PlayerMix.x). It shows once neither holds it.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Shared/Gestures/GestureHold.h"
#import "Shared/Haptics/Haptics.h"
#import "Shared/Player/SpeedPitch.h"
#import "Player.h"
#import "PlayerMix.h"
#import "PlayerLyricLine.h"

static const CGFloat kPausedScale = 0.84;
// The bar's 40pt cover lives in a tilt view of its own; the player's is 354.
static const CGFloat kCoverMinWidth = 200;
// The Music app's cover top under the window's safe area (its player, iOS 26 at 3x: 95 pt under a 62 pt inset, 22 pt
// under the grabber). Its cover is as wide as Spotify's tilt view, 24 pt in from the sides.
static const CGFloat kCoverTopUnderSafeArea = 33;

static char kPlateKey;
static __weak UIView *sg_reservedTilt;
static CGFloat sg_reservedSide;
static __weak UIView *sg_emptyStripHost;
static char kStripFillKey;
static NSHashTable<UIView *> *sg_tilts;
// The cover of each tilt view once found. A frame Spotify sets on a scaled view becomes its scaled
// size, leaving bounds that no longer match the tilt view's, so the cover is not looked for by size again.
static NSMapTable<UIView *, UIView *> *sg_covers;
// AutoMix's stage over the cover (SGRPlayerStageCover) and the cover it stands in for.
static __weak UIView *sg_stage, *sg_stagedCover;

// The child of the tilt view the size of the cover.
static UIView *coverIn(UIView *tilt) {
    UIView *cover = [sg_covers objectForKey:tilt];
    if (cover.superview == tilt) return cover;
    for (UIView *sub in tilt.subviews) {
        if (![sub isKindOfClass:SGRShadowPlate.class] && sub != sg_stage && CGSizeEqualToSize(sub.bounds.size, tilt.bounds.size)) {
            [sg_covers setObject:sub forKey:tilt];
            return sub;
        }
    }
    return nil;
}

static UIView *coverCellOf(UIView *tilt) {
    static Class cell;
    if (!cell) cell = NSClassFromString(@"_TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl");
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if ([v isKindOfClass:cell]) return v;
    }
    return nil;
}

// The header rows taking touches in a player (SGRPlayerCoverUnderRow): one showing where it plays from, Spotify's live
// arrow, the AI DJ's buttons.
static NSHashTable<UIView *> *sg_liveRows;
// Each live row's SGRCoverRowFollower, in the player the row was laid out in.
static char kFollowerKey;

// How far up from the top of its tilt view the cover is drawn, so its top stands kCoverTopUnderSafeArea under the
// window's safe area as the Music app's does, where Spotify's tilt view stands lower (118 pt on a 402x874 iPhone, the
// Music app's 95), but never above the bottom of a live header row in the cover's own player where the row is now
// (followed as Spotify moves it, SGRCoverRowFollower), which it would draw over and take touches from; a row moved out
// of that player limits it no more. The cell is the whole player, its top the player's, from which the grabber is
// placed the same way (PlayerHeader.x). Positions without transforms, so the lyrics' moves and Spotify's tilt leave it
// be. Only ever up, away from the title row, and only in a phone's portrait player: Spotify's landscape and iPad
// layouts are its own.
static CGFloat coverLift(UIView *tilt, UIView *cell) {
    UIWindow *window = cell.window;
    if (!window || cell.traitCollection.userInterfaceIdiom != UIUserInterfaceIdiomPhone || cell.bounds.size.width >= cell.bounds.size.height) return 0;
    CGFloat top = 0;
    for (UIView *view = tilt; view && view != cell; view = view.superview) {
        top += view.center.y - view.bounds.size.height / 2 - view.superview.bounds.origin.y;
    }
    CGFloat highest = window.safeAreaInsets.top + kCoverTopUnderSafeArea;
    for (UIView *row in sg_liveRows) {
        UIView *player = ((UIView *)objc_getAssociatedObject(row, &kFollowerKey)).superview;
        if (player && [cell isDescendantOfView:player] && [row isDescendantOfView:player]) {
            highest = MAX(highest, CGRectGetMaxY([cell convertRect:row.bounds fromView:row]));
        }
    }
    return MAX(0, top - highest);
}

static void layOutCoversIn(UIWindow *window) {
    for (UIView *tilt in sg_tilts) {
        if (tilt.window == window) [tilt setNeedsLayout];
    }
}

CGRect SGRPlayerNormalCover(UIView *host, UIView *tilt, CGFloat maxSide) {
    UIView *cell = coverCellOf(tilt);
    UIView *column = tilt.superview;
    CGFloat side = CGRectGetWidth(column.bounds);
    if (!cell || ![tilt isDescendantOfView:host] || tilt.bounds.size.width < kCoverMinWidth ||
        host.traitCollection.userInterfaceIdiom != UIUserInterfaceIdiomPhone ||
        fabs(tilt.bounds.size.width - tilt.bounds.size.height) > 1 ||
        fabs(side - maxSide) > 1 || tilt.bounds.size.width > side + 1 ||
        fabs(tilt.center.x - CGRectGetMidX(column.bounds)) > 1) return CGRectNull;
    CGFloat y = CGRectGetMinY(tilt.bounds) - coverLift(tilt, cell);
    CGPoint top = [host convertPoint:CGPointMake(CGRectGetMidX(tilt.bounds), y) fromView:tilt];
    return CGRectMake(top.x - side / 2, top.y, side, side);
}

void SGRPlayerEmptyStripIn(UIView *host) {
    UIView *prior = sg_emptyStripHost;
    if (prior == host) return;
    sg_emptyStripHost = host;
    for (UIView *tilt in sg_tilts.allObjects) {
        if ((prior && [tilt isDescendantOfView:prior]) || (host && [tilt isDescendantOfView:host]))
            [tilt setNeedsLayout];
    }
}

void SGRPlayerReserveCover(UIView *tilt, CGFloat side) {
    static NSString *track;
    NSString *playing = SGKaraokePlayingTrack();
    BOOL sameTrack = track == playing || [track isEqualToString:playing];
    if (!sameTrack) track = playing.copy;
    if (tilt == sg_reservedTilt && side == sg_reservedSide) return;
    // A centre crossing the screen edge is not a handover while the pager
    // is moving. Freeze the reservation, not Spotify's scrolling or the clock.
    if (sameTrack) for (UIView *v = sg_reservedTilt ?: tilt; v; v = v.superview) {
        if (![v isKindOfClass:UICollectionView.class]) continue;
        UICollectionView *pager = (UICollectionView *)v;
        if (pager.dragging || pager.decelerating) return;
        if (@available(iOS 17.4, *)) {
            if (pager.scrollAnimating) return;
        } else {
            CALayer *visible = pager.layer.presentationLayer;
            if (visible && visible.bounds.origin.x != pager.bounds.origin.x) return;
        }
        break;
    }
    UIView *prior = sg_reservedTilt;
    sg_reservedTilt = tilt;
    sg_reservedSide = side;
    SGRAnimate(SGRMotionLayout, ^{
        if (prior != tilt) { [prior setNeedsLayout]; [prior layoutIfNeeded]; }
        [tilt setNeedsLayout]; [tilt layoutIfNeeded];
    }, nil);
}

// A view in a live row's player, from the player's top to the row's bottom. Spotify 9.2.0 moves the row by its top
// constraint with no layout of the row (PlayerHeader.x); the engine resizes this with it, and its layout lays the covers
// in its window out again under the row's new place. First in the player, it is laid out before the covers in the same
// pass. Taking the row out of the player takes the tie with it (removeFromSuperview's contract); this then leaves.
@interface SGRCoverRowFollower : UIView
@property (nonatomic, strong) NSLayoutConstraint *tie;
@end

@implementation SGRCoverRowFollower
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    // The height it falls to once the tie is gone.
    NSLayoutConstraint *untied = [self.heightAnchor constraintEqualToConstant:0];
    untied.priority = UILayoutPriorityFittingSizeLevel;
    [NSLayoutConstraint activateConstraints:@[[self.widthAnchor constraintEqualToConstant:0], untied]];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    layOutCoversIn(self.window);
    if (self.tie.active) return;
    __weak SGRCoverRowFollower *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!weakSelf.tie.active) [weakSelf removeFromSuperview];
    });
}
@end

// Moving a page's artwork band does not lay out a same-sized tilt. Observe
// the model geometry coverLift reads, not the pager, presentation animations
// or the tilt transform. The observation belongs to the reusable tilt.
@interface SGRCoverLiftWatch : NSObject
@property (nonatomic, weak) UIView *tilt;
@property (nonatomic, copy) NSArray<CALayer *> *layers;
- (BOOL)stripOnlyIn:(UIView *)column;
- (void)stop;
@end

@implementation SGRCoverLiftWatch {
    CALayer *_column;
    NSArray<CALayer *> *_previews;
}
static char kPreviewChange;
- (BOOL)stripOnlyIn:(UIView *)column {
    if (!_column && !column) return NO;
    if (_column != column.layer) {
        [_column removeObserver:self forKeyPath:@"sublayers" context:&kPreviewChange];
        _column = column.layer;
        [_column addObserver:self forKeyPath:@"sublayers" options:0 context:&kPreviewChange];
    }
    BOOL showing = NO;
    NSArray *layers = column ? SGRPlayerPreviewLayers(column, &showing) : nil;
    for (CALayer *layer in _previews) if (![layers containsObject:layer])
        for (NSString *key in @[@"bounds", @"hidden", @"opacity"]) [layer removeObserver:self forKeyPath:key context:&kPreviewChange];
    for (CALayer *layer in layers) if (![_previews containsObject:layer])
        for (NSString *key in @[@"bounds", @"hidden", @"opacity"]) [layer addObserver:self forKeyPath:key options:0 context:&kPreviewChange];
    _previews = layers;
    return column && !showing;
}
- (void)observeValueForKeyPath:(NSString *)path ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kPreviewChange) {
        NSValue *old = change[NSKeyValueChangeOldKey], *now = change[NSKeyValueChangeNewKey];
        BOOL moved = [path isEqualToString:@"position"] ? old.CGPointValue.y != now.CGPointValue.y :
            old.CGRectValue.origin.y != now.CGRectValue.origin.y || old.CGRectValue.size.height != now.CGRectValue.size.height;
        if (!moved) return;
    }
    if (NSThread.isMainThread) [self.tilt setNeedsLayout];
    else dispatch_async(dispatch_get_main_queue(), ^{ [self.tilt setNeedsLayout]; });
}
- (void)stop {
    self.tilt = nil;
    [self stripOnlyIn:nil];
    for (CALayer *layer in _layers) {
        [layer removeObserver:self forKeyPath:@"position"];
        [layer removeObserver:self forKeyPath:@"bounds"];
    }
    _layers = nil;
}
@end

// Association destruction follows the thread of the last release. Keep both
// ends of each registration alive through removal, without retaining a view.
@interface SGRCoverLiftBinding : NSObject
@property (nonatomic, strong) SGRCoverLiftWatch *watch;
@end
@implementation SGRCoverLiftBinding
- (void)dealloc {
    SGRCoverLiftWatch *watch = _watch;
    if (NSThread.isMainThread) [watch stop];
    else dispatch_async(dispatch_get_main_queue(), ^{ [watch stop]; });
}
@end

static SGRCoverLiftWatch *followTilt(UIView *tilt, UIView *cell) {
    static char key;
    SGRCoverLiftBinding *binding = objc_getAssociatedObject(tilt, &key);
    if (!cell) {
        if (binding) objc_setAssociatedObject(tilt, &key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    NSArray<CALayer *> *layers = binding.watch.layers;
    NSUInteger count = 0;
    for (UIView *v = tilt; v && v != cell; v = v.superview) {
        if (count == layers.count || layers[count++] != v.layer) break;
        if (v.superview == cell && count == layers.count) return binding.watch;
    }
    SGRCoverLiftWatch *watch = [SGRCoverLiftWatch new];
    watch.tilt = tilt;
    NSMutableArray *chain = [NSMutableArray array];
    for (UIView *v = tilt; v && v != cell; v = v.superview) {
        [chain addObject:v.layer];
        for (NSString *path in @[@"position", @"bounds"])
            [v.layer addObserver:watch forKeyPath:path options:NSKeyValueObservingOptionOld|NSKeyValueObservingOptionNew context:NULL];
    }
    watch.layers = chain;
    binding = [SGRCoverLiftBinding new];
    binding.watch = watch;
    objc_setAssociatedObject(tilt, &key, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return watch;
}

void SGRPlayerCoverUnderRow(UIView *row, BOOL live, UIView *player) {
    if (!sg_liveRows) sg_liveRows = [NSHashTable weakObjectsHashTable];
    SGRCoverRowFollower *follower = objc_getAssociatedObject(row, &kFollowerKey);
    live = live && player;
    if (!live) {
        [follower removeFromSuperview];
    } else if (follower.superview != player || !follower.tie.active) {
        if (!follower) {
            follower = [SGRCoverRowFollower new];
            objc_setAssociatedObject(row, &kFollowerKey, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [follower removeFromSuperview];
        [player insertSubview:follower atIndex:0];
        follower.tie = [follower.bottomAnchor constraintEqualToAnchor:row.bottomAnchor];
        [NSLayoutConstraint activateConstraints:@[
            [follower.topAnchor constraintEqualToAnchor:player.topAnchor],
            [follower.leadingAnchor constraintEqualToAnchor:player.leadingAnchor], follower.tie,
        ]];
    }
    if ([sg_liveRows containsObject:row] == live) return;
    if (live) [sg_liveRows addObject:row];
    else [sg_liveRows removeObject:row];
    for (UIView *tilt in sg_tilts) [tilt setNeedsLayout];
    SGRPlayerMotionHeaderChanged();
}

BOOL SGRPlayerHeaderShowsIn(UIView *view) {
    UIWindow *window = view.window;
    for (UIView *row in sg_liveRows) {
        if (window && row.window == window) return YES;
    }
    return NO;
}

// The window's safe area can come after the cover's layout (a player laid out as its window is still being set up), and
// the cells' own safe areas do not follow it: a view of the window's size in each cover's window hears of a change and
// lays the covers in that window out again.
@interface SGRCoverInsetObserver : UIView
@end

@implementation SGRCoverInsetObserver
- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    layOutCoversIn(self.window);
}
@end

static void watchInsets(UIWindow *window) {
    if (!window) return;
    for (UIView *view in window.subviews) {
        if ([view isKindOfClass:SGRCoverInsetObserver.class]) return;
    }
    SGRCoverInsetObserver *observer = [[SGRCoverInsetObserver alloc] initWithFrame:window.bounds];
    observer.userInteractionEnabled = NO;
    observer.accessibilityElementsHidden = YES;
    observer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window insertSubview:observer atIndex:0];
}

static void scaleCover(UIView *tilt, CGFloat scale) {
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    CGAffineTransform transform = CGAffineTransformMakeScale(scale, scale);
    cover.transform = transform;
    plate.transform = transform;
    if (sg_stage.superview == tilt) sg_stage.transform = transform;
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

UIView *SGRPlayerShowingCover(void) {
    return coverIn(showingTilt());
}

CGRect SGRPlayerCoverFrameIn(UIView *host) {
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    // The cover's own transform is the paused shrink, which is what the eye sees it at.
    return cover && host ? [host convertRect:cover.bounds fromView:cover] : CGRectNull;
}

CGFloat SGRPlayerCoverScale(void) {
    SPTPlayerState *state = SGPlayerState();
    if (!state.isPaused) return 1;
    return SGRReduceMotion() ? 1 : kPausedScale;
}

CGRect SGRPlayerArtworkAreaIn(UIView *host) {
    UIView *tilt = showingTilt();
    if (!tilt || !host) return CGRectNull;
    UIView *content = ((UICollectionViewCell *)coverCellOf(tilt)).contentView;
    // The band is the child of the cell's content view containing the tilt, not the first ancestor as wide
    // as the host. During a resize the cell's width can lag behind the host's; width matching then
    // selected the full-height collection view and placed the lyric thumbnail over the header.
    for (UIView *v = tilt.superview; v; v = v.superview) {
        if (v == host) break;
        if (v.superview == content) return [host convertRect:v.bounds fromView:v];
    }
    return CGRectNull;
}

// The cover hidden for a stand-in, so the same one comes back if the list moved on meanwhile.
static __weak UIView *sg_hiddenCover, *sg_hiddenPlate;
// Asked for while no cover was laid out yet (the first open): the cover is hidden in the layout pass that makes it,
// so its first frame on screen is already hidden.
static BOOL sg_coverKeptHidden;

// The alpha of a cover no one hides: dimmed while paused under Reduce Motion, which keeps it from shrinking.
static CGFloat restingAlpha(void) {
    return SGRReduceMotion() && SGPlayerState().isPaused ? 0.75 : 1;
}

void SGRPlayerSetCoverHidden(BOOL hidden) {
    if (sg_hiddenCover != sg_stagedCover) sg_hiddenCover.alpha = restingAlpha();
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

#pragma mark - AutoMix's stage

// Over the cover in the tilt view, its bounds, center and scale, so it sits exactly where the cover is drawn.
static void placeStage(UIView *tilt, UIView *cover) {
    UIView *stage = sg_stage;
    if (stage.superview != tilt) [tilt insertSubview:stage aboveSubview:cover];
    if (!CGRectEqualToRect(stage.bounds, cover.bounds)) stage.bounds = cover.bounds;
    if (!CGPointEqualToPoint(stage.center, cover.center)) stage.center = cover.center;
    if (!CGAffineTransformEqualToTransform(stage.transform, cover.transform)) stage.transform = cover.transform;
}

// The stage leaves the cover it stood for, which shows again unless the morph hides it.
static void releaseStagedCover(void) {
    UIView *cover = sg_stagedCover;
    sg_stagedCover = nil;
    if (cover && cover != sg_hiddenCover) cover.alpha = restingAlpha();
}

BOOL SGRPlayerStageCover(UIView *stage) {
    UIView *old = sg_stage;
    sg_stage = nil;
    [old removeFromSuperview];
    releaseStagedCover();
    if (!stage) return YES;
    UIView *tilt = showingTilt();
    UIView *cover = coverIn(tilt);
    if (!cover) return NO;
    sg_stage = stage;
    sg_stagedCover = cover;
    placeStage(tilt, cover);
    cover.alpha = 0;
    return YES;
}

#pragma mark - the paused shrink

static void scaleEveryCover(BOOL animated) {
    CGFloat scale = SGRPlayerCoverScale();
    NSArray<UIView *> *tilts = sg_tilts.allObjects;
    void (^apply)(void) = ^{
        for (UIView *tilt in tilts) {
            scaleCover(tilt, scale);
            UIView *cover = coverIn(tilt);
            if (cover != sg_hiddenCover && cover != sg_stagedCover) cover.alpha = restingAlpha();
        }
    };
    if (animated) SGRAnimate(SGRReduceMotion() ? SGRMotionRespond : SGRMotionLayout, apply, nil);
    else apply();
}

#pragma mark - hold to play faster

// Holding either side of the cover plays at the chosen hold speed (Shared/Gestures/GestureHold.h) until the finger
// lifts, and the speed set before comes back. The middle third is left alone, and a hold that starts to move is a
// swipe to the next track. With the hold switched off the recognizer is disabled, so a press does nothing.
// It is a speed like the menu's, so with Pitch follows speed on (until switched off) it also plays higher, the way
// a record does. The native look's copy is in Native/Player/PlayerGestures.x.
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
        double speed = SGGestureHoldSpeed();
        _before = SGPlayerSpeed();
        SGSetPlayerSpeed(speed);
        SGPlayFeedback(SGFeedbackGrab);
        [self showBadge:YES on:cover];
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, SGGestureHoldAnnouncement(speed));
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
- (NSAttributedString *)badgeText {
    UIFont *font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    NSTextAttachment *arrows = [NSTextAttachment textAttachmentWithImage:[[UIImage systemImageNamed:@"forward.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithFont:font]] imageWithTintColor:UIColor.whiteColor
        renderingMode:UIImageRenderingModeAlwaysOriginal]];
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:[SGGestureHoldSpeedLabel(SGGestureHoldSpeed()) stringByAppendingString:@"  "]
        attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: UIColor.whiteColor}];
    [text appendAttributedString:[NSAttributedString attributedStringWithAttachment:arrows]];
    return text;
}

- (void)showBadge:(BOOL)shown on:(UIView *)cover {
    if (shown && !_badge) {
        _badgeLabel = [UILabel new];
        _badgeLabel.textAlignment = NSTextAlignmentCenter;
        _badge = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 92, 34)];
        _badge.userInteractionEnabled = NO;
        _badgeLabel.frame = _badge.bounds;
        _badgeLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_badge addSubview:_badgeLabel];
    }
    if (shown) _badgeLabel.attributedText = [self badgeText];   // the speed may have changed since the last hold
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
    SGRCoverHold *existing = objc_getAssociatedObject(tilt, &kHoldKey);
    if (existing) {
        existing.enabled = SGGestureHoldEnabled();
        return;
    }
    SGRCoverHold *hold = [[SGRCoverHold alloc] initWithTarget:nil action:nil];
    hold.enabled = SGGestureHoldEnabled();
    [hold addTarget:hold action:@selector(sgr_held)];
    hold.minimumPressDuration = 0.35;
    [tilt addGestureRecognizer:hold];
    objc_setAssociatedObject(tilt, &kHoldKey, hold, OBJC_ASSOCIATION_ASSIGN);
}

// Where the cover of a player's tilt view stands in it, its paused shrink left out; CGRectNull for any other tilt view.
static CGRect coverPlaceIn(UIView *tilt) {
    UIView *cover = [sg_tilts containsObject:tilt] ? coverIn(tilt) : nil;
    if (!cover) return CGRectNull;
    CGSize size = cover.bounds.size;
    return CGRectMake(cover.center.x - size.width / 2, cover.center.y - size.height / 2, size.width, size.height);
}

static Class imageProxyClass(void) {
    return NSClassFromString(@"_TtC22NowPlaying_ElementsKitP33_1D6A1393FEB35D7207F503DA17E7748E14ImageViewProxy");
}

static void fillParts(UIView *holder) {
    for (UIView *part in holder.subviews)
        if (!CGRectEqualToRect(part.frame, holder.bounds)) part.frame = holder.bounds;
}

%hook _TtC35CreativeWorkCommons_CoverArtTiltKit16CoverArtTiltView
// A cover laid out out of a window had no safe area to be lifted under.
- (void)didMoveToWindow {
    %orig;
    if (((UIView *)self).window) [(UIView *)self setNeedsLayout];
    else followTilt((UIView *)self, nil);
}

// The cover's touches (the hold, Spotify's own) are where it is drawn, lifted above the tilt view's top, not under it.
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGRect place = coverPlaceIn((UIView *)self);
    if (CGRectIsNull(place)) return %orig;
    return CGRectContainsPoint(place, point);
}

// VoiceOver's cover is the tilt view's (its label is Spotify's): its frame, and with it the activation point at its
// middle, is the cover as drawn, lifted and shrunk.
- (CGRect)accessibilityFrame {
    UIView *tilt = (UIView *)self;
    UIView *cover = [sg_tilts containsObject:tilt] ? coverIn(tilt) : nil;
    UIWindow *window = cover.window;
    // Through the window: converting from the cover itself handed back its bounds untouched (iOS 26.5 simulator).
    return window ? UIAccessibilityConvertFrameToScreenCoordinates([cover convertRect:cover.bounds toView:nil], window) : %orig;
}

- (void)layoutSubviews {
    UIView *tilt = (UIView *)self;
    UIView *cell = coverCellOf(tilt);
    %orig;
    if (tilt.bounds.size.width < kCoverMinWidth || !cell) return;
    UIView *cover = coverIn(tilt);
    if (!cover) return;
    [sg_tilts addObject:tilt];
    watchInsets(tilt.window);
    SGRCoverLiftWatch *watch = followTilt(tilt, cell.window && cell.traitCollection.userInterfaceIdiom == UIUserInterfaceIdiomPhone
                                               && cell.bounds.size.height > cell.bounds.size.width ? cell : nil);
    // Kept hidden, it is whichever cover is showing: the first open can lay out a second cell in its place. Not animated,
    // though this pass may run inside Spotify's transition.
    if (sg_coverKeptHidden && cover != sg_hiddenCover && showingTilt() == tilt) {
        [UIView performWithoutAnimation:^{ SGRPlayerSetCoverHidden(YES); }];
    }
    watchHold(tilt);
    SGRPlayerMixCoverLaidOut();
    // The cover fills the tilt view (01.txt:37), lifted to the Music app's top; bounds and center, unlike a frame, hold
    // under the scale.
    CGRect bounds = CGRectMake(0, 0, tilt.bounds.size.width, tilt.bounds.size.height);
    CGPoint middle = CGPointMake(CGRectGetMidX(tilt.bounds), CGRectGetMidY(tilt.bounds) - coverLift(tilt, cell));
    CGFloat side = sg_reservedTilt == tilt ? sg_reservedSide : 0;
    UIView *host = sg_emptyStripHost;
    BOOL stripFill = NO;
    CGRect normal = CGRectNull;
    if (!side && host && tilt.bounds.size.width < tilt.superview.bounds.size.width)
        normal = SGRPlayerNormalCover(host, tilt, host.bounds.size.width - 6 * SGRGrid);
    if ([watch stripOnlyIn:CGRectIsNull(normal) ? nil : tilt.superview]) {
        side = normal.size.width;
        stripFill = YES;
    }
    if (!!objc_getAssociatedObject(tilt, &kStripFillKey) != stripFill)
        objc_setAssociatedObject(tilt, &kStripFillKey, stripFill ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (side > 0) {
        middle.y += (side - bounds.size.height) / 2;
        bounds.size = CGSizeMake(side, side);
    }
    if (!CGSizeEqualToSize(cover.bounds.size, bounds.size)) cover.bounds = (CGRect){cover.bounds.origin, bounds.size};
    if (!CGPointEqualToPoint(cover.center, middle)) cover.center = middle;
    // A cell pass can reset just the bitmap. Matching outer frames do not
    // imply its descendants were laid out. Size all three in this transaction.
    for (UIView *proxy in cover.subviews) {
        if (!side) {
            // The ordinary issue #21 layout: only re-place a proxy whose own frame is stale.
            if (!CGRectEqualToRect(proxy.frame, cover.bounds)) { proxy.bounds = proxy.bounds; proxy.center = proxy.center; }
            continue;
        }
        if (![proxy isKindOfClass:imageProxyClass()]) continue;
        if (!CGRectEqualToRect(proxy.frame, cover.bounds)) proxy.frame = cover.bounds;
        fillParts(proxy);
        for (UIView *image in proxy.subviews)
            if ([image.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) fillParts(image);
    }
    SGRPlayerMotionCoverLaidOut(); // The square clip reads the final cover bounds.

    cover.layer.cornerRadius = SGRRadiusArtwork;
    cover.layer.cornerCurve = kCACornerCurveContinuous;
    cover.clipsToBounds = YES;
    SGRShadowPlate *plate = SGRShadowPlateIn(tilt, &kPlateKey);
    plate.bounds = cover.bounds;
    plate.center = cover.center;
    // The same value an animation in flight is heading to, so a layout pass never cuts one short.
    scaleCover(tilt, SGRPlayerCoverScale());
    // The stage goes with the cover showing: a new song can scroll the list to another cell during the mix.
    if (sg_stage && cover != sg_stagedCover && showingTilt() == tilt) {
        releaseStagedCover();
        sg_stagedCover = cover;
        cover.alpha = 0;
    }
    if (sg_stage && cover == sg_stagedCover) placeStage(tilt, cover);

    static dispatch_once_t once;
    dispatch_once(&once, ^{ SGLog(@"redesign player: cover %@ rounded %.0f with a shadow plate, scale %.2f", NSStringFromClass(cover.class), SGRRadiusArtwork, SGRPlayerCoverScale()); });
}
%end

// The lifted cover's top stands above the views holding its tilt view, where hit testing never reaches the tilt view: a
// touch there that would land on one of those holders is the tilt view's, as anywhere else on the cover.
%hook _TtC28NowPlaying_ContentLayersImpl16CoverArtCellImpl
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = %orig;
    UIView *cell = (UIView *)self;
    if (!hit) return nil;
    for (UIView *tilt in sg_tilts) {
        if (tilt != hit && [tilt isDescendantOfView:hit] && [tilt isDescendantOfView:cell] && SGShownUnder(tilt, cell)
            && [tilt pointInside:[cell convertPoint:point toView:tilt] withEvent:event]) {
            return tilt;
        }
    }
    return hit;
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
    fillParts(proxy);
}
%end

%hook _TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    if ([view.superview isKindOfClass:imageProxyClass()] && coverOfImage(view.superview)) fillParts(view);
}
%end


@interface SGRPlayerArtworkWatcher : NSObject <SGPlayerStateObserver>
@end

// Encore may write its original cell geometry to the bitmap after all three
// containers have finished layout. Own those writes only for this cover path.
static UIView *playerImageHolder(UIView *part) {
    UIView *holder = part.superview;
    static Class encore;
    if (!encore) encore = NSClassFromString(@"_TtCE15Encore_MediaKitO16EncoreFoundation6Encore9ImageView");
    if (![holder isKindOfClass:encore]) return nil;
    UIView *proxy = holder.superview;
    UIView *tilt = proxy.superview.superview;
    return tilt && (tilt == sg_reservedTilt || objc_getAssociatedObject(tilt, &kStripFillKey)) &&
           [proxy isKindOfClass:imageProxyClass()] && coverOfImage(proxy) ? holder : nil;
}

%hook UIImageView
- (void)setFrame:(CGRect)frame {
    UIView *holder = playerImageHolder(self);
    %orig(holder ? holder.bounds : frame);
}
- (void)setBounds:(CGRect)bounds {
    UIView *holder = playerImageHolder(self);
    %orig(holder ? (CGRect){bounds.origin, holder.bounds.size} : bounds);
}
- (void)setCenter:(CGPoint)center {
    UIView *holder = playerImageHolder(self);
    %orig(holder ? CGPointMake(CGRectGetMidX(holder.bounds), CGRectGetMidY(holder.bounds)) : center);
}
%end

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
