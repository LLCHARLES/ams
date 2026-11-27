// The redesign's copy of Native/Navbar/Navbar.x, composing the row the glass tab bar mirrors.
// Navbar: which tabs the bar shows, in what order, and tabs of the mod's own that open any
// spotify: URI. Spotify keeps its four items (Home, Search, Library, Create) as the arranged
// subviews of one stack view, but a tap on one of them is answered by counting the row off from
// the left, not by asking the item what it is: moved in the stack, an item takes the tap of
// whatever used to stand there. So the stack's own order is left exactly as Spotify built it.
//
// The row is split into equal slots instead, and each item is given the frame of its slot after
// the stack's own pass: hit testing goes by frame, so the touch follows the icon, while Spotify
// still counts its items off in the order it put them in. Items of the mod's own go on the end of
// the stack, past that count, and take a slot with the rest. A tap on one goes through Spotify's
// link dispatcher, the same route the app takes for a link it opens itself, so any URI works.
//
// The page that link pushes is the tab's: the glass bar lights the tab while that page is on its stack and
// the stack is on screen, and a second tap goes back to the page rather than opening the link again, the
// way a second tap on one of Spotify's tabs goes back to its root.
//
// Tree (trees/home.txt): NavigationUI_TabBarImpl.TabBarView > TabBarCompactView > UIStackView
//   402x49 of four ElementContentView<TabBarItemElement> 100x49, each an SPTEncoreIconView 24x24
//   at y 12.5 over an SPTEncoreLabel at y 35.
#import "Core/SGCore.h"
#import "Navbar.h"
#import "Shared/Navigation/Links.h"
#import "Shared/Navigation/TabIcons.h"
#import "Shared/WireGuard/SGWGABI.h"
#import <objc/message.h>

static const CGFloat kIconSize = 24;
static const CGFloat kIconTop = 12.5;
static const CGFloat kLabelTop = 35;
static const CGFloat kLabelHeight = 14;
static char kCustomKey, kOrderKey, kApartKey;
// Between the main group and the split tabs (Split tabs), when both have something on the bar.
static const CGFloat kSplitGap = 10;

// Where Spotify's own items keep their icon and label, read off one of them every pass, so an item of
// the mod's own sits on the same line as its neighbors.
static CGRect sg_iconBox = {{0, kIconTop}, {kIconSize, kIconSize}};
static CGRect sg_labelBox = {{0, kLabelTop}, {0, kLabelHeight}};

static __weak UIView *sg_navbarRoot;
// The bar's row of items, given its frames by placeRow after each of its own passes.
static __weak UIStackView *sg_row;
static UIFont *sg_tabFont;
// Spotify's own tabs in Spotify's order, from the first layout pass of this launch, before
// anything below has moved them.
static NSMutableArray<NSString *> *sg_stockOrder;
// How many tabs at the end of the row are split off from the rest, 0 for one group.
static NSUInteger sg_apartCount;

static UIColor *itemColor(void) { return [UIColor colorWithWhite:0xB3 / 255.0 alpha:1]; }

// A page pushed this soon after a tap on a tab of the mod's own is the page the tab opened.
static const CFTimeInterval kTabPush = 1;
static __weak UIView *sg_tappedTab, *sg_pageTab;
static CFTimeInterval sg_tappedAt;
static __weak UIViewController *sg_tabPage;

static BOOL tabPageShowing(void) {
    UIViewController *page = sg_tabPage;
    UINavigationController *nav = page.navigationController;
    return sg_pageTab && nav.viewIfLoaded.window && [nav.viewControllers containsObject:page];
}

#pragma mark - the mod's own items

// Drawn the way Spotify's own are, an Encore glyph or an SF Symbol at the glyphs' size
// (Shared/Navigation/TabIcons.h).
static UIView *iconView(NSDictionary *entry) {
    return SGTabIconView(entry[SGRNavbarIcon], [entry[SGRNavbarIconSet] isEqual:SGTabIconSetSymbols], itemColor());
}

