// Search redesign: each category card as Liquid Glass tinted by its own color. Under the glass, the card's color runs
// diagonally from itself at the top leading corner to a darker shade of it at the bottom trailing one; the glass is the
// clear style with that color at 35% for its tint, so its rim catches the color and its body stays as vivid as
// Spotify's card. The cover stays Spotify's, over the glass, and the title is the redesign's own over Spotify's
// (placeTitle), one size and one inset on every card. The card takes the card radius, continuous; and the card gives a
// little under a press, which Spotify showed by darkening the color
// the glass now covers. Picked on the iOS 27 simulator against plain tinted glass (flat on black), regular glass over
// the color (muddy) and the cover under clear glass (smeared), 2026-09-17.
//
// Under Reduce Transparency, or before iOS 26, the card is the color alone.
//
// Tree (trees/clean/search/01.txt:332-339): Control<Box> id=Components.UI.CategoryCardBrowse 177x108 >
// Encore.Box 177x108 clips > UIView r=4 clips (the Box's content view) > Encore.ImageView (the cover, turned 25 degrees
// at the trailing edge) and SPTEncoreLabel {8, 8} 120x18 (the title). The color is in no view: Box's layoutSubviews sets
// the path and the fill color of its animationLayer, a CAShapeLayer among its layer's sublayers, from the card's color
// set on every pass (Encore_LayoutKit.Box's fields, and -[Box layoutSubviews] calling setPath: and setFillColor:,
// 2026-09-17). So the color is read off that layer, and the layer is hidden rather than cleared, since Spotify fills it again.
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRKit.h"
#import "Search.h"

// The tint the glass takes of the card's color, and how dark the far corner of the color under it gets.
static const CGFloat kTintAlpha = 0.35;
static const CGFloat kFarBrightness = 0.55;
// Where the title's top leading corner is, clear of the larger corner, and how many lines it may take.
static const CGFloat kTitleInset = 12;
static const NSInteger kTitleLines = 2;
static const CGFloat kPressScale = 0.96;

static char kPartsKey, kRoundedKey, kTitleKey, kTitleWatchedKey;

@interface UIView (SGREncoreBox)
- (BOOL)isHighlighted;
@end

@interface SGRSearchCardPlate : UIView
@end

@implementation SGRSearchCardPlate
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

@interface SGRSearchCardParts : NSObject
@property (nonatomic) SGRSearchCardPlate *plate;
@property (nonatomic) UIVisualEffectView *glass;
@property (nonatomic) UIColor *color;
@end

@implementation SGRSearchCardParts
@end

static NSMutableSet<NSString *> *sg_loggedMessages;
#define kLogFormat @"redesign search: %@"

static BOOL isCategoryCard(UIView *box) {
    return [box.superview.accessibilityIdentifier isEqualToString:@"Components.UI.CategoryCardBrowse"];
}

// The Box's animationLayer: a shape layer no view owns.
static CAShapeLayer *fillLayerOf(UIView *box) {
    for (CALayer *layer in box.layer.sublayers) {
        if ([layer isKindOfClass:CAShapeLayer.class] && ![layer.delegate isKindOfClass:UIView.class]) return (CAShapeLayer *)layer;
    }
    return nil;
}

// Any other shape layer of the Box's that paints goes too: the glass is the card's only surface.
static void hideFills(UIView *box) {
    for (CALayer *layer in box.layer.sublayers) {
        if (![layer isKindOfClass:CAShapeLayer.class] || [layer.delegate isKindOfClass:UIView.class] || layer.hidden) continue;
        if (((CAShapeLayer *)layer).fillColor) layer.hidden = YES;
    }
}

// The Box's content view: its one subview of its own size that clips.
static UIView *contentOf(UIView *box) {
    for (UIView *sub in box.subviews) {
        if (sub.clipsToBounds && CGSizeEqualToSize(sub.bounds.size, box.bounds.size)) return sub;
    }
    return nil;
}

static void roundCorners(UIView *view, CGFloat radius) {
    CALayer *layer = view.layer;
    if (layer.cornerRadius != radius) layer.cornerRadius = radius;
    if (layer.cornerCurve != kCACornerCurveContinuous) layer.cornerCurve = kCACornerCurveContinuous;
}

static UIColor *darker(UIColor *color) {
    CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
    if (![color getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha]) return color;
    return [UIColor colorWithHue:hue saturation:saturation brightness:brightness * kFarBrightness alpha:alpha];
}

static BOOL glassAllowed(void) {
    if (SGRReduceTransparency()) return NO;
    if (@available(iOS 26.0, *)) return YES;
    return NO;
}

