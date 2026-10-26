// Player redesign: the player grows out of the now playing bar's card and the cover flies out of the
// card's artwork, the way the Music app opens its player, instead of Spotify's slide up and fade.
//
// Spotify 9.1.78 runs the open and the close through SPTBarOverlayPresentationTransition: it hides the
// real bar and tab bar, moves stand-ins, and sets -setProgress: (0 the bar, 1 the player, clamped) on
// every frame of its own display link, from a spring when tapped and from the finger when dragged
// (setProgress: at 0x109815464). There it sets the player's frame to the container's bounds moved down by
// the bar's bottom edge times (1 - progress), and the player's alpha, and moves and fades the bar's stand-in.
//
// The morph rides on that progress, after Spotify's own, so taps, drags and canceled drags follow:
//   the sheet   a rounded rect from the card's frame and radius to the screen's, under the player: frosted
//               glass filling in with the field's color as it grows, the screen's width early in an open
//               and kept late in a close, as the Music app's;
//   the player  masked to the sheet, its content scaled and moved so its top left is the sheet's
//               (sublayerTransform, and the frame's top moved to the sheet's; Spotify's gesture code
//               reads back only the frame's height), its own background color lifted off meanwhile
//               (a sublayerTransform does not move it), and faded in over the first part of the growth;
//   the bar     Spotify's stand-in riding the sheet's top edge until the player has mostly come in;
//   the tab bar Spotify's stand-in hidden, since the real one stays in view around the sheet
//               and the stand-in would be a second tab bar;
//   the cover   a copy of the player's cover kept on the sheet, growing out of the card with it as it fades in
//               on an open and shrinking back into it as it fades out on a close, the one the other played
//               backwards; the player's own cover and shadow hidden meanwhile. Flown from the card's artwork
//               on an open, it read as a second motion beside the sheet's.
// All of it is taken down in -destroyTransitioningContext, which Spotify calls from -animationEnded:.
//
// Skipped on a regular width (Spotify's iPad branch), with Reduce Motion on, or while the bar has no
// card (hidden, not styled yet): Spotify's own transition then runs untouched.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Player.h"

@interface SPTBarOverlayPresentationTransition : NSObject
- (id<UIViewControllerContextTransitioning>)transitioningContext;
- (UIView *)overlayView;
- (UIView *)barSnapshotView;
- (UIView *)tabBarSnapshotView;
- (CGRect)barFrame;
- (double)progress;
@end

static const CGFloat kScreenRadiusFallback = 55;
// How far into an open the sheet has taken the screen's width (apply:).
static const CGFloat kAcross = 0.4;
// Where the player and the card hand over, near the card: the player's content and the sheet's color go together, so the
// content clears straight into the card's glass with the card's row coming in. Faded apart (the content from 55% to 8%,
// the color from 85% to 30%), the sheet near the card was a bare colored pane with the row on it (a screen recording).
static const CGFloat kHandFrom = 0.25, kHandTo = 0.6;
// A let go close's spring, as SwiftUI's .spring(duration:bounce:) takes one: some 0.35 s with a little give, so the card
// dips a little past its place and settles back, as the Music app's mini player does. Its owner's recordings at 60 fps
// put the Music app's dip at 2.5 to 3.5 pt, settled a tenth of a second later: a bounce of 0.15 (some 0.6% of the way, 5
// pt on a close from the top); 0.25 dipped 22 pt. 0.2 for a while, then 0.15 again by its owner's pick (2026-10-26).
static const CFTimeInterval kReleaseSpring = 0.32, kReleaseSettle = 0.6;
static const double kReleaseBounce = 0.15;

// An underdamped spring from 0 to 1 at `elapsed`, from rest: it goes past 1 and settles back.
static double releaseSpring(double elapsed) {
    double zeta = 1 - kReleaseBounce, omega = 2 * M_PI / kReleaseSpring, wd = omega * sqrt(1 - zeta * zeta);
    double e = MAX(0, elapsed);
    return 1 - exp(-zeta * omega * e) * (cos(wd * e) + zeta * omega / wd * sin(wd * e));
}

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
@property (nonatomic) BOOL closing;   // a close animates the player's frame into the card's (apply:)
// A finger dragging the player holds it whole (dragging); let go towards the card (released), one animation of its own
// takes it there from where it was.
@property (nonatomic) BOOL dragging;
@property (nonatomic) BOOL dragged;   // a finger has had the player in this close
@property (nonatomic) BOOL released;
@property (nonatomic) CFTimeInterval releasedAt, releaseDuration;
@property (nonatomic) CGRect releaseRect;   // the sheet where the finger let go of it
@property (nonatomic) CGFloat releaseT;     // how far up the player was then
@property (nonatomic, readonly) CGRect lastSheet;
// When the frame being drawn will show (the display link's target): the release's spring is timed by it, so its steps
// come even however late in the frame the main thread gets to it.
@property (nonatomic) CFTimeInterval frameTime;
- (void)pictureCard:(UIView *)bar;
@property (nonatomic, readonly) CGRect card;
@property (nonatomic, readonly) BOOL masksStrip;
@end

@implementation SGRPlayerMorph {
    __weak UIView *_container, *_overlay, *_bar;
    UIView *_sheet, *_fill;
    UIImageView *_row;   // a picture of the card's content, standing in for Spotify's stand-in on a close
    CGRect _rowRest;     // where the pictured view stands, in the container
    CGRect _lastSheet;
    UIImageView *_cover;
    // The flying cover's shadow: the cover clips, so it is a plate of the Kit's under it, the player's own plate's look,
    // in and out with the cover. Without it the player's shadow appeared in one frame as the cover took over at the end
    // of an open (its owner's screen recordings, 2026-10-26).
    SGRShadowPlate *_coverShadow;
    CALayer *_mask;
    // In a Jam (follow mode only): the mask on the stand-in or its picture, its strip part fading on the way open, and
    // a close's copy of the strip's glass, which fades by alpha.
    CALayer *_stripMask, *_stripPart;
    __weak UIView *_masked, *_stripPane;
    CGFloat _stripPaneAlpha;
    CGRect _card, _barArtwork, _barRest, _spotifyFrame;
    CGFloat _cardRadius, _spotifyAlpha;
    CGColorRef _overlayColor;
    BOOL _coverHidden;
    BOOL _wholeShown;    // the player drawing itself whole under a finger (showWhole)
    BOOL _tornDown;
    BOOL _follows;   // 9.1.90: Spotify animates the player's frame and alpha, which the morph then only reads
}

// Where the player's top edge rests when it has become the bar: 9.1.90's CompactOverlayTransition slides it down only
// that far (y 727 of 874), not off the screen.
- (CGFloat)restY {
    return CGRectGetMinY(_card);
}