@interface SGRTabItemView : UIControl
@property (nonatomic, copy) NSString *uri;
- (instancetype)initWithEntry:(NSDictionary *)entry;
- (void)applyEntry:(NSDictionary *)entry;
@end

@implementation SGRTabItemView {
    NSString *_iconName;
    UIView *_icon;
    UILabel *_title;
}

- (instancetype)initWithEntry:(NSDictionary *)entry {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    _title = [UILabel new];
    _title.textAlignment = NSTextAlignmentCenter;
    _title.textColor = itemColor();
    [self addSubview:_title];
    [self applyEntry:entry];
    [self addTarget:self action:@selector(open) forControlEvents:UIControlEventTouchUpInside];
    return self;
}

- (void)applyEntry:(NSDictionary *)entry {
    self.uri = entry[SGRNavbarURI];
    _title.text = entry[SGRNavbarTitle];
    // The set is part of the name: "star" is a glyph in one and a symbol in the other.
    NSString *name = [NSString stringWithFormat:@"%@ %@", entry[SGRNavbarIconSet] ?: @"encore", entry[SGRNavbarIcon] ?: @"star"];
    if ([name isEqualToString:_iconName]) return;
    [_icon removeFromSuperview];
    _iconName = [name copy];
    _icon = iconView(entry);
    // Encore's views lay themselves out from constraints; this one is placed by frame.
    _icon.translatesAutoresizingMaskIntoConstraints = YES;
    _icon.frame = (CGRect){CGPointZero, sg_iconBox.size};
    [self addSubview:_icon];
}

// Both boxes come off a neighbor, so whatever Spotify does to the row's line-up is copied rather than
// guessed at; only the horizontal centering is the item's own.
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    // The glass bar of TabBar.x draws the names; the hidden row keeps its icons for the glyphs.
    _title.hidden = YES;
    _title.font = sg_tabFont ?: [UIFont systemFontOfSize:10];
    _title.frame = CGRectMake(0, CGRectGetMinY(sg_labelBox), width, CGRectGetHeight(sg_labelBox));
    _icon.frame = CGRectMake((width - CGRectGetWidth(sg_iconBox)) / 2, CGRectGetMinY(sg_iconBox),
                             CGRectGetWidth(sg_iconBox), CGRectGetHeight(sg_iconBox));
}

// A row that splits its width evenly ignores this, but one that sizes itself to its content would
// otherwise have nothing to go on for an item of ours.
- (CGSize)intrinsicContentSize {
    return CGSizeMake(kIconSize * 2, kLabelTop + kLabelHeight);
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.5 : 1;
}

// Through the app's own link dispatcher (Shared/Navigation/Links.h). What the dispatcher makes of the
// URI goes to the log first, so a tab that ends in Spotify's "Couldn't open link" says why.
- (void)open {
    UIViewController *page = sg_tabPage;
    if (sg_pageTab == self && tabPageShowing()) {
        UINavigationController *nav = page.navigationController;
        if (nav.topViewController != page) [nav popToViewController:page animated:YES];
        SGLog(@"navbar: back to the tab's page %@", NSStringFromClass(page.class));
        return;
    }
    sg_tappedTab = self;
    sg_tappedAt = CACurrentMediaTime();
    // A link that pushes no page leaves the light where Spotify has it.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((kTabPush + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SGRRefreshTabBar();
    });
    NSURL *url = SGRNavbarTabURL(self.uri);
    NSString *via = nil;
    SGLinkRoute route = SGSpotifyURIRoute(url, &via);
    SGLog(@"navbar: open %@ -> %@", url.absoluteString ?: self.uri,
          route == SGLinkRouteOpens ? via : route == SGLinkRouteNone ? @"no handler" : @"unknown");
    if (!SGOpenSpotifyURI(url)) SGLog(@"navbar: cannot open %@, dispatcher %@", self.uri, SGLinkDispatcher());
}

@end

#pragma mark - composition

