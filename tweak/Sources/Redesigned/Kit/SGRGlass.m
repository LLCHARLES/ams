#import "Core/SGCore.h"
#import "SGRGlass.h"
#import "SGRTokens.h"
#import <objc/message.h>

typedef NS_ENUM(NSInteger, SGRGlassMode) {
    SGRGlassModeGlass,
    SGRGlassModeBlur,
    SGRGlassModeSolid,
};

static SGRGlassMode glassMode(void) {
    if (SGRReduceTransparency()) return SGRGlassModeSolid;
    if (@available(iOS 26.0, *)) return SGRGlassModeGlass;
    return SGRGlassModeBlur;
}

#pragma mark - the listener's glass

// Light and Dark, laid in the glass as its tint: a shade, so what is behind it still comes through.
static const CGFloat kLightTintAlpha = 0.3, kDarkTintAlpha = 0.45;

SGRGlassMaterial SGRStoredGlassMaterial(void) {
    return SGInt(SGRKeyGlassMaterial, SGRGlassMaterialRegular) == SGRGlassMaterialClear ? SGRGlassMaterialClear : SGRGlassMaterialRegular;
}

SGRGlassTint SGRStoredGlassTint(void) {
    NSInteger tint = SGInt(SGRKeyGlassTint, SGRGlassTintNone);
    return tint == SGRGlassTintLight || tint == SGRGlassTintDark ? tint : SGRGlassTintNone;
}

// The choices the launch started with, read as the redesign starts rather than when the first glass is made: a launch
// under Reduce Transparency makes no glass until it is switched off, and choices changed in between wait for a restart.
static SGRGlassMaterial sg_material;
static SGRGlassTint sg_tint;
static BOOL sg_interactive;

__attribute__((constructor)) static void readGlassChoices(void) {
    if (!SGRedesignedUI()) return;
    sg_material = SGRStoredGlassMaterial();
    sg_tint = SGRStoredGlassTint();
    sg_interactive = SGEnabled(SGRKeyGlassInteractive);
}

UIVisualEffect *SGRGlassEffect(void) {
    if (@available(iOS 26.0, *)) {
        UIGlassEffect *effect = [UIGlassEffect effectWithStyle:sg_material == SGRGlassMaterialClear ? UIGlassEffectStyleClear : UIGlassEffectStyleRegular];
        if (sg_tint == SGRGlassTintLight) effect.tintColor = [UIColor colorWithWhite:1 alpha:kLightTintAlpha];
        if (sg_tint == SGRGlassTintDark) effect.tintColor = [UIColor colorWithWhite:0 alpha:kDarkTintAlpha];
        effect.interactive = sg_interactive;
        return effect;
    }
    return SGGlassEffect();
}

static char kRestyledKey;