// 9.1.90's CompactOverlayTransition animates the player itself, so the morph follows where it is drawn. Its stand-in
// for the bar is taken over to ride the sheet's top edge, as on 9.1.78 (apply:): hidden, the card went blank the
// moment the player began to open (a screen recording at 60 fps).
- (void)followFrom:(UIView *)source {
    _follows = YES;
    // Next turn, once every hook on the transition's start has run: a close's glass copies (BarTransition.x) exist by
    // then whichever hook runs first. At either end the strip sits in the stand-in at Spotify's own alpha, so the turn
    // without the mask shows nothing new.
    __weak SGRPlayerMorph *weak = self;
    __weak UIView *weakSource = source;
    dispatch_async(dispatch_get_main_queue(), ^{ [weak maskStripFrom:weakSource]; });
}

- (void)maskStripFrom:(UIView *)source {
    if (_tornDown || !source) return;
    // In a Jam the stand-in is the whole bar, strip and card, and the sheet grows from the card alone: the strip fades
    // in the first quarter of an open, so it never stands beside the growing player. Its place comes from Spotify's bar
    // the stand-in copies, scaled to the stand-in, not from the card: Spotify has already set the stand-in's end frame.
    UIView *bar = _bar;
    CGRect strip = SGRNowPlayingStripFrameIn(source);
    if (CGRectIsNull(strip) || !bar) return;
    CGSize from = source.bounds.size, to = bar.bounds.size;
    CGFloat sx = from.width > 0 ? to.width / from.width : 1, sy = from.height > 0 ? to.height / from.height : 1;
    strip = CGRectIntersection(CGRectMake(strip.origin.x * sx, strip.origin.y * sy, strip.size.width * sx, strip.size.height * sy), bar.bounds);
    if (CGRectIsEmpty(strip)) return;
    // A close's stand-in is a picture over copies of the bar's glass (BarTransition.x), which a mask above them would
    // break: the mask goes on the picture alone, and the strip's copy of the glass fades by alpha.
    UIView *masked = bar;
    if ([bar isKindOfClass:UIImageView.class] && !((UIImageView *)bar).image && [bar.subviews.lastObject isKindOfClass:UIImageView.class]) {
        masked = bar.subviews.lastObject;
        for (UIView *pane in bar.subviews) {
            if (pane != masked && CGRectContainsPoint(strip, CGPointMake(CGRectGetMidX(pane.frame), CGRectGetMidY(pane.frame)))) _stripPane = pane;
        }
        _stripPaneAlpha = _stripPane.alpha;
    }
    if (masked.layer.mask) {
        _stripPane = nil;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGLog(@"player morph: the bar's stand-in has a mask of its own, the Jam strip is not faded"); });
        return;
    }
    strip = [masked convertRect:strip fromView:bar];
    // Opaque but for the strip, above or below the card, which its own part covers at the fade's opacity.
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = masked.bounds;
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:masked.bounds];
    [path appendPath:[UIBezierPath bezierPathWithRect:strip]];
    mask.path = path.CGPath;
    mask.fillRule = kCAFillRuleEvenOdd;
    _stripPart = [CALayer layer];
    _stripPart.backgroundColor = UIColor.blackColor.CGColor;
    _stripPart.frame = strip;
    [mask addSublayer:_stripPart];
    _stripMask = mask;
    _masked = masked;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    masked.layer.mask = mask;
    [CATransaction commit];
}

- (BOOL)masksStrip {
    return _stripMask != nil;
}

- (instancetype)initWithContainer:(UIView *)container overlay:(UIView *)overlay bar:(UIView *)bar barRest:(CGRect)barRest {
    CGFloat radius = 0;
    CGRect card = SGRNowPlayingCardFrameIn(container, &radius);
    if (CGRectIsNull(card) || CGRectIsEmpty(card)) return nil;
    if (!(self = [super init])) return nil;
    _container = container;
    _overlay = overlay;
    _bar = bar;
    _barRest = barRest;
    _card = card;
    _cardRadius = radius;
    _barArtwork = SGRNowPlayingArtworkFrameIn(container);
    _spotifyAlpha = overlay.alpha;

    // Frosted glass that fills in with the field's color as it grows, as the Music app's sheet does: the page shows
    // blurred through it on the way and it is solid by the time it is the screen (screen recordings at 60 fps).
    _sheet = [[UIView alloc] initWithFrame:card];
    _sheet.userInteractionEnabled = NO;
    _sheet.layer.cornerCurve = kCACornerCurveContinuous;
    _sheet.clipsToBounds = YES;
    // The card's own glass, dark as the card's is: Spotify's stand-in for the card on 9.1.90 is a live replica, which
    // draws no glass, so the sheet is the card's glass at the card's end of the transition (apply:).
    UIVisualEffectView *frost = [[UIVisualEffectView alloc] initWithEffect:SGGlassEffect()];
    frost.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    frost.frame = _sheet.bounds;
    frost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_sheet addSubview:frost];
    _fill = [[UIView alloc] initWithFrame:_sheet.bounds];
    _fill.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _fill.backgroundColor = SGRPlayerField().fieldColor ?: UIColor.blackColor;
    [_sheet addSubview:_fill];
    [container insertSubview:_sheet belowSubview:overlay];

    // The player's own paint is not a sublayer, so the content's transform would leave it where Spotify
    // put the player, a band below the sheet's top edge; the sheet paints instead.
    _overlayColor = CGColorRetain(overlay.layer.backgroundColor);
    overlay.layer.backgroundColor = NULL;

    _mask = [CALayer layer];
    _mask.backgroundColor = UIColor.blackColor.CGColor;
    _mask.cornerCurve = kCACornerCurveContinuous;
    overlay.layer.mask = _mask;

    if (bar.superview == container) [container bringSubviewToFront:bar];
    // The sheet is opaque from the first frame (apply:), so it goes under the card's stand-in wherever Spotify put it: on
    // 9.1.90 the stand-in sits in the container below the player, and the sheet over it hid the card's title and buttons
    // for the first frames of an open (a screen recording).
    UIView *standIn = bar;
    while (standIn && standIn.superview != container) standIn = standIn.superview;
    if (standIn && [container.subviews indexOfObject:standIn] < [container.subviews indexOfObject:_sheet]) {
        [container insertSubview:_sheet belowSubview:standIn];
    }

    UIImage *artwork = SGRNowPlayingArtwork(NULL, NULL);
    if (artwork && !CGRectIsNull(_barArtwork)) {
        _cover = [[UIImageView alloc] initWithImage:artwork];
        _cover.userInteractionEnabled = NO;
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        _cover.layer.cornerCurve = kCACornerCurveContinuous;
        _coverShadow = [SGRShadowPlate new];
        _coverShadow.alpha = 0;
        [container addSubview:_coverShadow];
        [container addSubview:_cover];
    }

    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: card %@ r=%.0f, artwork %@, cover %@, screen r=%.0f", NSStringFromCGRect(card), radius,
                            NSStringFromCGRect(_barArtwork), _cover ? @"flown" : @"not flown", screenRadius());
    return self;
}

