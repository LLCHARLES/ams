#import "SGPageStyle.h"
#import <CoreText/SFNTLayoutTypes.h>
#import "Core/SGCore.h"
#import <objc/runtime.h>

static UIFont *sg_spotifyFont;

// The dark appearance's secondary label, fixed rather than dynamic so a view that is not set dark reads it too.
UIColor *SGGrey(void) { return [UIColor colorWithRed:0xEB / 255.0 green:0xEB / 255.0 blue:0xF5 / 255.0 alpha:0.6]; }

// Spotify's typeface at the sizes of its own lists, asked for by name so the app font of Shared/Fonts follows,
// and the system font before Spotify has registered it. Grown with Dynamic Type through the accessibility
// sizes, with no cap: the rows laid out by hand measure their text from these fonts.
static UIFont *scaled(UIFontTextStyle style, CGFloat size) {
    UIFont *font = [UIFont fontWithName:@"SpotifyMixUI-Regular" size:size] ?: [UIFont systemFontOfSize:size];
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:font];
}

UIFont *SGTitleFont(void) { return scaled(UIFontTextStyleBody, 13); }
UIFont *SGSubtitleFont(void) { return scaled(UIFontTextStyleFootnote, 11); }
UIFont *SGCappedFont(UIFont *font, CGFloat largest) {
    return font.pointSize > largest ? [font fontWithSize:largest] : font;
}

UIFont *SGCategoryCappedFont(UIFontTextStyle style, UIFontWeight weight, UIContentSizeCategory largest) {
    UIContentSizeCategory current = UIApplication.sharedApplication.preferredContentSizeCategory;
    if (largest && UIContentSizeCategoryCompareToCategory(current, largest) == NSOrderedDescending) current = largest;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:current];
    CGFloat size = [UIFont preferredFontForTextStyle:style compatibleWithTraitCollection:traits].pointSize;
    return [UIFont systemFontOfSize:size weight:weight];
}

void SGPositionPinnedPreview(UITableView *table, UIView *header, CGFloat height) {
    UIEdgeInsets insets = table.contentInset;
    if (insets.top != height) {
        BOOL top = table.contentOffset.y <= 0.5 - table.adjustedContentInset.top;
        insets.top = height;
        table.contentInset = insets;
        table.verticalScrollIndicatorInsets = insets;
        if (top) table.contentOffset = CGPointMake(table.contentOffset.x, -table.adjustedContentInset.top);
    }
    header.frame = CGRectMake(0, table.contentOffset.y + table.adjustedContentInset.top - height, table.bounds.size.width, height);
    [table bringSubviewToFront:header];
}

