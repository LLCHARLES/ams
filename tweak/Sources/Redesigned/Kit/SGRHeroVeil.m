// The scroll veil over a page's hero (SGRHeroVeil.h).
#import "Core/SGCore.h"
#import "SGRHeroVeil.h"

@interface CAFilter : NSObject
+ (instancetype)filterWithType:(NSString *)type;
@end

// The blur: none up to kBlurFrom points of d, kBlurMost points of radius from kBlurTo, drawn in kBlurStep steps.
static const CGFloat kBlurFrom = 60, kBlurTo = 320, kBlurMost = 24, kBlurStep = 0.25;
// The dim: none up to kDimFrom points of d, kDimMost alpha from kDimTo; an alpha under kDimLeast is not drawn.
static const CGFloat kDimFrom = 80, kDimTo = 400, kDimMost = 0.45, kDimLeast = 0.002;
// A pull shorter than kPullLeast, or a hero shorter than kHeroLeast, does not zoom.
static const CGFloat kPullLeast = 0.5, kHeroLeast = 1;
// How much of the hero's displacement the art keeps back, and how much of the scroll beyond it the art goes on with.
static const CGFloat kKeptBack = 0.25, kGoesOn = 0.75;
// A scroll within this of the top is the page at rest, where the hero's resting place is taken.
static const CGFloat kAtRest = 0.5;
// Over the art and the scrim (1), under the dissolve (2): the zPositions the heroes give those.
static const CGFloat kDimZ = 1.5;

static NSString *const kRadiusPath = @"filters.gaussianBlur.inputRadius";
static void *kOffsetContext = &kOffsetContext;

BOOL SGRHeroScrollVeilOn(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGFlag(SGRKeyHeroScrollVeil, NO); });
    return on;
}

CGFloat SGRHeroVeilRamp(CGFloat x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return x * x * x * (x * (6 * x - 15) + 10);
}

CGFloat SGRHeroVeilBlurRadius(CGFloat distance) {
    CGFloat radius = round(kBlurMost * SGRHeroVeilRamp((distance - kBlurFrom) / (kBlurTo - kBlurFrom)) / kBlurStep) * kBlurStep;
    return radius < kBlurStep ? 0 : radius;
}

CGFloat SGRHeroVeilDimAlpha(CGFloat distance) {
    CGFloat alpha = kDimMost * SGRHeroVeilRamp((distance - kDimFrom) / (kDimTo - kDimFrom));
    return alpha < kDimLeast ? 0 : alpha;
}

SGRHeroArtPlace SGRHeroVeilArtPlace(CGFloat pull, CGFloat height, CGFloat displacement, CGFloat beyond) {
    SGRHeroArtPlace place = {1, kKeptBack * displacement - kGoesOn * beyond};
    if (pull >= kPullLeast && height >= kHeroLeast) {
        place.scale = (height + pull) / height;
        place.shift -= pull / 2;
    }
    return place;
}

UIScrollView *SGRHeroVeilScrollAbove(UIView *view) {
    for (UIView *v = view.superview; v; v = v.superview) {
        if ([v isKindOfClass:UIScrollView.class]) return (UIScrollView *)v;
    }
    return nil;
}

// Every radius the blur draws, kBlurStep apart up to kBlurMost, made once: a step of the scroll allocates nothing.
static NSNumber *radiusNumber(CGFloat radius) {
    static NSArray<NSNumber *> *radii;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSInteger count = lround(kBlurMost / kBlurStep) + 1;
        NSMutableArray<NSNumber *> *all = [NSMutableArray arrayWithCapacity:count];
        for (NSInteger i = 0; i < count; i++) [all addObject:@(i * kBlurStep)];
        radii = all;
    });
    return radii[(NSUInteger)MIN((NSInteger)radii.count - 1, MAX(0, lround(radius / kBlurStep)))];
}

@implementation SGRHeroVeil {
    __weak UIView *_hero;
    __weak UIScrollView *_scroll;
    CALayer *_dim;
    CAFilter *_blur;            // nil where the filter does not exist
    __weak CALayer *_blurred;   // the layer the blur is on, nil while there is none
    // Where the hero's top was in the window the last time the page was at rest.
    CGFloat _restTop;
    BOOL _rested;
    // What is drawn.
    CGFloat _radius, _alpha;
    SGRHeroArtPlace _place;
}

- (instancetype)initWithHero:(UIView *)hero {
    if (!(self = [super init])) return nil;
    _hero = hero;
    _place = (SGRHeroArtPlace){1, 0};
    _dim = [CALayer layer];
    _dim.name = @"SGRHeroVeil.dim";
    _dim.zPosition = kDimZ;
    _dim.opacity = 0;
    _dim.hidden = YES;
    [hero.layer addSublayer:_dim];
    _blur = [NSClassFromString(@"CAFilter") filterWithType:@"gaussianBlur"];
    // The picture's edges blur against themselves, not against the clear around the hero.
    [_blur setValue:@YES forKey:@"inputNormalizeEdges"];
    return self;
}