static SGRSearchCardParts *partsIn(UIView *box, UIView *content) {
    SGRSearchCardParts *parts = objc_getAssociatedObject(box, &kPartsKey);
    if (!parts) {
        parts = [SGRSearchCardParts new];
        SGRSearchCardPlate *plate = [SGRSearchCardPlate new];
        plate.userInteractionEnabled = NO;
        plate.accessibilityElementsHidden = YES;
        plate.layer.zPosition = -2;
        CAGradientLayer *gradient = (CAGradientLayer *)plate.layer;
        gradient.startPoint = CGPointMake(0, 0);
        gradient.endPoint = CGPointMake(1, 1);
        parts.plate = plate;
        objc_setAssociatedObject(box, &kPartsKey, parts, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Behind the cover and the title whatever order Spotify keeps its own views in, by depth.
    if (parts.plate.superview != content) [content insertSubview:parts.plate atIndex:0];
    if (glassAllowed() && !parts.glass) {
        UIVisualEffectView *glass = [UIVisualEffectView new];
        // Dark like every glass of the redesign's, rather than by grace of the navigation stack Spotify
        // hosts the page in (Navbar/TabBar.x).
        glass.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        glass.userInteractionEnabled = NO;
        glass.accessibilityElementsHidden = YES;
        glass.layer.zPosition = -1;
        parts.glass = glass;
        parts.color = nil;
    }
    if (parts.glass && parts.glass.superview != content) [content insertSubview:parts.glass aboveSubview:parts.plate];
    if (parts.glass) parts.glass.hidden = !glassAllowed();
    return parts;
}

static void paint(SGRSearchCardParts *parts, UIColor *color) {
    if (parts.color && CGColorEqualToColor(parts.color.CGColor, color.CGColor)) return;
    parts.color = color;
    ((CAGradientLayer *)parts.plate.layer).colors = @[(id)color.CGColor, (id)darker(color).CGColor];
    if (@available(iOS 26.0, *)) {
        if (parts.glass) {
            UIGlassEffect *effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleClear];
            effect.tintColor = [color colorWithAlphaComponent:kTintAlpha];
            parts.glass.effect = effect;
        }
    }
}

// The title the Music app's tiles have: one size and weight on every card (Spotify draws 16 or 14 by the length of the
// name), kTitleInset in from the top leading corner on every card, on up to kTitleLines lines as wide as Spotify's
// label, which keeps clear of the turned cover. Spotify's label goes transparent and still measures the card; this one
// takes its text and color on every pass of the content view and on every text Spotify sets on its label (a reused
// card is given its new name without a pass), so it never shows the last card's.
static UILabel *spotifyTitleIn(UIView *content, UIView **holder) {
    for (UIView *sub in content.subviews) {
        if (![NSStringFromClass(sub.class) containsString:@"EncoreLabel"]) continue;
        for (UIView *inner in sub.subviews) {
            if (![inner isKindOfClass:UILabel.class]) continue;
            if (holder) *holder = sub;
            return (UILabel *)inner;
        }
    }
    return nil;
}

static void placeTitle(UIView *content) {
    UIView *holder = nil;
    UILabel *theirs = spotifyTitleIn(content, &holder);
    UILabel *mine = objc_getAssociatedObject(content, &kTitleKey);
    if (!theirs) {
        mine.hidden = YES;
        return;
    }
    if (!mine) {
        mine = [UILabel new];
        mine.numberOfLines = kTitleLines;
        mine.lineBreakMode = NSLineBreakByTruncatingTail;
        mine.userInteractionEnabled = NO;
        mine.accessibilityElementsHidden = YES;
        objc_setAssociatedObject(content, &kTitleKey, mine, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (mine.superview != content) [content addSubview:mine];
    else if (content.subviews.lastObject != mine) [content bringSubviewToFront:mine];
    mine.hidden = NO;
    if (!objc_getAssociatedObject(theirs, &kTitleWatchedKey)) {
        objc_setAssociatedObject(theirs, &kTitleWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakContent = content;
        SGRObserveText(theirs, ^(UILabel *label) { if (weakContent) placeTitle(weakContent); });
    }
    UIFont *font = SGCategoryCappedFont(UIFontTextStyleHeadline, UIFontWeightSemibold, UIContentSizeCategoryLarge);
    if (![mine.font isEqual:font]) mine.font = font;
    if (![mine.text ?: @"" isEqualToString:theirs.text ?: @""]) mine.text = theirs.text;
    if (theirs.textColor && ![mine.textColor isEqual:theirs.textColor]) mine.textColor = theirs.textColor;
    if (theirs.alpha != 0) theirs.alpha = 0;
    CGFloat width = MIN(holder.bounds.size.width, content.bounds.size.width - 2 * kTitleInset);
    CGFloat height = ceil([mine sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    BOOL rtl = content.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    mine.textAlignment = NSTextAlignmentNatural;
    CGRect frame = CGRectMake(rtl ? content.bounds.size.width - kTitleInset - width : kTitleInset, kTitleInset, width, height);
    if (!CGRectEqualToRect(mine.frame, frame)) mine.frame = frame;
}

static void roundCover(UIView *content) {
    for (UIView *sub in content.subviews) {
        if (![sub.accessibilityIdentifier isEqualToString:@"Encore.ImageView"]) continue;
        for (UIView *image in sub.subviews) {
            if (![image isKindOfClass:UIImageView.class]) continue;
            roundCorners(image, SGRRadiusThumb);
            if (!image.layer.masksToBounds) image.layer.masksToBounds = YES;
        }
    }
}

static void style(UIView *box) {
    if (!isCategoryCard(box)) return;
    UIView *content = contentOf(box);
    CAShapeLayer *fill = fillLayerOf(box);
    if (!content || !fill) {
        SGLogOnce(&sg_loggedMessages, ([NSString stringWithFormat:@"a category card without its %@, left as Spotify's", content ? @"fill layer" : @"content view"]), kLogFormat);
        return;
    }
    // A pressed card's fill is Spotify's pressed shade; the color is taken while it is not pressed.
    CGColorRef fillColor = fill.fillColor;
    SGRSearchCardParts *parts = partsIn(box, content);
    if (fillColor && CGColorGetAlpha(fillColor) > 0 && ![box isHighlighted]) paint(parts, [UIColor colorWithCGColor:fillColor]);
    if (!parts.color) return;
    hideFills(box);

    // The card is cut at the card radius by the Box, which clips already and which Spotify gives no radius. Spotify puts
    // its own 4pt back on the content view between layout passes, and the color and the cover then showed past the glass
    // at the corners (on the phone, 2026-09-17); the content view keeps the card radius only for as long as it lasts.
    if (content.layer.cornerRadius != SGRRadiusCard && objc_getAssociatedObject(box, &kRoundedKey)) {
        SGLogOnce(&sg_loggedMessages, ([NSString stringWithFormat:@"Spotify set a card's content radius back to %.0f; the Box's corner holds", content.layer.cornerRadius]), kLogFormat);
    }
    objc_setAssociatedObject(box, &kRoundedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    roundCorners(box, SGRRadiusCard);
    if (!box.layer.masksToBounds) box.layer.masksToBounds = YES;
    roundCorners(content, SGRRadiusCard);
    CGRect bounds = content.bounds;
    if (!CGRectEqualToRect(parts.plate.frame, bounds)) parts.plate.frame = bounds;
    if (parts.glass && !CGRectEqualToRect(parts.glass.frame, bounds)) {
        parts.glass.frame = bounds;
        SGShapeGlass(parts.glass, SGRRadiusCard, NO);
    }
    placeTitle(content);
    if (!objc_getAssociatedObject(content, &kTitleWatchedKey)) {
        objc_setAssociatedObject(content, &kTitleWatchedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRObserveLayout(content, ^(UIView *view) { placeTitle(view); });
    }
    roundCover(content);
    SGLogOnce(&sg_loggedMessages, parts.glass ? @"category cards on tinted glass" : @"category cards on their color, no glass", kLogFormat);
}

%hook _TtCE16Encore_LayoutKitO16EncoreFoundation6Encore3Box
- (void)layoutSubviews {
    %orig;
    style((UIView *)self);
}

- (void)setHighlighted:(BOOL)highlighted {
    UIView *box = (UIView *)self;
    BOOL was = [box isHighlighted];
    %orig;
    if (was == highlighted || !isCategoryCard(box)) return;
    SGRAnimate(SGRMotionPress, ^{
        box.transform = highlighted ? CGAffineTransformMakeScale(kPressScale, kPressScale) : CGAffineTransformIdentity;
    }, nil);
}
%end

%ctor {
    if (!SGRedesignedUI()) return;
    // Switched off (SGRKeySearchGlassCards), the cards are Spotify's own.
    if (!SGEnabled(SGRKeySearchGlassCards)) return;
    %init;
    SGRequireClasses(@[@"_TtCE16Encore_LayoutKitO16EncoreFoundation6Encore3Box"]);
}