- (void)apply:(CGFloat)t {
    UIView *container = _container, *overlay = _overlay, *bar = _bar;
    if (!container || !overlay) return;
    t = MIN(1, MAX(0, t));
    _spotifyAlpha = overlay.alpha;
    _spotifyFrame = overlay.frame;

    if (_follows) {
        // Where Spotify's animation has the player now: its frame's model value is already the end.
        CALayer *drawn = overlay.layer.presentationLayer ?: overlay.layer;
        _spotifyFrame = drawn.frame;
    }
    CGRect full = container.bounds;
    // The Music app's sheet takes the screen's width in the first part of an open and grows taller after, and a close
    // slides it down at the screen's width before it draws in to the card (screen recordings at 60 fps).
    CGFloat across = ramp(0, kAcross, t);
    CGRect sheet = CGRectMake(lerp(_card.origin.x, full.origin.x, across), lerp(_card.origin.y, full.origin.y, t),
                              lerp(_card.size.width, full.size.width, across), lerp(_card.size.height, full.size.height, t));
    CGFloat radius = lerp(_cardRadius, screenRadius(), t);
    BOOL closing = _closing;
    // A close as a recreation of the Music app's player goes (Sim-Radio-SwiftUI, AppleMusicStylePlayer): while a finger
    // drags it the player only moves down, whole; let go, one smooth animation of 0.3 s takes its frame from where it is
    // to the card's, every edge together, as the player's content fades out and the card's fades in over the same
    // animation. Its own clock, not the player's place: Spotify's slide is made to end with it (tick:). A close from a tap
    // is the same animation from the whole screen.
    CGFloat c = 0;
    // Under a finger, and springing back open after it, the player only moves down, whole: the screen's width and height,
    // its foot off the screen, nothing in it shrinking or fading (Sim-Radio's offsetY). With the open's steps it narrowed
    // and faded as it was dragged low, and jumped to a half collapsed shape springing back (a screen recording).
    BOOL whole = closing && (_dragging || (_dragged && !_released));
    if (whole) {
        [self showWhole];
        return;
    }
    if (_wholeShown) [self leaveWhole];
    if (closing) {
        CGFloat dip = -1;   // where the sheet's top is along its way to the card's, past 1 below it
        if (_released) {
            double spring = releaseSpring((_frameTime > 0 ? _frameTime : CACurrentMediaTime()) - _releasedAt);
            // The size never goes past the card's; the place does, the card dipping and settling back.
            c = MIN(1, spring);
            dip = spring;
            // Never behind Spotify's player, which UIKit takes on at a pace of its own after a drag (quicker after a flick):
            // the animation is all in when the player is, so taking the sheet down shows no jump (the phone's log: the
            // slide ended 0.23 s in, before the animation's 0.3 s).
            // Going back up after all (a spring back told late): the close is let go of, and the player stays whole.
            if (t > _releaseT + 0.04) {
                _released = NO;
                [self apply:t];
                return;
            }
            if (_releaseT > 0.01) {
                CGFloat behind = MIN(1, MAX(0, (_releaseT - t) / _releaseT));
                c = MAX(c, behind);
                if (dip < behind) dip = behind;
            }
        } else {
            c = 1 - t;
        }
        CGRect from = _released ? _releaseRect : full;
        sheet = lerpRect(from, _card, c);
        if (dip >= 0) sheet.origin.y = lerp(from.origin.y, _card.origin.y, dip);
        radius = lerp(screenRadius(), _cardRadius, c);
    }
    _lastSheet = sheet;
    CGFloat scale = full.size.width > 0 ? sheet.size.width / full.size.width : 1;
    // Closing into the card the player's content shrinks with the sheet's height too, centered across it: by its width
    // alone, which hardly changes, the art stayed near its full size, cut off and to one side in the narrowing sheet (a
    // screen recording).
    CGFloat inset = 0;
    if (closing && !whole && full.size.height > 0) {
        CGFloat tall = sheet.size.height / full.size.height;
        if (tall < scale) {
            inset = (sheet.size.width - full.size.width * tall) / 2;
            scale = tall;
        }
    }
    // The player's top goes to the sheet's: a mask clips nothing above the layer's bounds, so content
    // raised above Spotify's frame would show square corners. Spotify reads back only the player's
    // height (0x109815b4c, 0x109815c28), which stays.
    CGPoint origin = _follows ? _spotifyFrame.origin : CGPointMake(_spotifyFrame.origin.x, sheet.origin.y);
    CGSize size = overlay.bounds.size;
    CGPoint middle = CGPointMake(size.width / 2, size.height / 2);
    CGPoint target = CGPointMake(sheet.origin.x + inset - origin.x, sheet.origin.y - origin.y);
    // A point q of the player lands at middle + scale * (q - middle) + shift; the top left at target.
    CGPoint shift = CGPointMake(target.x - middle.x + scale * middle.x, target.y - middle.y + scale * middle.y);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [UIView performWithoutAnimation:^{
        overlay.layer.sublayerTransform = CATransform3DIdentity;
        if (!self->_follows) overlay.frame = (CGRect){origin, self->_spotifyFrame.size};
        CGRect coverInPlayer = SGRPlayerCoverFrameIn(overlay);

        overlay.layer.sublayerTransform = CATransform3DScale(CATransform3DMakeTranslation(shift.x, shift.y, 0), scale, scale, 1);
        self->_mask.frame = CGRectMake(target.x - inset, target.y, sheet.size.width, sheet.size.height);
        self->_mask.cornerRadius = radius;
        if (!self->_follows) overlay.alpha = ramp(kHandFrom, kHandTo, t);
        // On 9.1.90 the player's own fade is Spotify's, which the spring's takeover plays where the slide is, at its very
        // end: the player's header and cover stayed over the card's stand-in in the card's last frames (a screen
        // recording). Faded through the mask instead, as the sheet nears the card, the card alone is left, as in the
        // Music app's.
        else {
            self->_mask.opacity = whole ? 1 : closing ? 1 - ramp(0, 0.6, c) : ramp(kHandFrom, kHandTo, t);
            // Spotify fades the player on a schedule of its own as well (an opacity keyframe animation beside the slide,
            // the phone's log), which went on top of the mask's and had the content gone before the sheet's color, a bare
            // colored pane near the card. Taken off, the content and the color fade together (kHandFrom).
            if ([overlay.layer animationForKey:@"opacity"]) [overlay.layer removeAnimationForKey:@"opacity"];
            if (overlay.alpha != 1) overlay.alpha = 1;
        }

        self->_sheet.frame = sheet;
        self->_sheet.layer.cornerRadius = radius;
        // Never faded: at the card's end it is the card's glass under the stand-in. Faded out over the last 15% of a
        // close, the card had no glass for a few frames and the real card's glass blinked back in after (and the
        // other way round as an open began).
        self->_sheet.alpha = 1;
        self->_fill.alpha = whole ? 1 : closing ? 1 - ramp(0, 0.6, c) : ramp(kHandFrom, kHandTo, t);

        // The card's top edge is the sheet's, and the card stays on it until the player has mostly come in, as the
        // Music app's mini player does. On 9.1.90 Spotify animates the stand-in itself, so its animations are lifted
        // and it is placed here instead, from where it was first drawn.
        CGFloat rise = sheet.origin.y - self->_card.origin.y;
        if (bar) {
            if (self->_follows) {
                if (CGRectIsEmpty(self->_barRest)) self->_barRest = (bar.layer.presentationLayer ?: bar.layer).frame;
                [bar.layer removeAllAnimations];
            }
            CGRect frame = self->_barRest;
            frame.origin.y += rise;
            frame.origin.x += sheet.origin.x - self->_card.origin.x;
            // Closing, the row stands in the middle of the sheet's top edge while the sheet is wider than the card.
            if (closing) frame.origin.x += (sheet.size.width - self->_card.size.width) / 2;
            bar.frame = frame;
            bar.alpha = whole ? 0 : closing ? ramp(0.2, 0.8, c) : 1 - ramp(kHandFrom - 0.05, kHandTo - 0.05, t);
            if (self->_row) {
                CGFloat dx = sheet.origin.x - self->_card.origin.x + (closing ? (sheet.size.width - self->_card.size.width) / 2 : 0);
                self->_row.frame = CGRectOffset(self->_rowRest, dx, rise);
                self->_row.alpha = bar.alpha;
                bar.alpha = 0;
            }
        }
        if (self->_stripPart) {
            // In a Jam the stand-in is the whole bar: its strip fades in the first quarter of an open and the last of a
            // close, so it never stands beside the growing player.
            CGFloat strip = 1 - ramp(0, 0.25, t);
            self->_stripPart.opacity = strip;
            self->_stripPane.alpha = self->_stripPaneAlpha * strip;
        }

        if (self->_cover) {
            // Worked out relative to the sheet, so the cover stays on it the whole way rather than
            // heading for where the player's cover is while that is still below the screen.
            CGRect from = CGRectOffset(self->_barArtwork, -self->_card.origin.x, -self->_card.origin.y);
            if (CGRectIsNull(coverInPlayer)) {
                self->_cover.hidden = YES;
                self->_coverShadow.hidden = YES;
            } else {
                CGRect to = CGRectMake(middle.x + scale * (coverInPlayer.origin.x - middle.x) + shift.x + origin.x,
                                       middle.y + scale * (coverInPlayer.origin.y - middle.y) + shift.y + origin.y,
                                       coverInPlayer.size.width * scale, coverInPlayer.size.height * scale);
                self->_cover.hidden = NO;
                // The first open lays the cover out mid-way, so it is hidden once it is there.
                if (!self->_coverHidden) {
                    SGRPlayerSetCoverHidden(YES);
                    self->_coverHidden = YES;
                }
                to = CGRectOffset(to, -sheet.origin.x, -sheet.origin.y);
                // The cover stays the player's, riding the sheet and growing or shrinking with it.
                CGFloat coverT = 1;
                self->_cover.frame = CGRectOffset(lerpRect(from, to, coverT), sheet.origin.x, sheet.origin.y);
                // The cover's corners are drawn under its paused shrink too.
                self->_cover.layer.cornerRadius = lerp(from.size.width / 2, SGRRadiusArtwork * SGRPlayerCoverScale() * scale, coverT);
                // Closing, it fades with the player's content as the player collapses into the card. While the track's
                // animated artwork plays there is no still cover to fly at all: told by the clip itself, not the setting,
                // since a track with none falls back to Fluid and flies its cover as usual. The clip stays loaded while the
                // player is closed, so an open knows from the start.
                BOOL animated = SGRPlayerMotionShowing();
                self->_cover.alpha = animated ? 0 : whole ? 1 : closing ? 1 - ramp(0, 0.6, c) : 1;
                // An open fades it in as a close fades it out, backwards: in over the last 60% of the way.
                if (!animated && !whole && !closing) self->_cover.alpha = 1 - ramp(0, 0.6, 1 - t);
                SGRShadowPlate *shadow = self->_coverShadow;
                shadow.hidden = NO;
                shadow.bounds = (CGRect){CGPointZero, self->_cover.bounds.size};
                shadow.center = self->_cover.center;
                shadow.cornerRadius = self->_cover.layer.cornerRadius;
                shadow.alpha = self->_cover.alpha;
            }
        }
    }];
    [CATransaction commit];
}