void SGPresentInformation(UIViewController *presenter, NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    SGPresentDark(alert);
    [alert addAction:[UIAlertAction actionWithTitle:SGL(@"common.ok", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

UIFont *SGMonospacedDigitsFont(UIFont *font) {
    if (!font) return nil;
    NSArray *features = @[@{UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType), UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)}];
    UIFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{UIFontDescriptorFeatureSettingsAttribute: features}];
    return [UIFont fontWithDescriptor:descriptor size:font.pointSize];
}

BOOL SGAccessibilityTextSize(void) {
    return UIContentSizeCategoryIsAccessibilityCategory(UIApplication.sharedApplication.preferredContentSizeCategory);
}

static CGFloat textHeight(NSString *text, UIFont *font, CGFloat width) {
    if (!text.length) return 0;
    return ceil([text boundingRectWithSize:CGSizeMake(MAX(1, width), CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin
                                attributes:@{NSFontAttributeName: font} context:nil].size.height);
}

CGFloat SGSliderTextHeight(NSString *title, NSString *subtitle, CGFloat width) {
    CGFloat line = ceil(SGTitleFont().lineHeight);
    CGFloat height = SGAccessibilityTextSize() ? textHeight(title, SGTitleFont(), width) + line : line;
    return height + textHeight(subtitle, SGSubtitleFont(), width);
}

CGFloat SGLayOutSliderText(UILabel *title, UILabel *value, UILabel *subtitle, CGFloat x, CGFloat y, CGFloat width) {
    CGFloat line = ceil(title.font.lineHeight);
    BOOL stacked = SGAccessibilityTextSize();
    // Right to left, the value sits at the left end of the line and the title at the right.
    BOOL rtl = title.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    title.numberOfLines = stacked ? 0 : 1;
    value.textAlignment = stacked ? NSTextAlignmentNatural : rtl ? NSTextAlignmentLeft : NSTextAlignmentRight;
    if (stacked) {
        CGFloat height = textHeight(title.text, title.font, width);
        title.frame = CGRectMake(x, y, width, height);
        y += height;
        value.frame = CGRectMake(x, y, width, line);
    } else {
        [value sizeToFit];
        CGFloat valueWidth = MIN(width, MAX(value.bounds.size.width, 44));
        CGFloat titleWidth = MAX(1, width - valueWidth - 8);
        value.frame = CGRectMake(rtl ? x : x + width - valueWidth, y, valueWidth, line);
        title.frame = CGRectMake(rtl ? x + width - titleWidth : x, y, titleWidth, line);
    }
    y += line;
    if (subtitle && !subtitle.hidden && subtitle.text.length) {
        subtitle.numberOfLines = 0;
        CGFloat height = textHeight(subtitle.text, subtitle.font, width);
        subtitle.frame = CGRectMake(x, y, width, height);
        y += height;
    }
    return y;
}

UIFont *SGSpotifyListFont(void) { return sg_spotifyFont ?: [UIFont systemFontOfSize:13 weight:UIFontWeightBold]; }

UIImageView *SGSymbolView(NSString *name, CGFloat size, UIImageSymbolWeight weight, CGFloat box) {
    UIImage *image = [UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:weight]];
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    view.tintColor = UIColor.whiteColor;
    view.contentMode = UIViewContentModeCenter;
    view.frame = CGRectMake(0, 0, box, box);
    return view;
}

// A gray note in a wrapper view, for the table header and footer.
UIView *SGNote(NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = SGSubtitleFont();
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = SGGrey();
    label.numberOfLines = 0;
    UIView *wrapper = [UIView new];
    [wrapper addSubview:label];
    return wrapper;
}

// Header and footer views keep the height they are given, so size them to their text. Only the
// size is compared: the table moves the footer's origin itself, and reassigning on that would
// loop forever.
void SGFitNote(UITableView *table, UIView *wrapper, CGFloat top, CGFloat bottom) {
    UILabel *label = wrapper.subviews.firstObject;
    label.font = SGSubtitleFont();
    CGFloat inset = table.layoutMargins.left;
    CGFloat width = table.bounds.size.width - 2 * inset;
    CGFloat height = ceil([label sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)].height);
    label.frame = CGRectMake(inset, top, width, height);
    CGSize size = CGSizeMake(table.bounds.size.width, top + height + bottom);
    if (CGSizeEqualToSize(wrapper.bounds.size, size)) return;
    wrapper.frame = (CGRect){wrapper.frame.origin, size};
    if (wrapper == table.tableHeaderView) table.tableHeaderView = wrapper;
    else table.tableFooterView = wrapper;
}

// The bars found in a window, held weakly and hidden or not, so a layout measures them without
// walking the window's view tree (Spotify's is large, and a scroll lays the table out on every frame).
@interface SGBarsMemory : NSObject
@property (nonatomic, weak) UITableView *lastTable;
@property (nonatomic, strong) NSHashTable<UIView *> *bars;
@property (nonatomic) NSUInteger generation;
@end

@implementation SGBarsMemory
@end

static const void *kBarsMemoryKey = &kBarsMemoryKey;

static BOOL isBarClassName(const char *name) {
    return strstr(name, "NowPlaying_BarPageImpl") || strcmp(name, "_TtC23NavigationUI_TabBarImpl10TabBarView") == 0;
}

// Counts the times a bar was put into a window or taken out of one, anywhere. UIKit calls
// -didMoveToWindow on the main thread, where the layouts that read this run too.
static NSUInteger barGeneration;

