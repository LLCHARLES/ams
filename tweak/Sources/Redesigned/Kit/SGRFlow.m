#import "SGRFlow.h"

enum { kDiscs = 5 };

// Each disc: where it rests, as shares of the layer (top left, top right, bottom left, bottom right,
// middle), its diameter as a share of the layer's longer side, the loop it drifts on (radii as shares of
// width and height), how long one loop takes and which way it runs, and how long a breath takes.
// The periods share no factor, so the picture they make together does not come round again for hours.
typedef struct {
    CGFloat x, y, diameter, driftX, driftY;
    CFTimeInterval loop;
    BOOL clockwise;
    CFTimeInterval breath;
} SGRDisc;

static const SGRDisc kDisc[kDiscs] = {
    {0.22, 0.20, 0.80, 0.26, 0.10, 29, YES, 13},
    {0.80, 0.28, 0.75, 0.22, 0.12, 37, NO, 17},
    {0.20, 0.74, 0.78, 0.24, 0.11, 31, NO, 19},
    {0.78, 0.84, 0.80, 0.26, 0.09, 41, YES, 11},
    {0.50, 0.50, 0.75, 0.18, 0.14, 53, YES, 23},
};
// How far a breath takes a disc's size either way, and how long new colors take to blend in.
static const CGFloat kBreathSmall = 0.85, kBreathLarge = 1.18;
static const CFTimeInterval kRecolor = 1.2;
// The color under the discs is the artwork's main color at this share of its light.
static const CGFloat kBaseShade = 0.55;
// The shade over everything: clear down to this share of the height, then this much black at the bottom.
static const CGFloat kShadeFrom = 0.45, kShadeBottom = 0.35;
// How often the discs are moved, and the pixels to a point the field is drawn at before it is stretched to the screen.
// Played by the render server the field was drawn again, across the whole screen and at its full resolution, on every
// frame anything else asked for: 21% of an iPhone 13 Pro's GPU with the player open and 34% under the lyrics page at
// 120 Hz, against 1.4% held still. A disc's edge is some 180 pt wide and passes at about 20 pt a second, so a step this
// long changes a pixel by a level or two of 255, and half a pixel to a point is far finer than anything in it.
static const NSTimeInterval kStepsPerSecond = 15;
static const CGFloat kDrawScale = 0.5;

static NSDictionary *noActions(void) {
    static NSDictionary *none;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSNull *off = NSNull.null;
        none = @{@"bounds": off, @"position": off, @"frame": off, @"transform": off, @"backgroundColor": off,
                 @"colors": off, @"hidden": off, @"opacity": off};
    });
    return none;
}

static UIColor *shaded(UIColor *color, CGFloat share) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) return color;
    return [UIColor colorWithRed:r * share green:g * share blue:b * share alpha:1];
}

static NSArray *discColors(UIColor *color) {
    return @[(id)color.CGColor, (id)[color colorWithAlphaComponent:0.55].CGColor, (id)[color colorWithAlphaComponent:0].CGColor];
}

@implementation SGRFlowLayer {
    CALayer *_base;
    CAGradientLayer *_discs[kDiscs];
    CAGradientLayer *_shade;
    CGSize _laidOutFor;
    // Seconds of drift so far, and since when it has been running.
    CFTimeInterval _elapsed, _since;
    NSTimer *_steps;   // moves the discs while it drifts
    BOOL _moving;
    UIColor *_baseColor;
}

- (instancetype)init {
    if (!(self = [super init])) return nil;
    self.actions = noActions();
    self.shouldRasterize = YES;
    self.rasterizationScale = kDrawScale;
    _base = [CALayer layer];
    _base.actions = noActions();
    [self addSublayer:_base];
    for (int i = 0; i < kDiscs; i++) {
        CAGradientLayer *disc = [CAGradientLayer layer];
        disc.actions = noActions();
        disc.type = kCAGradientLayerRadial;
        disc.startPoint = CGPointMake(0.5, 0.5);
        disc.endPoint = CGPointMake(1, 1);
        disc.locations = @[@0, @0.45, @1];
        disc.colors = discColors(UIColor.clearColor);
        // The whole artwork's color lies under the four quarters', so it fills between them rather than over them.
        if (i == kDiscs - 1) [self insertSublayer:disc above:_base];
        else [self addSublayer:disc];
        _discs[i] = disc;
    }
    _shade = [CAGradientLayer layer];
    _shade.actions = noActions();
    _shade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:kShadeBottom].CGColor];
    _shade.locations = @[@(kShadeFrom), @1];
    [self addSublayer:_shade];
    return self;
}