// UIKit's own glass behind its tab bar's tabs is Regular, untinted and interactive, the choices' defaults, and any effect
// handed to it comes out with its smoothness 0 where UIKit's is 6 (iOS 26.5 simulator, -[UIView _background]), so it is
// left as UIKit made it unless the listener chose otherwise. Set once per view: -[UIView _glassEffect] reads the style
// back as Regular whatever was set, so it cannot tell whether the glass is still the one given, and UIKit kept it
// through selections, resizes and the bar minimizing and expanding (iOS 26.5 simulator, harness/tabbar glass-check.py).
void SGRGlassRestyle(UIView *view) {
    if (@available(iOS 26.0, *)) {
        if (sg_material == SGRGlassMaterialRegular && sg_tint == SGRGlassTintNone && sg_interactive) return;
        if (objc_getAssociatedObject(view, &kRestyledKey)) return;
        SEL get = NSSelectorFromString(@"_glassEffect"), set = NSSelectorFromString(@"_setGlassEffect:");
        if (![view respondsToSelector:get] || ![view respondsToSelector:set]) return;
        if (![((id (*)(id, SEL))objc_msgSend)(view, get) isKindOfClass:UIGlassEffect.class]) return;
        ((void (*)(id, SEL, id))objc_msgSend)(view, set, SGRGlassEffect());
        objc_setAssociatedObject(view, &kRestyledKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// A shape takes no touch: the control it backs does. Interactive glass gives under the touches of the view UIKit
// asks -_flexInteractionGestureView for when a finger comes down, the glass itself unless that view names another,
// as UIKit's own glass background behind a button names the button. So the shape names its control, the one
// SGRGlassBacks gave it or else the control it sits in: the glass answers the control's touches while the control
// keeps them, with its action, highlight and accessibility. A disabled control names nothing, so its glass stays
// still as UIKit's does. Should UIKit stop asking, the glass stays still and the control works as ever (the
// simulator, iOS 26.5: a shape that took touches itself left its button without a tap).
@interface SGRGlassShape : UIVisualEffectView
@property (nonatomic, weak) UIControl *backedControl;
@end

@implementation SGRGlassShape
- (UIView *)_flexInteractionGestureView {
    UIView *control = self.backedControl ?: self.superview;
    if (!control || ([control isKindOfClass:UIControl.class] && !((UIControl *)control).isEnabled)) return self;
    return control;
}
@end

void SGRGlassBacks(UIView *shape, UIControl *control) {
    if ([shape isKindOfClass:SGRGlassShape.class]) ((SGRGlassShape *)shape).backedControl = control;
}

static UIView *newShape(SGRGlassMode mode) {
    UIView *shape;
    switch (mode) {
        case SGRGlassModeGlass:
            shape = [[SGRGlassShape alloc] initWithEffect:SGRGlassEffect()];
            break;
        case SGRGlassModeBlur:
            shape = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark]];
            break;
        case SGRGlassModeSolid:
            shape = [UIView new];
            shape.backgroundColor = SGRSolidGlassFill();
            break;
    }
    shape.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    shape.userInteractionEnabled = NO;
    return shape;
}

#pragma mark - inside a control

static char kInsideModeKey, kFilmKey;

// The film that makes a shape prominent, inside the effect's own content view so the corners clip it.
static void keepFilm(UIView *shape, BOOL prominent, SGRGlassMode mode) {
    if (mode == SGRGlassModeSolid) {
        shape.backgroundColor = prominent ? [SGRSolidGlassFill() colorWithAlphaComponent:0.26] : SGRSolidGlassFill();
        return;
    }
    UIView *film = objc_getAssociatedObject(shape, &kFilmKey);
    if (!prominent) {
        film.hidden = YES;
        return;
    }
    UIView *content = [shape isKindOfClass:UIVisualEffectView.class] ? ((UIVisualEffectView *)shape).contentView : shape;
    if (!film) {
        film = [UIView new];
        film.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        film.userInteractionEnabled = NO;
        film.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        objc_setAssociatedObject(shape, &kFilmKey, film, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    film.hidden = NO;
    if (film.superview != content) [content addSubview:film];
    // The effect's content view does not clip, so the film carries the shape's corners itself; square ones
    // drew a lighter rectangle around the playlist's Play capsule (harness, 2026-09-17).
    if (!CGRectEqualToRect(film.frame, content.bounds)) {
        film.frame = content.bounds;
        film.layer.cornerRadius = MIN(content.bounds.size.width, content.bounds.size.height) / 2;
        film.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

UIView *SGRGlassCapsuleInside(UIView *control, const void *key, CGSize size, BOOL prominent) {
    if (!control || !key) return nil;
    SGRGlassMode mode = glassMode();
    UIView *shape = objc_getAssociatedObject(control, key);
    if (shape && [objc_getAssociatedObject(shape, &kInsideModeKey) integerValue] != mode) {
        [shape removeFromSuperview];
        shape = nil;
    }
    if (!shape) {
        shape = newShape(mode);
        shape.accessibilityElementsHidden = YES;
        shape.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
        objc_setAssociatedObject(shape, &kInsideModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(control, key, shape, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (shape.superview != control) [control addSubview:shape];
    // First among the control's subviews, so the glyph the control draws is genuinely after the shape in the
    // tree. The shape used to be added last and pushed back with zPosition -1 instead, which sorts the
    // compositing but not what glass takes for its backdrop: on the phone the glyph above it was captured
    // into it, so the button showed a soft ghost of its icon through the glass and no icon over it
    // (issue #39, iOS 26.1). The simulator's glass does not refract and shows neither order failing, so this
    // one is ordered the plain way rather than by depth. Re-asserted on every pass the caller makes, since a
    // control that rebuilds its content puts that in at index 0 too and would end up under the shape.
    if (control.subviews.firstObject != shape) [control insertSubview:shape atIndex:0];
    shape.hidden = size.width <= 0 || size.height <= 0;
    CGRect bounds = CGRectMake(0, 0, size.width, size.height);
    if (!CGRectEqualToRect(shape.bounds, bounds)) {
        shape.bounds = bounds;
        SGShapeGlass(shape, MIN(size.width, size.height) / 2, YES);
    }
    keepFilm(shape, prominent, mode);
    CGPoint middle = CGPointMake(CGRectGetMidX(control.bounds), CGRectGetMidY(control.bounds));
    if (!CGPointEqualToPoint(shape.center, middle)) shape.center = middle;
    return shape;
}

UIView *SGRGlassInside(UIView *control, const void *key, CGFloat side) {
    return SGRGlassCapsuleInside(control, key, CGSizeMake(side, side), NO);
}

void SGRShowGlass(UIView *shape, BOOL shown) {
    if ([shape isKindOfClass:UIVisualEffectView.class]) {
        UIVisualEffectView *glass = (UIVisualEffectView *)shape;
        if ((glass.effect != nil) != shown) glass.effect = shown ? SGRGlassEffect() : nil;
    } else {
        shape.alpha = shown ? 1 : 0;
    }
}
