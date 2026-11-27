// Player redesign: the player grows out of the now playing bar's card and the cover flies out of the
// card's artwork, the way the Music app opens its player, instead of Spotify's slide up and fade.
//
// CompactOverlayTransition owns the player's frame, the bar crossfade and completion. The morph
// follows the presented layer to place the sheet, mask and flying cover. Music-style close instead
// adds keyframes to Spotify's animator and restores the overlay before Spotify's completion.
//
// Skipped on a regular width (Spotify's iPad branch), with Reduce Motion on, or while the bar has no
// card (hidden, not styled yet): Spotify's own transition then runs untouched.
#import "Core/SGCore.h"
#import "Shared/WireGuard/SGWGABI.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Player.h"

static const CGFloat kScreenRadiusFallback = 55;
// Exported here so the settings row and the transition use the same preference.
NSString *const SGRKeyPlayerMusicClose = @"spotifyglass.redesign.player.musicClose";
static const NSTimeInterval kMusicCloseDurationSeconds = 0.32;
static const NSTimeInterval kMusicVelocityMaxAgeSeconds = 0.15;
static const NSInteger kMusicCloseSteps = 20;
static const CGPoint kMusicCloseControl1 = {0.245, 0.222};
static const CGPoint kMusicCloseControl2 = {0.13, 1};
static const CGPoint kMusicVelocityControl2 = {0.7, 1};
static BOOL sMusicCloseEnabled;

static CGFloat lerp(CGFloat a, CGFloat b, CGFloat t) {
    return a + (b - a) * t;
}

static CGRect lerpRect(CGRect a, CGRect b, CGFloat t) {
    return CGRectMake(lerp(a.origin.x, b.origin.x, t), lerp(a.origin.y, b.origin.y, t),
                      lerp(a.size.width, b.size.width, t), lerp(a.size.height, b.size.height, t));
}

// 0 until `from`, 1 from `to`, eased between.
static CGFloat ramp(CGFloat from, CGFloat to, CGFloat t) {
    CGFloat x = MIN(1, MAX(0, (t - from) / (to - from)));
    return x * x * (3 - 2 * x);
}

static CGFloat screenRadius(void) {
    static CGFloat radius;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        radius = kScreenRadiusFallback;
        @try {
            id value = [UIScreen.mainScreen valueForKey:@"_displayCornerRadius"];
            if ([value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0) radius = [value doubleValue];
        } @catch (__unused NSException *e) {}
    });
    return radius;
}

@interface SGRPlayerMorph : NSObject
@property (nonatomic, readonly) CGFloat restY;
@property (nonatomic) CGFloat releaseVelocity; // full-player-to-card travel per second
@property (nonatomic) CFTimeInterval releaseSampleTime;
- (void)beginMusicClose;
- (void)addMusicCloseKeyframes;
- (void)sampleReleaseFromPan:(UIPanGestureRecognizer *)pan atTime:(CFTimeInterval)time;
- (NSTimeInterval)musicReleaseDurationAt:(CGFloat)progress now:(CFTimeInterval)now;
@end

@implementation SGRPlayerMorph {
    __weak UIView *_container, *_overlay;
    UIView *_sheet;
    UIImageView *_cover;
    CALayer *_mask;
    CGRect _card, _barArtwork;
    CGFloat _cardRadius, _barArtworkRadius;
    id _overlayColor; // ARC owns the layer's original CGColor even if the transition is abandoned
    BOOL _coverHidden;
    UIView *_musicMask, *_dim;
    CGRect _musicOpenFrame, _musicCoverFrame;
    CGAffineTransform _musicOpenTransform;
    CGFloat _musicOpenAlpha;
}

// Where the player's top edge rests when it has become the bar: 9.1.90's CompactOverlayTransition slides it down only
// that far (y 727 of 874), not off the screen.
- (CGFloat)restY {
    return CGRectGetMinY(_card);
}

