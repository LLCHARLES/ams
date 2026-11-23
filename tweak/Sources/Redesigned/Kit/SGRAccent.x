// The Kit owns accent provenance and global repaint. Only Spotify's brand inputs become tokens;
// their resolved RGB is never used to infer ownership of other content.
#import "Core/SGCore.h"
#import "SGRAccent.h"

static const uint32_t kGreens[] = {0x1ED760, 0x1DB954};
static char imageSourceKey, imageBaseKey, fillKey, strokeKey, backgroundKey, resolvingKey, layerOverrideKey;
static NSHashTable *painted;
static NSString *const kAnimationSources = @"sgr.accent.sources";

static CGFloat tokenShade(CGFloat r, CGFloat g, CGFloat b) {
    // Installed hooks retain provenance even while tokens resolve to their original stock color.
    for (NSUInteger i = 0; i < sizeof(kGreens)/sizeof(kGreens[0]); i++) {
        CGFloat gr = ((kGreens[i] >> 16)&255)/255.0, gg = ((kGreens[i] >> 8)&255)/255.0, gb = (kGreens[i]&255)/255.0;
        if (fabs(r-gr) <= .01 && fabs(g-gg) <= .01 && fabs(b-gb) <= .01) return MAX(gr,MAX(gg,gb))/(0xD7/255.0);
    }
    return -1;
}
static SGRAccentToken *componentSource(CGFloat r, CGFloat g, CGFloat b, CGFloat alpha) {
    CGFloat shade = tokenShade(r,g,b);
    if (shade < 0) return nil;
    NSInteger original = (lround(r*255)<<16)|(lround(g*255)<<8)|lround(b*255);
    return [[SGRAccentToken alloc] initWithAlpha:alpha shade:shade originalRGB:original];
}
BOOL SGRAccentSwap(CGFloat *r, CGFloat *g, CGFloat *b) {
    if (!SGRAccentSubstitutionEnabled()) return NO;
    CGFloat shade = tokenShade(*r,*g,*b);
    if (shade < 0) return NO;
    NSInteger rgb = SGRAccentRGB();
    *r = ((rgb>>16)&255)/255.0 * shade; *g = ((rgb>>8)&255)/255.0 * shade; *b = (rgb&255)/255.0 * shade;
    return YES;
}
SGRAccentToken *SGRAccentCGSource(CGColorRef color) {
    if (!color || CFGetTypeID(color) != CGColorGetTypeID()) return nil;
    SGRAccentToken *source = SGRAccentMarkedCGSource(color);
    if (source) return source;
    if (CGColorGetNumberOfComponents(color) != 4) return nil;
    const CGFloat *c = CGColorGetComponents(color);
    return componentSource(c[0],c[1],c[2],c[3]);
}
SGRAccentToken *SGRAccentImageSource(UIImage *image) { return objc_getAssociatedObject(image, &imageSourceKey); }
SGRAccentToken *SGRAccentLayerSource(CAShapeLayer *layer, BOOL stroke) {
    return objc_getAssociatedObject(layer, stroke ? &strokeKey : &fillKey);
}
static id resolved(SGRAccentToken *source, UIColor *override) {
    if (!source) return nil;
    if (!override) return CFBridgingRelease([source copyGlobalCGColor]);
    NSInteger rgb = SGRAccentRGB();
    if (override) {
        CGFloat r,g,b,a;
        [override getRed:&r green:&g blue:&b alpha:&a];
        rgb = (lround(r*255)<<16)|(lround(g*255)<<8)|lround(b*255);
    }
    return CFBridgingRelease([source copyCGColorForRGB:rgb]);
}
static void track(id object) {
    if (!NSThread.isMainThread) {
        __weak id weak = object;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weak) track(weak); });
        return;
    }
    if (!painted) painted = [NSHashTable weakObjectsHashTable];
    [painted addObject:object];
}