// Spotify's items are told apart by the label under the icon: it survives the element views being
// rebuilt, and it is the name the Navbar page lists them under.
static NSString *stockID(UIView *item) {
    __block NSString *text = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!text && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) text = ((UILabel *)v).text;
    });
    return text;
}

static void measureItem(UIView *item) {
    __block UIView *icon = nil, *label = nil;
    SGForEachView(item, ^(UIView *v) {
        if (!icon && [NSStringFromClass(v.class) containsString:@"IconView"] && v.bounds.size.width > 1) icon = v;
        if (!label && [v isKindOfClass:UILabel.class] && ((UILabel *)v).text.length) label = v;
    });
    if (icon) sg_iconBox = SGFrameIn(icon, item);
    if (!label) return;
    sg_labelBox = SGFrameIn(label, item);
    if (!sg_tabFont) sg_tabFont = ((UILabel *)label).font;
}

static NSMutableDictionary<NSString *, SGRTabItemView *> *customItems(UIStackView *stack) {
    NSMutableDictionary *items = objc_getAssociatedObject(stack, &kCustomKey);
    if (!items) {
        items = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(stack, &kCustomKey, items, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return items;
}

void SGRComposeTabBar(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    if (!stack) return;
    sg_navbarRoot = tabBar;

    NSMutableDictionary<NSString *, UIView *> *stockViews = [NSMutableDictionary dictionary];
    NSMutableArray<UIView *> *stockItems = [NSMutableArray array];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (UIView *item in stack.arrangedSubviews) {
        if ([item isKindOfClass:SGRTabItemView.class]) continue;
        NSString *ident = stockID(item);
        if (ident) {
            if (stockViews[ident]) continue;
            stockViews[ident] = item;
            [labels addObject:ident];
        }
        [stockItems addObject:item];
        measureItem(item);
    }
    // Publish the names in Spotify's order once every item has one. The
    // partially constructed row still contributes each individual view below.
    if (labels.count && labels.count == stockItems.count) {
        if (!sg_stockOrder) sg_stockOrder = [NSMutableArray array];
        for (NSString *ident in labels) if (![sg_stockOrder containsObject:ident]) [sg_stockOrder addObject:ident];
        if (![sg_stockOrder isEqualToArray:SGRNavbarStock()]) SGRSetNavbarStock(sg_stockOrder);
    }

    NSMutableDictionary<NSString *, SGRTabItemView *> *custom = customItems(stack);
    NSMutableArray<UIView *> *wanted = [NSMutableArray array];
    NSMutableSet<NSString *> *placed = [NSMutableSet set];
    NSMutableSet<NSString *> *keep = [NSMutableSet set];
    NSArray<NSDictionary *> *splitList = SGEnabled(SGRKeyNavbar) ? SGRNavbarSplit() : @[];
    NSMutableSet<NSString *> *splitStock = [NSMutableSet set];
    for (NSDictionary *entry in splitList) if (!entry[SGRNavbarURI] && [entry[SGRNavbarID] isKindOfClass:NSString.class]) [splitStock addObject:entry[SGRNavbarID]];
    NSMutableSet<UIView *> *apart = [NSMutableSet set];

    if (SGEnabled(SGRKeyNavbar)) {
        for (NSDictionary *entry in SGRNavbarLayout()) {
            NSString *ident = entry[SGRNavbarID];
            if (![ident isKindOfClass:NSString.class] || [placed containsObject:ident]) continue;
            [placed addObject:ident];
            BOOL hidden = [entry[SGRNavbarHidden] boolValue];
            if (entry[SGRNavbarURI]) {
                if (hidden) continue;
                SGRTabItemView *item = custom[ident];
                if (item) [item applyEntry:entry];
                else custom[ident] = item = [[SGRTabItemView alloc] initWithEntry:entry];
                [keep addObject:ident];
                [wanted addObject:item];
            } else if (stockViews[ident] && ![splitStock containsObject:ident]) {
                stockViews[ident].hidden = hidden;
                [wanted addObject:stockViews[ident]];
            }
        }
    }
    // Tabs of Spotify's the list does not name — or named before Spotify had built them — keep
    // Spotify's own place, at the end, shown.
    for (UIView *item in stockItems) {
        if ([wanted containsObject:item]) continue;
        NSString *ident = stockID(item);
        if (ident && [splitStock containsObject:ident]) continue;
        item.hidden = NO;
        [wanted addObject:item];
    }
    // The split tabs, from their own list: the mod's own are separate from the bar's, Spotify's are shown.
    NSMutableSet<NSString *> *placedApart = [NSMutableSet set];
    for (NSDictionary *entry in splitList) {
        NSString *ident = entry[SGRNavbarID];
        if (![ident isKindOfClass:NSString.class] || [placedApart containsObject:ident]) continue;
        [placedApart addObject:ident];
        if (entry[SGRNavbarURI]) {
            SGRTabItemView *item = custom[ident];
            if (item) [item applyEntry:entry];
            else custom[ident] = item = [[SGRTabItemView alloc] initWithEntry:entry];
            [keep addObject:ident];
            [wanted addObject:item];
            [apart addObject:item];
        } else if (stockViews[ident]) {
            stockViews[ident].hidden = NO;
            [wanted addObject:stockViews[ident]];
            [apart addObject:stockViews[ident]];
        }
    }
    for (NSString *ident in custom.allKeys) {
        if ([keep containsObject:ident]) continue;
        [custom[ident] removeFromSuperview];
        [custom removeObjectForKey:ident];
    }

    // A bar with nothing on it would strand whoever emptied it, so the last word is Spotify's.
    BOOL empty = YES;
    for (UIView *item in wanted) if (!item.hidden) empty = NO;
    if (empty) for (UIView *item in wanted) item.hidden = NO;

    // Items of the mod's own join the stack at the end, where they are past whatever Spotify
    // counts, and Spotify's own keep the places it gave them.
    for (UIView *item in wanted) {
        if ([item isKindOfClass:SGRTabItemView.class] && item.superview != stack) [stack addArrangedSubview:item];
    }
    // Split tabs go to the end, each group in the list's order. With nothing left in the main group they
    // are the bar's one group.
    NSMutableArray<UIView *> *order = [NSMutableArray array], *trailing = [NSMutableArray array];
    for (UIView *item in wanted) {
        if (item.hidden || item.superview != stack) continue;
        [([apart containsObject:item] ? trailing : order) addObject:item];
    }
    NSUInteger apartCount = order.count ? trailing.count : 0;
    [order addObjectsFromArray:trailing];
    [order enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        objc_setAssociatedObject(item, &kApartKey, i + apartCount >= order.count ? @YES : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
    sg_row = stack;
    if (![order isEqualToArray:objc_getAssociatedObject(stack, &kOrderKey)] || apartCount != sg_apartCount) {
        sg_apartCount = apartCount;
        objc_setAssociatedObject(stack, &kOrderKey, order, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [stack setNeedsLayout];
    }
}

NSArray<UIView *> *SGRComposedTabItems(UIView *tabBar) {
    UIStackView *stack = SGRowIn(tabBar);
    NSArray<UIView *> *order = objc_getAssociatedObject(stack, &kOrderKey);
    NSMutableArray<UIView *> *visible = [NSMutableArray arrayWithCapacity:order.count];
    for (UIView *view in order) {
        if (!view.hidden && view.superview == stack && [stack.arrangedSubviews containsObject:view]) [visible addObject:view];
    }
    return visible;
}

// Spotify placed the icon and the label for the width it measured (trees/test5.txt: x 28 in a
// 134pt slot, the center of the 80pt it had with five tabs) and lays the item out no further
// once the slot changes. Assigning the centers back sends them through the hooks below, which look no further
// up for the slot than the deepest of these views sits in one (3 in Spotify's items: trees, 2026-10).
static NSUInteger sg_slotDepth;
static void centreContents(UIView *item) {
    SGForEachView(item, ^(UIView *v) {
        if (![v isKindOfClass:%c(SPTEncoreIconView)] && ![v isKindOfClass:%c(SPTEncoreLabel)]) return;
        NSUInteger depth = 1;
        for (UIView *up = v.superview; up && up != item; up = up.superview) depth++;
        if (depth > sg_slotDepth) sg_slotDepth = depth;
        v.center = v.center;
    });
}

// Equal slots across the bar, in the order composed above, the split tabs' after a gap. The frames go on
// after the stack's own pass, so Spotify's own widths never decide whether a fifth item fits.
static void placeRow(UIStackView *stack) {
    NSArray<UIView *> *order = objc_getAssociatedObject(stack, &kOrderKey);
    UIView *bar = sg_navbarRoot;
    if (!order.count || !bar) return;
    CGFloat gap = sg_apartCount ? kSplitGap : 0;
    CGFloat width = (bar.bounds.size.width - gap) / order.count;
    CGFloat height = stack.bounds.size.height;
    NSUInteger firstApart = order.count - sg_apartCount;
    [order enumerateObjectsUsingBlock:^(UIView *item, NSUInteger i, BOOL *stop) {
        CGFloat left = i * width + (i >= firstApart ? gap : 0);
        CGFloat x = [bar convertPoint:CGPointMake(left, 0) toView:stack].x;
        CGRect frame = CGRectMake(x, 0, width, height);
        if (!CGAffineTransformIsIdentity(item.transform)) item.transform = CGAffineTransformIdentity;
        if (!CGRectEqualToRect(item.frame, frame)) item.frame = frame;
        centreContents(item);
    }];
}

%hook UIStackView
- (void)layoutSubviews {
    %orig;
    if ((UIStackView *)self == sg_row) placeRow((UIStackView *)self);
}
%end

// Spotify's element layout places the icon and the label from the width it measured, not from
// the slot above (trees/test5.txt: x 38 in a 134pt element in a 126pt slot), and a view placed by
// its parent gets no layout pass of its own. So the placement itself is bent: on the bar, whatever
// x Spotify sets, the view lands centered on its slot.
static CGFloat slotCentreX(UIView *view) {
    UIStackView *row = sg_row;
    if (!row) return NAN;
    UIView *slot = nil;
    // No depth seen yet means no row centred yet: the walk goes all the way up.
    NSUInteger steps = 0, limit = sg_slotDepth ? sg_slotDepth : NSUIntegerMax;
    for (UIView *v = view; v.superview && steps++ <= limit; v = v.superview) if (v.superview == row) { slot = v; break; }
    if (!slot) return NAN;
    return [slot convertPoint:CGPointMake(CGRectGetMidX(slot.bounds), 0) toView:view.superview].x;
}

%hook SPTEncoreIconView
- (void)setFrame:(CGRect)frame {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) frame.origin.x = centre - frame.size.width / 2;
    %orig(frame);
}
- (void)setCenter:(CGPoint)center {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) center.x = centre;
    %orig(center);
}
%end

%hook SPTEncoreLabel
- (void)setFrame:(CGRect)frame {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) frame.origin.x = centre - frame.size.width / 2;
    %orig(frame);
}
- (void)setCenter:(CGPoint)center {
    CGFloat centre = slotCentreX((UIView *)self);
    if (!isnan(centre)) center.x = centre;
    %orig(center);
}
%end

UIView *SGRNavbarLitTab(void) {
    if (tabPageShowing()) return sg_pageTab;
    // From the tap until its page comes, so the bar does not go back to Spotify's tab in between.
    return CACurrentMediaTime() - sg_tappedAt < kTabPush ? sg_tappedTab : nil;
}

void SGRNavbarForgetTab(void) {
    sg_tappedTab = sg_pageTab = nil;
    sg_tabPage = nil;
}

%hook SPNavigationController
- (void)pushViewController:(UIViewController *)page animated:(BOOL)animated {
    UIView *tab = sg_tappedTab;
    if (tab && CACurrentMediaTime() - sg_tappedAt < kTabPush) {
        sg_pageTab = tab;
        sg_tabPage = page;
        sg_tappedTab = nil;
        SGLog(@"navbar: %@ is the tab's page", NSStringFromClass(page.class));
    }
    %orig;
}

// A push, a pop or a swipe back: the bar looks again at whether the tab's page is still up.
- (void)navigationController:(UINavigationController *)controller didShowViewController:(UIViewController *)page animated:(BOOL)animated {
    %orig;
    if (sg_pageTab) SGRRefreshTabBar();
}
%end

BOOL SGRTabIsApart(UIView *item) {
    return objc_getAssociatedObject(item, &kApartKey) != nil;
}

void SGRRefreshTabBar(void) {
    [sg_navbarRoot setNeedsLayout];
}

// Whether Spotify reads its own item list through this ObjC bridge decides whether the bar can be
// composed at the model level, where the order, the taps and the widths would all follow by
// themselves, instead of by moving views about. Silence in the log says it cannot. It does read it (phone log,
// 9.1.90: 홈 · spotify:home, 검색하기 · spotify:find, 내 라이브러리 · spotify:collection, 만들기 ·
// spotify:internal:playlist-creation-container), each title the label under the tab's icon, so the pages the tabs
// open are kept by those labels for Apple symbols (SGRNavbarStockURIs). The bar lays out again when they change, on the
// main queue, as nothing says Spotify reads the list on the main thread.
%group SGRStockItems
%hook _TtC28NavigationUI_TabBarItemsImpl29TabBarItemsNavigationListImpl
- (NSArray *)items {
    NSArray *items = %orig;
    if (![items isKindOfClass:NSArray.class]) {
        SGRSetNavbarStockURIs(@{});
        return items;
    }
    NSMutableString *out = [NSMutableString stringWithFormat:@"list read, %lu items", (unsigned long)items.count];
    NSMutableDictionary<NSString *, NSString *> *uris = [NSMutableDictionary dictionary];
    for (id item in items) {
        if (![item respondsToSelector:@selector(title)] || ![item respondsToSelector:NSSelectorFromString(@"viewURI")]) {
            static dispatch_once_t once;
            dispatch_once(&once, ^{ SGLog(@"navbar: item title or viewURI unavailable"); });
            continue;
        }
        id title = [item valueForKey:@"title"], uri = [item valueForKey:@"viewURI"];
        [out appendFormat:@"\n  %@ · %@", title, uri];
        NSString *page = [uri isKindOfClass:NSURL.class] ? [uri absoluteString] : [uri isKindOfClass:NSString.class] ? uri : nil;
        if ([title isKindOfClass:NSString.class] && page.length) uris[title] = page;
    }
    SGRSetNavbarStockURIs(uris);
    // Spotify may read the list on any thread; the dedupe's last line is shared between them.
    static NSString *last;
    BOOL changed;
    @synchronized ([(id)self class]) {
        changed = ![out isEqualToString:last];
        if (changed) last = [out copy];
    }
    if (changed) SGLogLong(@"navbar", out);
    return items;
}
%end
%end

%ctor {
    if (!SGRedesignedUI()) return;
    SGRMigrateNavbarSplit();
    %init;
    Class list = NSClassFromString(@"_TtC28NavigationUI_TabBarItemsImpl29TabBarItemsNavigationListImpl");
    if (SGWGMethodMatches(class_getInstanceMethod(list, @selector(items)), "@", @[])) {
        %init(SGRStockItems);
    } else {
        SGLog(@"navbar: stock items getter unavailable");
    }
    SGRequireClasses(@[
        @"SPNavigationController",
        @"SPTEncoreIcon",
        @"SPTEncoreIconView",
        @"SPTEncoreLabel",
        @"_TtC28NavigationUI_TabBarItemsImpl29TabBarItemsNavigationListImpl",
    ]);
}