- (instancetype)initWithContainer:(UIView *)container overlay:(UIView *)overlay bar:(UIView *)bar {
    CGFloat radius = 0;
    CGRect card = SGRNowPlayingCardFrameIn(container, &radius);
    if (CGRectIsNull(card) || CGRectIsEmpty(card)) return nil;
    if (!(self = [super init])) return nil;
    _container = container;
    _overlay = overlay;
    _card = card;
    _cardRadius = radius;
    _barArtwork = SGRNowPlayingArtworkFrameIn(container, &_barArtworkRadius);

    _sheet = [[UIView alloc] initWithFrame:card];
    _sheet.userInteractionEnabled = NO;
    _sheet.backgroundColor = SGRPlayerBackdropShowing() ? UIColor.blackColor : SGRPlayerField().fieldColor ?: UIColor.blackColor;
    _sheet.layer.cornerCurve = kCACornerCurveContinuous;
    _sheet.clipsToBounds = YES;
    [container insertSubview:_sheet belowSubview:overlay];

    // The player's own paint is not a sublayer, so the content's transform would leave it where Spotify
    // put the player, a band below the sheet's top edge; the sheet paints instead.
    _overlayColor = (__bridge id)overlay.layer.backgroundColor;
    overlay.layer.backgroundColor = NULL;

    _mask = [CALayer layer];
    _mask.backgroundColor = UIColor.blackColor.CGColor;
    _mask.cornerCurve = kCACornerCurveContinuous;
    overlay.layer.mask = _mask;

    if (bar.superview == container) [container bringSubviewToFront:bar];

    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    if (artwork && !CGRectIsNull(_barArtwork)) {
        _cover = [[UIImageView alloc] initWithImage:artwork];
        _cover.userInteractionEnabled = NO;
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        [container addSubview:_cover];
    }

    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: card %@ r=%.0f, artwork %@, cover %@, screen r=%.0f", NSStringFromCGRect(card), radius,
                            NSStringFromCGRect(_barArtwork), _cover ? @"flown" : @"not flown", screenRadius());
    return self;
}

- (void)apply:(CGFloat)t {
    UIView *container = _container, *overlay = _overlay;
    if (!container || !overlay) return;
    t = MIN(1, MAX(0, t));
    // The model frame is already at the end. Before the first drawn frame the player is at the bar and transparent.
    CALayer *drawn = overlay.layer.presentationLayer;
    CGPoint origin = drawn ? drawn.frame.origin : CGPointMake(overlay.frame.origin.x, self.restY);
    CGFloat opacity = drawn ? drawn.opacity : 0;
    CGRect full = container.bounds;
    CGRect sheet = lerpRect(_card, full, t);
    CGFloat radius = lerp(_cardRadius, screenRadius(), t);
    CGFloat scale = full.size.width > 0 ? sheet.size.width / full.size.width : 1;
    CGSize size = overlay.bounds.size;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint target = CGPointMake(sheet.origin.x - origin.x, sheet.origin.y - origin.y);
    // A point q of the player lands at middle + scale * (q - middle) + shift; the top left at target.
    CGPoint shift = CGPointMake(target.x - middle.x + scale * middle.x, target.y - middle.y + scale * middle.y);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [UIView performWithoutAnimation:^{
        overlay.layer.sublayerTransform = CATransform3DIdentity;
        CGRect coverInPlayer = SGRPlayerCoverFrameIn(overlay);

        overlay.layer.sublayerTransform = CATransform3DScale(CATransform3DMakeTranslation(shift.x, shift.y, 0), scale, scale, 1);
        self->_mask.frame = CGRectMake(target.x, target.y, sheet.size.width, sheet.size.height);
        self->_mask.cornerRadius = radius;

        self->_sheet.frame = sheet;
        self->_sheet.layer.cornerRadius = radius;
        // The sheet is the player's own paint, so it fades with the player Spotify fades against its bar stand-in.
        self->_sheet.alpha = opacity;

        if (self->_cover) {
            // Worked out relative to the sheet, so the cover stays on it the whole way rather than
            // heading for where the player's cover is while that is still below the screen.
            CGRect from = CGRectOffset(self->_barArtwork, -self->_card.origin.x, -self->_card.origin.y);
            // The player's cover is held hidden from the first frame, laid out or not: the first open lays it out
            // between two frames of the morph, and it is hidden in that layout pass (PlayerArtwork.x).
            if (!self->_coverHidden) {
                SGRPlayerSetCoverHidden(YES);
                self->_coverHidden = YES;
            }
            if (CGRectIsNull(coverInPlayer)) {
                self->_cover.hidden = YES;
            } else {
                CGRect to = CGRectMake(middle.x + scale * (coverInPlayer.origin.x - middle.x) + shift.x + origin.x,
                                       middle.y + scale * (coverInPlayer.origin.y - middle.y) + shift.y + origin.y,
                                       coverInPlayer.size.width * scale, coverInPlayer.size.height * scale);
                self->_cover.hidden = NO;
                to = CGRectOffset(to, -sheet.origin.x, -sheet.origin.y);
                self->_cover.frame = CGRectOffset(lerpRect(from, to, t), sheet.origin.x, sheet.origin.y);
                // The cover's corners are drawn under its paused shrink too.
                self->_cover.layer.cornerRadius = lerp(self->_barArtworkRadius, SGRRadiusArtwork * SGRPlayerCoverScale() * scale, t);
                // Over a clip or lyric stage the player's cover is hidden: the flown one fades out on the
                // way there instead of landing on an empty slot.
                self->_cover.alpha = SGRPlayerCoverHidden() ? 1 - ramp(0.6, 1, t) : 1;
            }
        }
    }];
    [CATransaction commit];
}