// Spotify's slide can end before the release's spring has settled: what is left of its dip goes onto the real card, an
// animation of the system's on the bar's own view, so the card settles as the sheet would have.
- (void)settleCard {
    if (!_closing || !_released) return;
    double from = CACurrentMediaTime() - _releasedAt;
    if (from >= kReleaseSettle) return;
    UIView *glass = SGRNowPlayingCardView(), *bar = glass.superview;
    if (!bar) return;
    CGFloat travel = CGRectGetMinY(_card) - CGRectGetMinY(_releaseRect);
    NSMutableArray<NSNumber *> *values = [NSMutableArray array];
    enum { kSteps = 40 };
    for (int i = 0; i <= kSteps; i++) {
        double at = from + (kReleaseSettle - from) * i / kSteps;
        // Only the dip below its place: the sheet was never behind the player, so the card is there already.
        [values addObject:@(MAX(0, releaseSpring(at) - 1) * travel)];
    }
    values[kSteps] = @0;
    CAKeyframeAnimation *settle = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.y"];
    settle.values = values;
    settle.duration = kReleaseSettle - from;
    settle.additive = YES;
    settle.calculationMode = kCAAnimationLinear;
    [bar.layer addAnimation:settle forKey:@"sgr.settle"];
}

// Spotify's stand-in for the card on 9.1.90 is a live replica of the real bar, which Spotify hides while the player is up,
// so it drew nothing and the sheet came down into the card empty, the card's content only showing once it was there (a
// screen recording; the phone's log had it placed and opaque). On a close the real bar's content is drawn into a picture
// before anything moves, and the picture goes with the sheet in the stand-in's place. The bar's glass does not draw into
// it; the sheet is the glass.
- (void)pictureCard:(UIView *)npb {
    UIView *container = _container;
    // The card's own view, wherever it stands: in the minimized bar's row it is moved down out of the now playing bar's
    // bounds (NowPlayingBar.x's placeInline), and a picture of those bounds came out empty, the card's content only
    // showing once the close was over (a screen recording).
    UIView *bar = SGRNowPlayingCardView().superview ?: ([npb isKindOfClass:UIView.class] ? npb : nil);
    if (!bar || !container || bar.bounds.size.width < 1) return;
    _rowRest = [bar convertRect:bar.bounds toView:container];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    BOOL hidden = bar.hidden;
    CGFloat alpha = bar.alpha;
    float opacity = bar.layer.opacity;
    bar.hidden = NO;
    bar.alpha = 1;
    bar.layer.opacity = 1;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:bar.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        for (CALayer *sub in bar.layer.sublayers) {
            CGContextSaveGState(context.CGContext);
            CGContextConcatCTM(context.CGContext, CGAffineTransformMakeTranslation(sub.frame.origin.x, sub.frame.origin.y));
            [sub renderInContext:context.CGContext];
            CGContextRestoreGState(context.CGContext);
        }
    }];
    bar.hidden = hidden;
    bar.alpha = alpha;
    bar.layer.opacity = opacity;
    [CATransaction commit];
    _row = [[UIImageView alloc] initWithImage:image];
    _row.userInteractionEnabled = NO;
    _row.alpha = 0;
    [container insertSubview:_row aboveSubview:_sheet];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: the card drawn into a picture %@ for the close", NSStringFromCGSize(image.size));
}