// The bar classes tell the count when one of their views changes window, which is the one signal a table has
// that a bar came or went. The classes are the ones the walk below recognizes, and each is given its own
// -didMoveToWindow that counts and then runs the one it had; no other class and no UIView method is touched.
static void countBarMoves(void) {
    static unsigned int scannedCount;
    if ((unsigned int)objc_getClassList(NULL, 0) == scannedCount) return;
    static NSHashTable<Class> *hooked;
    if (!hooked) hooked = [NSHashTable hashTableWithOptions:NSPointerFunctionsOpaqueMemory | NSPointerFunctionsOpaquePersonality];
    SEL moved = @selector(didMoveToWindow);
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    scannedCount = count;
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!isBarClassName(class_getName(cls))) continue;
        Class ancestor = cls;
        while (ancestor && ancestor != UIView.class) ancestor = class_getSuperclass(ancestor);
        if (!ancestor || [hooked containsObject:cls]) continue;
        [hooked addObject:cls];
        // Instances may already have moved into a cached window before this hook.
        barGeneration++;
        IMP original = class_getMethodImplementation(cls, moved);
        class_replaceMethod(cls, moved, imp_implementationWithBlock(^(UIView *view) {
            barGeneration++;
            ((void (*)(UIView *, SEL))original)(view, moved);
        }), "v16@0:8");
    }
    free(classes);
}

