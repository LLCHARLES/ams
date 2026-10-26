#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import "SGRTokens.h"
#import "SGRAccent.h"

const CGFloat SGRSideMargin = 16;
const CGFloat SGRGrid = 8;
const CGFloat SGRRadiusArtwork = 12;
const CGFloat SGRRadiusCard = 16;
const CGFloat SGRRadiusCover = 8;
const CGFloat SGRRadiusThumb = 6;
const CGFloat SGRGlassCircleSize = 44;
const CGFloat SGRActionHeight = 48;
const CGFloat SGRActionSpacing = 12;
const CGFloat SGRGlassSpacing = 16;
const NSTimeInterval SGRCrossfade = 0.35;

// A layout spring settles in about this long without overshooting; a press gives a little back.
static const NSTimeInterval kLayoutDuration = 0.45, kPressDuration = 0.32;
// The tab bar's minimize, fitted to the Music app's on iOS 26: in a screen recording at 60 fps its card rose 61 pt
// 29% of the way in 0.04 s, 61% in 0.07, 90% in 0.12, overshot by 4% at 0.2 s and had settled by 0.4, an
// underdamped spring of some 0.3 s with a damping ratio of 0.7. A spring that settles in 0.26 s with no overshoot
// took the card most of the way in two frames and read as a snap; one of 0.42 s with a bounce of 0.1 got there at
// half the Music app's pace and read as a glide.
static const NSTimeInterval kBarDuration = 0.3;
static const CGFloat kBarBounce = 0.3;
static const CGFloat kPressDamping = 0.62;
// A response lands within the press feedback's budget, on a curve that is most of the way there at once.
static const NSTimeInterval kRespondDuration = 0.2;
// An exit is quicker still; Native/Player/PlayerGestures.x keeps its own copy of the value.
static const NSTimeInterval kExitDuration = 0.15;

UIColor *SGRPrimary(void) {
    return UIColor.whiteColor;
}

UIColor *SGRSecondary(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.80 : 0.65];
}

UIColor *SGRTertiary(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.60 : 0.40];
}

// Read per call: the accent is stored as it is picked, and the color row reads it the same way.
UIColor *SGRAccent(void) {
    return SGRAccentColor() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1];
}

UIColor *SGRNeutralField(void) {
    return [UIColor colorWithRed:0x12 / 255.0 green:0x12 / 255.0 blue:0x12 / 255.0 alpha:1];
}

UIColor *SGRSolidGlassFill(void) {
    return [UIColor colorWithWhite:1 alpha:0.16];
}

UIColor *SGRHairline(void) {
    return [UIColor colorWithWhite:1 alpha:SGRIncreaseContrast() ? 0.20 : 0.12];
}

UIColor *SGRElevated(UIColor *field) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    if (![field getRed:&r green:&g blue:&b alpha:&a]) return [UIColor colorWithWhite:1 alpha:0.08];
    // 12% toward white keeps a card on a black field clear of the grays SGRAmoled.x turns black.
    CGFloat lift = 0.12;
    return [UIColor colorWithRed:r + (1 - r) * lift green:g + (1 - g) * lift blue:b + (1 - b) * lift alpha:1];
}

UIFont *SGRFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    // Asked for on every layout pass of the Search and Library headers. A font is immutable and the same inputs
    // give the same one, so each is kept per input; the live category above and Bold Text are read on every call,
    // so a Dynamic Type change is a new key at once.
    // A string key: an array's hash is its count, so array keys would all collide.
    static NSMutableDictionary<NSString *, UIFont *> *fonts;
    if (!fonts) fonts = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@|%g|%@|%@|%d", style, weight, largest ?: @"", current ?: @"", UIAccessibilityIsBoldTextEnabled()];
    UIFont *font = fonts[key];
    if (font) return font;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    font = [UIFont systemFontOfSize:size weight:weight];
    fonts[key] = font;
    return font;
}

UIFont *SGRMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL SGRReduceMotion(void) {
    return UIAccessibilityIsReduceMotionEnabled();
}

BOOL SGRReduceTransparency(void) {
    return UIAccessibilityIsReduceTransparencyEnabled();
}