- (UIColor *)baseColor {
    return _baseColor;
}

- (BOOL)moving {
    return _moving;
}

#pragma mark - where the discs are

- (void)layoutSublayers {
    [super layoutSublayers];
    CGRect bounds = self.bounds;
    _base.frame = bounds;
    _shade.frame = bounds;
    if (CGSizeEqualToSize(bounds.size, _laidOutFor) || bounds.size.width < 1 || bounds.size.height < 1) return;
    _laidOutFor = bounds.size;
    BOOL moving = _moving;
    if (moving) [self stop];
    CGFloat side = MAX(bounds.size.width, bounds.size.height);
    for (int i = 0; i < kDiscs; i++) {
        CGFloat diameter = round(side * kDisc[i].diameter);
        _discs[i].bounds = CGRectMake(0, 0, diameter, diameter);
        _discs[i].position = [self restOf:i];
        _discs[i].transform = CATransform3DIdentity;
    }
    if (moving) [self start];
}

- (CGPoint)restOf:(int)i {
    CGSize size = self.bounds.size;
    return CGPointMake(size.width * kDisc[i].x, size.height * kDisc[i].y);
}

#pragma mark - moving

- (void)dealloc {
    [_steps invalidate];
}

- (void)setMoving:(BOOL)moving {
    if (moving == _moving) return;
    _moving = moving;
    if (moving) [self start];
    else [self stop];
}

- (void)start {
    if (self.bounds.size.width < 1 || _steps) return;
    _since = CACurrentMediaTime();
    __weak SGRFlowLayer *weakSelf = self;
    _steps = [NSTimer timerWithTimeInterval:1 / kStepsPerSecond repeats:YES block:^(NSTimer *timer) { [weakSelf step]; }];
    _steps.tolerance = 0.2 / kStepsPerSecond;
    // Common modes: the lyrics page scrolls over it.
    [NSRunLoop.mainRunLoop addTimer:_steps forMode:NSRunLoopCommonModes];
    [self step];
}

// Every disc where the drift so far puts it: on its loop, an ellipse round a center one radius to the side of its
// resting place, so it starts and ends there, and at its breath's size, eased at both ends of each breath.
- (void)step {
    CGSize size = self.bounds.size;
    CFTimeInterval seconds = _elapsed + (_since > 0 ? CACurrentMediaTime() - _since : 0);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (int i = 0; i < kDiscs; i++) {
        CGPoint rest = [self restOf:i];
        CGFloat rx = size.width * kDisc[i].driftX, ry = size.height * kDisc[i].driftY;
        double angle = M_PI + (kDisc[i].clockwise ? -2 : 2) * M_PI * fmod(seconds, kDisc[i].loop) / kDisc[i].loop;
        _discs[i].position = CGPointMake(rest.x + rx + rx * cos(angle), rest.y + ry * sin(angle));
        double breath = fmod(seconds, 2 * kDisc[i].breath) / kDisc[i].breath;
        if (breath > 1) breath = 2 - breath;
        breath = breath * breath * (3 - 2 * breath);
        CGFloat scale = kBreathSmall + (kBreathLarge - kBreathSmall) * breath;
        _discs[i].transform = CATransform3DMakeScale(scale, scale, 1);
    }
    [CATransaction commit];
}

// Every disc stays where the last step put it, so starting again carries on from the same picture.
- (void)stop {
    if (_since > 0) _elapsed += CACurrentMediaTime() - _since;
    _since = 0;
    [_steps invalidate];
    _steps = nil;
}

#pragma mark - colors

- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated {
    if (colors.count < kDiscs) return;
    _baseColor = shaded(colors[4], kBaseShade);
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [self recolor:_base key:@"backgroundColor" to:(__bridge id)_baseColor.CGColor animated:animated];
    for (int i = 0; i < kDiscs; i++) [self recolor:_discs[i] key:@"colors" to:discColors(colors[i]) animated:animated];
    [CATransaction commit];
}

- (void)recolor:(CALayer *)layer key:(NSString *)key to:(id)value animated:(BOOL)animated {
    id from = [(layer.presentationLayer ?: layer) valueForKey:key];
    [layer setValue:value forKey:key];
    if (!animated || !from) return;
    CABasicAnimation *blend = [CABasicAnimation animationWithKeyPath:key];
    blend.fromValue = from;
    blend.toValue = value;
    blend.duration = kRecolor;
    blend.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [layer addAnimation:blend forKey:key];
}

@end
