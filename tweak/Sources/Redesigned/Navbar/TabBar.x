// Tab bar: Spotify's own bar stays where it is but goes invisible, and a system UITabBar sits on top
// of it. On iOS 26+ with UIDesignRequiresCompatibility off, UIKit draws that bar as real Liquid Glass
// (selection bubble, lensing, light/dark adaptation) with no glass API of ours. Spotify's bar keeps
// its frame, so the page insets and the now playing bar stay where Spotify puts them; where the system
// bar is taller than Spotify's, Spotify is made to leave it the room (see "room for the glass bar").
//
// A tab picked on the system bar is passed on as a tap on the hidden Spotify item it mirrors, and the
// system bar's selection follows whichever Spotify label is painted white, or the tab of the mod's own whose
// page is up (SGRNavbarLitTab), which Spotify does not know of. Navbar.x composes the
// hidden row, so its order, hidden tabs and tabs of the mod's own carry over. Always on in the redesign.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView of
//   ElementContentView<TabBarItemElement>, each with an SPTEncoreIconView and an SPTEncoreLabel.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Redesigned/Kit/SGRTokens.h"
#import "Redesigned/Kit/SGRGlass.h"
#import "Redesigned/NowPlayingBar/NowPlayingBar.h"
#import "Settings/SGPage.h"
#import "Headers/SPTEncoreIconView.h"
#import "Shared/Navigation/TabIcons.h"
#import "BarGeometry.h"
#import <objc/message.h>

static char kBarKey, kApartBarKey, kHostKey, kFadeKey, kItemIconKey;
// On a UITabBarItem: the SF Symbol Apple symbols drew it with, none for a glyph off the tab's own icon (fillBar).
static char kItemSymbolKey;
// On a UITabBarItem: the keys of the icons its image and selectedImage were drawn from (glyphKeysOf, fillBar).
static char kGlyphKeysKey;
static const NSUInteger kMinimumMinimizedTabs = 2;
static __weak UIView *sg_stockBar;
static NSUInteger sg_syncGeneration;
static CGFloat sg_room, sg_glassHeight;   // see "room for the glass bar"
// The split tabs the expanded row has (syncBar), and that row's glass in the window as the now playing card was last
// told of it, CGRectNull for none (see "the glass row").
static NSUInteger sg_rowApartCount;
static CGRect sg_glassRow = {{INFINITY, INFINITY}, {0, 0}};
// The minimized row's slot for the card in the window as noteGlassRow last saw it, CGRectNull for none.
static CGRect sg_inlineSlot = {{INFINITY, INFINITY}, {0, 0}};
// See "minimized". sg_keepApart holds the second bar on screen while the main one grows back under it.
static BOOL sg_minimized, sg_keepApart;

@interface SGRSystemTabBar : UITabBar <UITabBarDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *stockBar;
@property (nonatomic, copy) NSArray<UIView *> *sources;
// Only the main bar schedules retries, including missing glyphs on its partner.
@property (nonatomic, copy) NSArray<UIView *> *retrySources;
@property (nonatomic) NSUInteger glyphRetries;
@property (nonatomic, strong) NSTimer *glyphTimer;
@property (nonatomic, weak) UILongPressGestureRecognizer *hold;
@property (nonatomic) BOOL holding;
// The other bar, when the split tabs have one of their own: a tab picked on one bar clears the other's.
@property (nonatomic, weak) SGRSystemTabBar *partner;
// The item last shown selected, so a tap on it can be told from a tap that changes the tab.
@property (nonatomic, weak) UITabBarItem *shown;
// Expanded, the glass platter UIKit drew on the bar, as its distances from the bar's left and right sides at the bar
// width they were read at (see "the glass row"); a width of 0 before the first read.
@property (nonatomic) CGFloat glassLeftPt, glassRightPt, glassBarWidthPt;
@end

static void syncBar(UIView *stockBar);
static void noteGlassRow(void);
static BOOL isTabButton(UIView *view);
static BOOL isLitCopy(UIView *view, UIView *host);
static UIView *platterOf(UIView *bar);

#pragma mark - reading Spotify's items

// The items the bar shows, left to right as Navbar/Navbar.x placed them.
static NSArray<UIView *> *tabItems(UIView *tabBar) {
    NSArray<UIView *> *composed = SGRComposedTabItems(tabBar);
    if (composed.count) return composed;
    NSMutableArray<UIView *> *items = [NSMutableArray array];
    for (UIView *item in SGRowIn(tabBar).arrangedSubviews) {
        if (!item.hidden && item.bounds.size.width >= 20) [items addObject:item];
    }
    return [items sortedArrayUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@(SGFrameIn(a, tabBar).origin.x) compare:@(SGFrameIn(b, tabBar).origin.x)];
    }];
}

// Navbar.x never reorders Spotify's row and appends the mod's own tabs after it, so Home stays first.
static BOOL isHome(UIView *item, UIView *tabBar) {
    return item && item == SGRowIn(tabBar).arrangedSubviews.firstObject;
}

// A tab of the mod's own, which Navbar.x makes under a class of its own.
static BOOL isOwnTab(UIView *item) {
    return [NSStringFromClass(item.class) isEqualToString:@"SGRTabItemView"];
}

static UILabel *labelIn(UIView *item) {
    __block UILabel *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = (UILabel *)v;
    });
    return label;
}

static UIView *iconIn(UIView *item) {
    __block UIView *icon = nil;
    SGForEachView(item, ^(UIView *v) {
        if (icon || v.bounds.size.width < 2) return;
        if ([v isKindOfClass:UIImageView.class] || [NSStringFromClass(v.class) containsString:@"IconView"]) icon = v;
    });
    return icon;
}

// Spotify paints the selected tab's label white and the rest #B3B3B3.
static BOOL isActive(UIView *item) {
    UIColor *color = labelIn(item).textColor;
    CGFloat white = 0, alpha = 0, r, g, b;
    if (![color getWhite:&white alpha:&alpha] && [color getRed:&r green:&g blue:&b alpha:&alpha]) white = MIN(r, MIN(g, b));
    return white > 0.95;
}

static BOOL hasInk(UIImage *image) {
    CGImageRef cg = image.CGImage;
    size_t width = CGImageGetWidth(cg), height = CGImageGetHeight(cg);
    if (!width || !height) return NO;
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height];
    CGContextRef context = CGBitmapContextCreate(pixels.mutableBytes, width, height, 8, width, NULL, (CGBitmapInfo)kCGImageAlphaOnly);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(context);
    const uint8_t *alpha = pixels.bytes;
    for (size_t i = 0; i < pixels.length; i++) if (alpha[i] > 16) return YES;
    return NO;
}

static UIImage *renderLayer(CALayer *layer, CGSize size) {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [layer renderInContext:context.CGContext];
    }];
    return hasInk(image) ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] : nil;
}

// The SPTEncoreIcon an icon view was built with. Encore keeps it in a Swift ivar with no getter.
static id encoreIconOf(UIView *view) {
    Ivar ivar = class_getInstanceVariable(view.class, "icon");
    const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
    return type && type[0] == '@' ? object_getIvar(view, ivar) : nil;
}

// An SPTEncoreIcon's name, which is what tells two icons apart: Spotify may hand a view a new instance of the
// same glyph. Nil for an icon that does not say.
static NSString *iconName(id icon) {
    id name = [icon respondsToSelector:@selector(name)] ? [icon name] : nil;
    return [name isKindOfClass:NSString.class] ? name : nil;
}

// The filled variant of a tab's SPTEncoreIcon (-active, which fillBar's log prints), when it has one. A filled
// icon has none: its -active is itself, or the same glyph again.
static id activeVariantOf(id icon) {
    SEL selector = NSSelectorFromString(@"active");
    if (!icon || ![icon respondsToSelector:selector]) return nil;
    id variant = ((id (*)(id, SEL))objc_msgSend)(icon, selector);
    if (variant == icon || ![variant isKindOfClass:[icon class]]) return nil;
    NSString *name = iconName(icon);
    return name && [name isEqualToString:iconName(variant)] ? nil : variant;
}

// The glyph pair an icon view holds when Encore keeps it as a Swift object Objective-C cannot read, so
// encoreIconOf has nothing: from 9.1.90 the view's `icon` is an Encore.Icon carrying both glyphs, the outline and
// the filled one, and the view draws the filled one while isActive (simulator, 9.1.90: Home's view kept the same
// Encore.Icon, glyphs f1b6 and f3b5, selected or not, its isActive following the selection). Known by the reference's
// value, never followed. Nil for a view without one.
static BOOL fitsWord(id owner, Ivar field) {
    ptrdiff_t offset = ivar_getOffset(field);
    size_t size = class_getInstanceSize(object_getClass(owner));
    return offset >= 0 && size >= sizeof(uintptr_t) && (size_t)offset <= size - sizeof(uintptr_t);
}

