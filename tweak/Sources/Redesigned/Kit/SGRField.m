#import "Core/SGCore.h"
#import "SGRField.h"
#import "SGRMotionBudget.h"
#import "SGRFlow.h"
#import "SGRFluid.h"
#import "SGRBridges.h"
#import "SGRPalette.h"
#import "SGRTokens.h"

NSNotificationName const SGRFieldColorDidChangeNotification = @"spotifyglass.redesign.fieldColorDidChange";
NSNotificationName const SGRFieldPaletteDidChangeNotification = @"spotifyglass.redesign.fieldPaletteDidChange";

static const UIEdgeInsets kPageBleed = {600, 0, 600, 0};

SGRArtworkField *SGRPageFieldOn(UIView *view, const void *key) {
    for (UIView *v = view; v; v = v.superview) {
        SGRArtworkField *field = objc_getAssociatedObject(v, key);
        if (field) return field;
    }
    return nil;
}

SGRArtworkField *SGRPageFieldIn(UIView *page, const void *key, NSString *pageName) {
    SGRArtworkField *field = objc_getAssociatedObject(page, key);
    if (!field) {
        field = [[SGRArtworkField alloc] initWithFrame:page.bounds];
        field.bleed = kPageBleed;
        field.mainColor = YES;
        field.accentPage = page;
        objc_setAssociatedObject(page, key, field, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGLog(@"redesign %@: field on the page %.0fx%.0f", pageName, page.bounds.size.width, page.bounds.size.height);
    }
    if (field.superview != page) [page insertSubview:field atIndex:0];
    else if (page.subviews.firstObject != field) [page sendSubviewToBack:field];
    if (!CGRectEqualToRect(field.frame, page.bounds)) field.frame = page.bounds;
    return field;
}

static const CGFloat kFallbackHeight = 874;   // a window-less field sizes for an iPhone 17 Pro

// Where the color starts fading to black and where it is black, as shares of the window's height:
// the redesign is AMOLED throughout (SGRAmoled.x).
static const CGFloat kBlackFrom = 0.55, kBlackTo = 1;

static CGFloat windowHeight(UIView *view) {
    CGFloat height = view.window.bounds.size.height;
    return height > 0 ? height : kFallbackHeight;
}

// The field paints on sublayers of its own rather than on the view's layer: a repaint hook only clears
// the paint of a view's own layer, so the neutral color cannot be taken for Spotify's base surface.
static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"contents": off, @"backgroundColor": off, @"hidden": off, @"locations": off};
    });
    return none;
}

const NSTimeInterval SGRFieldHoldLimit = 0.5;

// `color` given to `layer` as its paint, and the paint as the layer took it: the redesign's paint rules (SGRAmoled.x)
// apply as it is set, so this is what the layer shows rather than what it was asked for.
static UIColor *paint(CALayer *layer, UIColor *color) {
    layer.backgroundColor = color.CGColor;
    return [UIColor colorWithCGColor:layer.backgroundColor];
}

UIColor *SGRFieldShownColor(UIColor *color) {
    return color ? paint([CALayer layer], color) : nil;
}

// The veil over a held page: black, the redesign's field before a color arrives (SGRAmoled.x), painted on a
// sublayer for the reason the field is, so the repaint hook does not take it for Spotify's base surface.
@interface SGRFieldVeil : UIView
@end

@implementation SGRFieldVeil {
    CALayer *_paint;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.accessibilityElementsHidden = YES;
    _paint = [CALayer layer];
    _paint.actions = noActions();
    _paint.backgroundColor = UIColor.blackColor.CGColor;
    [self.layer addSublayer:_paint];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _paint.frame = self.bounds;
}

@end