BOOL SGRIncreaseContrast(void) {
    return UIAccessibilityDarkerSystemColorsEnabled();
}

// A perceptual duration, as the system's own springs take it: the older call's duration is the time to
// settle, which front-loads the move.
static void barSpring(NSTimeInterval delay, UIViewAnimationOptions options, void (^animations)(void), void (^completion)(BOOL)) {
    if (@available(iOS 17.0, *)) {
        [UIView animateWithSpringDuration:kBarDuration bounce:kBarBounce initialSpringVelocity:0 delay:delay options:options animations:animations completion:completion];
    } else {
        [UIView animateWithDuration:kBarDuration delay:delay usingSpringWithDamping:0.9 initialSpringVelocity:0 options:options animations:animations completion:completion];
    }
}

void SGRAnimateBarAfter(NSTimeInterval delay, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (SGRReduceMotion() || delay <= 0) {
        SGRAnimate(SGRMotionBar, animations, completion);
        return;
    }
    barSpring(delay, UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState, animations, completion);
}

CASpringAnimation *SGRBarSpringAnimation(NSString *keyPath, id from, NSTimeInterval delay) {
    if (SGRReduceMotion()) return nil;
    CASpringAnimation *spring;
    if (@available(iOS 17.0, *)) {
        spring = [[CASpringAnimation alloc] initWithPerceptualDuration:kBarDuration bounce:kBarBounce];
    } else {
        spring = [CASpringAnimation animationWithKeyPath:keyPath];
        spring.damping = 2 * 0.9 * sqrt(spring.stiffness * spring.mass);
    }
    spring.keyPath = keyPath;
    spring.fromValue = from;
    spring.duration = spring.settlingDuration;
    if (delay > 0) {
        spring.beginTime = CACurrentMediaTime() + delay;
        spring.fillMode = kCAFillModeBackwards;
    }
    return spring;
}

void SGRAnimate(SGRMotion motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if ((motion == SGRMotionLayout || motion == SGRMotionPress || motion == SGRMotionBar) && SGRReduceMotion()) {
        [UIView performWithoutAnimation:animations];
        if (completion) completion(YES);
        return;
    }
    UIViewAnimationOptions options = UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState;
    switch (motion) {
        case SGRMotionLayout:
            [UIView animateWithDuration:kLayoutDuration delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionBar:
            barSpring(0, options, animations, completion);
            break;
        case SGRMotionPress:
            [UIView animateWithDuration:kPressDuration delay:0 usingSpringWithDamping:kPressDamping initialSpringVelocity:0 options:options animations:animations completion:completion];
            break;
        case SGRMotionFade:
            [UIView animateWithDuration:SGRCrossfade delay:0 options:options | UIViewAnimationOptionCurveEaseInOut animations:animations completion:completion];
            break;
        case SGRMotionRespond: {
            // UIView's own curves are too soft for this; a property animator takes any curve, and like the
            // others it starts from what is on screen, so it can take over a fade halfway out.
            UICubicTimingParameters *curve = [[UICubicTimingParameters alloc] initWithControlPoint1:CGPointMake(0.23, 1)
                                                                                     controlPoint2:CGPointMake(0.32, 1)];
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:kRespondDuration timingParameters:curve];
            [animator addAnimations:animations];
            if (completion) [animator addCompletion:^(UIViewAnimatingPosition position) { completion(position == UIViewAnimatingPositionEnd); }];
            [animator startAnimation];
            break;
        }
        case SGRMotionExit:
            [UIView animateWithDuration:kExitDuration delay:0 options:options | UIViewAnimationOptionCurveEaseOut animations:animations completion:completion];
            break;
    }
}

void SGRAnimateLayout(UIView *host, void (^animations)(void), void (^completion)(BOOL finished)) {
    if (!animations) return;
    if (!SGRReduceMotion() || !host.window) {
        SGRAnimate(SGRMotionLayout, animations, completion);
        return;
    }
    // Snapshot the host, so the layout changes in place while the old picture dissolves.
    [UIView transitionWithView:host duration:0.2
        options:UIViewAnimationOptionTransitionCrossDissolve | UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:animations completion:completion];
}