// Unlike the follower, these views belong to Spotify's property animator. The overlay keeps its
// full-size bounds (and hence its layout); its view transform and a UIView mask supply the clipping.
// No display link writes over the render server, including while the animator is paused/reversed.
- (void)beginMusicClose {
    UIView *overlay = _overlay;
    _musicOpenFrame = overlay.frame;
    _musicOpenTransform = overlay.transform;
    _musicOpenAlpha = overlay.alpha;
    _musicCoverFrame = SGRPlayerCoverFrameIn(_container);
    _musicMask = [UIView new];
    _musicMask.backgroundColor = UIColor.blackColor;
    _musicMask.layer.cornerCurve = kCACornerCurveContinuous;
    overlay.layer.mask = nil;
    overlay.maskView = _musicMask;
    _dim = [[UIView alloc] initWithFrame:_container.bounds];
    _dim.backgroundColor = UIColor.blackColor;
    _dim.userInteractionEnabled = NO;
    [_container insertSubview:_dim belowSubview:_sheet];
    if (_cover && !CGRectIsNull(_musicCoverFrame)) {
        SGRPlayerSetCoverHidden(YES);
        _coverHidden = YES;
    } else {
        [_cover removeFromSuperview];
        _cover = nil;
    }
    [self applyMusicClose:0];
}

- (void)applyMusicClose:(CGFloat)p {
    CGRect full = _container.bounds;
    CGFloat side = ramp(0.70, 1, p), bottom = ramp(0.80, 1, p);
    CGFloat left = lerp(CGRectGetMinX(full), CGRectGetMinX(_card), side);
    CGFloat right = lerp(CGRectGetMaxX(full), CGRectGetMaxX(_card), side);
    CGFloat top = lerp(CGRectGetMinY(full), CGRectGetMinY(_card), p);
    CGFloat foot = lerp(CGRectGetMaxY(full), CGRectGetMaxY(_card), bottom);
    CGRect sheet = CGRectMake(left, top, right - left, foot - top);
    CGFloat radius = MIN(lerp(screenRadius(), _cardRadius, ramp(0.55, 1, p)), sheet.size.height / 2);
    CGFloat scale = sheet.size.width / _overlay.bounds.size.width;
    _sheet.frame = sheet;
    _sheet.layer.cornerRadius = radius;
    _sheet.alpha = 1;
    _overlay.transform = CGAffineTransformMakeScale(scale, scale);
    _overlay.center = CGPointMake(CGRectGetMidX(sheet), top + _overlay.bounds.size.height * scale / 2);
    _musicMask.frame = CGRectMake(0, 0, sheet.size.width / scale, sheet.size.height / scale);
    _musicMask.layer.cornerRadius = radius / scale;
    _overlay.alpha = 1 - ramp(0.80, 1, p);
    _dim.alpha = 0.30 * (1 - p);
    _cover.frame = lerpRect(_musicCoverFrame, _barArtwork, p);
    _cover.layer.cornerRadius = lerp(SGRRadiusArtwork * SGRPlayerCoverScale(), _barArtworkRadius, p);
    _cover.alpha = SGRPlayerCoverHidden() ? ramp(0, 0.4, p) : 1;
}