// Under a finger the player moves whole and nothing about it needs reshaping, so it is left to draw itself, the sheet
// moved into it so the two go as one: placed from the player's place read each frame, the sheet and the content were a
// frame behind Spotify's moves under the finger, a band of the sheet's color showing at its top (its owner).
- (void)showWhole {
    UIView *overlay = _overlay, *bar = _bar;
    if (!overlay) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [UIView performWithoutAnimation:^{
        overlay.layer.sublayerTransform = CATransform3DIdentity;
        self->_mask.frame = overlay.layer.bounds;
        self->_mask.cornerRadius = screenRadius();
        self->_mask.opacity = 1;
        if (self->_sheet.superview != overlay) [overlay insertSubview:self->_sheet atIndex:0];
        self->_sheet.frame = overlay.bounds;
        self->_sheet.layer.cornerRadius = screenRadius();
        self->_sheet.alpha = 1;
        self->_fill.alpha = 1;
        bar.alpha = 0;
        self->_row.alpha = 0;
        self->_cover.hidden = YES;
        self->_coverShadow.hidden = YES;
    }];
    [CATransaction commit];
    if (_coverHidden) {
        SGRPlayerSetCoverHidden(NO);
        _coverHidden = NO;
    }
    _wholeShown = YES;
    // Where the sheet takes over from when the finger lets go: the player's own frame, as drawn.
    CALayer *drawn = overlay.layer.presentationLayer ?: overlay.layer;
    _lastSheet = drawn.frame;
}

// The sheet back under the player in the container, for the close to reshape (apply:).
- (void)leaveWhole {
    UIView *container = _container, *overlay = _overlay, *bar = _bar;
    _wholeShown = NO;
    if (!container || !overlay) return;
    [container insertSubview:_sheet belowSubview:overlay];
    UIView *standIn = bar;
    while (standIn && standIn.superview != container) standIn = standIn.superview;
    if (standIn && [container.subviews indexOfObject:standIn] < [container.subviews indexOfObject:_sheet]) {
        [container insertSubview:_sheet belowSubview:standIn];
    }
    if (_row) [container insertSubview:_row aboveSubview:_sheet];
}

- (void)tearDown {
    _tornDown = YES;
    [_row removeFromSuperview];
    _row = nil;
    [self settleCard];
    UIView *overlay = _overlay;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    overlay.layer.sublayerTransform = CATransform3DIdentity;
    if (overlay.layer.mask == _mask) overlay.layer.mask = nil;
    UIView *masked = _masked, *pane = _stripPane;
    if (_stripMask && masked.layer.mask == _stripMask) masked.layer.mask = nil;
    pane.alpha = _stripPaneAlpha;
    _stripMask = nil;
    _stripPart = nil;
    _stripPane = nil;
    if (!_follows) overlay.alpha = _spotifyAlpha;
    if (overlay && !_follows) overlay.frame = _spotifyFrame;
    if (_follows) _bar.hidden = NO;
    // The stand-in goes back where it started, so Spotify never shows it where the sheet's edge last took it.
    if (_bar && !CGRectIsEmpty(_barRest)) _bar.frame = _barRest;
    if (!overlay.layer.backgroundColor) overlay.layer.backgroundColor = _overlayColor;
    CGColorRelease(_overlayColor);
    _overlayColor = NULL;
    [_sheet removeFromSuperview];
    [_cover removeFromSuperview];
    [_coverShadow removeFromSuperview];
    [CATransaction commit];
    if (_coverHidden) SGRPlayerSetCoverHidden(NO);
    _coverHidden = NO;
    _cover = nil;
    _coverShadow = nil;
}

@end

static char kMorphKey;

