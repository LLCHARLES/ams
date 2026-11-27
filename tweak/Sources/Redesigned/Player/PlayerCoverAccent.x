// Player redesign: Follow the cover, the player's accent from the cover of the song playing.
//
// Spotify draws its lit controls with the accent baked in (Kit/SGRAccent.x swaps it where a color is made): the
// shuffle and repeat icons are images drawn in it, the repeat dot is a view with it as its background, and the like
// checkmark is a Lottie animation whose shape layers are filled with it. None of them asks for the color again, so
// the player paints them itself, over Spotify's bottom stack (the title row with the like, the progress bar, the
// controls and the footer): token-owned images are tinted from their own shape, and token-owned backgrounds,
// shapes and new animation submissions take the color. Running animations are left alone.
// Releasing the override resolves the current global token for known model/image colors,
// not a captured RGB or a similar-looking hue. It paints whenever the cover's color
// changes and whenever the stack or one of its buttons lays out, which is when Spotify hands a button its new state.
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Player.h"

static NSInteger sg_cover = -1;   // 0xRRGGBB while a cover gives one, else -1
static __weak UIView *sg_stack;   // the bottom stack last painted
static char kOriginalKey, kTintedKey, kTintedCoverKey, kInkKey, kOriginalFillKey, kOriginalStrokeKey;
static char kPaintedFillKey, kPaintedStrokeKey;

BOOL SGRPlayerFollowsCover(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = SGHidden(SGRKeyPlayerFollowsCover); });
    return on;
}

static void unpack(NSInteger rgb, CGFloat *r, CGFloat *g, CGFloat *b) {
    *r = ((rgb >> 16) & 0xFF) / 255.0;
    *g = ((rgb >> 8) & 0xFF) / 255.0;
    *b = (rgb & 0xFF) / 255.0;
}

// Made once per cover color: every pass over the stack hands it out.
static UIColor *coverColor(void) {
    static NSInteger madeFor = -1;
    static UIColor *made;
    if (made && madeFor == sg_cover) return made;
    CGFloat r, g, b;
    unpack(sg_cover, &r, &g, &b);
    made = [UIColor colorWithRed:r green:g blue:b alpha:1];
    madeFor = sg_cover;
    return made;
}

BOOL SGRPlayerAccentLike(UIColor *color) {
    if (SGRAccentIsToken(color)) return YES;
    // The footer also uses this public query to classify a lit Spotify control during its natural
    // repaint. Preserve that pre-batch classification; it is NOT provenance and never authorizes
    // the cover painter to recolor a background, image, shape or animation.
    const CGFloat hueDistance = .05, minimumSaturation = .35, minimumBrightness = .2;
    CGFloat r,g,b,a, h,s,v, ah,as,av;
    if (!color || ![color getRed:&r green:&g blue:&b alpha:&a] || a <= .5) return NO;
    SGRAccentSwap(&r,&g,&b);
    UIColor *ink = [UIColor colorWithRed:r green:g blue:b alpha:a];
    if (![ink getHue:&h saturation:&s brightness:&v alpha:&a]) return NO;
    NSInteger rgb = SGRAccentRGB();
    CGFloat ar,ag,ab;
    unpack(rgb,&ar,&ag,&ab);
    UIColor *accent = [UIColor colorWithRed:ar green:ag blue:ab alpha:1];
    if (![accent getHue:&ah saturation:&as brightness:&av alpha:&a]) return NO;
    CGFloat distance = fabs(h-ah);
    return MIN(distance,1-distance) < hueDistance && s > minimumSaturation && v > minimumBrightness;
}