- (void)addMusicCloseKeyframes {
    [UIView animateKeyframesWithDuration:kMusicCloseDurationSeconds delay:0
                                options:UIViewKeyframeAnimationOptionCalculationModeLinear animations:^{
        for (NSInteger step = 1; step <= kMusicCloseSteps; step++) {
            [UIView addKeyframeWithRelativeStartTime:(CGFloat)(step - 1) / kMusicCloseSteps
                                   relativeDuration:1.0 / kMusicCloseSteps animations:^{
                [self applyMusicClose:(CGFloat)step / kMusicCloseSteps];
            }];
        }
    } completion:nil];
}

- (void)sampleReleaseFromPan:(UIPanGestureRecognizer *)pan atTime:(CFTimeInterval)time {
    CGFloat travel = CGRectGetMinY(_card) - CGRectGetMinY(_container.bounds);
    if (!pan || travel <= 0) return;
    self.releaseVelocity = [pan velocityInView:_container].y / travel;
    self.releaseSampleTime = time;
}

- (NSTimeInterval)musicReleaseDurationAt:(CGFloat)progress now:(CFTimeInterval)now {
    CGFloat remaining = 1 - progress;
    CFTimeInterval age = now - self.releaseSampleTime;
    if (age < 0 || age > kMusicVelocityMaxAgeSeconds || remaining < 0.02 || self.releaseVelocity <= 0)
        return 0; // Keep the fixed curve; Spotify alone decides finish versus cancel.
    return MIN(kMusicCloseDurationSeconds, MAX(0.05, remaining / self.releaseVelocity * 1.1));
}

- (void)tearDown {
    UIView *overlay = _overlay;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (_musicMask) {
        overlay.maskView = nil;
        overlay.transform = _musicOpenTransform;
        overlay.frame = _musicOpenFrame;
        overlay.alpha = _musicOpenAlpha;
        [_dim removeFromSuperview];
        _dim = nil;
        _musicMask = nil;
    }
    overlay.layer.sublayerTransform = CATransform3DIdentity;
    if (overlay.layer.mask == _mask) overlay.layer.mask = nil;
    if (!overlay.layer.backgroundColor) overlay.layer.backgroundColor = (__bridge CGColorRef)_overlayColor;
    _overlayColor = nil;
    [_sheet removeFromSuperview];
    [_cover removeFromSuperview];
    [CATransaction commit];
    if (_coverHidden) SGRPlayerSetCoverHidden(NO);
    _coverHidden = NO;
    _cover = nil;
}

@end

#pragma mark - Compact overlay transition

// 9.1.90 presents the player with MainUI_TabBarUIImpl.CompactOverlayTransition, a UIKit animator that moves the
// player up from below the screen (animateTransition:, and startInteractiveTransition: for a drag) with its own
// stand-ins (npbSnapshotView, tabBarSnapshotView; BarTransition.x). A display link reads how far up Spotify's animation
// has the player and morphs to match, so Spotify's frame, alpha and completion stay its own. It is let go once the
// transition is no longer interactive and the player has no animation left and holds still a few frames.
static const CFTimeInterval kGiveUp = 0.9;   // ticking with no move this long; UIKit's whole presentation runs about 0.5 s
static const float kCloseSpeed = 1.5;         // how much faster than Spotify's a close it runs on its own plays

@interface SGRMorphFollower : NSObject
@property (nonatomic, strong) SGRPlayerMorph *morph;
@property (nonatomic, weak) UIView *container, *overlay;
@property (nonatomic, weak) id<UIViewControllerContextTransitioning> context;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSInteger still;
@property (nonatomic) CGFloat lastY;
@property (nonatomic) CFTimeInterval settledSince;   // when it last moved or was driven by a finger, or began
@property (nonatomic) CFTimeInterval lastTick;
@property (nonatomic) BOOL sped;                     // the container's layer runs at kCloseSpeed until let go
@property (nonatomic) BOOL closing, wasInteractive;
@end