// All pages in this window share its walk until a bar comes or goes.
static NSArray<UIView *> *barsIn(UIWindow *window, UITableView *table) {
    SGBarsMemory *memory = objc_getAssociatedObject(window, kBarsMemoryKey);
    if (memory.lastTable != table || memory.generation != barGeneration) countBarMoves();
    memory.lastTable = table;
    if (memory && memory.generation == barGeneration) return memory.bars.allObjects;
    NSMutableArray<UIView *> *found = [NSMutableArray array];
    SGForEachView(window, ^(UIView *v) {
        if (isBarClassName(class_getName(v.class))) [found addObject:v];
    });
    if (!memory) {
        memory = [SGBarsMemory new];
        memory.lastTable = table;
        objc_setAssociatedObject(window, kBarsMemoryKey, memory, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    memory.bars = [NSHashTable weakObjectsHashTable];
    for (UIView *bar in found) [memory.bars addObject:bar];
    memory.generation = barGeneration;
    return found;
}

static CGFloat barsHeight(UITableView *table) {
    UIWindow *window = table.window;
    if (!window) return 0;
    CGFloat top = window.bounds.size.height;
    for (UIView *v in barsIn(window, table)) {
        if (v.hidden || v.alpha == 0 || v.bounds.size.height == 0) continue;
        top = MIN(top, SGFrameIn(v, window).origin.y);
    }
    return window.bounds.size.height - top;
}

// The now playing bar and the tab bar float over the content, and the safe area does not cover
// them, so the pages inset themselves by however much of the window the bars take.
void SGInsetForBars(UITableView *table) {
    CGFloat bottom = MAX(0, barsHeight(table) - table.safeAreaInsets.bottom);
    if (table.contentInset.bottom == bottom) return;
    UIEdgeInsets inset = table.contentInset;
    inset.bottom = bottom;
    table.contentInset = inset;
    table.verticalScrollIndicatorInsets = inset;
}

// The pages follow the running look's accent color, read here by its key so the page framework depends on no
// layer: the native look's (Native/Appearance) or the redesign's (Redesigned/Kit/SGRAccent.h).
static NSString *const kAccentKey = @"spotifyglass.accent";
static NSString *const kRedesignAccentKey = @"spotifyglass.redesign.accent";

static UIColor *lookAccent(void) {
    NSInteger rgb = SGInt(SGRedesignedUI() ? kRedesignAccentKey : kAccentKey, -1);
    if (rgb < 0 || rgb > 0xFFFFFF) return nil;
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

UIColor *SGGreen(void) { return lookAccent() ?: [UIColor colorWithRed:0x1E / 255.0 green:0xD7 / 255.0 blue:0x60 / 255.0 alpha:1]; }
// Relative sRGB luminance, shared by filled controls and small marks on the dark cards.
static CGFloat luminance(UIColor *color) {
    CGFloat r = 0, g = 0, b = 0, a = 1;
    [color getRed:&r green:&g blue:&b alpha:&a];
    CGFloat (^linear)(CGFloat) = ^CGFloat(CGFloat c) { return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); };
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b);
}

UIColor *SGOnAccent(void) {
    CGFloat light = luminance(SGGreen());
    return (light + 0.05) / 0.05 >= 1.05 / (light + 0.05) ? UIColor.blackColor : UIColor.whiteColor;
}

UIColor *SGAccentMark(void) {
    CGFloat contrast = (luminance(SGGreen()) + 0.05) / (luminance(SGCardBackground()) + 0.05);
    return contrast >= (UIAccessibilityDarkerSystemColorsEnabled() ? 4.5 : 3) ? SGGreen() : UIColor.whiteColor;
}

// The dark appearance's system red, and its grouped background and the cards on it, whichever look runs.
UIColor *SGRed(void) { return [UIColor colorWithRed:0xFF / 255.0 green:0x45 / 255.0 blue:0x3A / 255.0 alpha:1]; }
UIColor *SGPageBackground(void) { return UIColor.blackColor; }
UIColor *SGCardBackground(void) { return [UIColor colorWithRed:0x1C / 255.0 green:0x1C / 255.0 blue:0x1E / 255.0 alpha:1]; }

// 29pt with a 7pt continuous corner and the glyph at 16pt, the size Settings draws its own; a row's title
// starts 13pt after it, as before the tiles grew, so the pages' own separator insets still line up.
const CGFloat SGTileRowInset = 16 + 29 + 13;

UIImage *SGTileImageTinted(NSString *symbol, UIColor *color) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
    UIImage *glyph = [[UIImage systemImageNamed:symbol withConfiguration:config] imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    CGRect box = CGRectMake(0, 0, 29, 29);
    // A system color is drawn in its dark appearance, the one the pages wear, whatever the phone's.
    color = [color resolvedColorWithTraitCollection:[UITraitCollection traitCollectionWithUserInterfaceStyle:UIUserInterfaceStyleDark]];
    UIImage *tile = [[[UIGraphicsImageRenderer alloc] initWithSize:box.size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:box cornerRadius:7] fill];
        // A wide glyph is fitted inside the square's padding rather than over its edge.
        CGSize size = glyph.size;
        CGFloat fit = MIN(1, MIN(21 / size.width, 21 / size.height));
        size = CGSizeMake(size.width * fit, size.height * fit);
        [glyph drawInRect:CGRectMake((box.size.width - size.width) / 2, (box.size.height - size.height) / 2, size.width, size.height)];
    }];
    return [tile imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *SGTileImage(NSString *symbol) {
    return SGTileImageTinted(symbol, [UIColor colorWithRed:0x8E / 255.0 green:0x8E / 255.0 blue:0x93 / 255.0 alpha:1]);
}

UIImageView *SGChevronView(void) {
    UIImageView *chevron = SGSymbolView(@"chevron.right", 13, UIImageSymbolWeightBold, 16);
    // Points the way the page goes: to the left in a right-to-left layout.
    chevron.image = chevron.image.imageFlippedForRightToLeftLayoutDirection;
    return chevron;
}

CGFloat SGSectionHeaderHeight(void) { return MAX(38, ceil(SGSubtitleFont().lineHeight) + 14); }
const CGFloat SGSectionGap = 20;

// Every page below draws the same row: a 13pt white title over an 11pt gray subtitle in Spotify's typeface,
// with an optional symbol in the leading slot.
void SGFillCell(UITableViewCell *cell, NSString *title, NSString *subtitle, UIColor *color, NSString *symbolName) {
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = title;
    content.secondaryText = subtitle;
    content.textProperties.font = SGTitleFont();
    content.textProperties.color = color ?: UIColor.whiteColor;
    content.secondaryTextProperties.font = SGSubtitleFont();
    content.secondaryTextProperties.color = SGGrey();
    content.textToSecondaryTextVerticalPadding = 2;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(11, 16, 11, 16);
    if (symbolName) {
        content.image = [UIImage systemImageNamed:symbolName withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular]];
        content.imageProperties.tintColor = color ?: UIColor.whiteColor;
        content.imageToTextPadding = 13;
    }
    cell.contentConfiguration = content;
    cell.backgroundColor = SGCardBackground();
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
}

UIView *SGSectionHeader(UITableView *table, NSString *title) {
    UILabel *label = [UILabel new];
    label.text = title.uppercaseString;
    label.font = SGSubtitleFont();
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = SGGrey();
    // On the header's foot, 7pt over the card, however tall Dynamic Type makes the line.
    CGFloat height = ceil(label.font.lineHeight);
    label.frame = CGRectMake(16, SGSectionHeaderHeight() - 7 - height, table.bounds.size.width - 32, height);
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, SGSectionHeaderHeight())];
    [header addSubview:label];
    return header;
}