static NSString *swiftIconKey(UIView *view) {
    static char offsetKey;
    Class cls = object_getClass(view);
    NSNumber *cached = objc_getAssociatedObject(cls, &offsetKey);
    if (!cached) {
        Ivar ivar = class_getInstanceVariable(cls, "icon");
        const char *type = ivar ? ivar_getTypeEncoding(ivar) : NULL;
        cached = @(type && !*type && fitsWord(view, ivar) ? ivar_getOffset(ivar) : -1);
        objc_setAssociatedObject(cls, &offsetKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSInteger offset = cached.integerValue;
    if (offset < 0) return nil;
    uintptr_t value;
    memcpy(&value, (const uint8_t *)(__bridge const void *)view + offset, sizeof(value));
    return value ? [NSString stringWithFormat:@"Encore.Icon %lx", (unsigned long)value] : nil;
}

// What tells the glyphs a tab's view draws from apart, the one it holds now first: an SPTEncoreIcon's name and its
// filled variant's, or the Encore.Icon of swiftIconKey. Nil for a view with neither (a tab of the mod's own drawing
// an image), which is drawn again only as another view.
static NSArray<NSString *> *glyphKeysOf(UIView *live) {
    id icon = live ? encoreIconOf(live) : nil;
    if (!icon) {
        NSString *key = live ? swiftIconKey(live) : nil;
        return key ? @[key] : nil;
    }
    NSString *name = iconName(icon), *litName = iconName(activeVariantOf(icon));
    return name ? (litName ? @[name, litName] : @[name]) : nil;
}

// `live` drawn as it is, or in the other state for a moment when it is an Encore view holding an Encore.Icon, whose
// isActive picks its glyph. Set and set back in one turn of the run loop, so nothing on screen sees it.
static UIImage *drawLive(UIView *live, BOOL active) {
    CGSize size = live.bounds.size;
    if (size.width < 2) return nil;
    SPTEncoreIconView *view = (SPTEncoreIconView *)live;
    BOOL turn = swiftIconKey(live) && [view respondsToSelector:@selector(setIsActive:)] &&
        [view respondsToSelector:@selector(isActive)] && view.isActive != active;
    if (turn) {
        view.isActive = active;
        [view layoutIfNeeded];
        [view.layer displayIfNeeded];
    }
    UIImage *image = renderLayer(view.layer, size);
    if (turn) {
        view.isActive = !active;
        [view layoutIfNeeded];
        [view.layer displayIfNeeded];
    }
    return image;
}

// One glyph of a tab, outline or filled, from the icon view `live` holds now. An SPTEncoreIcon is drawn on an
// icon view of our own, off screen, so the images do not wait for Spotify's views to lay out and paint: the filled
// glyph from its -active variant, since isActive on such a view only picks its colors, white either way, and the
// cache key names the glyph actually drawn. An Encore.Icon, a tab of the mod's own drawing an image, or an icon
// Encore would not draw off screen is drawn from `live` itself.
static UIImage *glyphOfIcon(UIView *live, BOOL active) {
    if (!live) return nil;
    CGSize size = live.bounds.size;
    id icon = encoreIconOf(live);
    if (active) icon = activeVariantOf(icon) ?: icon;
    Class viewClass = NSClassFromString(@"SPTEncoreIconView");
    if (icon && viewClass) {
        static NSCache<NSString *, UIImage *> *cache;
        if (!cache) { cache = [NSCache new]; cache.countLimit = 16; }
        NSString *key = [NSString stringWithFormat:@"%@ %d %@", iconName(icon) ?: icon, active, NSStringFromCGSize(size)];
        UIImage *cached = [cache objectForKey:key];
        if (cached) return cached;
        SPTEncoreIconView *view = [[viewClass alloc] initWithIcon:icon];
        view.frame = (CGRect){CGPointZero, size};
        [view setForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setActiveForegroundColor:)]) [view setActiveForegroundColor:UIColor.whiteColor];
        if ([view respondsToSelector:@selector(setIsActive:)]) [view setIsActive:active];
        [view layoutIfNeeded];
        UIImage *image = renderLayer(view.layer, size);
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    return drawLive(live, active);
}

// A tab's glyph from what its view holds now.
static UIImage *glyphOf(UIView *item, BOOL active) {
    return glyphOfIcon(iconIn(item), active);
}

// An SF Symbol on a tab, its filled variant on the selected tab where the symbol has one: UIKit's own symbol image
// with no size of its own, so the bar sizes and weighs it the way UIKit does every app's tab symbols, the Music app's
// included. One object per name, so setGlyphs sees the same image again and leaves the item alone.
// The Music app's Home glyph, drawn by Retrine to its measure (its tab bar at 3x, 2026-11-25): a house 71 x 72 px
// with no chimney, its roof meeting the walls 28.5 px down, the apex and the foot rounded, the eaves a little, and a
// door 20.5 px wide open at the foot whose top stands 46 px down. The same glyph in either state, as the Music app's.
static UIImage *musicHomeGlyph(void) {
    static UIImage *image;
    if (image) return image;
    const CGFloat unit = 1.0 / 3, width = 71 * unit, height = 72 * unit;
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat preferredFormat];
    format.opaque = NO;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height) format:format];
    image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGMutablePathRef path = CGPathCreateMutable();
        // Corners in px, each with the radius it is rounded by; the apex's corner stands above the drawing so that
        // its arc's top meets it.
        struct { CGFloat x, y, r; } corners[] = {
            {35.5, -2, 7}, {71, 28.5, 3}, {71, 72, 6}, {45.5, 72, 0}, {45.5, 46, 1.5},
            {25, 46, 1.5}, {25, 72, 0}, {0, 72, 6}, {0, 28.5, 3},
        };
        const int count = sizeof corners / sizeof corners[0];
        // Starting halfway along the last side, so every corner is drawn as an arc between its sides.
        CGPathMoveToPoint(path, NULL, (corners[count - 1].x + corners[0].x) / 2 * unit, (corners[count - 1].y + corners[0].y) / 2 * unit);
        for (int i = 0; i < count; i++) {
            int next = (i + 1) % count;
            CGFloat r = corners[i].r * unit;
            if (r > 0) CGPathAddArcToPoint(path, NULL, corners[i].x * unit, corners[i].y * unit, corners[next].x * unit, corners[next].y * unit, r);
            else CGPathAddLineToPoint(path, NULL, corners[i].x * unit, corners[i].y * unit);
        }
        CGPathCloseSubpath(path);
        CGContextAddPath(context.CGContext, path);
        CGContextSetFillColorWithColor(context.CGContext, UIColor.blackColor.CGColor);
        CGContextFillPath(context.CGContext);
        CGPathRelease(path);
    }];
    image = [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return image;
}

static UIImage *symbolGlyph(NSString *symbol, BOOL active) {
    static NSCache<NSString *, UIImage *> *cache;
    if (!cache) { cache = [NSCache new]; cache.countLimit = 16; }
    NSString *filled = [symbol stringByAppendingString:@".fill"];
    NSString *name = active && [UIImage systemImageNamed:filled] ? filled : symbol;
    UIImage *image = [cache objectForKey:name];
    if (image) return image;
    image = [[UIImage systemImageNamed:name] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    if (image) [cache setObject:image forKey:name];
    return image;
}

// A tab's icon as a tab of the mod's own is given it (SGTabIconView): an SF Symbol as the symbol itself, an Encore
// glyph drawn white at the glyphs' size.
static UIImage *iconGlyph(NSString *icon, BOOL symbol, BOOL active) {
    UIView *view = SGTabIconView(icon, symbol, UIColor.whiteColor);
    NSString *symbolName = SGTabIconSymbolName(view);
    if (symbolName) return symbolGlyph(symbolName, active);
    UIView *holder = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
    view.translatesAutoresizingMaskIntoConstraints = YES;
    view.frame = holder.bounds;
    if ([view isKindOfClass:UIImageView.class]) view.contentMode = UIViewContentModeScaleAspectFit;
    [holder addSubview:view];
    [holder layoutIfNeeded];
    return glyphOf(holder, active);
}

#pragma mark - Apple symbols

// Search's page is spotify:find on 9.1.90 and spotify:search on 9.2.0.
static NSString *const kFindURI = @"spotify:find", *const kSearchURI = @"spotify:search";

// The SF Symbol for each page Spotify's tabs open (SGRNavbarStockURIs). 9.1.90 opens Create as the playlist
// creation container; spotify:create-menu is the same page by the name the router also takes.
static NSDictionary<NSString *, NSString *> *pageSymbols(void) {
    return @{
        @"spotify:home": @"house",
        kFindURI: @"magnifyingglass",
        kSearchURI: @"magnifyingglass",
        @"spotify:collection": @"books.vertical",
        @"spotify:internal:playlist-creation-container": @"plus",
        @"spotify:create-menu": @"plus",
    };
}
// Premium's pages (spotify:upsell:premium_in_app_destination, spotify:premium-page:… in the binary), and any other
// tab Spotify adds.
static NSString *const kPremiumSymbol = @"crown";
static NSString *const kOtherTabSymbol = @"square.grid.2x2";

// Apple symbols' SF Symbol for the tab of Spotify's named `title`; nil with the switch off, and for a tab whose page
// Spotify's list has not named, which keeps Spotify's own glyph.
static NSString *stockSymbol(NSString *title) {
    if (!SGEnabled(SGRKeyNavbarSymbols) || !title) return nil;
    NSString *uri = SGRNavbarStockURIs()[title];
    if (!uri) return nil;
    if (pageSymbols()[uri]) return pageSymbols()[uri];
    if ([uri hasPrefix:@"spotify:upsell:"] || [uri hasPrefix:@"spotify:premium"]) return kPremiumSymbol;
    return kOtherTabSymbol;
}

// A glyph Apple symbols gives one of Spotify's tabs (stockSymbol): Home's is the house drawn to the Music app's
// measure, every other its SF Symbol. Only Apple symbols draws that house; a tab of the mod's own given the house
// symbol keeps the symbol.
static UIImage *stockGlyph(NSString *symbol, BOOL active) {
    if ([symbol isEqualToString:pageSymbols()[@"spotify:home"]]) return musicHomeGlyph();
    return symbolGlyph(symbol, active);
}

// Spotify's own Search tab, known by the page it opens in Spotify's list of tabs, never by its name or its place. A tab
// of the mod's own is not, whatever it opens.
static BOOL isSearch(UIView *item) {
    if (isOwnTab(item)) return NO;
    NSString *title = labelIn(item).text;
    NSString *uri = title ? SGRNavbarStockURIs()[title] : nil;
    return [uri isEqualToString:kSearchURI] || [uri isEqualToString:kFindURI];
}

// The title a tab of Spotify's shows on the bar: Search's is the Music app's word for it ("검색" where Spotify says
// "검색하기"), every other its label's.
NSString *SGRStockTabTitle(NSString *title) {
    if (![title isEqualToString:@"검색하기"]) return title;
    NSString *uri = SGRNavbarStockURIs()[title];
    return [uri isEqual:kSearchURI] || [uri isEqual:kFindURI] ? @"검색" : title;
}

static NSString *tabTitle(UIView *item) {
    NSString *title = labelIn(item).text;
    return isOwnTab(item) ? title : SGRStockTabTitle(title);
}

// For the Tab bar page's list and preview: a tab of Spotify's drawn from its item on the bar, hidden or not,
// found by the label its entry is named after, or with Apple symbols' symbol; a tab of the mod's own drawn from
// its entry, as Navbar.x draws it on the bar. Nil while Spotify's item has not been built.
UIImage *SGRNavbarGlyph(NSDictionary *entry, BOOL active) {
    if (entry[SGRNavbarURI]) return iconGlyph(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], active);
    NSString *symbol = stockSymbol(entry[SGRNavbarID]);
    if (symbol) return stockGlyph(symbol, active);
    for (UIView *item in SGRowIn(sg_stockBar).arrangedSubviews) {
        if (isOwnTab(item)) continue;
        if ([labelIn(item).text isEqualToString:entry[SGRNavbarID]]) return glyphOf(item, active);
    }
    return nil;
}

#pragma mark - passing a tap on

// NavigationUI_TabBarImpl's TabBarItemElementUI answers a tap recognizer (-handleTap), so the tap is
// replayed through the recognizer's own target-action pairs, the same call a real touch ends in.
@interface SGRTargetLayout : NSObject
@property Ivar target;
@property ptrdiff_t actionOffset;
@end
@implementation SGRTargetLayout
@end