static SGRPlayerMorph *morphFor(SPTBarOverlayPresentationTransition *transition, BOOL create) {
    SGRPlayerMorph *morph = objc_getAssociatedObject(transition, &kMorphKey);
    if (morph || !create || SGRReduceMotion()) return morph;
    id<UIViewControllerContextTransitioning> context = [transition transitioningContext];
    UIView *container = context.containerView, *overlay = [transition overlayView];
    if (!container || !overlay || overlay.superview != container) return nil;
    if (container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return nil;
    morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay bar:[transition barSnapshotView] barRest:[transition barFrame]];
    if (morph) objc_setAssociatedObject(transition, &kMorphKey, morph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return morph;
}

%hook SPTBarOverlayPresentationTransition
- (void)setProgress:(double)progress {
    %orig;
    SGRPlayerMorph *morph = morphFor(self, YES);
    [morph apply:[self progress]];
    if (morph) [self tabBarSnapshotView].alpha = 0;
}

- (void)destroyTransitioningContext {
    SGRPlayerMorph *morph = morphFor(self, NO);
    if (morph) {
        [morph tearDown];
        objc_setAssociatedObject(self, &kMorphKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
}
%end

#pragma mark - 9.1.90

// 9.1.90 presents the player with MainUI_TabBarUIImpl.CompactOverlayTransition, a UIKit animator that moves the
// player up from below the screen (animateTransition:, and startInteractiveTransition: for a drag) with its own
// stand-ins (npbSnapshotView, tabBarSnapshotView; BarTransition.x). A display link reads how far up Spotify's animation
// has the player and morphs to match, so Spotify's frame, alpha and completion stay its own. It is let go once the
// transition is no longer interactive and the player has no animation left and holds still a few frames.
static const CFTimeInterval kGiveUp = 0.9;   // UIKit's presentation runs about 0.5 s

// The Music app's player opens and closes on a spring: in screen recordings at 60 fps its sheet sets off from rest, is
// half way in some 0.1 s and eases in, each of its last frames some 75% of the one before (123, 87, 67, 55, 40, 35, 25
// px), a critically damped spring of omega 16 (SwiftUI's smooth spring, which AppleMusicStylePlayer, a recreation of the
// Music app's player, uses). Spotify's CompactOverlayTransition slides the player in 0.3 s on an ease of its own (a
// UIViewPropertyAnimator: a position and an opacity CABasicAnimation, the phone's log), most of the way in its first
// frames. So a transition Spotify plays on its own is played by where the player is: the container's layer is paused and
// each frame its time is set to the moment Spotify's ease has the player where the spring has it, worked out from the
// position animation's own timing function. Spotify's slide, its fade, its stand-ins and the morph keep in step, and
// Spotify's completion comes when its time is let run on from the end. Each frame is timed by when it will show (the
// display link's target), or the steps came uneven. A drag is UIKit's to scrub, and left alone.
//
// Tried and dropped: a morph on a clock of its own (it got ahead of Spotify's slide, which had not laid the player's foot
// in, and a close outlasted it and was cut off); Spotify's time scrubbed along an ease (the ease on top of Spotify's own,
// the player up in 0.15 s); the player's place sampled along Spotify's time (a paused layer's presentation is not worked
// out again until the next frame, so every sample read the same place and the takeover gave up).
static const CFTimeInterval kWarpDuration = 0.45;
static const double kOpenOmega = 16, kCloseOmega = 15;

// A critically damped spring from 0 to 1 setting off at `kick` (of the way per second: a finger's pace when let go, 0 from
// a tap), scaled to end exactly at 1.
static CGFloat warpCurve(CGFloat u, BOOL opening, double kick, CFTimeInterval duration) {
    // The same shape over a shorter run: the stiffness scaled up by as much as the run is shorter.
    double omega = (opening ? kOpenOmega : kCloseOmega) * kWarpDuration / duration;
    double t = MIN(1, MAX(0, u)) * duration, T = duration;
    return (1 - exp(-omega * t) * (1 + (omega - kick) * t)) / (1 - exp(-omega * T) * (1 + (omega - kick) * T));
}

// A timing function's cubic, from 0 to 1 through its control points a and b, at s.
static double cubicAt(double a, double b, double s) {
    return 3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s;
}

// The s at which a cubic reaches `value`, by halving (the curve rises from 0 to 1).
static double cubicSolve(double a, double b, double value) {
    double low = 0, high = 1;
    for (int i = 0; i < 32; i++) {
        double mid = (low + high) / 2;
        if (cubicAt(a, b, mid) < value) low = mid;
        else high = mid;
    }
    return (low + high) / 2;
}

// When the last of a layer's animations ends, in `space`'s time; 0 with none. One not yet given its start (beginTime 0
// until the transaction it was added in commits) starts now.
static CFTimeInterval animationsEnd(CALayer *layer, CALayer *space) {
    CFTimeInterval end = 0, now = [space convertTime:CACurrentMediaTime() fromLayer:nil];
    for (NSString *key in layer.animationKeys) {
        CAAnimation *animation = [layer animationForKey:key];
        if (animation.repeatCount > 1) continue;
        CFTimeInterval length = animation.duration / MAX(animation.speed, 0.01);
        end = MAX(end, animation.beginTime > 0 ? [space convertTime:animation.beginTime + length fromLayer:layer] : now + length);
    }
    return end;
}

@interface SGRMorphFollower : NSObject
@property (nonatomic, strong) SGRPlayerMorph *morph;
@property (nonatomic, weak) UIView *container, *overlay;
@property (nonatomic, weak) id<UIViewControllerContextTransitioning> context;
@property (nonatomic, strong) CADisplayLink *link;
@property (nonatomic) NSInteger still;
@property (nonatomic) CGFloat lastY, appliedT;   // appliedT: the last t the morph was given, for the Jam close log
@property (nonatomic) CGRect npbFrame;   // Spotify's bar frame, for the Jam close log
@property (nonatomic) CFTimeInterval settledSince;   // when it was last driven by a finger, or began
@property (nonatomic) BOOL sped;                     // the container's layer runs at a pace of the morph's until let go
@property (nonatomic) BOOL closing, wasInteractive;
// The container's time set along the spring (warp): Spotify's slide's start and length and its ease's control points in
// the container's time, where the slide already was, the end of all the player's animations, and since when.
@property (nonatomic) BOOL warping, warped;
@property (nonatomic) CGFloat warpT;                  // where the morph is while warping
@property (nonatomic) CGFloat warpTFrom, warpTTo;     // where the morph sets off from and goes to
@property (nonatomic) double warpKick;
@property (nonatomic) CGFloat lastT;                  // where a finger had the morph, and its pace, for a let go
@property (nonatomic) CFTimeInterval lastTime;
@property (nonatomic) double pace;
@property (nonatomic) BOOL letGo;   // a finger has let go of the player
@property (nonatomic) CFTimeInterval warpBegin, warpLength, warpTo, warpStart, warpDuration;
@property (nonatomic) double warpFrom, ease1x, ease1y, ease2x, ease2y;
@end

@implementation SGRMorphFollower

// The container's clock runs on at its own pace from `local`.
static void runFrom(CALayer *layer, CFTimeInterval local) {
    CFTimeInterval now = CACurrentMediaTime();
    layer.speed = 1;
    layer.beginTime = layer.superlayer ? [layer.superlayer convertTime:now fromLayer:nil] : now;
    layer.timeOffset = local;
}

// Pauses the container where its animations are, to be played along the spring (stepWarp:). Called as Spotify adds its
// animations, before they are given their start: paused, they start at the container's paused time.
- (void)warpFrom:(CGFloat)from pace:(double)pace {
    CALayer *layer = self.container.layer, *player = self.overlay.layer;
    CFTimeInterval local = [layer convertTime:CACurrentMediaTime() fromLayer:nil], end = animationsEnd(player, layer);
    CAAnimation *slide = [player animationForKey:@"position"];
    if (![slide isKindOfClass:CABasicAnimation.class] || end <= local + 0.05) {
        static NSUInteger logged;
        if (logged++ < 3) SGLog(@"player morph: no slide to take over (%lu animations), Spotify's own plays", (unsigned long)player.animationKeys.count);
        return;
    }
    CFTimeInterval length = slide.duration / MAX(slide.speed, 0.01);
    CFTimeInterval begin = slide.beginTime > 0 ? [layer convertTime:slide.beginTime fromLayer:player] : local;
    float c1[2] = {0, 0}, c2[2] = {1, 1};
    if (slide.timingFunction) {
        [slide.timingFunction getControlPointAtIndex:1 values:c1];
        [slide.timingFunction getControlPointAtIndex:2 values:c2];
    }
    self.ease1x = c1[0];
    self.ease1y = c1[1];
    self.ease2x = c2[0];
    self.ease2y = c2[1];
    double done = MIN(1, MAX(0, (local - begin) / MAX(length, 0.01)));
    self.warpFrom = cubicAt(self.ease1y, self.ease2y, cubicSolve(self.ease1x, self.ease2x, done));
    self.warpBegin = begin;
    self.warpLength = length;
    self.warpTo = MAX(end, begin + length);
    self.warpStart = CACurrentMediaTime();
    // No longer than what is left of Spotify's slide: UIKit ends the transition on the wall clock however its time is
    // set, and a spring that ran past it had the page under the player taken away before the sheet covered it (a black
    // band at the top of an open) and the card's real glass come back before the sheet had drawn in (a blink at a close).
    self.warpDuration = MIN(kWarpDuration, MAX(0.12, begin + length - local));
    // Where Spotify's slide ends, its model value already there: the screen, or the bar (a close, or a drag let go short).
    CGFloat rest = self.morph.restY > 0 ? self.morph.restY : self.container.bounds.size.height;
    self.warpTTo = player.frame.origin.y > rest / 2 ? 0 : 1;
    // Let go by a finger (from NAN), the morph sets off from where Spotify's slide is: the player's place read back
    // during the drag did not move (the phone's log: the morph from 1.00 with the slide 36% and 80% done).
    if (isnan(from)) from = self.warpTTo < 0.5 ? 1 - self.warpFrom : self.warpFrom;
    self.warpTFrom = from;
    self.warpKick = fabs(self.warpTTo - from) > 0.01 ? MIN(40, MAX(0, pace / (self.warpTTo - from))) : 0;
    self.warpT = from;
    layer.speed = 0;
    layer.timeOffset = local;
    self.warping = self.warped = YES;
    static NSUInteger logged;
    if (logged++ < 6) SGLog(@"player morph: plays Spotify's %.2f s slide (ease %.2f %.2f %.2f %.2f, %.0f%% done) on a spring of %.2f s, the morph %.2f to %.0f kicked %.1f",
                            length, c1[0], c1[1], c2[0], c2[1], self.warpFrom * 100, self.warpDuration, from, self.warpTTo, self.warpKick);
}

- (void)stepWarp:(CFTimeInterval)now {
    if (!self.warping) return;
    CALayer *layer = self.container.layer;
    CGFloat u = (now - self.warpStart) / self.warpDuration;
    if (u >= 1) {
        // From the end on, so the animations finish and Spotify's completion comes.
        runFrom(layer, self.warpTo);
        self.warping = NO;
        return;
    }
    // How far along its slide the spring has the player, and the moment Spotify's ease has it there.
    double spring = warpCurve(u, self.warpTTo > 0.5, self.warpKick, self.warpDuration);
    double along = self.warpFrom + (1 - self.warpFrom) * spring;
    double x = cubicAt(self.ease1x, self.ease2x, cubicSolve(self.ease1y, self.ease2y, along));
    layer.timeOffset = self.warpBegin + self.warpLength * x;
    // The morph goes with it, worked out rather than read back: a paused layer's place is drawn a frame late.
    self.warpT = self.warpTFrom + (self.warpTTo - self.warpTFrom) * spring;
}

- (void)tick:(CADisplayLink *)link {
    UIView *container = self.container, *overlay = self.overlay;
    if (!container || !overlay || !overlay.window) {
        [self finish];
        return;
    }
    BOOL interactive = self.context.isInteractive;
    // Let go: UIKit plays the rest of Spotify's slide on its own, faster for a close, and the morph follows where it has the
    // player. Taken over as a tap's slide is, the player showed the whole screen as the finger lifted: UIKit's slide after
    // a drag is not the one it starts with (screen recordings and the phone's log). On the frame the finger lifts UIKit
    // reports the player where its slide ends, so that frame keeps the finger's place.
    BOOL letGo = !interactive && self.wasInteractive && !self.letGo;
    self.morph.dragging = interactive;
    self.morph.frameTime = link.targetTimestamp;
    if (interactive) self.morph.dragged = YES;
    if (letGo) {
        self.letGo = YES;
        // Towards the card (Spotify's slide's model value is already its end), one animation of the morph's own takes the
        // sheet there from where it is. One springing back open is followed.
        CGFloat rest = self.morph.restY > 0 ? self.morph.restY : container.bounds.size.height;
        // Which way UIKit takes it the transition itself says once the finger lifts: cancelled, it springs back open. Told
        // by where Spotify's slide ends instead, which is not always set by then, a drag let go short collapsed towards
        // the card for a frame and snapped back open (a screen recording).
        BOOL towardsCard = !self.context.transitionWasCancelled && overlay.layer.frame.origin.y > rest / 2;
        // Spotify's slide is left at UIKit's pace: its clock is held while a finger drags, so what is left of it cannot be
        // read to set it to the animation's (the phone's log read the whole 0.3 s every time); the animation keeps up with it
        // instead (apply:). It sets off from where the finger left the sheet.
        if (self.closing && towardsCard) {
            self.morph.releaseRect = self.morph.lastSheet;
            self.morph.releaseT = self.lastTime > 0 ? self.lastT : 1;
            self.morph.releaseDuration = kReleaseSpring;
            self.morph.releasedAt = link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime();
            self.morph.released = YES;
            SGLog(@"player morph: let go at %.3f, the sheet from %@", self.morph.releaseT, NSStringFromCGRect(self.morph.releaseRect));
        }
    }
    // Timed by when this frame will show, so the steps come even.
    BOOL warping = self.warping;
    [self stepWarp:link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime()];
    CALayer *drawn = overlay.layer.presentationLayer ?: overlay.layer;
    CGFloat y = drawn.frame.origin.y, rest = self.morph.restY > 0 ? self.morph.restY : container.bounds.size.height;
    // A close is measured to where Spotify's slide brings the player to rest (its model value is already there), not the
    // card's top: Spotify stops it 12 pt above (805 against 817), so the sheet stopped short of the card, 61 pt high to the
    // card's 48, and jumped to it when taken down (the phone's log).
    CGFloat end = overlay.layer.frame.origin.y;
    // The same in the minimized bar's row, where the card stands lower than where Spotify stops the player.
    if (self.closing && end > 1 && end < container.bounds.size.height) rest = end;
    // After a finger lets go the morph follows where UIKit draws the player, but what it reads is this frame's place and
    // what it sets shows on the next: the sheet trailed the player by a frame all the way (the phone's log). Led by one
    // frame's movement, it keeps with it. Not while a finger drags (its steps are uneven), nor on the frame it lifts.
    CGFloat ahead = y;
    if (!interactive && self.letGo && !letGo && self.lastY < CGFLOAT_MAX / 2 && fabs(y - self.lastY) < 120) ahead = y + (y - self.lastY);
    CGFloat followed = rest > 0 ? MIN(1, MAX(0, 1 - ahead / rest)) : 1;
    CGFloat applied = warping ? self.warpT : letGo && self.lastTime > 0 ? self.lastT : followed;
    self.appliedT = applied;
    [self.morph apply:applied];
    CFTimeInterval at = link.targetTimestamp > 0 ? link.targetTimestamp : CACurrentMediaTime();
    if (interactive) {
        self.lastT = followed;
        self.lastTime = at;
    }
    self.wasInteractive = interactive;
    BOOL moving = overlay.layer.animationKeys.count > 0 || fabs(y - self.lastY) > 0.5 || interactive || self.warping;
    self.lastY = y;
    self.still = moving ? 0 : self.still + 1;
    // Let go once still, or kGiveUp after a finger last drove it whatever the layer holds: a mask and a transform left
    // on the player would keep its glass buttons from drawing.
    CFTimeInterval now = CACurrentMediaTime();
    if (interactive || !self.settledSince) self.settledSince = now;
    if (self.still >= 3 || now - self.settledSince > kGiveUp + (self.warped ? kWarpDuration : 0)) [self finish];
}
- (void)finish {
    if (!self.link) return;
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: let go after %.2f s, %@", CACurrentMediaTime() - self.settledSince, self.still >= 3 ? @"settled" : @"given up");
    [self.link invalidate];
    self.link = nil;
    CALayer *layer = self.container.layer;
    if (self.warping) runFrom(layer, self.warpTo);
    self.warping = NO;
    if (self.sped || self.warped) {
        layer.speed = 1;
        layer.beginTime = 0;
        layer.timeOffset = 0;
    }
    // Whether a close in a Jam ends at t 0: Spotify parks the player at its bar frame's top, the strip's, and restY is the card's.
    if (self.closing && self.morph.masksStrip) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            SGLog(@"player morph: Jam close ended, npbFrame %@, card %@, restY %.1f, last t %.3f", NSStringFromCGRect(self.npbFrame),
                  NSStringFromCGRect(self.morph.card), self.morph.restY, self.appliedT);
        });
    }
    [self.morph tearDown];
    self.morph = nil;
}
@end