@implementation SGRArtworkField {
    SGRFieldVeil *_veil;
    CFTimeInterval _heldSince;
    BOOL _shown;   // the page has been shown once, and is never held again
    CALayer *_solid;
    CAGradientLayer *_black;
    CALayer *_backdrop;
    SGRFlowLayer *_flow;
    SGRFluidLayer *_fluidLayer;
    BOOL _watching, _deferredPalette;
    id _activeObserver;
    UIColor *_color;          // the color asked for
    UIColor *_shownColor;     // and the one _solid paints for it (-fieldColor)
    UIColor *_paletteColor;   // the last palette's field color, shown again when the override goes
    BOOL _paletteCurrent;     // _paletteColor is the one of _image
    UIImage *_image;
    NSString *_identity;
    NSUInteger _generation;
    BOOL _read, _clipCovered;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = NO;
    self.accessibilityElementsHidden = YES;
    _color = SGRNeutralField();

    _solid = [CALayer layer];
    _solid.actions = noActions();
    _shownColor = paint(_solid, _color);
    [self.layer addSublayer:_solid];

    _black = [CAGradientLayer layer];
    _black.actions = noActions();
    _black.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)UIColor.blackColor.CGColor];
    [self.layer addSublayer:_black];

    _backdrop = [CALayer layer];
    _backdrop.actions = noActions();
    _backdrop.contentsGravity = kCAGravityResize;
    _backdrop.hidden = YES;
    [self.layer addSublayer:_backdrop];
    __weak SGRArtworkField *weakSelf = self;
    _activeObserver = [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification
        object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf becameActive]; });
        }];
    return self;
}

- (UIColor *)fieldColor {
    return _shownColor;
}

- (CGFloat)backdropHeightNow {
    return _backdropHeight > 0 ? _backdropHeight : windowHeight(self);
}

- (void)setBleed:(UIEdgeInsets)bleed {
    _bleed = bleed;
    [self setNeedsLayout];
}

- (void)setBackdropHeight:(CGFloat)height {
    _backdropHeight = height;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    UIEdgeInsets bleed = _bleed;
    CGRect painted = CGRectMake(-bleed.left, -bleed.top, bounds.size.width + bleed.left + bleed.right, bounds.size.height + bleed.top + bleed.bottom);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _solid.frame = painted;
    CGFloat height = windowHeight(self), total = MAX(1, painted.size.height);
    CGFloat from = height * kBlackFrom + bleed.top;
    CGFloat to = MAX(from + 1, height * kBlackTo + bleed.top);
    _black.frame = painted;
    _black.locations = @[@(MIN(1, from / total)), @(MIN(1, to / total))];
    _backdrop.frame = CGRectMake(0, 0, bounds.size.width, [self backdropHeightNow]);
    _flow.frame = CGRectMake(0, 0, bounds.size.width, [self backdropHeightNow]);
    _fluidLayer.frame = painted;
    // The screen's part of it, so the copies turn about it and the shade ends at the screen's foot.
    _fluidLayer.visibleRect = CGRectMake(bleed.left, bleed.top, bounds.size.width, height);
    [CATransaction commit];
}

#pragma mark - the moving field

- (void)setFluid:(BOOL)fluid {
    if (fluid == _fluid) return;
    _fluid = fluid;
    if (fluid && !_fluidLayer) {
        _fluidLayer = [SGRFluidLayer layer];
        _fluidLayer.hidden = YES;
        [self.layer insertSublayer:_fluidLayer above:_solid];
    }
    // Turning off Colours also updates motion, which may uncover a retained Fluid layer.
    if (fluid) {
        if (_image) [_fluidLayer setArtwork:_image animated:NO];
        self.flows = NO;
    }
    _black.hidden = fluid || _flows;
    if (fluid) _backdrop.hidden = YES;
    if (!fluid && !_flows) [self readPaletteAnimated:NO];
    [self watch];
    [self updateMotion];
    [self setNeedsLayout];
}

- (void)setFlows:(BOOL)flows {
    if (flows == _flows) return;
    _flows = flows;
    if (flows) self.fluid = NO;
    if (flows && !_flow) {
        _flow = [SGRFlowLayer layer];
        _flow.hidden = YES;
        [self.layer insertSublayer:_flow above:_solid];
    }
    // The moving field is the whole picture: no still backdrop over it, no fade to black under it.
    _black.hidden = flows;
    if (flows) _backdrop.hidden = YES;
    else _flow.hidden = YES;
    [self readPaletteAnimated:NO];
    [self watch];
    [self updateMotion];
    [self setNeedsLayout];
}

- (void)setMotionHeld:(BOOL)held {
    if (held == _motionHeld) return;
    _motionHeld = held;
    [self updateMotion];
}

- (void)setOffscreen:(BOOL)offscreen {
    if (_offscreen == offscreen) return;
    _offscreen = offscreen;
    [self updateMotion];
}

- (void)setCovered:(BOOL)covered {
    if (covered == _clipCovered) return;
    _clipCovered = covered;
    [self updateCoverage];
}