static SGRTargetLayout *layoutOfPair(id pair) {
    static char key;
    Class cls = object_getClass(pair);
    SGRTargetLayout *layout = objc_getAssociatedObject(cls, &key);
    if (!layout) {
        layout = [SGRTargetLayout new];
        Ivar target = class_getInstanceVariable(cls, "_target"), action = class_getInstanceVariable(cls, "_action");
        const char *t = target ? ivar_getTypeEncoding(target) : NULL, *a = action ? ivar_getTypeEncoding(action) : NULL;
        if (t && *t == '@' && a && !strcmp(a, @encode(SEL)) && fitsWord(pair, action)) {
            layout.target = target;
            layout.actionOffset = ivar_getOffset(action);
        }
        objc_setAssociatedObject(cls, &key, layout, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return layout;
}

static BOOL navigationTarget(id target, SEL action) {
    if (!target || action != NSSelectorFromString(@"handleTap")) return NO;
    static char key;
    Class cls = object_getClass(target);
    NSNumber *valid = objc_getAssociatedObject(cls, &key);
    if (!valid) {
        NSString *name = @(class_getName(cls));
        Method method = class_getInstanceMethod(cls, action);
        char result[2] = {};
        if (method) method_getReturnType(method, result, sizeof(result));
        valid = @([name hasPrefix:@"_TtC23NavigationUI_TabBarImpl"] && [name hasSuffix:@"19TabBarItemElementUI"] &&
                  result[0] == 'v' && method_getNumberOfArguments(method) == 2);
        objc_setAssociatedObject(cls, &key, valid, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return valid.boolValue;
}

static BOOL routeAtView(UIView *view, BOOL send) {
    static Ivar targetsIvar;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Ivar field = class_getInstanceVariable(UIGestureRecognizer.class, "_targets");
        const char *type = field ? ivar_getTypeEncoding(field) : NULL;
        if (type && *type == '@') targetsIvar = field;
    });
    for (UITapGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (!targetsIvar || ![recognizer isKindOfClass:UITapGestureRecognizer.class] || !recognizer.enabled ||
            recognizer.numberOfTapsRequired != 1 || recognizer.numberOfTouchesRequired != 1) continue;
        id pairs = object_getIvar(recognizer, targetsIvar);
        if (![pairs isKindOfClass:NSArray.class]) continue;
        for (id pair in pairs) {
            SGRTargetLayout *layout = layoutOfPair(pair);
            if (!layout.target) continue;
            id target = object_getIvar(pair, layout.target);
            SEL action;
            memcpy(&action, (char *)(__bridge void *)pair + layout.actionOffset, sizeof(action));
            if (!navigationTarget(target, action)) continue;
            if (send) ((void (*)(id, SEL))objc_msgSend)(target, action);
            return YES;
        }
    }
    UIControl *control = (UIControl *)view;
    if (![control isKindOfClass:UIControl.class] || !control.enabled || !(control.allControlEvents & UIControlEventTouchUpInside)) return NO;
    if (send) [control sendActionsForControlEvents:UIControlEventTouchUpInside];
    return YES;
}

static BOOL routeTap(UIView *item, BOOL send) {
    // A steady layout checks only the last routing view, not every descendant of every tab.
    static NSMapTable<UIView *, UIView *> *hosts;
    if (!hosts) hosts = [NSMapTable weakToWeakObjectsMapTable];
    UIView *host = [hosts objectForKey:item];
    if (host && [host isDescendantOfView:item] && routeAtView(host, send)) return YES;
    // While on the stock row, recognizers can become available on an existing view.
    // Rediscover descendants only when a child isn't in the last unsuccessful search.
    static char missingKey;
    NSHashTable<UIView *> *known = objc_getAssociatedObject(item, &missingKey);
    if (known) {
        BOOL changed = NO;
        for (UIView *v in known) {
            if (![v isDescendantOfView:item]) continue;
            if (routeAtView(v, send)) {
                [hosts setObject:v forKey:item];
                objc_setAssociatedObject(item, &missingKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                return YES;
            }
            for (UIView *child in v.subviews) if (![known containsObject:child]) { changed = YES; break; }
        }
        if (!changed) return NO;
    }
    __block UIView *found = nil;
    known = [NSHashTable weakObjectsHashTable];
    SGForEachView(item, ^(UIView *v) {
        [known addObject:v];
        if (!found && v != host && routeAtView(v, send)) found = v;
    });
    objc_setAssociatedObject(item, &missingKey, found ? nil : known, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (found) [hosts setObject:found forKey:item];
    else [hosts removeObjectForKey:item];
    return found != nil;
}

#pragma mark - the system bar

// A name too long for its tab (one of the user's own, a split tab's circle) shrinks a little before UIKit cuts
// it short, to 8 pt from 10.
void SGRShrinkTabTitles(UIView *bar) {
    SGForEachView(bar, ^(UIView *v) {
        if (![v isKindOfClass:UILabel.class] || ((UILabel *)v).adjustsFontSizeToFitWidth) return;
        ((UILabel *)v).adjustsFontSizeToFitWidth = YES;
        ((UILabel *)v).minimumScaleFactor = 0.8;
    });
}

// The item a tab button of `bar` draws, outside the copy UIKit draws lit under the selection's bubble. UIKit's buttons
// are private, but its platter holds them in the items' order in either layout direction, so a button's place among
// them names its item where a glyph or a name two tabs share would not.
static UITabBarItem *itemOfButton(UITabBar *bar, UIView *button) {
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    for (UIView *sibling in button.superview.subviews) if (isTabButton(sibling)) [buttons addObject:sibling];
    if (buttons.count != bar.items.count) {
        static NSMutableSet<NSString *> *logged;
        NSString *counts = [NSString stringWithFormat:@"%lu buttons for %lu items", (unsigned long)buttons.count, (unsigned long)bar.items.count];
        SGLogOnce(&logged, counts, @"tab bar: %@, so a button names no tab");
        return nil;
    }
    return bar.items[[buttons indexOfObject:button]];
}

@implementation SGRSystemTabBar

// UIKit makes the labels as it lays the items out, so they are shrunk after each pass, and its platters, which take
// the listener's glass (SGRGlass.h).
- (void)layoutSubviews {
    [super layoutSubviews];
    SGRShrinkTabTitles(self);
    for (UIView *sub in self.subviews) {
        if ([NSStringFromClass(sub.class) hasSuffix:@"PlatterView"]) SGRGlassRestyle(sub);
    }
    noteGlassRow();
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item {
    NSUInteger index = [self.items indexOfObject:item];
    if (index == NSNotFound || index >= self.sources.count) return;
    BOOL again = item == self.shown;
    self.shown = item;
    // On the minimized bar the leading circle brings the whole bar back, as the Music app's does; passed on,
    // the tap would take Spotify's stack back to its root. Minimizing builds the circle's item anew, so it
    // is told by the bar it is on, not by being the item shown before.
    BOOL leading = self.stockBar && objc_getAssociatedObject(self.stockBar, &kBarKey) == self;
    if (sg_minimized && (again || leading)) {
        SGRSetTabBarMinimized(NO, YES);
        return;
    }
    // One of Spotify's own takes the light back from a tab of the mod's own.
    UIView *source = self.sources[index];
    if (!isOwnTab(source)) SGRNavbarForgetTab();
    // Home tapped while on Home pops Spotify's stack, which would take Mod Settings straight off it.
    if (!self.holding && !routeTap(source, YES)) {
        syncBar(self.stockBar);
        return;
    }
    self.partner.selectedItem = nil;
    self.partner.shown = nil;
    // Spotify repaints its labels a moment later; a tap it did not take snaps the selection back.
    UIView *stockBar = self.stockBar;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (stockBar) syncBar(stockBar);
    });
}

// The item under a touch: that of the tab button nearest it, outside the copy UIKit draws lit under the selection's
// bubble.
- (UITabBarItem *)itemAt:(CGPoint)point {
    __block UIView *nearest = nil;
    __block CGFloat best = CGFLOAT_MAX;
    SGForEachView(self, ^(UIView *v) {
        if (!isTabButton(v) || isLitCopy(v, self)) return;
        CGFloat distance = fabs([v convertPoint:CGPointMake(CGRectGetMidX(v.bounds), 0) toView:self].x - point.x);
        if (distance >= best) return;
        best = distance;
        nearest = v;
    });
    return nearest ? itemOfButton(self, nearest) : nil;
}

// UIView asks itself this for its own recognizers too, so only the hold is answered here.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.hold) return [super gestureRecognizerShouldBegin:recognizer];
    NSUInteger index = [self.items indexOfObject:[self itemAt:[recognizer locationInView:self]]];
    return index < self.sources.count && isHome(self.sources[index], self.stockBar);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    return YES;
}

- (void)held:(UILongPressGestureRecognizer *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) {
        self.holding = YES;
        SGOpenModSettings(self);
    } else if (hold.state != UIGestureRecognizerStateChanged) {
        // The bar may still pick Home as the finger lifts, after this.
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            weakSelf.holding = NO;
        });
    }
}

@end

// The system bar's own view in Spotify's bar. UIKit measures the system bar and lays it out by the safe
// area of the view it stands in, and the room made under Spotify's bar is not the phone's: on a phone
// with a home button it went under the platter as well, squeezing it to 49 pt. So this view hands the
// bar the safe area without the room.
@interface SGRTabBarHost : UIView
@end

@implementation SGRTabBarHost
- (UIEdgeInsets)safeAreaInsets {
    UIEdgeInsets insets = [super safeAreaInsets];
    insets.bottom = MAX(0, insets.bottom - sg_room);
    return insets;
}
@end

@interface SGRHomeHold : UILongPressGestureRecognizer
@end

@implementation SGRHomeHold
+ (void)held:(SGRHomeHold *)hold {
    if (hold.state == UIGestureRecognizerStateBegan) SGOpenModSettings(hold.view);
}
@end

// On Spotify's own bar a hold that begins fails the item's tap recognizer, so Home is not tapped too.
static void holdHome(UIView *stockBar) {
    UIView *home = SGRowIn(stockBar).arrangedSubviews.firstObject;
    if (!home) return;
    for (UIGestureRecognizer *recognizer in home.gestureRecognizers) {
        if ([recognizer isKindOfClass:SGRHomeHold.class]) return;
    }
    [home addGestureRecognizer:[[SGRHomeHold alloc] initWithTarget:SGRHomeHold.class action:@selector(held:)]];
}

static void logBarOnce(UITabBar *bar) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGLogLong(@"navbar", [NSString stringWithFormat:@"system tab bar %@\n%@", NSStringFromCGRect(bar.superview.frame), [bar recursiveDescription]]);
        });
    });
}

#pragma mark - the fade under the bars

// The pages darken toward the bottom of the screen under the glass bar and the now playing bar, from clear
// a little above the now playing card to half black at the screen's foot, so a row going under the glass
// reads as passing behind it. Never darker than half: the glass still has the page to lens. The fade is the
// stock bar's own subview, behind the glass, so it slides away with the bar when a page hides it; Spotify's
// bar does not clip, or the glass bar would not have stood over the now playing bar before the room was made.
@interface SGRBarFade : UIView
@property (nonatomic, strong) NSArray<NSLayoutConstraint *> *placement;
@property (nonatomic, strong) NSLayoutConstraint *glassTop;
@end

@implementation SGRBarFade
+ (Class)layerClass {
    return CAGradientLayer.class;
}
@end

// The now playing card (56), its gap over the bar (8) and 24 more, whether a song is playing or not.
const CGFloat SGRBarFadeAbovePt = 88;

void SGRStyleBarFade(CAGradientLayer *layer) {
    // Eased rather than straight, so the fade has no edge where it starts.
    layer.colors = @[(id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.3].CGColor,
                     (id)[UIColor colorWithWhite:0 alpha:0.5].CGColor];
    layer.locations = @[@0, @0.5, @1];
}

static UIViewController *containerOf(UIView *stockBar);

