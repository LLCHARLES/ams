#import "SGMarquee.h"

// Points a second the text moves at, the rest at each end, and the fade over the edge it runs past.
static const CGFloat kSpeed = 30, kFade = 16;
static const CFTimeInterval kRest = 2;
static NSString *const kScroll = @"sg.marquee";

@implementation SGMarqueeLabel {
    UILabel *_label;
    CAGradientLayer *_fade;
    CGFloat _scrolled;   // how far, and which way, the running animation travels; 0 while still, NAN to start over
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.clipsToBounds = YES;
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitStaticText;
    _label = [UILabel new];
    [self addSubview:_label];
    _fade = [CAGradientLayer layer];
    _fade.startPoint = CGPointMake(0, 0.5);
    _fade.endPoint = CGPointMake(1, 0.5);
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(setNeedsLayout)
                                               name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSString *)text { return _label.text; }
- (UIFont *)font { return _label.font; }
- (UIColor *)textColor { return _label.textColor; }

- (void)setText:(NSString *)text {
    if ([text isEqualToString:_label.text]) return;
    _label.text = text;
    self.accessibilityLabel = text;
    _scrolled = NAN;   // starts over from its start
    [self setNeedsLayout];
}

- (void)setFont:(UIFont *)font {
    _label.font = font;
    _scrolled = NAN;
    [self setNeedsLayout];
}

- (void)setTextColor:(UIColor *)textColor {
    _label.textColor = textColor;
}

- (void)setScrollingPaused:(BOOL)paused {
    if (_scrollingPaused == paused) return;
    _scrollingPaused = paused;
    CALayer *layer = _label.layer;
    CFTimeInterval offset = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.speed = paused ? 0 : 1;
    layer.timeOffset = paused ? offset : 0;
    if (!paused) {
        layer.beginTime = 0;
        layer.beginTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - offset;
    }
    [CATransaction commit];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // A view out of its window loses its animations; back in one, it scrolls again.
    _scrolled = NAN;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    CGFloat textWidth = ceil([_label sizeThatFits:CGSizeMake(CGFLOAT_MAX, size.height)].width);
    CGFloat overflow = textWidth - size.width;
    BOOL scrolls = overflow > 0.5 && !UIAccessibilityIsReduceMotionEnabled() && self.window;
    // Right to left the text starts at the right edge and runs on, and moves, toward the left.
    BOOL rtl = self.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    _label.lineBreakMode = scrolls ? NSLineBreakByClipping : NSLineBreakByTruncatingTail;
    CGRect frame = CGRectMake(scrolls && rtl ? size.width - textWidth : 0, 0, scrolls ? textWidth : size.width, size.height);
    if (!CGRectEqualToRect(_label.frame, frame)) _label.frame = frame;

    self.layer.mask = scrolls ? _fade : nil;
    if (scrolls) {
        _fade.frame = self.bounds;
        CGFloat edge = MIN(kFade / size.width, 0.2);
        // The trailing edge fades, where the text runs on; its start stays crisp at rest.
        _fade.colors = @[(id)UIColor.blackColor.CGColor, (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor];
        _fade.locations = @[@0, @(1 - edge), @1];
        _fade.startPoint = CGPointMake(rtl ? 1 : 0, 0.5);
        _fade.endPoint = CGPointMake(rtl ? 0 : 1, 0.5);
    }

    // The distance the text moves, toward its trailing side: leftward (negative) left to right.
    CGFloat travel = scrolls ? (rtl ? 1 : -1) * (overflow + kFade) : 0;
    if (travel == _scrolled && [_label.layer animationForKey:kScroll]) return;
    _scrolled = travel;
    [_label.layer removeAnimationForKey:kScroll];
    if (!scrolls) return;
    CFTimeInterval glide = fabs(travel) / kSpeed, total = 2 * (kRest + glide);
    CAKeyframeAnimation *scroll = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    scroll.values = @[@0, @0, @(travel), @(travel), @0];
    scroll.keyTimes = @[@0, @(kRest / total), @((kRest + glide) / total), @((2 * kRest + glide) / total), @1];
    scroll.timingFunctions = @[
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear],
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut],
    ];
    scroll.duration = total;
    scroll.repeatCount = HUGE_VALF;
    // A text's glide needs no more than the display's base rate.
    scroll.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
    [_label.layer addAnimation:scroll forKey:kScroll];
}

@end