- (BOOL)covered {
    return _clipCovered || _backdropCovered;
}

- (void)setBackdropCovered:(BOOL)covered {
    if (covered == _backdropCovered) return;
    _backdropCovered = covered;
    [self updateCoverage];
}

- (void)updateCoverage {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self updateMotion];
    [CATransaction commit];
}

- (void)watch {
    if (_watching || (!_flows && !_fluid)) return;
    _watching = YES;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[UIApplicationWillResignActiveNotification,
                                      NSProcessInfoPowerStateDidChangeNotification, NSProcessInfoThermalStateDidChangeNotification,
                                      UIAccessibilityReduceMotionStatusDidChangeNotification]) {
        [center addObserver:self selector:@selector(updateMotionSoon) name:name object:nil];
    }
    SGRObservePlayerTransition(self, ^(id owner) { [owner updateMotion]; });
}

- (void)becameActive {
    if (_deferredPalette && SGRArtworkAppIsActive()) [self readPaletteAnimated:NO];
    [self updateMotion];
}

- (void)dealloc {
    if (_activeObserver) [NSNotificationCenter.defaultCenter removeObserver:_activeObserver];
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

// Power and thermal changes can be reported off the main thread.
- (void)updateMotionSoon {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateMotion]; });
}

- (void)updateMotion {
    if (!_flow && !_fluidLayer) return;
    // Keep the last frame for the switcher snapshot.
    BOOL front = SGRArtworkAppIsActive();
    BOOL visible = self.window && !self.hidden && !_offscreen;
    BOOL covered = self.covered;
    _fluidLayer.hidden = !_fluid || covered || !visible;
    BOOL may = visible && front && !SGRPlayerIsTransitioning() && !SGRReduceMotion()
            && !SGRMotionHeldForPowerOrHeat() && !_motionHeld;
    _fluidLayer.moving = may && _fluid && !covered;
    BOOL moving = may && _flows && !covered && !_flow.hidden;
    if (!_flow || moving == _flow.moving) return;
    _flow.moving = moving;
    static NSUInteger logged;
    if (logged++ < 6) SGLog(@"redesign kit: moving field %@", moving ? @"moves" : @"holds still");
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMotion];
}

- (void)setHidden:(BOOL)hidden {
    [super setHidden:hidden];
    [self updateMotion];
}

- (void)applyColor:(UIColor *)color animated:(BOOL)animated {
    if (!color || CGColorEqualToColor(color.CGColor, _color.CGColor)) return;
    CALayer *shown = _solid.presentationLayer ?: _solid;
    id from = (__bridge id)shown.backgroundColor;
    _color = color;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _shownColor = paint(_solid, color);
    [CATransaction commit];
    if (animated && from) {
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        fade.fromValue = from;
        fade.toValue = (__bridge id)_shownColor.CGColor;
        fade.duration = SGRCrossfade;
        fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [_solid addAnimation:fade forKey:@"backgroundColor"];
    }
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFieldColorDidChangeNotification object:self userInfo:@{@"color": color}];
}

- (void)setProvisionalColor:(UIColor *)color {
    if (_read || !color) return;
    [self applyColor:SGRFieldColorFor(color) animated:self.window != nil];
}

- (void)setArtwork:(UIImage *)image identity:(NSString *)identity animated:(BOOL)animated {
    if (!image || image == _image || (identity && [identity isEqualToString:_identity])) return;
    _image = image;
    _identity = [identity copy];
    _paletteCurrent = NO;
    if (_fluid) [_fluidLayer setArtwork:image animated:animated && !_fluidLayer.hidden];
    [self readPaletteAnimated:animated];
}

- (void)readPaletteAnimated:(BOOL)animated {
    NSUInteger generation = ++_generation;
    if (!_image) return;
    _deferredPalette = !SGRArtworkAppIsActive();
    if (_deferredPalette) return;
    SGRPaletteRequest request = {.flow = _flows, .mainColor = _mainColor};
    if (_showsBackdrop && !_flows && !_fluid) request.backdropSize = CGSizeMake(self.bounds.size.width > 0 ? self.bounds.size.width : 402, [self backdropHeightNow]);
    __weak SGRArtworkField *weakSelf = self;
    [SGRPalette paletteForImage:_image request:request completion:^(SGRPalette *palette) {
        SGRArtworkField *field = weakSelf;
        if (!field || !palette || generation != field->_generation) return;
        [field applyPalette:palette animated:animated && field.window != nil];
    }];
}