static const CGFloat kFooterTop = 8, kFooterBottom = 4;

static CGFloat footerTextHeight(UITableView *table, NSString *text) {
    // An inset grouped table narrows its footers by its side margins, and the label wraps at that width.
    CGFloat inset = table.style == UITableViewStyleInsetGrouped ? table.layoutMargins.left + table.layoutMargins.right : 0;
    CGFloat width = MAX(table.bounds.size.width - inset - 32, 100);
    return ceil([text boundingRectWithSize:CGSizeMake(width, CGFLOAT_MAX)
                                   options:NSStringDrawingUsesLineFragmentOrigin
                                attributes:@{NSFontAttributeName: SGSubtitleFont()}
                                   context:nil].size.height);
}

UIView *SGSectionFooter(UITableView *table, NSString *text) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = SGSubtitleFont();
    label.adjustsFontForContentSizeCategory = YES;
    label.textColor = SGGrey();
    label.numberOfLines = 0;
    label.frame = CGRectMake(16, kFooterTop, table.bounds.size.width - 32, footerTextHeight(table, text));
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, table.bounds.size.width, SGSectionFooterHeight(table, text))];
    [footer addSubview:label];
    return footer;
}

CGFloat SGSectionFooterHeight(UITableView *table, NSString *text) {
    return kFooterTop + footerTextHeight(table, text) + kFooterBottom;
}

UITableViewCell *SGDequeueCell(UITableView *table, NSString *identifier) {
    return [table dequeueReusableCellWithIdentifier:identifier]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier];
}

// Spotify's list titles carry its typeface at 13pt.
void SGAdoptFonts(UIView *list, UIView *row) {
    if (sg_spotifyFont) return;
    SGForEachView(list, ^(UIView *v) {
        if (sg_spotifyFont || ![v isKindOfClass:UILabel.class] || SGIsInside(v, row)) return;
        UILabel *label = (UILabel *)v;
        if (label.text.length >= 2 && label.font.pointSize == 13) sg_spotifyFont = label.font;
    });
}

UIViewController *SGTopController(void) {
    UIViewController *top = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden) continue;
            if (!top || window.isKeyWindow) top = window.rootViewController;
        }
    }
    while (top.presentedViewController) top = top.presentedViewController;
    return top;
}

@interface SGPopoverStyle : NSObject <UIPopoverPresentationControllerDelegate>
@end

@implementation SGPopoverStyle
- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traits {
    return UIModalPresentationNone;
}
@end

void SGPresentPopover(UIViewController *panel, UIView *from) {
    if (!from.window) return;
    static SGPopoverStyle *style;
    if (!style) style = [SGPopoverStyle new];
    panel.modalPresentationStyle = UIModalPresentationPopover;
    UIPopoverPresentationController *popover = panel.popoverPresentationController;
    popover.sourceView = from;
    popover.sourceRect = from.bounds;
    popover.permittedArrowDirections = UIPopoverArrowDirectionUp | UIPopoverArrowDirectionDown;
    popover.delegate = style;
    SGPresentDark(panel);
    __block int tries = 0;
    __block void (^present)(void);
    present = ^{
        UIViewController *top = SGTopController();
        if (!from.window || from.window != top.viewIfLoaded.window) {
            present = nil;
            return;
        }
        if ((top.isBeingDismissed || top.isBeingPresented || top.transitionCoordinator) && ++tries < 20) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), present);
            return;
        }
        present = nil;
        [top presentViewController:panel animated:YES completion:nil];
    };
    dispatch_async(dispatch_get_main_queue(), present);
}

// The fork's repo. Its links stay hidden while this is nil.
NSString *const SGRepoURL = @"https://github.com/oneulddu/Retrine";

void SGOpenURL(NSString *url) {
    NSURL *target = url ? [NSURL URLWithString:url] : nil;
    if (![target.scheme.lowercaseString isEqual:@"https"] || !target.host.length) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication openURL:target options:@{} completionHandler:nil];
    });
}