// The container's clock runs at `speed` from now on, continuing from where its animations are.
static void runAtSpeed(CALayer *layer, float speed) {
    CFTimeInterval now = CACurrentMediaTime(), local = [layer convertTime:now fromLayer:nil];
    layer.speed = speed;
    layer.beginTime = layer.superlayer ? [layer.superlayer convertTime:now fromLayer:nil] : now;
    layer.timeOffset = local;
}

@implementation SGRMorphFollower
- (void)tick:(CADisplayLink *)link {
    UIView *container = self.container, *overlay = self.overlay;
    if (!container || !overlay || !overlay.window) {
        [self finish];
        return;
    }
    CALayer *drawn = overlay.layer.presentationLayer;
    CGFloat rest = self.morph.restY > 0 ? self.morph.restY : container.bounds.size.height;
    // An open's first frame has no presentation layer yet and its model already holds the end; Spotify starts it at the bar.
    CGFloat y = drawn ? drawn.frame.origin.y : rest;
    [self.morph apply:rest > 0 ? MIN(1, MAX(0, 1 - y / rest)) : 1];
    BOOL interactive = self.context.isInteractive;
    // A close dragged by a finger runs faster from the moment it is let go.
    if (self.closing && self.wasInteractive && !interactive && !self.sped) {
        runAtSpeed(container.layer, kCloseSpeed);
        self.sped = YES;
    }
    self.wasInteractive = interactive;
    BOOL moved = fabs(y - self.lastY) > 0.5;
    BOOL moving = overlay.layer.animationKeys.count > 0 || moved || interactive;
    self.lastY = y;
    self.still = moving ? 0 : self.still + 1;
    // Let go once still, or kGiveUp after it last moved whatever the layer holds: a mask and a transform left on the player
    // would keep its glass buttons from drawing. Counted from the last move and over ticks only, so a stall of the main
    // thread before the slide (a cold open's first layout) does not use it up.
    CFTimeInterval now = CACurrentMediaTime();
    if (interactive || moved || !self.settledSince || now - self.lastTick > kGiveUp / 4) self.settledSince = now;
    self.lastTick = now;
    if (self.still >= 3 || now - self.settledSince > kGiveUp) [self finish];
}
- (void)finish {
    if (!self.link) return;
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: let go after %.2f s still, %@", CACurrentMediaTime() - self.settledSince, self.still >= 3 ? @"settled" : @"given up");
    [self.link invalidate];
    self.link = nil;
    // Back to 1 from where its animations are, so a close Spotify has not finished does not jump back.
    if (self.sped) runAtSpeed(self.container.layer, 1);
    [self.morph tearDown];
    self.morph = nil;
}
@end

@interface SGStoredField : NSObject
+ (BOOL)supportsField:(NSString *)name on:(id)object ofClass:(Class)cls;
+ (id)field:(NSString *)name on:(id)object ofClass:(Class)cls;
@end

static UIView *ivarOf(id object, const char *name) {
    return [SGStoredField field:@(name) on:object ofClass:UIView.class];
}

static BOOL hasSnapshotFields(id transition) {
    return [SGStoredField supportsField:@"npbSnapshotView" on:transition ofClass:UIView.class] &&
           [SGStoredField supportsField:@"tabBarSnapshotView" on:transition ofClass:UIView.class];
}

static char kFollowerKey;
static char kMusicAnimatorKey;
// UIKit transition entry points and gesture callbacks are main-thread only. These scopes identify
// precisely the animator being constructed/released; no unrelated UIKit animator is changed.
static id sMusicTransition;
static id<UIViewControllerContextTransitioning> sMusicContext;
static BOOL sMusicClaimed;
static UIPanGestureRecognizer *sMusicPan;
static CFTimeInterval sMusicPanTime;

static UICubicTimingParameters *musicTiming(BOOL velocityShaped) {
    return [[UICubicTimingParameters alloc] initWithControlPoint1:kMusicCloseControl1
                                                 controlPoint2:velocityShaped ? kMusicVelocityControl2 : kMusicCloseControl2];
}