UIColor *SGRPlayerImageInk(UIImage *image) {
    SGRAccentToken *source = SGRAccentImageSource(image);
    if (source) return source.color;
    id known = objc_getAssociatedObject(image, &kInkKey);
    if (known) return known == NSNull.null ? nil : known;
    enum { kSide = 16 };
    uint8_t pixels[kSide * kSide * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, kSide, kSide, 8, kSide * 4, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    UIColor *ink = nil;
    if (context && image.CGImage) {
        CGContextDrawImage(context, CGRectMake(0, 0, kSide, kSide), image.CGImage);
        double r = 0, g = 0, b = 0, n = 0;
        for (int i = 0; i < kSide * kSide; i++) {
            uint8_t alpha = pixels[i * 4 + 3];
            if (alpha < 128) continue;
            r += pixels[i * 4] / (double)alpha;
            g += pixels[i * 4 + 1] / (double)alpha;
            b += pixels[i * 4 + 2] / (double)alpha;
            n++;
        }
        if (n >= 4) {
            // Sampling is for the footer's appearance, not proof of token ownership.
            CGFloat rgba[] = {r/n, g/n, b/n, 1};
            CGColorSpaceRef sampledSpace = CGColorSpaceCreateDeviceRGB();
            CGColorRef sampled = CGColorCreate(sampledSpace, rgba);
            ink = [UIColor colorWithCGColor:sampled];
            CGColorRelease(sampled);
            CGColorSpaceRelease(sampledSpace);
        }
    }
    if (context) CGContextRelease(context);
    objc_setAssociatedObject(image, &kInkKey, ink ?: NSNull.null, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return ink;
}

static void paintImageView(UIImageView *view) {
    UIImage *image = view.image, *tinted = objc_getAssociatedObject(view, &kTintedKey);
    UIImage *original = image == tinted ? objc_getAssociatedObject(view, &kOriginalKey) : image;
    if (!original) return;
    SGRAccentToken *source = SGRAccentImageSource(original);
    if (!source) return;
    if (sg_cover < 0) {
        view.image = SGRAccentTintedImage(original, nil);
        objc_setAssociatedObject(view, &kOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &kTintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    // A tint made for an earlier cover is drawn again in this one; Spotify's icons only change on a state change.
    if (image == tinted && tinted && [objc_getAssociatedObject(view, &kTintedCoverKey) integerValue] == sg_cover) return;
    UIImage *made = SGRAccentTintedImage(original, coverColor());
    objc_setAssociatedObject(view, &kOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kTintedKey, made, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &kTintedCoverKey, @(sg_cover), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    view.image = made;
}

static void paintBackground(UIView *view) {
    UIColor *original = objc_getAssociatedObject(view, &kOriginalKey);
    UIColor *current = view.backgroundColor;
    if (!original && !SGRAccentIsToken(current)) return;
    if (!original) {
        original = current;
        objc_setAssociatedObject(view, &kOriginalKey, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *color = sg_cover < 0 ? original : [coverColor() colorWithAlphaComponent:SGRAccentSource(original).alpha];
    if (![view.backgroundColor isEqual:color]) view.backgroundColor = color;
}

static void paintShape(CAShapeLayer *layer) {
    for (int stroke = 0; stroke < 2; stroke++) {
        void *key = stroke ? &kOriginalStrokeKey : &kOriginalFillKey;
        void *paintedKey = stroke ? &kPaintedStrokeKey : &kPaintedFillKey;
        SGRAccentToken *original = objc_getAssociatedObject(layer, key);
        id painted = objc_getAssociatedObject(layer, paintedKey);
        CGColorRef current = stroke ? layer.strokeColor : layer.fillColor;
        // A fresh Spotify state replaces our previous paint. Restore that new state's source later,
        // not the source from the first time this reusable layer was seen.
        if (original && (!current || !painted || !CGColorEqualToColor(current, (__bridge CGColorRef)painted))) {
            original = nil;
            objc_setAssociatedObject(layer, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(layer, paintedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!original) {
            original = SGRAccentLayerSource(layer, stroke);
            if (!original) continue;
            objc_setAssociatedObject(layer, key, original, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *ink = sg_cover < 0 ? original.color : [coverColor() colorWithAlphaComponent:original.alpha];
        CGColorRef color = ink.CGColor;
        objc_setAssociatedObject(layer, paintedKey, sg_cover < 0 ? nil : (__bridge id)color, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!CGColorEqualToColor(current, color)) {
            if (stroke) layer.strokeColor = color;
            else layer.fillColor = color;
        }
        if (sg_cover < 0) objc_setAssociatedObject(layer, key, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static void paintLayers(CALayer *layer) {
    // Remember the override for the next natural submission, never replace a running animation:
    // replacing it cancels Spotify's delegate/completion even when its colors are unchanged.
    SGRAccentSetLayerOverride(layer, sg_cover < 0 ? nil : coverColor());
    if ([layer isKindOfClass:CAShapeLayer.class]) paintShape((CAShapeLayer *)layer);
    for (CALayer *sublayer in layer.sublayers) paintLayers(sublayer);
}

void SGRPlayerPaintCover(UIView *stack) {
    if (!SGRPlayerFollowsCover() || !stack) return;
    if (stack.superview && [stack isKindOfClass:UIStackView.class]) sg_stack = stack;
    static Class lottie;
    if (!lottie) lottie = NSClassFromString(@"Lottie.LottieAnimationView");
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    SGForEachView(stack, ^(UIView *view) {
        if ([view.accessibilityIdentifier isEqualToString:SGRPlainCheckIdentifier]) view.tintColor = sg_cover < 0 ? SGRAccent() : coverColor();
        else if ([view isKindOfClass:UIImageView.class]) paintImageView((UIImageView *)view);
        else if (lottie && [view isKindOfClass:lottie]) paintLayers(view.layer);
        else paintBackground(view);
    });
    [CATransaction commit];
}

void SGRPlayerSetCoverAccent(UIColor *cover) {
    NSInteger rgb = -1;
    CGFloat h, s, v, a;
    if ([cover getHue:&h saturation:&s brightness:&v alpha:&a] && s >= 0.15) {
        // Bright and clear enough to read on the dark player, the hue kept.
        UIColor *bright = [UIColor colorWithHue:h saturation:MIN(0.85, MAX(0.45, s)) brightness:MAX(0.9, v) alpha:1];
        CGFloat r, g, b;
        [bright getRed:&r green:&g blue:&b alpha:&a];
        rgb = ((NSInteger)lround(r * 255) << 16) | ((NSInteger)lround(g * 255) << 8) | (NSInteger)lround(b * 255);
    }
    if (rgb == sg_cover) return;
    sg_cover = rgb;
    SGLog(@"redesign player: follow the cover %@", rgb < 0 ? @"gives the accent back (a gray cover)" : [NSString stringWithFormat:@"paints #%06lX", (long)rgb]);
    SGRPlayerPaintCover(sg_stack);
}

// A button in the player's stack laid out: Spotify hands it a new state's icon or animation this way.
%hook UIButton
- (void)layoutSubviews {
    %orig;
    UIView *stack = sg_stack;
    if (stack && sg_cover >= 0 && [(UIView *)self isDescendantOfView:stack]) {
        SGRPlayerPaintCover((UIView *)self);
    }
}
%end

%ctor {
    if (!SGRedesignedUI() || !SGRPlayerFollowsCover()) return;
    %init;
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
        // The Kit first refreshes its global tokens. Follow the cover then overrides the player's stack,
        // even if Spotify hands it a new baked icon or Lottie animation without another layout pass.
        dispatch_async(dispatch_get_main_queue(), ^{ SGRPlayerPaintCover(sg_stack); });
    }];
}