#pragma mark - holding a page

- (void)holdPage:(UIView *)page {
    if (_shown || _read || !page) return;
    if (!_veil) {
        _veil = [[SGRFieldVeil alloc] initWithFrame:page.bounds];
        _heldSince = CACurrentMediaTime();
        __weak SGRArtworkField *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SGRFieldHoldLimit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf sgr_showPage:@"the artwork took too long"];
        });
    }
    if (!CGRectEqualToRect(_veil.frame, page.bounds)) _veil.frame = page.bounds;
    // On top of everything the page holds but its pinned buttons, which bring themselves to the front on the
    // header's passes: ⋯, and download right under it carrying the glass capsule the two share (SGRActionRow.m).
    // Under both, not between them, or the veil would cover ⋯'s half of the capsule and leave ⋯ a bare glyph for
    // the hold. Moved only when out of place: a move lays the page out again. The class is looked up by name so a
    // screen that has a field and no action row (the player) does not have to link SGRActionRow.m.
    static Class pinned;
    if (!pinned) pinned = NSClassFromString(@"SGRMirrorButton");
    NSArray<UIView *> *subviews = page.subviews;
    NSUInteger lowest = subviews.count;
    while (pinned && lowest > 0 && [subviews[lowest - 1] isKindOfClass:pinned]) lowest--;
    if (lowest == subviews.count) {
        if (subviews.lastObject != _veil) [page addSubview:_veil];
    } else if (lowest == 0 || subviews[lowest - 1] != _veil) {
        [page insertSubview:_veil belowSubview:subviews[lowest]];
    }
}

- (void)showPage {
    [self sgr_showPage:@"it has no artwork"];
}

- (void)sgr_showPage:(NSString *)why {
    if (_shown) return;
    _shown = YES;
    SGRFieldVeil *veil = _veil;
    _veil = nil;
    if (!veil) return;
    static NSUInteger logged;
    if (logged++ < 4) SGLog(@"redesign kit: page shown whole after %.0f ms, %@", (CACurrentMediaTime() - _heldSince) * 1000, why);
    SGRAnimate(SGRMotionFade, ^{ veil.alpha = 0; }, ^(BOOL finished) { [veil removeFromSuperview]; });
}

- (void)applyPalette:(SGRPalette *)palette animated:(BOOL)animated {
    _read = YES;
    // Under the veil the color goes in at once, and the page fades in with it.
    if (_veil) animated = NO;
    if (_flows && palette.flowColors) {
        [_flow setColors:palette.flowColors animated:animated && !_flow.hidden];
        _flow.hidden = NO;
        [self updateMotion];
        // Past the moving field's edges (the pull that dismisses the player) the color under it goes on.
        [self applyColor:_flow.baseColor animated:animated];
        return;
    }
    if (_showsBackdrop && !_flows && !_fluid && palette.backdrop) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (animated) {
            CATransition *fade = [CATransition animation];
            fade.type = kCATransitionFade;
            fade.duration = SGRCrossfade;
            [_backdrop addAnimation:fade forKey:@"contents"];
        }
        _backdrop.contents = (__bridge id)palette.backdrop.CGImage;
        _backdrop.hidden = NO;
        [CATransaction commit];
    }
    _paletteColor = palette.fieldColor;
    _paletteCurrent = YES;
    if (!_overrideColor) [self applyColor:palette.fieldColor animated:animated];
    [self sgr_showPage:@"its artwork was read"];
    [NSNotificationCenter.defaultCenter postNotificationName:SGRFieldPaletteDidChangeNotification object:self];
}

- (UIColor *)paletteColor {
    return _paletteCurrent ? _paletteColor : nil;
}

- (void)setOverrideColor:(UIColor *)color {
    if (color == _overrideColor || [color isEqual:_overrideColor]) return;
    _overrideColor = [color copy];
    BOOL animated = self.window != nil && !_veil;
    if (color) {
        _read = YES;
        [self applyColor:color animated:animated];
        [self sgr_showPage:@"its owner gave it its color"];
    } else if (_paletteColor) {
        [self applyColor:_paletteColor animated:animated];
    }
}

@end