static id ivarOf(id object, const char *name) {
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    return ivar ? object_getIvar(object, ivar) : nil;
}

static char kFollowerKey;

// A CGRect a Swift object keeps, read at its ivar's offset; CGRectNull without that ivar, or when it cannot be a CGRect
// (an Objective-C type other than one, or too little room in the object), and the class's ivars are then logged once.
static CGRect rectIvarOf(id object, const char *name) {
    Class cls = object_getClass(object);
    Ivar ivar = class_getInstanceVariable(cls, name);
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    BOOL fits = ivar && ivar_getOffset(ivar) >= 0 && (size_t)ivar_getOffset(ivar) + sizeof(CGRect) <= class_getInstanceSize(cls);
    if (fits && (!type || !*type || strncmp(type, "{CGRect", 7) == 0)) return *(CGRect *)((char *)(__bridge void *)object + ivar_getOffset(ivar));
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        unsigned int count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        NSMutableString *names = [NSMutableString string];
        for (unsigned int i = 0; i < count; i++) [names appendFormat:@" %s", ivar_getName(ivars[i])];
        free(ivars);
        SGLog(@"player morph: %@ has no CGRect %s, its ivars:%@", cls, name, names);
    });
    return CGRectNull;
}

static void followTransition(id transition, id<UIViewControllerContextTransitioning> context) {
    if (SGRReduceMotion() || !context) return;
    UIView *container = context.containerView;
    if (container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular) return;
    UIViewController *to = [context viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *overlay = to.isBeingPresented ? [context viewForKey:UITransitionContextToViewKey] : [context viewForKey:UITransitionContextFromViewKey];
    if (!overlay || overlay.superview != container) return;
    SGRMorphFollower *old = objc_getAssociatedObject(transition, &kFollowerKey);
    [old finish];
    // Where the card's stand-in starts is where the real now playing bar stands. Read from the stand-in, it was where
    // Spotify's animation sends it, already set at the screen's top, and the stand-in showed there for an open's first
    // frame, a second card over the status bar (its owner's screenshot).
    UIView *npbView = ivarOf(transition, "npbView");
    CGRect barRest = [npbView isKindOfClass:UIView.class] && npbView.window ? [npbView convertRect:npbView.bounds toView:container] : CGRectZero;
    SGRPlayerMorph *morph = [[SGRPlayerMorph alloc] initWithContainer:container overlay:overlay bar:ivarOf(transition, "npbSnapshotView") barRest:barRest];
    if (!morph) return;
    [morph followFrom:npbView];
    morph.closing = !to.isBeingPresented;
    if (morph.closing) [morph pictureCard:npbView];
    ((UIView *)ivarOf(transition, "tabBarSnapshotView")).alpha = 0;
    SGRMorphFollower *follower = [SGRMorphFollower new];
    follower.morph = morph;
    follower.container = container;
    follower.overlay = overlay;
    follower.context = context;
    follower.lastY = CGFLOAT_MAX;
    if (SGRNowPlayingStripHeight() > 0) follower.npbFrame = rectIvarOf(transition, "npbFrame");
    follower.closing = !to.isBeingPresented;
    follower.wasInteractive = context.isInteractive;
    // One Spotify plays on its own, opened or closed by a tap, is played along the spring (stepWarp:); one dragged by a
    // finger is UIKit's, and a close let go runs faster.
    if (!context.isInteractive) [follower warpFrom:follower.closing ? 1 : 0 pace:0];
    follower.link = [CADisplayLink displayLinkWithTarget:follower selector:@selector(tick:)];
    follower.link.preferredFrameRateRange = CAFrameRateRangeMake(80, 120, 120);
    [follower.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    objc_setAssociatedObject(transition, &kFollowerKey, follower, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [follower tick:follower.link];
    static NSUInteger logged;
    if (logged++ < 3) SGLog(@"player morph: follows CompactOverlayTransition (%@)", to.isBeingPresented ? @"open" : @"close");
}

%hook _TtC19MainUI_TabBarUIImpl24CompactOverlayTransition
- (void)animateTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    followTransition(self, context);
}
- (void)startInteractiveTransition:(id<UIViewControllerContextTransitioning>)context {
    %orig;
    followTransition(self, context);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    SGRequireClasses(@[@"SPTBarOverlayPresentationTransition"]);
}