// The fade hides with the stock bar, but its sides follow the container even when the iPad
// player moves the bar's stack after the bar has laid out. Anchor its top to the glass
// (bottom-aligned in the bar) and extend to whichever foot is lower, the glass or the page.
static void placeFade(UIView *stockBar, CGFloat glassHeightPt) {
    SGRBarFade *fade = objc_getAssociatedObject(stockBar, &kFadeKey);
    UIView *container = SGEnabled(SGRKeyNavbarFade) ? containerOf(stockBar).viewIfLoaded : nil;
    if (!container || ![stockBar isDescendantOfView:container]) {
        if (!fade) return;
        [NSLayoutConstraint deactivateConstraints:fade.placement];
        [fade removeFromSuperview];
        objc_setAssociatedObject(stockBar, &kFadeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!fade) {
        fade = [SGRBarFade new];
        fade.translatesAutoresizingMaskIntoConstraints = NO;
        fade.userInteractionEnabled = NO;
        SGRStyleBarFade((CAGradientLayer *)fade.layer);
        objc_setAssociatedObject(stockBar, &kFadeKey, fade, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSLayoutConstraint *leading = fade.placement.firstObject;
    CGFloat top = -glassHeightPt - SGRBarFadeAbovePt;
    if (fade.superview != stockBar || leading.secondItem != container || !leading.active) {
        if (leading) [NSLayoutConstraint deactivateConstraints:fade.placement];
        if (fade.superview != stockBar) [stockBar insertSubview:fade atIndex:0];
        fade.glassTop = [fade.topAnchor constraintEqualToAnchor:stockBar.bottomAnchor constant:top];
        NSLayoutConstraint *foot = [fade.bottomAnchor constraintEqualToAnchor:container.bottomAnchor];
        foot.priority = UILayoutPriorityDefaultLow;
        fade.placement = @[
            [fade.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
            [fade.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
            fade.glassTop, foot,
            [fade.bottomAnchor constraintGreaterThanOrEqualToAnchor:stockBar.bottomAnchor],
            [fade.bottomAnchor constraintGreaterThanOrEqualToAnchor:container.bottomAnchor],
        ];
        [NSLayoutConstraint activateConstraints:fade.placement];
    } else if (fade.glassTop.constant != top) fade.glassTop.constant = top;
    if (stockBar.subviews.firstObject != fade) [stockBar sendSubviewToBack:fade];
}

// The bar the glass was last laid out on lays out again, and its pass puts the fade on or takes it off. The bar is
// the one this file follows rather than the one Navbar.x composed (SGRRefreshTabBar): the fade is this file's, and
// it is on that bar whether or not the composition found its row.
void SGRRefreshBarFade(void) {
    [sg_stockBar setNeedsLayout];
}

#pragma mark - room for the glass bar

// UIKit's glass bar asks for 83 pt, the platter the top 62 of it, over no more safe area than a Face ID
// phone's 34 (simulator, iOS 26.5 and 27). Spotify's bar is its 49 pt row over the bottom safe area of
// TabBarContainerImpl's view: a guide from 49 pt above the safe area's bottom to the view's bottom sets
// its height (its viewDidLoad, 0x100840a2c), the now playing bar stands on that guide's top
// (MainUIContainer's chrome bottom anchor, 0x100ae0178), the bar slides away by the inset plus 49 when
// Spotify hides it (0x1037169a4) and the pages get 49 on top of the inset (0x10707bde4). A Face ID
// phone gives the view 34 and the two bars match. A phone with a home button gives it none, and so does
// Spotify's message bar (LimitedExperienceIndicatorBar: Offline, Private Session) coming in under the
// tab bar, which takes the home indicator's inset for itself: the glass bar stood 34 pt above
// Spotify's, over the now playing bar. So the view gets the rest of the glass bar's height as safe
// area, and Spotify lays its bar, the now playing bar, the pages and the hide out for the glass bar
// itself, and moves them all with the message bar.
static const CGFloat kStockRow = 49;

// UIKit asks for 62 + max(21, inset) on a phone with a home button, max(83, 49 + inset) on a Face ID
// phone, by the safe area of the view the bar stands in. SGRTabBarHost keeps the room out of that; if
// it ever reached the bar again, the bar would ask for more room every pass, so what it asks for with
// no room made is what is kept.
static CGFloat glassHeight(UITabBar *bar, UIView *stockBar) {
    if (sg_room < 0.5 || sg_glassHeight <= 0) sg_glassHeight = [bar sizeThatFits:CGSizeMake(stockBar.bounds.size.width, kStockRow)].height;
    return sg_glassHeight;
}

static UIViewController *containerOf(UIView *stockBar) {
    Class containerClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl");
    for (UIResponder *r = stockBar.nextResponder; r; r = r.nextResponder) {
        if ([r isKindOfClass:containerClass]) return (UIViewController *)r;
    }
    return nil;
}

static void makeRoom(UIViewController *container) {
    UIView *stockBar = sg_stockBar;
    UITabBar *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    if (!bar.window || !container.isViewLoaded || ![stockBar isDescendantOfView:container.view]) return;
    UIEdgeInsets extra = container.additionalSafeAreaInsets;
    CGFloat inset = container.view.safeAreaInsets.bottom - extra.bottom;
    CGFloat height = glassHeight(bar, stockBar);
    // Spotify's regular width bar is a fixed 76 pt that ignores the inset.
    BOOL compact = container.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact;
    CGFloat room = compact ? MAX(0, ceil(height - kStockRow - inset)) : 0;
    if (fabs(extra.bottom - room) < 0.5) return;
    sg_room = extra.bottom = room;
    container.additionalSafeAreaInsets = extra;
    SGLog(@"tab bar: %.0f pt of room made under Spotify's bar for the glass bar's %.0f, over an inset of %.0f", room, height, inset);
}

static SGRSystemTabBar *makeBar(UIView *stockBar) {
    SGRSystemTabBar *bar = [[SGRSystemTabBar alloc] initWithFrame:stockBar.bounds];
    // UIKit draws the glass in the appearance the bar inherits, and the bar is outside the navigation
    // stacks Spotify makes dark itself (-[SPNavigationController viewDidLoad] while +[SPTLiquidGlass
    // isEnabled]), so a phone in light mode had it light over Spotify's black. Spotify is dark whatever
    // the system is, and so is the bar.
    bar.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    bar.delegate = bar;
    bar.stockBar = stockBar;
    UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:bar action:@selector(held:)];
    hold.delegate = bar;
    [bar addGestureRecognizer:hold];
    bar.hold = hold;
    return bar;
}

// Setting a tab's image lays its bar's items out again, so an image is set only when it is another one: the glyph
// cache hands back the same object for the same glyph.
static void setGlyphs(UITabBarItem *item, UIImage *image, UIImage *selectedImage) {
    if (image && item.image != image) item.image = image;
    if (selectedImage && item.selectedImage != selectedImage) item.selectedImage = selectedImage;
}

// One bar's share of the tabs: its items, their glyphs and titles. YES while a glyph is still missing.
// The bar takes its items again when one that had no glyph gets it. In a regular width UIKit sets a title beside its
// glyph and gives the tab the width the two need as the bar takes the item, never again when the glyph comes later:
// items handed over bare kept the width of the title alone, which the glyph then took 21 pt of (iPad Pro 11-inch,
// iOS 26.5: "홈" 4 pt wide for 10.5, "만들기" 19.5 for 31.5, cut to "만…").
static BOOL fillBar(SGRSystemTabBar *bar, NSArray<UIView *> *sources, BOOL hideLabels, NSUInteger generation) {
    bar.tintColor = SGRAccent();
    if (![sources isEqualToArray:bar.sources] || bar.items.count != sources.count) {
        NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
        for (UIView *source in sources) [items addObject:[[UITabBarItem alloc] initWithTitle:hideLabels ? nil : tabTitle(source) image:nil tag:items.count]];
        bar.sources = sources;
        [bar setItems:items animated:NO];
        NSMutableString *out = [NSMutableString stringWithString:@"tab bar icons"];
        for (UIView *source in sources) {
            UIView *live = iconIn(source);
            id icon = live ? encoreIconOf(live) : nil;
            id variant = activeVariantOf(icon);
            [out appendFormat:@"\n  %@: %@ icon %@ active-variant %@ live-isActive %d label-white %d", labelIn(source).text, NSStringFromClass(live.class),
                 iconName(icon) ?: icon ?: (live ? swiftIconKey(live) : nil), iconName(variant) ?: variant,
                 [live respondsToSelector:@selector(isActive)] ? [(SPTEncoreIconView *)live isActive] : -1, isActive(source)];
        }
        SGLogLong(@"navbar", out);
    }

    // Drawing a glyph can lay Spotify's row out and start a newer syncBar pass.
    NSArray<UITabBarItem *> *barItems = bar.items;
    if (generation != sg_syncGeneration || barItems.count != sources.count) return NO;
    BOOL missing = NO, drew = NO;
    for (NSUInteger i = 0; i < sources.count; i++) {
        UITabBarItem *item = barItems[i];
        // A tab not selected when its item was drawn kept an outlined selectedImage, and one selected kept its filled
        // glyph as image. Both images come from the icon the view holds (glyphOfIcon), known by the icon itself and
        // never by the label's color, which Spotify repaints apart from the icon: an SPTEncoreIcon, which Spotify
        // swaps for its filled one on the selected tab, gives image and its -active variant selectedImage, a filled
        // one or one with no variant both; an Encore.Icon holds both glyphs. The item keeps the keys it was drawn
        // from (glyphKeysOf) and is drawn again when the view holds an icon outside them, so a filled SPTEncoreIcon
        // whose outline drew the item changes nothing. Another icon view (a tab of the mod's own given another icon,
        // which has no Encore name when it is an image) draws the item anew too, and so does Apple symbols coming,
        // going or naming another symbol: one of Spotify's tabs is then drawn with its symbol, not off its view. A tab
        // of the mod's own wearing an SF Symbol is drawn with that symbol (SGTabIconSymbolName), as Apple symbols draws
        // Spotify's.
        UIView *live = iconIn(sources[i]);
        BOOL own = isOwnTab(sources[i]);
        NSString *symbol = own ? SGTabIconSymbolName(live) : stockSymbol(labelIn(sources[i]).text);
        NSString *drawnSymbol = objc_getAssociatedObject(item, &kItemSymbolKey);
        if (objc_getAssociatedObject(item, &kItemIconKey) != live || ((symbol || drawnSymbol) && ![symbol isEqualToString:drawnSymbol])) {
            item.image = nil;
            item.selectedImage = nil;
            objc_setAssociatedObject(item, &kGlyphKeysKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(item, &kItemIconKey, live, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(item, &kItemSymbolKey, symbol, OBJC_ASSOCIATION_COPY_NONATOMIC);
        }
        NSArray<NSString *> *keys = symbol ? nil : glyphKeysOf(live);
        if (!item.image || !item.selectedImage || (keys && ![objc_getAssociatedObject(item, &kGlyphKeysKey) containsObject:keys.firstObject])) {
            BOOL bare = !item.image;
            if (symbol && own) setGlyphs(item, symbolGlyph(symbol, NO), symbolGlyph(symbol, YES));
            else if (symbol) setGlyphs(item, stockGlyph(symbol, NO), stockGlyph(symbol, YES));
            else {
                UIImage *plain = glyphOfIcon(live, NO);
                if (generation != sg_syncGeneration) return NO;
                UIImage *selected = glyphOfIcon(live, YES);
                if (generation != sg_syncGeneration) return NO;
                setGlyphs(item, plain, selected);
            }
            drew |= bare && item.image;
            if (item.image && item.selectedImage) objc_setAssociatedObject(item, &kGlyphKeysKey, keys, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        missing |= !item.image || !item.selectedImage;
        NSString *resolvedTitle = tabTitle(sources[i]);
        item.accessibilityLabel = resolvedTitle;
        item.largeContentSizeImage = item.image;
        item.accessibilityHint = sg_minimized && bar == objc_getAssociatedObject(bar.stockBar, &kBarKey) ? SGL(@"settings.tabbar.minimized.hint", @"Shows all tabs") : nil;
        NSString *title = hideLabels ? nil : resolvedTitle;
        if (hideLabels ? item.title != nil : title.length && ![title isEqualToString:item.title]) item.title = title;
    }
    if (drew && generation == sg_syncGeneration && [bar.sources isEqualToArray:sources] && [bar.items isEqualToArray:barItems]) {
        // The same items again, which UIKit only measures anew once the bar has let go of them. The selection goes
        // with them and comes back, for a bar whose tab Spotify paints no selection for (selectActive).
        UITabBarItem *selected = bar.selectedItem;
        [bar setItems:@[] animated:NO];
        if (generation != sg_syncGeneration) return NO;
        [bar setItems:barItems animated:NO];
        if (generation == sg_syncGeneration) bar.selectedItem = selected;
    }
    return missing;
}

// The bar holding the tab Spotify paints as selected selects it, and the other one lets go of its selection and of the
// item it last showed selected: after a tab picked from elsewhere (a link, the side drawer) a tap on the other bar's tab
// is a change of tab, not a tap again. With no tab painted (a tab of the mod's own, a repaint still to come) both keep
// what they have.
static void selectActive(SGRSystemTabBar *bar, UIView *active) {
    if (!active) return;
    NSUInteger index = [bar.sources indexOfObject:active];
    UITabBarItem *item = index == NSNotFound ? nil : bar.items[index];
    if (bar.selectedItem != item) bar.selectedItem = item;
    bar.shown = item;
}

// The tab a bar shows selected, when Spotify paints none: a tab of the mod's own.
static UIView *selectedSource(SGRSystemTabBar *bar) {
    NSUInteger index = bar.selectedItem ? [bar.items indexOfObject:bar.selectedItem] : NSNotFound;
    return index < bar.sources.count ? bar.sources[index] : nil;
}

// The tab the minimized bar keeps on a circle at its trailing end: the last split tab, or with none Spotify's Search
// wherever the row holds it, as the Music app keeps Search there. Nil for neither.
static UIView *trailingTab(NSArray<UIView *> *sources, NSArray<UIView *> *apart) {
    if (apart.count) return apart.lastObject;
    for (UIView *source in sources) if (isSearch(source)) return source;
    return nil;
}

// Split tabs stand on a glass bar of their own at the trailing end, the way the Music app sets Search
// apart. A standalone UITabBar has no way to set an item apart (iOS 27 SDK: only UITabBarController's
// UISearchTab does), so it is a second bar. UIKit draws each bar's platter 21 pt in from its sides
// (harness/tabbar, iPhone 17 Pro, iOS 27: a 72 pt bar got a 30 pt platter at x 21), so a split bar is
// a 62 pt platter, a circle as tall as the bar's, per tab plus those insets, and the main bar runs under
// its leading inset to leave 12 pt of glassless gap between the two platters.
static char kStockAppearanceKey, kParentColorsKey, kGradientAlphaKey;
static NSHashTable<UIView *> *stockGradients;

static void mirrorGradient(UIView *gradient) {
    UIView *bar = sg_stockBar;
    BOOL mirror = objc_getAssociatedObject(bar, &kStockAppearanceKey) &&
        [gradient isDescendantOfView:containerOf(bar).viewIfLoaded];
    NSNumber *saved = objc_getAssociatedObject(gradient, &kGradientAlphaKey);
    if (mirror && !saved) {
        CGFloat alpha = gradient.alpha;
        objc_setAssociatedObject(gradient, &kGradientAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gradient.alpha = alpha; // setAlpha: keeps Spotify's requested value and renders zero
    } else if (!mirror && saved) {
        objc_setAssociatedObject(gradient, &kGradientAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        gradient.alpha = saved.doubleValue;
    }
}

static NSUInteger sg_barChange;
static void handOver(void);

static void retryMissingGlyphs(SGRSystemTabBar *bar, NSArray<UIView *> *sources, BOOL missing) {
    if (!missing || ![bar.retrySources isEqualToArray:sources]) {
        [bar.glyphTimer invalidate];
        bar.glyphTimer = nil;
        bar.glyphRetries = 0;
        bar.retrySources = missing ? sources : nil;
    }
    if (!missing || bar.glyphTimer || bar.glyphRetries >= 40) return;
    __weak SGRSystemTabBar *weakBar = bar;
    bar.glyphTimer = [NSTimer scheduledTimerWithTimeInterval:.25 repeats:NO block:^(NSTimer *timer) {
        SGRSystemTabBar *bar = weakBar;
        UIView *stockBar = bar.stockBar;
        if (bar.glyphTimer != timer) return;
        bar.glyphTimer = nil;
        if (!stockBar || stockBar != sg_stockBar || !stockBar.window) return;
        bar.glyphRetries++;
        syncBar(stockBar);
    }];
}

static void syncBar(UIView *stockBar) {
    NSUInteger generation = ++sg_syncGeneration;
    if (sg_stockBar != stockBar) {
        retryMissingGlyphs(objc_getAssociatedObject(sg_stockBar, &kBarKey), nil, NO);
        sg_stockBar = stockBar;
    }

    NSArray<UIView *> *sources = tabItems(stockBar);
    BOOL canForward = sources.count != 0;
    for (UIView *source in sources) {
        if (!routeTap(source, NO)) { canForward = NO; break; }
    }
    NSMapTable<UIView *, NSArray<NSNumber *> *> *stockAppearance = objc_getAssociatedObject(stockBar, &kStockAppearanceKey);
    NSMapTable<CALayer *, id> *parentColors = objc_getAssociatedObject(stockBar, &kParentColorsKey);
    if (!canForward) {
        if (stockAppearance) {
            retryMissingGlyphs(objc_getAssociatedObject(stockBar, &kBarKey), nil, NO);
            ++sg_barChange;
            handOver();
            sg_minimized = sg_keepApart = NO;
            sg_rowApartCount = 0;
            [objc_getAssociatedObject(stockBar, &kHostKey) removeFromSuperview];
            [objc_getAssociatedObject(stockBar, &kFadeKey) removeFromSuperview];
            for (UIView *sub in stockAppearance) {
                NSArray<NSNumber *> *before = [stockAppearance objectForKey:sub];
                sub.alpha = before[0].doubleValue;
                sub.userInteractionEnabled = before[1].boolValue;
            }
            objc_setAssociatedObject(stockBar, &kStockAppearanceKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            for (UIView *v in stockGradients) mirrorGradient(v);
            for (CALayer *layer in parentColors) layer.backgroundColor = (__bridge CGColorRef)[parentColors objectForKey:layer];
            objc_setAssociatedObject(stockBar, &kParentColorsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (sg_room > 0) {
                UIViewController *container = containerOf(stockBar);
                UIEdgeInsets extra = container.additionalSafeAreaInsets;
                extra.bottom -= sg_room;
                sg_room = 0;
                container.additionalSafeAreaInsets = extra;
            }
            SGRNowPlayingBarFollowTabBar();
        }
        return;
    }
    if (!stockAppearance) {
        stockAppearance = [NSMapTable weakToStrongObjectsMapTable];
        objc_setAssociatedObject(stockBar, &kStockAppearanceKey, stockAppearance, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *v in stockGradients) mirrorGradient(v);
    }
    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    if (!bar) {
        bar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kBarKey, bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SGRTabBarHost *host = [SGRTabBarHost new];
        [host addSubview:bar];
        objc_setAssociatedObject(stockBar, &kHostKey, host, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);

    for (UIView *sub in stockBar.subviews) {
        if (sub == host || [sub isKindOfClass:SGRBarFade.class] || [stockGradients containsObject:sub]) continue;
        if (![stockAppearance objectForKey:sub])
            [stockAppearance setObject:@[@(sub.alpha), @(sub.userInteractionEnabled)] forKey:sub];
        sub.alpha = 0;
        sub.userInteractionEnabled = NO;
    }
    CALayer *parent = stockBar.superview.layer;
    if (parent.backgroundColor) {
        if (!parentColors) {
            parentColors = [NSMapTable weakToStrongObjectsMapTable];
            objc_setAssociatedObject(stockBar, &kParentColorsKey, parentColors, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [parentColors setObject:(__bridge id)parent.backgroundColor forKey:parent];
        parent.backgroundColor = NULL;
    }

    // A bar minimized in a compact width expands when the width turns regular (an iPad's window widened), where it
    // could not have minimized (setMinimized).
    BOOL regular = stockBar.window && stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact;
    if (sg_minimized && (sources.count < kMinimumMinimizedTabs || regular)) {
        SGRSetTabBarMinimized(NO, NO);
        return;
    }
    // An item with no title is drawn by UIKit as its glyph alone, centered, on a bar of the same height.
    BOOL hideLabels = SGHidden(SGRKeyNavbarHideLabels);
    SGRSystemTabBar *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    UIView *active = SGRNavbarLitTab();
    if (![sources containsObject:active]) active = nil;
    for (UIView *source in sources) if (!active && isActive(source)) active = source;
    active = active ?: selectedSource(bar) ?: selectedSource(apartBar);

    NSMutableArray<UIView *> *main = [NSMutableArray array], *apart = [NSMutableArray array];
    for (UIView *source in sources) [(SGRTabIsApart(source) ? apart : main) addObject:source];
    if (!main.count) {
        main = [sources mutableCopy];
        [apart removeAllObjects];
    }
    sg_rowApartCount = apart.count;
    // Minimized, the bar keeps two tabs, glyph only, each on a circle: at the trailing end trailingTab's, on the second
    // bar, and at the leading end the tab it is on, or when that is the trailing one the first other tab of the main
    // bar. With no trailing tab the now playing card has the rest of the row.
    BOOL minimized = sg_minimized;
    if (minimized) {
        UIView *trailing = trailingTab(sources, apart);
        [main removeObject:trailing];
        main = [NSMutableArray arrayWithObject:active && active != trailing ? active : main.firstObject];
        apart = trailing ? [NSMutableArray arrayWithObject:trailing] : [NSMutableArray array];
        hideLabels = YES;
    }
    if (apart.count && !apartBar) {
        apartBar = makeBar(stockBar);
        objc_setAssociatedObject(stockBar, &kApartBarKey, apartBar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        apartBar.partner = bar;
        bar.partner = apartBar;
        [host addSubview:apartBar];
    }
    // Expanding, sg_keepApart holds the second bar until the spring ends only if it is on screen; one hidden stays so.
    apartBar.hidden = !apart.count && (!sg_keepApart || apartBar.hidden);
    if (apartBar.hidden) apartBar.sources = nil;

    CGRect bounds = stockBar.bounds;
    CGFloat width = bounds.size.width;
    CGFloat height = MAX(bounds.size.height, glassHeight(bar, stockBar));
    CGRect frame = CGRectMake(0, CGRectGetMaxY(bounds) - height, width, height);
    if (!CGRectEqualToRect(host.frame, frame)) host.frame = frame;
    placeFade(stockBar, height);
    CGRect mainFrame = host.bounds, apartFrame = CGRectZero;
    if (minimized) {
        CGFloat side = SGRBarApartItemWidthPt + 2 * SGRBarPlatterInsetPt;
        mainFrame.size.width = side;
        if (apart.count) apartFrame = CGRectMake(width - side, 0, side, height);
    } else {
        SGRExpandedBarFrames(host.bounds, apart.count, &mainFrame, &apartFrame);
    }
    if (!CGRectEqualToRect(bar.frame, mainFrame)) bar.frame = mainFrame;
    if (apart.count && !CGRectEqualToRect(apartBar.frame, apartFrame)) apartBar.frame = apartFrame;

    // The items go in once the bars are laid out at their frames. UIKit sizes an item's title by the platter it
    // is made in and never again when the bar grows, so items made while a bar was still a circle kept "…" for
    // their names at full width (harness/tabbar, `names`).
    [host layoutIfNeeded];
    if (generation != sg_syncGeneration) return;
    BOOL missing = fillBar(bar, main, hideLabels, generation);
    if (generation != sg_syncGeneration) return;
    if (apart.count) {
        missing |= fillBar(apartBar, apart, hideLabels, generation);
        if (generation != sg_syncGeneration) return;
    }
    selectActive(bar, active);
    if (apart.count) selectActive(apartBar, active);
    // An icon view Spotify has not built yet is looked for again shortly, not on the next touch.
    retryMissingGlyphs(bar, sources, missing);
    if (host.superview != stockBar) [stockBar addSubview:host];
    else if (stockBar.subviews.lastObject != host) [stockBar bringSubviewToFront:host];
    noteGlassRow();
    logBarOnce(bar);
    makeRoom(containerOf(stockBar));
}

#pragma mark - minimized

// A page scrolled down minimizes the bar (TabBarMinimize.x), the way the Music app's does. Spotify's tab bar
// container is a UIViewController of its own, not a UITabBarController (the binary's ObjC metadata), so
// UIKit's tabBarMinimizeBehavior and bottomAccessory have nothing to act on. The minimized bar is built
// from the two bars this file already has: the main bar narrowed to one circle at the leading end, the
// second bar to one at the trailing end, and the now playing card between them (NowPlayingBar.x). The
// bars get their new items and are laid out where they are going at once; then every view of theirs goes back
// to where it was and moves on one spring with the card (see "one move"); nothing fades a bar's glass.
BOOL SGRTabBarMinimized(void) {
    return sg_minimized;
}

static void setMinimized(BOOL minimized, BOOL animated);

// The scroll asks from inside -[UIScrollView setContentOffset:], which Spotify can call inside an animation of
// its own: a block, whose length the spring then took, or a property animator held part way, which kept the bar's
// and the card's moves at its fraction for good, the circle stopped half way along the row and the card half way
// down to it (harness/tabbar, `nested`). So an animated change asked for inside an animation is made on the main
// queue's next turn, outside it, and only if nothing was asked for since; one asked for outside any is made at
// once. A change with no animation stays at once too: the player's transition takes its pictures of the bars
// right after asking.
static NSUInteger sg_request;

void SGRSetTabBarMinimized(BOOL minimized, BOOL animated) {
    NSUInteger request = ++sg_request;
    if (!animated) {
        [UIView performWithoutAnimation:^{ setMinimized(minimized, NO); }];
        return;
    }
    if (UIView.areAnimationsEnabled && UIView.inheritedAnimationDuration <= 0) {
        setMinimized(minimized, YES);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (request == sg_request) setMinimized(minimized, YES);
    });
}

#pragma mark - one move

// The bars, the circles and the card move as one: on one spring (SGRMotionBar), from what is on screen. UIKit
// lays a bar's items out by its width, so a bar laid out where it was with its new items put them where they
// never were: minimizing, the circle's tab stood in the middle of the old full bar and slid to the leading end
// from there (harness/tabbar, `motion`: 124 pt in one frame). So each bar is laid out where it is going, and
// every view of the bars that was already there goes back to its frame from before, under its animations still
// running, and moves to its new one in the spring. UIView's animations add up, so a change that turns one back
// carries on from where the screen is, at the speed it had. UIKit takes the animations off its platters when it
// lays new items out, though, and a platter turned back half way then started from the old move's end, 62 pt from
// where it was shown (`motion`, four quick turns); one whose move was taken off starts from what was shown. A tab's
// new button starts with its glyph where its old one's was, on either bar, so a tab moving between the row and a
// circle shows one glyph all the way; the other new buttons fade in, and the buttons that went fade out from where
// they were.
typedef struct {
    NSMapTable<UIView *, NSArray<NSValue *> *> *frames; // every view of the host: its frame, the frame shown, moving
    NSMutableDictionary<NSString *, NSValue *> *glyphs; // each shown tab button's glyph center in the host (buttonKey)
    NSMapTable<UIView *, UIView *> *buttons;            // each shown tab button, a picture of it
    NSMapTable<UIView *, NSString *> *keys;             // each shown tab button, its buttonKey
} SGRBarState;

// UIKit draws every tab twice, the second time in the accent under the selection's bubble only.
static BOOL isLitCopy(UIView *view, UIView *host) {
    for (UIView *up = view.superview; up && up != host; up = up.superview) {
        if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) return YES;
    }
    return NO;
}

static BOOL isMoving(UIView *view) {
    for (NSString *key in view.layer.animationKeys) if ([key hasPrefix:@"position"] || [key hasPrefix:@"bounds"]) return YES;
    return NO;
}

static UIImageView *glyphView(UIView *button) {
    __block UIImageView *glyph = nil;
    SGForEachView(button, ^(UIView *v) {
        if (!glyph && [v isKindOfClass:UIImageView.class] && !v.hidden && ((UIImageView *)v).image) glyph = (UIImageView *)v;
    });
    return glyph;
}

static BOOL isTabButton(UIView *view) {
    return [view isKindOfClass:UIControl.class] && glyphView(view) != nil;
}

// Whether a view of the host is drawn: neither it nor a view above it hidden or clear.
static BOOL isShownIn(UIView *view, UIView *host) {
    for (UIView *up = view; up && up != host; up = up.superview) if (up.hidden || up.alpha < 0.01) return NO;
    return YES;
}

static NSString *tabKey(UIView *source) {
    return [NSString stringWithFormat:@"%p", source];
}

// Which old button a new one takes over from. UIKit draws its glyphs anew with each set of items (each copy a UIImage
// of its own), so a button is known by the tab its item stands for (itemOfButton), on whichever bar. The copy UIKit
// draws lit under the selection's bubble is known by being the selected one.
static NSString *buttonKey(UIView *button, UIView *host) {
    if (!isTabButton(button)) return nil;
    if (isLitCopy(button, host)) return ((UIControl *)button).selected ? @"lit" : nil;
    UIView *up = button.superview;
    while (up && ![up isKindOfClass:SGRSystemTabBar.class]) up = up.superview;
    SGRSystemTabBar *bar = (SGRSystemTabBar *)up;
    UITabBarItem *item = bar ? itemOfButton(bar, button) : nil;
    NSUInteger index = item ? [bar.items indexOfObject:item] : NSNotFound;
    return index < bar.sources.count ? tabKey(bar.sources[index]) : nil;
}

// `bar`'s tab button for `source`, outside the lit copy; nil when it has none.
static UIView *buttonOf(SGRSystemTabBar *bar, UIView *source) {
    NSUInteger index = [bar.sources indexOfObject:source];
    if (index == NSNotFound || index >= bar.items.count) return nil;
    __block UIView *button = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (!button && isTabButton(v) && !isLitCopy(v, bar) && itemOfButton(bar, v) == bar.items[index]) button = v;
    });
    return button;
}

static CGRect shownIn(UIView *view, UIView *host) {
    CALayer *layer = view.layer.presentationLayer ?: view.layer, *top = host.layer.presentationLayer ?: host.layer;
    return [layer convertRect:layer.bounds toLayer:top];
}

static SGRBarState barState(UIView *host) {
    SGRBarState state = {
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
        [NSMutableDictionary dictionary],
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality valueOptions:NSPointerFunctionsStrongMemory],
    };
    SGForEachView(host, ^(UIView *v) {
        CALayer *shownLayer = v.layer.presentationLayer;
        [state.frames setObject:@[[NSValue valueWithCGRect:v.frame], [NSValue valueWithCGRect:shownLayer ? shownLayer.frame : v.frame], @(isMoving(v))] forKey:v];
        // A button not drawn (on a hidden bar, or the circle's while its tab goes back into the row) is no glyph to
        // take over from, and no picture to fade.
        if (!v.window || v == host || !isTabButton(v) || !isShownIn(v, host)) return;
        CGRect shown = shownIn(v, host), glyph = shownIn(glyphView(v), host);
        NSString *key = buttonKey(v, host);
        if (key) {
            state.glyphs[key] = [NSValue valueWithCGPoint:CGPointMake(CGRectGetMidX(glyph), CGRectGetMidY(glyph))];
            [state.keys setObject:key forKey:v];
        }
        // The lit copy is left out, or its picture would show the tab lit outside the bubble.
        if (isLitCopy(v, host)) return;
        UIView *picture = [v snapshotViewAfterScreenUpdates:NO];
        if (picture) {
            picture.frame = shown;
            [state.buttons setObject:picture forKey:v];
        }
    });
    return state;
}

// Moves the host's views from `before` to where they are now, with `along` (the card) in the same spring.
static void moveFrom(UIView *host, SGRBarState before, void (^along)(void), void (^completion)(BOOL)) {
    NSMutableArray<UIView *> *moved = [NSMutableArray array], *faded = [NSMutableArray array];
    NSMutableArray<NSValue *> *starts = [NSMutableArray array], *targets = [NSMutableArray array];
    NSMutableSet<NSString *> *taken = [NSMutableSet set];
    SGForEachView(host, ^(UIView *v) {
        if (v == host) return;
        NSArray<NSValue *> *old = [before.frames objectForKey:v];
        if (old) {
            BOOL stopped = [(NSNumber *)old[2] boolValue] && !isMoving(v);
            CGRect start = stopped ? old[1].CGRectValue : old[0].CGRectValue;
            if (!stopped && CGRectEqualToRect(start, v.frame)) return;
            [moved addObject:v];
            [starts addObject:[NSValue valueWithCGRect:start]];
            [targets addObject:[NSValue valueWithCGRect:v.frame]];
            return;
        }
        // A view made for the new items. A tab's button starts where its old one's glyph was, on whichever bar that
        // stood. Of the others, those whose superview was there before: a tab button fades in where it is going; the
        // rest (the selection's bubble) are there at once, or the selected tab's glyph, drawn under the bubble, went
        // with it.
        if ([v isKindOfClass:UITabBar.class]) return;
        NSString *key = isShownIn(v, host) ? buttonKey(v, host) : nil;
        NSValue *was = key ? before.glyphs[key] : nil;
        if (was) {
            [moved addObject:v];
            [starts addObject:was];   // a center in the host, placed once the views above it are back
            [targets addObject:[NSValue valueWithCGRect:v.frame]];
            [taken addObject:key];
        } else if ([before.frames objectForKey:v.superview] && isTabButton(v) && v.alpha > 0.01) {
            [faded addObject:v];
        }
    });
    NSMutableArray<UIView *> *gone = [NSMutableArray array];
    for (UIView *button in before.buttons) {
        NSString *key = [before.keys objectForKey:button];
        if (!button.window && !(key && [taken containsObject:key])) [gone addObject:[before.buttons objectForKey:button]];
    }

    [UIView performWithoutAnimation:^{
        // Top down, so a button's center is placed in its platter where the platter starts.
        for (NSUInteger i = 0; i < moved.count; i++) {
            UIView *v = moved[i];
            if (strcmp(starts[i].objCType, @encode(CGPoint)) != 0) {
                v.frame = starts[i].CGRectValue;
                continue;
            }
            // Its glyph where the old one's was: the button moved by as much as its glyph is off its center.
            UIImageView *glyph = glyphView(v);
            CGPoint inButton = [v convertPoint:glyph.center fromView:glyph.superview], to = [host convertPoint:starts[i].CGPointValue toView:v.superview];
            v.center = CGPointMake(to.x - (inButton.x - CGRectGetMidX(v.bounds)), to.y - (inButton.y - CGRectGetMidY(v.bounds)));
        }
        for (UIView *v in faded) v.alpha = 0;
        for (UIView *picture in gone) [host addSubview:picture];
    }];
    SGRAnimate(SGRMotionBar, ^{
        for (NSUInteger i = 0; i < moved.count; i++) moved[i].frame = targets[i].CGRectValue;
        if (along) along();
    }, completion);
    // The buttons that went leave quickly, and those that came arrive as the platter reaches them.
    SGRAnimate(SGRMotionExit, ^{ for (UIView *picture in gone) picture.alpha = 0; }, ^(BOOL finished) {
        for (UIView *picture in gone) [picture removeFromSuperview];
    });
    SGRAnimate(SGRMotionFade, ^{ for (UIView *v in faded) v.alpha = 1; }, nil);
}

// How far apart two of UIKit's glass platters are, both capsules lying along x (a circle is one too), as `a` and `b` give
// them in one view: the gap between their outlines, negative where they overlap.
static CGFloat platterGapPt(CGRect a, CGRect b) {
    CGFloat ra = MIN(a.size.width, a.size.height) / 2, rb = MIN(b.size.width, b.size.height) / 2;
    CGFloat across = MAX(0, MAX((CGRectGetMinX(a) + ra) - (CGRectGetMaxX(b) - rb), (CGRectGetMinX(b) + rb) - (CGRectGetMaxX(a) - ra)));
    return hypot(across, CGRectGetMidY(a) - CGRectGetMidY(b)) - ra - rb;
}

// The share of the way at which the main bar's growing glass first touches the trailing circle's, each moving from its
// `…From` frame to its `…To` frame in one spring, so in step: on the same share of its way at every moment. 0 when they
// touch at the start, 1 when they never do.
static CGFloat touchFraction(CGRect rowFrom, CGRect rowTo, CGRect circleFrom, CGRect circleTo) {
    CGRect (^at)(CGRect, CGRect, CGFloat) = ^CGRect(CGRect from, CGRect to, CGFloat share) {
        return CGRectMake(from.origin.x + (to.origin.x - from.origin.x) * share, from.origin.y + (to.origin.y - from.origin.y) * share,
                          from.size.width + (to.size.width - from.size.width) * share, from.size.height + (to.size.height - from.size.height) * share);
    };
    if (platterGapPt(rowFrom, circleFrom) <= 0) return 0;
    if (platterGapPt(rowTo, circleTo) > 0) return 1;
    // The gap only closes as the row grows toward the circle and the circle goes into it. Halved this often, the share is
    // known to far less than a point of the row's way.
    const int halvings = 32;
    CGFloat apart = 0, touching = 1;
    for (int i = 0; i < halvings; i++) {
        CGFloat middle = (apart + touching) / 2;
        if (platterGapPt(at(rowFrom, rowTo, middle), at(circleFrom, circleTo, middle)) > 0) apart = middle;
        else touching = middle;
    }
    return touching;
}

// How long `spring` takes to cover `share` of its way, by the physics it is given (mass, stiffness, damping, initial
// velocity), stepped a tenth of a millisecond at a time; its whole duration when it does not get there.
static CFTimeInterval springTimeTo(CASpringAnimation *spring, CGFloat share) {
    const CFTimeInterval stepS = 1e-4;
    double done = 0, speed = spring.initialVelocity;
    for (CFTimeInterval t = 0; t < spring.duration; t += stepS) {
        if (done >= share) return t;
        speed += (-spring.stiffness * (done - 1) - spring.damping * speed) / spring.mass * stepS;
        done += speed * stepS;
    }
    return spring.duration;
}

// The spring a view was last given (SGRMotionBar's, which UIKit makes a CASpringAnimation); nil for none.
static CASpringAnimation *lastSpringOf(UIView *view) {
    CASpringAnimation *spring = nil;
    for (NSString *key in view.layer.animationKeys) {
        CAAnimation *animation = [view.layer animationForKey:key];
        if ([animation isKindOfClass:CASpringAnimation.class]) spring = (CASpringAnimation *)animation;
    }
    return spring;
}

// Expanding, the tab on the trailing circle goes back into the row (setMinimized), and the main bar's platter grows
// from the leading circle under it. The row's button for the tab is clipped by that platter until its edge has passed
// it, and a glyph drawn on the circle kept the circle's glass over the row as a darker disc (issue #35). So the glyph
// travels as a view of its own over both bars, drawn as the row draws it, from the circle's glyph to the row's on the
// bar's spring, the row's glyphs for the tab cleared and its name left to the row. The circle, its own button hidden,
// goes under the main bar along x, and is drawn until the spring reaches the share of its way at which
// the growing platter touches it, so its glass is never over the row's nor under it: its layer's opacity is held at 1
// that long over a model of 0, in the same transaction as the spring, so the render server takes it away in that very
// frame however busy the main thread is. The view's alpha would not do: UIKit hands it to the glass, which went at
// once. As the spring ends the row's glyph, which the spring has brought to the same place, takes over.
@interface SGRHandOver : NSObject
@property (nonatomic, weak) UIView *rowBar, *circleBar;
@property (nonatomic, strong) UIImageView *glyph;            // the travelling glyph
// The glyphs of the row's button and, for the selected tab, its lit copy: cleared while the glyph travels, the buttons
// and their names drawn as the row draws every other tab's. Cleared rather than hidden: a hidden glyph is no tab button
// to tell the bar's buttons apart by (glyphView).
@property (nonatomic, copy) NSArray<UIView *> *rowGlyphs;
@property (nonatomic) CFTimeInterval circleGoneS;            // when the circle stops being drawn (CACurrentMediaTime)
@end

@implementation SGRHandOver
@end

static SGRHandOver *sg_handOver;
static NSString *const kCircleHoldKey = @"sgr.circleHold";

// The pending hand over made now: as the spring ends, or as another change starts, which then takes the tab from the
// row's button and the circle as it is shown, there or gone. The circle's own button stays hidden: the bar is hidden as
// the expand settles, and a minimize gives it its item anew.
static void handOver(void) {
    SGRHandOver *pending = sg_handOver;
    if (!pending) return;
    sg_handOver = nil;
    [pending.glyph removeFromSuperview];
    for (UIView *glyph in pending.rowGlyphs) glyph.alpha = 1;
    UIView *circleBar = pending.circleBar;
    [circleBar.layer removeAnimationForKey:kCircleHoldKey];
    if (CACurrentMediaTime() >= pending.circleGoneS) circleBar.hidden = YES;
    circleBar.layer.opacity = 1;
    circleBar.userInteractionEnabled = YES;
}

// Starts the hand over of the tab whose row button is `rowButton`, back from `circleBar` into `bar`'s row: the circle's
// buttons hidden and it no longer taking touches, the travelling glyph drawn at `from` in `host`, over everything there,
// as the row draws the tab. The caller moves the glyph, then clears the row's glyphs and times the circle (setMinimized).
static SGRHandOver *beginHandOver(UIView *host, SGRSystemTabBar *bar, UIView *circleBar, UIView *rowButton, CGRect from) {
    NSMutableArray<UIView *> *rowGlyphs = [NSMutableArray arrayWithObject:glyphView(rowButton)];
    // The lit copies are drawn only under the selection's bubble, which stands on the selected tab.
    if (((UIControl *)rowButton).selected) {
        SGForEachView(bar, ^(UIView *v) {
            if (isTabButton(v) && isLitCopy(v, bar) && ((UIControl *)v).selected) [rowGlyphs addObject:glyphView(v)];
        });
    }
    // Hidden rather than cleared: an animation of UIKit's own on a button's opacity would keep it drawn.
    SGForEachView(circleBar, ^(UIView *v) {
        if (isTabButton(v)) v.hidden = YES;
    });
    // A finger there is on the row's tab under it, its own tab already going back into the row.
    circleBar.userInteractionEnabled = NO;
    // The glyph the row shows for the tab: its lit copy's when it is the selected one.
    UIImageView *shown = (UIImageView *)rowGlyphs.lastObject;
    UIImageView *glyph = [[UIImageView alloc] initWithImage:shown.image];
    glyph.preferredSymbolConfiguration = shown.preferredSymbolConfiguration;
    glyph.contentMode = shown.contentMode;
    // Resolved where the row draws it: the host keeps the system's appearance, the bars are dark (makeBar).
    glyph.tintColor = [shown.tintColor resolvedColorWithTraitCollection:shown.traitCollection];
    glyph.userInteractionEnabled = NO;
    glyph.frame = from;
    [host addSubview:glyph];
    SGRHandOver *pending = [SGRHandOver new];
    pending.rowBar = bar;
    pending.circleBar = circleBar;
    pending.glyph = glyph;
    pending.rowGlyphs = rowGlyphs;
    pending.circleGoneS = INFINITY;
    sg_handOver = pending;
    return pending;
}

// The circle of `pending` drawn until the main bar's spring, just begun, has covered `share` of its way.
static void holdCircle(SGRHandOver *pending, CGFloat share) {
    UIView *circleBar = pending.circleBar;
    CASpringAnimation *spring = share > 0 ? lastSpringOf(pending.rowBar) : nil;
    if (share > 0 && !spring) SGLog(@"tab bar: no spring on the expanding bar, so the trailing circle goes at once");
    CFTimeInterval holdS = spring ? springTimeTo(spring, share) : 0;
    pending.circleGoneS = CACurrentMediaTime() + holdS;
    circleBar.layer.opacity = 0;
    if (holdS <= 0) return;
    CABasicAnimation *hold = [CABasicAnimation animationWithKeyPath:@"opacity"];
    hold.fromValue = hold.toValue = @1;
    hold.duration = holdS;
    [circleBar.layer addAnimation:hold forKey:kCircleHoldKey];
}

static void setMinimized(BOOL minimized, BOOL animated) {
    UIView *stockBar = sg_stockBar;
    if (minimized && !objc_getAssociatedObject(stockBar, &kStockAppearanceKey)) return;
    if (minimized && tabItems(stockBar).count < kMinimumMinimizedTabs) minimized = NO;
    if (minimized == sg_minimized) return;
    // Spotify's regular width bar is not the glass one's row of tabs; it stays as it is.
    if (minimized && (!stockBar.window || stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact)) return;
    sg_minimized = minimized;
    sg_keepApart = !minimized;
    NSUInteger change = ++sg_barChange;
    SGLog(@"tab bar: %@", minimized ? @"minimized" : @"expanded");
    // An expand turned back hands its tab over to the row first, so the minimize takes it from the row's button.
    handOver();
    if (!stockBar) return;
    UIView *host = objc_getAssociatedObject(stockBar, &kHostKey);
    SGRSystemTabBar *bar = objc_getAssociatedObject(stockBar, &kBarKey);
    // A spring a later change has turned back still ends on its own time, inside the later one's: an expand, a minimize
    // and an expand again, the first expand's end would take the second one's hand over half way.
    void (^settle)(BOOL) = ^(BOOL finished) {
        if (change != sg_barChange) return;
        handOver();
        sg_keepApart = NO;
        syncBar(stockBar);
        // At rest the second bar stands over the main one, as the main bar grows back under split tabs' bar.
        UIView *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
        if (apartBar) [host bringSubviewToFront:apartBar];
    };
    animated &= host.window != nil;
    SGRBarState before = animated ? barState(host) : (SGRBarState){0};
    // The trailing circle's tab, when it is one the expanded row holds (Search, with no split tabs), goes back into the
    // row as the bar expands, its glyph and the two platters from where the screen shows them.
    SGRSystemTabBar *apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    BOOL apartShown = apartBar && !apartBar.hidden;
    UIView *returning = !minimized && apartShown && !sg_rowApartCount ? apartBar.sources.firstObject : nil;
    __block UIView *circleButton = nil;
    if (returning) {
        SGForEachView(apartBar, ^(UIView *v) {
            if (!circleButton && isTabButton(v) && !isLitCopy(v, apartBar)) circleButton = v;
        });
    }
    UIView *mainPlatter = platterOf(bar), *circlePlatter = platterOf(apartBar);
    CGRect circleGlyph = animated && circleButton && mainPlatter && circlePlatter ? shownIn(glyphView(circleButton), host) : CGRectNull;
    CGRect rowGlassFrom = mainPlatter ? shownIn(mainPlatter, host) : CGRectNull, circleGlassFrom = circlePlatter ? shownIn(circlePlatter, host) : CGRectNull;
    // The items are made where the bars are going, before anything moves. UIKit sizes a tab's name by the platter
    // its item is made in and never again, and the first pass made the expanding row's items while the bar still
    // held the circle's one item, its platter a circle: "Your Library" stayed cut. So they are made a second time,
    // the platters now the full row's, and the names are whole all the way.
    [UIView performWithoutAnimation:^{
        syncBar(stockBar);
        [host layoutIfNeeded];
        if (!minimized) {
            ((SGRSystemTabBar *)objc_getAssociatedObject(stockBar, &kBarKey)).sources = nil;
            ((SGRSystemTabBar *)objc_getAssociatedObject(stockBar, &kApartBarKey)).sources = nil;
            syncBar(stockBar);
            [host layoutIfNeeded];
        }
        if (!animated) SGRNowPlayingBarFollowTabBar();
    }];
    if (!animated) {
        settle(YES);
        return;
    }
    // A tab moving between the row and the trailing circle is never under another bar's glass. Minimizing, the circle
    // comes out of the place the tab had in the row, over the main bar. Expanding, the main bar stands over the circle,
    // and the tab's glyph travels over both to the row (SGRHandOver). Only the glyph rises to make room for its name;
    // the circle stays level with the growing platter until they touch.
    apartBar = objc_getAssociatedObject(stockBar, &kApartBarKey);
    __block UIView *rowButton = nil;
    __block CGRect glyphTo = CGRectNull;
    __block CGFloat circleShare = 0;
    [UIView performWithoutAnimation:^{
        if (returning && !apartBar.hidden) {
            rowButton = CGRectIsNull(circleGlyph) ? nil : buttonOf(bar, returning);
            if (rowButton) {
                UIImageView *rowGlyph = glyphView(rowButton), *ownGlyph = glyphView(circleButton);
                glyphTo = [host convertRect:rowGlyph.bounds fromView:rowGlyph];
                CGRect from = [host convertRect:ownGlyph.bounds fromView:ownGlyph];
                apartBar.frame = CGRectOffset(apartBar.frame, CGRectGetMidX(glyphTo) - CGRectGetMidX(from), 0);
                UIView *rowGlass = platterOf(bar), *circleGlass = platterOf(apartBar);
                circleShare = touchFraction(rowGlassFrom, [host convertRect:rowGlass.bounds fromView:rowGlass],
                                            circleGlassFrom, [host convertRect:circleGlass.bounds fromView:circleGlass]);
            }
            [host bringSubviewToFront:bar];
            return;
        }
        if (!minimized || !apartBar || apartBar.hidden) return;
        NSValue *glyph = apartShown ? nil : before.glyphs[tabKey(apartBar.sources.firstObject)];
        if (glyph) {
            CGRect start = apartBar.frame;
            start.origin.x = glyph.CGPointValue.x - start.size.width / 2;
            [before.frames setObject:@[[NSValue valueWithCGRect:start], [NSValue valueWithCGRect:start], @NO] forKey:apartBar];
        }
        [host bringSubviewToFront:apartBar];
    }];
    SGRHandOver *travel = rowButton ? beginHandOver(host, bar, apartBar, rowButton, circleGlyph) : nil;
    moveFrom(host, before, ^{
        SGRNowPlayingBarFollowTabBar();
        travel.glyph.frame = glyphTo;
    }, settle);
    // The row's glyphs are cleared once moveFrom has had them travel with the glyph, so a change that turns the expand
    // back finds the tab's glyph there, and the circle is timed by the spring moveFrom has begun. A spring done at once
    // (Reduce Motion) has already settled.
    if (travel && travel == sg_handOver) {
        for (UIView *glyph in travel.rowGlyphs) glyph.alpha = 0;
        holdCircle(travel, circleShare);
    }
}

CGRect SGRTabBarInlineSlot(UIView *host, CGFloat height) {
    UIView *stockBar = sg_stockBar;
    UIView *bar = stockBar ? objc_getAssociatedObject(stockBar, &kBarKey) : nil;
    UIView *apartBar = stockBar ? objc_getAssociatedObject(stockBar, &kApartBarKey) : nil;
    if (!sg_minimized || !host || !bar.window || stockBar.hidden || stockBar.alpha < 0.01) return CGRectNull;
    // The frames the bars are going to, not what is on screen mid-spring. Without a trailing circle the card
    // runs to where that circle's glass would end.
    CGRect lead = [bar.superview convertRect:bar.frame toView:host];
    CGFloat left = CGRectGetMinX(lead) + SGRBarPlatterInsetPt + SGRBarApartItemWidthPt + SGRGrid;
    CGFloat right;
    if (apartBar && !apartBar.hidden) {
        CGRect trail = [apartBar.superview convertRect:apartBar.frame toView:host];
        right = CGRectGetMaxX(trail) - SGRBarPlatterInsetPt - SGRBarApartItemWidthPt - SGRGrid;
    } else {
        CGRect whole = [stockBar convertRect:stockBar.bounds toView:host];
        right = CGRectGetMaxX(whole) - SGRBarPlatterInsetPt;
    }
    CGFloat middle = CGRectGetMinY(lead) + SGRBarApartItemWidthPt / 2;
    CGRect slot = CGRectMake(left, middle - height / 2, right - left, height);
    // A bar Spotify has slid away for a page takes the slot off the screen with it.
    CGRect inWindow = [host convertRect:slot toView:nil];
    if (slot.size.width < 100 || CGRectGetMaxY(inWindow) > CGRectGetMaxY(bar.window.bounds)) return CGRectNull;
    return slot;
}

#pragma mark - the glass row

// The expanded row's glass, whether the bar is expanded now or minimized: each bar at its SGRExpandedBarFrames frame,
// its platter where UIKit drew it there. UIKit draws a platter SGRBarPlatterInsetPt in from the sides of a bar its
// items fill, and a narrower one centered in it when they do not: with Search split the main bar's three tabs got a
// 274 pt platter at x 27 in a 328 pt bar (harness/tabbar, iPhone 17 Pro). So each bar's platter is read while it is
// expanded (noteGlassRow) and kept for its width; a bar not yet read at its width counts as filled. Only the x edges
// are meant; a bar Spotify has slid away for a page keeps them.
static CGRect glassIn(SGRSystemTabBar *bar, CGRect frame) {
    if (!bar || fabs(bar.glassBarWidthPt - frame.size.width) >= 0.5) return CGRectInset(frame, SGRBarPlatterInsetPt, 0);
    return CGRectMake(CGRectGetMinX(frame) + bar.glassLeftPt, CGRectGetMinY(frame), frame.size.width - bar.glassLeftPt - bar.glassRightPt, frame.size.height);
}

CGRect SGRTabBarGlassRow(UIView *view) {
    UIView *stockBar = sg_stockBar;
    UIView *host = stockBar ? objc_getAssociatedObject(stockBar, &kHostKey) : nil;
    if (!view || !host.window || stockBar.traitCollection.horizontalSizeClass != UIUserInterfaceSizeClassCompact) return CGRectNull;
    CGRect main, apart;
    SGRExpandedBarFrames(host.bounds, sg_rowApartCount, &main, &apart);
    CGRect row = glassIn(objc_getAssociatedObject(stockBar, &kBarKey), main);
    if (sg_rowApartCount) row = CGRectUnion(row, glassIn(objc_getAssociatedObject(stockBar, &kApartBarKey), apart));
    return [host convertRect:row toView:view];
}

// The widest glass platter UIKit drew on `bar`; nil before it has drawn one.
static UIView *platterOf(UIView *bar) {
    __block UIView *widest = nil;
    SGForEachView(bar, ^(UIView *v) {
        if (v == bar || v.hidden || ![NSStringFromClass(v.class) hasSuffix:@"PlatterView"]) return;
        if (!widest || [v convertRect:v.bounds toView:bar].size.width > [widest convertRect:widest.bounds toView:bar].size.width) widest = v;
    });
    return widest;
}

// Expanded, each bar's platter read again where the pass that laid it out has left it, and the now playing card told
// when the row comes, goes or its sides move. Once per turn of the run loop however many passes ask.
static void noteGlassRow(void) {
    static BOOL pending;
    if (pending) return;
    pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        pending = NO;
        UIView *stockBar = sg_stockBar;
        UIView *host = stockBar ? objc_getAssociatedObject(stockBar, &kHostKey) : nil;
        if (!host) return;
        if (!sg_minimized) {
            CGRect main, apart;
            SGRExpandedBarFrames(host.bounds, sg_rowApartCount, &main, &apart);
            NSArray *bars = @[objc_getAssociatedObject(stockBar, &kBarKey) ?: NSNull.null, objc_getAssociatedObject(stockBar, &kApartBarKey) ?: NSNull.null];
            for (NSUInteger i = 0; i < bars.count; i++) {
                SGRSystemTabBar *bar = bars[i];
                // Read only at its expanded frame's width: the main bar still growing back under a split bar is not.
                CGFloat width = (i ? apart : main).size.width;
                if (![bar isKindOfClass:SGRSystemTabBar.class] || bar.hidden || !bar.window || fabs(bar.bounds.size.width - width) >= 0.5) continue;
                UIView *platterView = platterOf(bar);
                if (!platterView) continue;
                CGRect platter = [platterView convertRect:platterView.bounds toView:bar];
                bar.glassLeftPt = CGRectGetMinX(platter);
                bar.glassRightPt = bar.bounds.size.width - CGRectGetMaxX(platter);
                bar.glassBarWidthPt = bar.bounds.size.width;
            }
        }
        CGRect row = SGRTabBarGlassRow(stockBar.window);
        BOOL moved = CGRectIsNull(row) != CGRectIsNull(sg_glassRow)
            || (!CGRectIsNull(row) && (fabs(CGRectGetMinX(row) - CGRectGetMinX(sg_glassRow)) >= 0.5
                                       || fabs(CGRectGetMaxX(row) - CGRectGetMaxX(sg_glassRow)) >= 0.5));
        // Minimized, the slot's sides move when the trailing circle comes or goes with Spotify's list of tabs (Search
        // leaving the row), the expanded row's staying put. The slot coming or going is the minimize's own, which moves
        // the card in its spring (setMinimized), or Spotify sliding the bar away, which the card's own layout follows.
        CGRect slot = stockBar.window ? SGRTabBarInlineSlot(stockBar.window, 0) : CGRectNull;
        moved |= !CGRectIsNull(slot) && !CGRectIsNull(sg_inlineSlot)
            && (fabs(CGRectGetMinX(slot) - CGRectGetMinX(sg_inlineSlot)) >= 0.5 || fabs(CGRectGetMaxX(slot) - CGRectGetMaxX(sg_inlineSlot)) >= 0.5);
        sg_inlineSlot = slot;
        if (!moved) return;
        sg_glassRow = row;
        SGRNowPlayingBarFollowTabBar();
    });
}

#pragma mark - hooks

static UIView *tabBarOf(UIView *item) {
    Class barClass = NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView");
    for (UIView *v = item.superview; v; v = v.superview) if ([v isKindOfClass:barClass]) return v;
    return nil;
}

// The bar in its own pass, and whether one of its items laid out during it.
static __weak UIView *sg_passBar;
static BOOL sg_itemsLaidOut;

%hook _TtC23NavigationUI_TabBarImpl10TabBarView
- (void)layoutSubviews {
    // A pass nested in another (an item's layoutIfNeeded) hands both back, so the outer one still composes.
    UIView *bar = (UIView *)self, *outer = sg_passBar;
    BOOL outerLaidOut = sg_itemsLaidOut;
    sg_passBar = bar;
    %orig;
    SGRComposeTabBar(bar);
    sg_itemsLaidOut = NO;
    for (UIView *sub in bar.subviews) {
        if (![sub isKindOfClass:SGRTabBarHost.class] && ![sub isKindOfClass:SGRBarFade.class]) [sub layoutIfNeeded];
    }
    // Items the row's pass laid out are composed once, all together, rather than once each.
    if (sg_itemsLaidOut) SGRComposeTabBar(bar);
    sg_passBar = outer;
    sg_itemsLaidOut = outerLaidOut;
    holdHome(bar);
    syncBar(bar);
}
%end

// The bar's own pass runs before Spotify has filled the row; the items lay out as they arrive. Inside the bar's
// pass, the pass composes once after them; outside it, the item composes at once, so no frame shows Spotify's row.
static void itemDidLayOut(UIView *item) {
    UIView *bar = tabBarOf(item);
    if (!bar) return;
    if (bar == sg_passBar) {
        sg_itemsLaidOut = YES;
        return;
    }
    SGRComposeTabBar(bar);
    holdHome(bar);
    syncBar(bar);
}

%hook _TtC23NavigationUI_TabBarImpl21TabBarItemElementView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

%hook _TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView
- (void)layoutSubviews {
    %orig;
    itemDidLayOut((UIView *)self);
}
%end

// A tab changed from elsewhere (a link, the side drawer) repaints the labels without a layout pass.
%hook _TtC23NavigationUI_TabBarImpl19TabBarContainerImpl
- (void)setSelectedViewController:(UIViewController *)controller {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Another tab brings the minimized bar back (HIG, Tab bars).
        SGRSetTabBarMinimized(NO, YES);
        UIView *bar = sg_stockBar;
        if (bar) syncBar(bar);
    });
}
// The message bar coming or going changes the view's safe area before Spotify lays the bar out for it,
// so the room follows in that same pass, and inside the message bar's animation.
- (void)viewSafeAreaInsetsDidChange {
    %orig;
    makeRoom((UIViewController *)self);
}
%end

// Spotify's own fade under its bar, 219 pt down to black from 9.1.90 (TabBarGradientView), stacked with SGRBarFade
// into a band near black over the page's foot. SGRBarFade is the redesign's, so Spotify's stays clear.
%group SpotifyBarFade
%hook _TtC23NavigationUI_TabBarImpl18TabBarGradientView
- (void)didMoveToWindow {
    %orig;
    UIView *gradient = (UIView *)self;
    if (!stockGradients) stockGradients = [NSHashTable weakObjectsHashTable];
    [stockGradients addObject:gradient];
    mirrorGradient(gradient);
}
- (void)setAlpha:(CGFloat)alpha {
    if (objc_getAssociatedObject(self, &kGradientAlphaKey)) {
        objc_setAssociatedObject(self, &kGradientAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        alpha = 0;
    }
    %orig(alpha);
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    %init;
    if (objc_getClass("_TtC23NavigationUI_TabBarImpl18TabBarGradientView")) %init(SpotifyBarFade);
    SGRequireClasses(@[
        @"_TtC23NavigationUI_TabBarImpl10TabBarView",
        @"_TtC23NavigationUI_TabBarImpl21TabBarItemElementView",
        @"_TtC25CreateMenu_TabBarItemImpl24CreateMenuTabBarItemView",
        @"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl",
    ]);
}