- (void)dealloc {
    [_scroll removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
}

- (void)setArt:(NSArray<CALayer *> *)art {
    if ([_art isEqualToArray:art]) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in _art) {
        if (![art containsObject:layer]) layer.affineTransform = CGAffineTransformIdentity;
    }
    _art = [art copy];
    [self artDidLayOut];
    [CATransaction commit];
}

- (UIView *)sgr_surface {
    return _surface ?: _hero;
}

- (void)setSurface:(UIView *)surface {
    _surface = surface;
    CALayer *layer = [self sgr_surface].layer;
    if (!layer || _dim.superlayer == layer) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGFloat radius = _radius;
    _blurred.filters = nil;
    _blurred = nil;
    _radius = 0;
    [layer addSublayer:_dim];
    [self sgr_fitDim];
    [self sgr_drawRadius:radius alpha:_alpha place:_place];
    [CATransaction commit];
}

// The dim over the whole surface, which can be resized by its owner without the veil being told (Spotify's square).
- (void)sgr_fitDim {
    CGRect bounds = _dim.superlayer.bounds;
    if (!CGRectEqualToRect(_dim.frame, bounds)) _dim.frame = bounds;
}

- (void)setColor:(UIColor *)color {
    if (!color || [_color isEqual:color]) return;
    _color = [color copy];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _dim.backgroundColor = color.CGColor;
    [CATransaction commit];
}

- (void)followScroll:(UIScrollView *)scroll {
    if (scroll == _scroll) return;
    [_scroll removeObserver:self forKeyPath:@"contentOffset" context:kOffsetContext];
    _scroll = scroll;
    _rested = NO;
    [scroll addObserver:self forKeyPath:@"contentOffset" options:0 context:kOffsetContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != kOffsetContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    [self update];
}

- (void)update {
    UIView *hero = _hero;
    if (!hero.window) return;
    UIScrollView *scroll = _scroll;
    CGFloat scrolled = scroll ? scroll.contentOffset.y + scroll.adjustedContentInset.top : 0;
    CGFloat top = [hero convertPoint:CGPointZero toView:nil].y;
    if (fabs(scrolled) < kAtRest) {
        _restTop = top;
        _rested = YES;
    }
    // A page never seen at rest (opened scrolled) is taken to have moved its hero with the scroll.
    CGFloat rest = _rested ? _restTop : top + scrolled;
    CGFloat displacement = MAX(0, rest - top), beyond = MAX(0, scrolled - displacement);
    CGFloat distance = displacement + beyond, pull = _stretchesItself ? 0 : MAX(0, -scrolled);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self sgr_fitDim];
    [CATransaction commit];
    [self sgr_drawRadius:SGRHeroVeilBlurRadius(distance) alpha:SGRHeroVeilDimAlpha(distance)
                   place:SGRHeroVeilArtPlace(pull, hero.bounds.size.height, displacement, beyond)];
}

- (void)sgr_drawRadius:(CGFloat)radius alpha:(CGFloat)alpha place:(SGRHeroArtPlace)place {
    BOOL blur = _blur && radius != _radius, dim = alpha != _alpha;
    BOOL moved = place.scale != _place.scale || place.shift != _place.shift;
    if (!blur && !dim && !moved) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    if (blur) {
        CALayer *layer = [self sgr_surface].layer;
        // A filter someone else put on the layer stays, and the dim is all there is.
        if (radius > 0 && !_blurred && !layer.filters) {
            layer.filters = @[_blur];
            _blurred = layer;
        } else if (radius <= 0 && _blurred) {
            _blurred.filters = nil;
            _blurred = nil;
        }
        [_blurred setValue:radiusNumber(radius) forKeyPath:kRadiusPath];
        _radius = radius;
    }
    if (dim) {
        _dim.opacity = alpha;
        _dim.hidden = alpha <= 0;
        _alpha = alpha;
    }
    if (moved) {
        _place = place;
        [self sgr_placeArt];
    }
    [CATransaction commit];
}

// Each art layer scaled about the hero's top edge and middle, and moved, by a transform about its own anchor.
- (void)sgr_placeArt {
    CGFloat scale = _place.scale, middle = CGRectGetMidX(_hero.layer.bounds);
    BOOL still = scale == 1 && _place.shift == 0;
    for (CALayer *layer in _art) {
        CGPoint anchor = layer.position;
        CGAffineTransform placed = still ? CGAffineTransformIdentity
            : CGAffineTransformMake(scale, 0, 0, scale, (scale - 1) * (anchor.x - middle), (scale - 1) * anchor.y + _place.shift);
        if (!CGAffineTransformEqualToTransform(layer.affineTransform, placed)) layer.affineTransform = placed;
    }
}

- (void)artWillLayOut {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (CALayer *layer in _art) {
        if (!CGAffineTransformIsIdentity(layer.affineTransform)) layer.affineTransform = CGAffineTransformIdentity;
    }
    [CATransaction commit];
}

- (void)artDidLayOut {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self sgr_fitDim];
    [self sgr_placeArt];
    [CATransaction commit];
}

@end