static void followTransition(id transition, id<UIViewControllerContextTransitioning> context) {
    if (SGRReduceMotion() || !context || !hasSnapshotFields(transition)) return;
    UIView *container = context.containerView;
    if (container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *overlay = to.isBeingPresented ? [context viewForKey:UITransitionContextToViewKey] : [context viewForKey:UITransitionContextFromViewKey];
    if (!overlay || overlay.superview != container) return;
    SGRMorphFollower *old = objc_getAssociatedObject(transition, &kFollowerKey);
    [old finish];
    SGRPlayerMorph *morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay bar:ivarOf(transition, "npbSnapshotView")];
    if (!morph) return;
    ((UIView *)ivarOf(transition, "tabBarSnapshotView")).alpha = 0;
    SGRMorphFollower *follower = [SGRMorphFollower new];
    follower.morph = morph;
    follower.container = container;
    follower.overlay = overlay;
    follower.context = context;
    follower.lastY = CGFLOAT_MAX;
    // A close plays faster: its slide, its stand-ins and so the morph that follows them. One Spotify runs on its own
    // from the start, one dragged by a finger from when it is let go (tick:).
    follower.closing = !to.isBeingPresented;
    follower.wasInteractive = context.isInteractive;
    if (follower.closing && !context.isInteractive) {
        runAtSpeed(container.layer, kCloseSpeed);
        follower.sped = YES;
    }
    follower.link = [CADisplayLink displayLinkWithTarget:follower selector:@selector(tick:)];
    [NSNotificationCenter.defaultCenter addObserver:follower selector:@selector(finish)
                                               name:UIApplicationWillResignActiveNotification object:nil];
    follower.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [follower.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(transition, &kFollowerKey, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [follower tick:follower.link];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: follows CompactOverlayTransition (%@)", to.isBeingPresented ? @"open" : @"close");
}

// Check the owner's capabilities before changing either its advertised duration or its animator.
// Ivar values are populated during setup; their declarations must already exist at the duration query.
static BOOL musicCloseSupportedOwner(id transition, id<UIViewControllerContextTransitioning> context) {
    if (!sMusicCloseEnabled || !context ||
        [context viewControllerForKey:UITransitionContextToViewControllerKey].isBeingPresented || SGRReduceMotion() ||
        context.containerView.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return NO;
    if (!hasSnapshotFields(transition) ||
        ![SGStoredField supportsField:@"overlayView" on:transition ofClass:UIView.class]) return NO;
    CGRect card = SGRNowPlayingCardFrameIn(context.containerView, NULL);
    return !CGRectIsNull(card) && !CGRectIsEmpty(card);
}

static void compactTransition(id transition, id<UIViewControllerContextTransitioning> context, void (^original)(void)) {
    id previousTransition = sMusicTransition;
    id<UIViewControllerContextTransitioning> previousContext = sMusicContext;
    BOOL previousClaimed = sMusicClaimed;
    sMusicTransition = musicCloseSupportedOwner(transition, context) ? transition : nil;
    sMusicContext = sMusicTransition ? context : nil;
    sMusicClaimed = NO;
    BOOL claimed;
    @try {
        original();
        claimed = sMusicClaimed;
    } @finally {
        sMusicTransition = previousTransition;
        sMusicContext = previousContext;
        sMusicClaimed = previousClaimed;
    }
    if (!claimed) followTransition(transition, context);
}

%group SGRCompactMorph
%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)context {
    if (musicCloseSupportedOwner(self, context)) return kMusicCloseDurationSeconds;
    return %orig;
}
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    compactTransition(self, context, ^{
        %orig;
    });
}
- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)context {
    compactTransition(self, context, ^{
        %orig;
    });
}
%end