// Metadata is stored through CAAnimation's KVC, which survives copying into a layer.
static BOOL animationOwned(CAAnimation *animation) {
    return [(NSDictionary *)[animation valueForKey:kAnimationSources] count] != 0;
}
static CAAnimation *preparedAnimation(CAAnimation *animation, UIColor *override) {
    NSDictionary *sources = [animation valueForKey:kAnimationSources];
    NSMutableDictionary *changes = [NSMutableDictionary dictionary];
    for (NSString *slot in sources) {
        id source = sources[slot];
        if ([slot isEqualToString:@"values"]) {
            NSArray *current = [(CAKeyframeAnimation *)animation values];
            NSMutableArray *values = nil;
            NSArray *tokens = source;
            for (NSUInteger index = 0; index < tokens.count; index++) {
                if (tokens[index] == NSNull.null) continue;
                id value = resolved(tokens[index], override);
                if (CGColorEqualToColor((__bridge CGColorRef)value, (__bridge CGColorRef)current[index])) continue;
                if (!values) values = [current mutableCopy];
                values[index] = value;
            }
            if (values) changes[slot] = values;
        } else {
            id value = resolved(source, override), current = [animation valueForKey:slot];
            if (!CGColorEqualToColor((__bridge CGColorRef)value, (__bridge CGColorRef)current)) changes[slot] = value;
        }
    }
    if (!changes.count) return animation;
    CAAnimation *copy = [animation copy];
    objc_setAssociatedObject(copy, &resolvingKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (NSString *slot in changes) [copy setValue:changes[slot] forKey:slot];
    objc_setAssociatedObject(copy, &resolvingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return copy;
}
void SGRAccentSetLayerOverride(CALayer *layer, UIColor *override) {
    objc_setAssociatedObject(layer, &layerOverrideKey, override, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void recordAnimation(CAAnimation *animation, NSString *slot, id sources) {
    NSDictionary *existing = [animation valueForKey:kAnimationSources];
    if (!sources && !existing[slot]) return;
    NSMutableDictionary *all = [existing mutableCopy] ?: [NSMutableDictionary dictionary];
    if (sources) all[slot] = sources; else [all removeObjectForKey:slot];
    [animation setValue:all.count ? all : nil forKey:kAnimationSources];
}
static id animationValue(CAAnimation *animation, NSString *slot, id value) {
    if (objc_getAssociatedObject(animation, &resolvingKey)) return value;
    SGRAccentToken *source = SGRAccentCGSource((__bridge CGColorRef)value);
    recordAnimation(animation, slot, source);
    return source ? resolved(source, nil) : value;
}

// Only UIKit's complete tint operation establishes image ownership. Arbitrary renderer callbacks
// can also draw through CoreGraphics, so neither their output nor sampled pixels establish ownership.
static UIImage *markImage(UIImage *image, SGRAccentToken *source, UIImage *base) {
    if (image == base || image.renderingMode == UIImageRenderingModeAlwaysTemplate) return image;
    objc_setAssociatedObject(image, &imageSourceKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(image, &imageBaseKey, source ? base : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return image;
}
UIImage *SGRAccentTintedImage(UIImage *image, UIColor *override) {
    SGRAccentToken *source = SGRAccentImageSource(image);
    UIImage *base = objc_getAssociatedObject(image, &imageBaseKey);
    if (!source || !base) return image;
    UIColor *ink = override ? [override colorWithAlphaComponent:source.alpha] : source.color;
    return [base imageWithTintColor:ink renderingMode:UIImageRenderingModeAlwaysOriginal];
}

static void refreshPaint(void) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (id object in painted.allObjects) {
        if ([object isKindOfClass:UIView.class]) {
            UIView *view = object;
            UIColor *tint = view.tintColor, *background = view.backgroundColor;
            if (SGRAccentIsToken(tint)) { view.tintColor = nil; view.tintColor = tint; }
            if (SGRAccentIsToken(background)) { view.backgroundColor = nil; view.backgroundColor = background; }
            if ([view isKindOfClass:UILabel.class]) {
                UILabel *label = (UILabel *)view; UIColor *text = label.textColor;
                if (SGRAccentIsToken(text)) { label.textColor = nil; label.textColor = text; }
            }
            if ([view isKindOfClass:UIImageView.class]) {
                UIImageView *image = (UIImageView *)view;
                SGRAccentToken *source = SGRAccentImageSource(image.image);
                if (source) image.image = SGRAccentTintedImage(image.image, nil);
            }
            [view setNeedsDisplay];
        } else if ([object isKindOfClass:CALayer.class]) {
            CALayer *layer = object;
            SGRAccentToken *background = objc_getAssociatedObject(layer, &backgroundKey);
            if (background) layer.backgroundColor = background.color.CGColor;
            if ([layer isKindOfClass:CAShapeLayer.class]) {
                CAShapeLayer *shape = (CAShapeLayer *)layer;
                SGRAccentToken *fill = SGRAccentLayerSource(shape, NO), *stroke = SGRAccentLayerSource(shape, YES);
                if (fill) shape.fillColor = fill.color.CGColor;
                if (stroke) shape.strokeColor = stroke.color.CGColor;
            }
            // Never replace installed animations: even equal-looking replacements cancel delegates.
        }
    }
    [CATransaction commit];
}

%group SGRAccentPaint
%hook UIColor
- (UIColor *)initWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    SGRAccentToken *source = componentSource(r,g,b,a);
    if (source) return (__bridge UIColor *)CFBridgingRetain(source.color);
    return %orig;
}
+ (UIColor *)colorWithRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a {
    SGRAccentToken *source = componentSource(r,g,b,a);
    if (source) return source.color;
    return %orig;
}
%end
%hook UIImage
- (UIImage *)imageWithTintColor:(UIColor *)color renderingMode:(UIImageRenderingMode)mode {
    UIImage *image = %orig;
    return markImage(image, SGRAccentSource(color), self);
}
- (UIImage *)imageWithTintColor:(UIColor *)color {
    UIImage *image = %orig;
    return markImage(image, SGRAccentSource(color), self);
}
- (UIImage *)imageWithRenderingMode:(UIImageRenderingMode)mode {
    UIImage *image = %orig;
    UIImage *base = objc_getAssociatedObject(self, &imageBaseKey);
    return markImage(image, SGRAccentImageSource(self), [base imageWithRenderingMode:mode]);
}
- (UIImage *)imageWithAlignmentRectInsets:(UIEdgeInsets)insets {
    UIImage *image = %orig;
    UIImage *base = objc_getAssociatedObject(self, &imageBaseKey);
    return markImage(image, SGRAccentImageSource(self), [base imageWithAlignmentRectInsets:insets]);
}
%end
%hook UIImageView
- (void)setImage:(UIImage *)image {
    %orig;
    if (SGRAccentImageSource(image)) track(self);
}
%end
%hook UIView
- (void)setTintColor:(UIColor *)color {
    %orig;
    if (SGRAccentIsToken(color)) track(self);
}
- (void)setBackgroundColor:(UIColor *)color {
    %orig;
    if (SGRAccentIsToken(color)) track(self);
}
%end
%hook UILabel
- (void)setTextColor:(UIColor *)color {
    %orig;
    if (SGRAccentIsToken(color)) track(self);
}
%end
%end
%group SGRAccentLifecycle
%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    SGRAccentTrackTransition(((UIViewController *)self).transitionCoordinator);
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Container setters finish committing their selected child after delivering appearance.
    dispatch_async(dispatch_get_main_queue(), ^{ SGRAccentRefreshContext(); });
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ SGRAccentRefreshContext(); });
}
%end
%hook UINavigationController
- (UIViewController *)popViewControllerAnimated:(BOOL)animated {
    // During an interactive pop UIKit can deliver the destination's willAppear before attaching
    // its coordinator. Hold the committed owner across that gap, then observe the real transition.
    SGRAccentNavigationWillChange();
    UIViewController *page = %orig;
    SGRAccentNavigationDidChange(((UINavigationController *)self).transitionCoordinator);
    return page;
}
%end
%end

%group SGRAccentPaint
%hook CAShapeLayer
- (void)setFillColor:(CGColorRef)color {
    SGRAccentToken *source = SGRAccentCGSource(color);
    objc_setAssociatedObject(self, &fillKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id used = source ? resolved(source,nil) : (__bridge id)color;
    %orig((__bridge CGColorRef)used);
    if (source) track(self);
}
- (void)setStrokeColor:(CGColorRef)color {
    SGRAccentToken *source = SGRAccentCGSource(color);
    objc_setAssociatedObject(self, &strokeKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id used = source ? resolved(source,nil) : (__bridge id)color;
    %orig((__bridge CGColorRef)used);
    if (source) track(self);
}
%end
%hook CALayer
- (void)setBackgroundColor:(CGColorRef)color {
    SGRAccentToken *source = SGRAccentCGSource(color);
    objc_setAssociatedObject(self, &backgroundKey, source, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    id used = source ? resolved(source,nil) : (__bridge id)color;
    %orig((__bridge CGColorRef)used);
    if (source) track(self);
}
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    // This is Spotify/Retrine submitting a new animation, never a repaint of an installed one.
    if (animationOwned(animation))
        animation = preparedAnimation(animation, objc_getAssociatedObject(self, &layerOverrideKey));
    %orig(animation,key);
}
%end
%hook CABasicAnimation
- (void)setFromValue:(id)value {
    id used = animationValue(self,@"fromValue",value);
    %orig(used);
}
- (void)setToValue:(id)value {
    id used = animationValue(self,@"toValue",value);
    %orig(used);
}
- (void)setByValue:(id)value {
    id used = animationValue(self,@"byValue",value);
    %orig(used);
}
%end
%hook CAKeyframeAnimation
- (void)setValues:(NSArray *)values {
    if (objc_getAssociatedObject(self, &resolvingKey)) {
        %orig;
        return;
    }
    NSMutableArray *sources = nil, *mapped = nil;
    for (NSUInteger index = 0; index < values.count; index++) {
        id value = values[index];
        SGRAccentToken *source = SGRAccentCGSource((__bridge CGColorRef)value);
        if (source && !sources) {
            sources = [NSMutableArray arrayWithCapacity:values.count];
            for (NSUInteger prefix = 0; prefix < index; prefix++) [sources addObject:NSNull.null];
            mapped = [values mutableCopy];
        }
        if (sources) [sources addObject:source ?: NSNull.null];
        if (source) mapped[index] = resolved(source,nil);
    }
    recordAnimation(self,@"values", sources);
    %orig(mapped ?: values);
}
%end
%end
// The factory's dynamic class overrides UIColor's derivations. Bind the actual produced class.
%group SGRTokenDerivation
%hook SGRDerivedColor
- (UIColor *)colorWithAlphaComponent:(CGFloat)alpha {
    SGRAccentToken *source = SGRAccentSource((UIColor *)self);
    if (source)
        return [[[SGRAccentToken alloc] initWithAlpha:alpha shade:source.shade originalRGB:source.originalRGB] color];
    return %orig;
}
%end
%end
%ctor {
    if (!SGRedesignedUI()) return;
    // A stock launch installs the per-color/per-animation hooks only for Follow the cover, which paints the
    // player's controls by their provenance; the tokens then resolve to Spotify's own colors everywhere else.
    // Otherwise none are installed. The Appearance page's existing restart note applies when enabling from
    // stock (and Follow the cover is read at launch too); live changes only repaint existing provenance.
    SGRAccentPreferencesChanged();
    %init(SGRAccentLifecycle);
    if (SGRAccentSubstitutionEnabled() || SGHidden(SGRKeyPlayerFollowsCover)) {
        %init(SGRAccentPaint);
        %init(SGRTokenDerivation, SGRDerivedColor = object_getClass(SGRAccentTokenColor(1, 1)));
    }
    [NSNotificationCenter.defaultCenter addObserverForName:SGRAccentDidChangeNotification object:nil queue:nil
        usingBlock:^(NSNotification *note) { refreshPaint(); }];
    dispatch_async(dispatch_get_main_queue(), ^{ SGRAccentStart(); });
}