%end
%group SGRMusicCloseHooks
%hook UIViewPropertyAnimator
- (id)initWithDuration:(NSTimeInterval)duration curve:(UIViewAnimationCurve)curve animations:(void (^)(void))animations {
    if (!NSThread.isMainThread || !sMusicTransition || sMusicClaimed ||
        !musicCloseSupportedOwner(sMusicTransition, sMusicContext)) return %orig;
    UIView *overlay = ivarOf(sMusicTransition, "overlayView");
    UIView *container = sMusicContext.containerView;
    if (!overlay || overlay != [sMusicContext viewForKey:UITransitionContextFromViewKey] || overlay.superview != container)
        return %orig;
    SGRPlayerMorph *morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay
        bar:ivarOf(sMusicTransition, "npbSnapshotView")];
    if (!morph) return %orig;
    sMusicClaimed = YES;
    [morph beginMusicClose];
    [morph sampleReleaseFromPan:sMusicPan atTime:sMusicPanTime];
    ((UIView *)ivarOf(sMusicTransition, "tabBarSnapshotView")).alpha = 0;
    void (^staged)(void) = ^{
        if (animations) animations();
        [morph addMusicCloseKeyframes];
    };
    // Call the other initializer on the same allocation. Raw ownership is deliberate: Logos's
    // replacement is a C function, while init consumes +1 and may return a different object.
    void *raw = ((void *(*)(void *, SEL, NSTimeInterval, CGPoint, CGPoint, id))objc_msgSend)(
        (__bridge void *)self, @selector(initWithDuration:controlPoint1:controlPoint2:animations:),
        kMusicCloseDurationSeconds, kMusicCloseControl1, kMusicCloseControl2, staged);
    UIViewPropertyAnimator *animator = CFBridgingRelease(raw);
    objc_setAssociatedObject(animator, &kMusicAnimatorKey, morph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Registered before Spotify's completion: restore our paint, then let Spotify alone restore the
    // hierarchy and call completeTransition: using transitionWasCancelled.
    [animator addCompletion:^(__unused UIViewAnimatingPosition position) { [morph tearDown]; }];
    return (__bridge id)CFBridgingRetain(animator);
}
- (void)setFractionComplete:(CGFloat)fraction {
    SGRPlayerMorph *morph = objc_getAssociatedObject(self, &kMusicAnimatorKey);
    [morph sampleReleaseFromPan:sMusicPan atTime:sMusicPanTime];
    %orig;
}
- (void)continueAnimationWithTimingParameters:(id<UITimingCurveProvider>)parameters durationFactor:(CGFloat)factor {
    SGRPlayerMorph *morph = objc_getAssociatedObject(self, &kMusicAnimatorKey);
    if (!morph) {
        %orig;
        return;
    }
    [morph sampleReleaseFromPan:sMusicPan atTime:sMusicPanTime];
    NSTimeInterval remaining = self.isReversed ? 0 :
        [morph musicReleaseDurationAt:self.fractionComplete now:CACurrentMediaTime()];
    %orig(musicTiming(remaining > 0), remaining > 0 ? remaining / self.duration : factor);
}
%end

%hook _TtC19MainUI_TabBarUIImpl25CompactGestureCoordinator
- (void)handleDismissPan:(UIPanGestureRecognizer *)pan {
    UIPanGestureRecognizer *previous = sMusicPan;
    CFTimeInterval previousTime = sMusicPanTime;
    sMusicPan = pan;
    sMusicPanTime = CACurrentMediaTime();
    @try {
        %orig;
    } @finally {
        sMusicPan = previous;
        sMusicPanTime = previousTime;
    }
}
- (void)scrollPanAction:(UIPanGestureRecognizer *)pan {
    UIPanGestureRecognizer *previous = sMusicPan;
    CFTimeInterval previousTime = sMusicPanTime;
    sMusicPan = pan;
    sMusicPanTime = CACurrentMediaTime();
    @try {
        %orig;
    } @finally {
        sMusicPan = previous;
        sMusicPanTime = previousTime;
    }
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    Class compact = NSClassFromString(@"_TtC19MainUI_TabBarUIImpl24CompactOverlayTransition");
    BOOL supported = SGWGMethodMatches(class_getInstanceMethod(compact, @selector(animateTransition:)), "v", @[@"@"]) &&
        SGWGMethodMatches(class_getInstanceMethod(compact, @selector(startInteractiveTransition:)), "v", @[@"@"]) &&
        SGWGMethodMatches(class_getInstanceMethod(compact, @selector(transitionDuration:)), "d", @[@"@"]);
    sMusicCloseEnabled = supported && SGHidden(SGRKeyPlayerMusicClose);
    if (supported) {
        %init(SGRCompactMorph);
    } else {
        SGLog(@"player morph: compact animator API unavailable");
    }
    if (sMusicCloseEnabled) {
        %init(SGRMusicCloseHooks);
    }
}
