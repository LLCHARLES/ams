// The Tab bar page (Redesigned/Navbar/NavbarSettings.m) over the harness's bar, `navsettings`: its fade switch starts
// on, its preview reads the fade, and flipping the switch takes the fade off the real bar under the page at once and
// out of the preview.
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGViewTree.h"
#import "Core/SGPrefs.h"
#import "Redesigned/Navbar/Navbar.h"
#import "Shared/Navigation/TabIcons.h"

@class SGHarnessChrome;

static UISwitch *switchNamed(UIView *root, NSString *title) {
    __block UISwitch *found = nil;
    for (UITableViewCell *cell in ((UITableView *)root).visibleCells) {
        __block BOOL named = NO;
        SGForEachView(cell, ^(UIView *view) {
            if ([view isKindOfClass:UILabel.class] && [((UILabel *)view).text isEqualToString:title]) named = YES;
        });
        if (named && [cell.accessoryView isKindOfClass:UISwitch.class]) found = (UISwitch *)cell.accessoryView;
    }
    return found;
}

static UIView *previewIn(UIView *root) {
    __block UIView *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!found && [view.accessibilityLabel isEqualToString:@"Tab bar preview"]) found = view;
    });
    return found;
}

static void expectPreview(UIView *preview, BOOL on, NSString *moment) {
    if ([preview.accessibilityValue containsString:@"Fade under the bar"] != on) HARNESS_FAIL(@"%@: the preview reads \"%@\"", moment, preview.accessibilityValue);
    printf("PASS %s: the preview reads \"%s\"\n", moment.UTF8String, preview.accessibilityValue.UTF8String);
    fflush(stdout);
}

void SGHarnessRunNavbarPage(SGHarnessChrome *chrome, void (^barChecked)(BOOL on)) {
    UIViewController *owner = (UIViewController *)chrome;
    // What Navbar.x records off Spotify's bar, which the harness does not compile: the mock's tabs.
    SGRSetNavbarStock(@[@"Home", @"Search", @"Your Library", @"Create"]);
    SGSetEnabled(SGRKeyNavbarHideLabels, NO);
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGRNavbarSettingsPage()];
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [owner presentViewController:nav animated:NO completion:nil];
    [nav.view layoutIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    UITableView *table = ((UITableViewController *)nav.topViewController).tableView;
    UISwitch *toggle = switchNamed(table, @"Fade under the bar");
    UIView *preview = previewIn(table.tableHeaderView);
    if (!toggle || !toggle.on || !preview) HARNESS_FAIL(@"the fade switch %@, the preview %@", toggle ? (toggle.on ? @"on" : @"off") : @"missing", preview);
    expectPreview(preview, YES, @"switch on");
    barChecked(YES);
    toggle.on = NO;
    [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    if (SGEnabled(SGRKeyNavbarFade)) HARNESS_FAIL(@"the switch did not store %@", SGRKeyNavbarFade);
    [owner.view layoutIfNeeded];
    barChecked(NO);
    expectPreview(preview, NO, @"switch off");
    UIView *labels = [table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]].contentView.subviews.firstObject;
    UIControl *iconsOnly = ((UIStackView *)labels).arrangedSubviews.lastObject;
    HARNESS_CHECK(iconsOnly);
    [iconsOnly sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK(SGEnabled(SGRKeyNavbarHideLabels));
    UISwitch *custom = (UISwitch *)[table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].accessoryView;
    HARNESS_CHECK(custom);
    custom.on = NO;
    [custom sendActionsForControlEvents:UIControlEventValueChanged];
    HARNESS_CHECK(!SGEnabled(SGRKeyNavbar));
    custom.on = YES;
    [custom sendActionsForControlEvents:UIControlEventValueChanged];
    NSIndexPath *homePath = nil;
    for (NSInteger section = 0; section < table.numberOfSections; section++) {
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
            if ([((UIListContentConfiguration *)cell.contentConfiguration).text isEqual:@"Home"]) homePath = path;
        }
    }
    HARNESS_CHECK(homePath);
    [table scrollToRowAtIndexPath:homePath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [table layoutIfNeeded];
    UITableViewCell *home = [table cellForRowAtIndexPath:homePath];
    __block UIButton *hide;
    SGForEachView(home.contentView, ^(UIView *view) {
        if ([view isKindOfClass:UIButton.class]) hide = (UIButton *)view;
    });
    HARNESS_CHECK(hide);
    [hide sendActionsForControlEvents:UIControlEventTouchUpInside];
    HARNESS_CHECK([SGRNavbarLayout().firstObject[SGRNavbarHidden] boolValue]);
    printf("PASS all navsettings\n");
    fflush(stdout);
    exit(0);
}

#pragma mark - Apple symbols (`symbols`)

// main.m: the tab of the mod's own on the bar after Spotify's, and the SF Symbol picked for it.
extern NSString *const SGHarnessOwnTabTitle;
NSString *SGHarnessOwnTabSymbol(void);

static NSArray<NSString *> *spotifyTabs(void) {
    return @[@"Home", @"Search", @"Your Library", @"Create"];
}

static NSData *png(UIImage *image) {
    return image ? UIImagePNGRepresentation(image) : NSData.data;
}

// The first bar with tabs under `root`: the glass bar over Spotify's, or the preview's main bar.
static UITabBar *barIn(UIView *root) {
    __block UITabBar *found = nil;
    SGForEachView(root, ^(UIView *view) {
        if (!found && [view isKindOfClass:UITabBar.class] && !view.hidden && ((UITabBar *)view).items.count) found = (UITabBar *)view;
    });
    return found;
}

// Each tab's picture by its name: a bar's glyphs, or its selected ones.
static NSDictionary<NSString *, NSData *> *barGlyphs(UITabBar *bar, BOOL selected) {
    NSMutableDictionary<NSString *, NSData *> *glyphs = [NSMutableDictionary dictionary];
    for (UITabBarItem *item in bar.items) if (item.title) glyphs[item.title] = png(selected ? item.selectedImage : item.image);
    return glyphs;
}

// The glyphs of the page's list as it shows them, from the rows on screen.
static NSDictionary<NSString *, NSData *> *listGlyphs(UITableView *table) {
    NSMutableDictionary<NSString *, NSData *> *glyphs = [NSMutableDictionary dictionary];
    NSArray<NSString *> *titles = [spotifyTabs() arrayByAddingObject:SGHarnessOwnTabTitle];
    for (UITableViewCell *cell in table.visibleCells) {
        UIListContentConfiguration *content = (UIListContentConfiguration *)cell.contentConfiguration;
        if (![content isKindOfClass:UIListContentConfiguration.class] || ![titles containsObject:content.text]) continue;
        glyphs[content.text] = png(content.image);
    }
    return glyphs;
}

// Off, Spotify's tabs show the mock's glyphs, the same ring for each one not selected, and as they were before the
// switch went on; on, each of Spotify's tabs has a symbol of its own, none of them its glyph from before. The tab of
// the mod's own keeps its picture throughout.
static void expectGlyphs(NSString *moment, NSString *where, NSDictionary<NSString *, NSData *> *glyphs, BOOL on, NSDictionary<NSString *, NSData *> *off) {
    NSArray<NSString *> *spotify = spotifyTabs();
    for (NSString *title in [spotify arrayByAddingObject:SGHarnessOwnTabTitle]) {
        if (!glyphs[title].length) HARNESS_FAIL(@"%@: the %@ has no glyph for %@", moment, where, title);
    }
    if (off && ![glyphs[SGHarnessOwnTabTitle] isEqual:off[SGHarnessOwnTabTitle]]) HARNESS_FAIL(@"%@: the %@ changed the icon of the tab of the mod's own", moment, where);
    if (on) {
        NSSet *distinct = [NSSet setWithArray:[glyphs objectsForKeys:spotify notFoundMarker:(id)NSNull.null]];
        if (distinct.count != spotify.count) HARNESS_FAIL(@"%@: the %@ gives %lu pictures to Spotify's %lu tabs", moment, where, (unsigned long)distinct.count, (unsigned long)spotify.count);
        for (NSString *title in spotify) if ([glyphs[title] isEqual:off[title]]) HARNESS_FAIL(@"%@: the %@ still has Spotify's glyph for %@", moment, where, title);
    } else {
        if (![glyphs[@"Search"] isEqual:glyphs[@"Your Library"]] || ![glyphs[@"Search"] isEqual:glyphs[@"Create"]]) HARNESS_FAIL(@"%@: the %@ does not show Spotify's glyphs", moment, where);
        for (NSString *title in spotify) if (off && ![glyphs[title] isEqual:off[title]]) HARNESS_FAIL(@"%@: the %@ did not get Spotify's glyph back for %@", moment, where, title);
    }
    printf("PASS %s: the %s\n", moment.UTF8String, where.UTF8String);
    fflush(stdout);
}

// What Navbar.x's SGRRefreshTabBar does, which stubs.m's does not: the bar it composed lays out again.
static void layOutBar(UIView *root) {
    SGForEachView(root, ^(UIView *view) {
        if ([view isKindOfClass:NSClassFromString(@"_TtC23NavigationUI_TabBarImpl10TabBarView")]) [view setNeedsLayout];
    });
    [root layoutIfNeeded];
}

// stubs.m's SGRRefreshTabBar: how often it was called, and whether once off the main thread.
extern NSUInteger sgHarnessTabBarRefreshes;
extern BOOL sgHarnessTabBarRefreshedOffMain;

// Spotify's list of tabs read twice at once off the main thread, as Navbar.x's hook hands it on (SGRSetNavbarStockURIs):
// nothing lays the bar out off the main thread, and on it the pages are kept and the bar laid out once. The scenario runs
// in a block on the main queue, which runs nothing else until it returns, so `then` comes on the main queue after
// whatever both reads put there.
static void readListOffMain(NSDictionary<NSString *, NSString *> *uris, NSString *moment, dispatch_block_t then) {
    sgHarnessTabBarRefreshes = 0;
    sgHarnessTabBarRefreshedOffMain = NO;
    dispatch_group_t reads = dispatch_group_create();
    for (int read = 0; read < 2; read++) {
        dispatch_group_async(reads, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ SGRSetNavbarStockURIs(uris); });
    }
    dispatch_group_wait(reads, DISPATCH_TIME_FOREVER);
    if (sgHarnessTabBarRefreshedOffMain) HARNESS_FAIL(@"%@: the list read off the main thread laid the bar out off it", moment);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (sgHarnessTabBarRefreshes != 1) HARNESS_FAIL(@"%@: the list read twice off the main thread laid the bar out %lu times, not once", moment, (unsigned long)sgHarnessTabBarRefreshes);
        if (![SGRNavbarStockURIs() isEqualToDictionary:uris]) HARNESS_FAIL(@"%@: the pages kept are %@", moment, SGRNavbarStockURIs());
        then();
    });
}

// The glyph UIKit shows for the tab named `title` on `bar`: the image view in the tab's button, outside the copy UIKit
// draws lit under the selection's bubble.
static UIImageView *shownGlyph(UITabBar *bar, NSString *title) {
    __block UIImageView *found = nil;
    SGForEachView(bar, ^(UIView *view) {
        if (found || ![view isKindOfClass:UIControl.class]) return;
        for (UIView *up = view.superview; up && up != bar; up = up.superview) {
            if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) return;
        }
        __block BOOL named = NO;
        __block UIImageView *glyph = nil;
        SGForEachView(view, ^(UIView *sub) {
            if ([sub isKindOfClass:UILabel.class] && [((UILabel *)sub).text isEqualToString:title]) named = YES;
            if (!glyph && [sub isKindOfClass:UIImageView.class] && !sub.hidden && ((UIImageView *)sub).image) glyph = (UIImageView *)sub;
        });
        if (named) found = glyph;
    });
    return found;
}

// The tab of the mod's own wears an SF Symbol: on the bar and the preview UIKit is handed the symbol itself, heart and
// heart.fill selected, and shows it at the size a plain UITabBar shows a tab given that symbol.
static void expectOwnSymbol(NSString *moment, UITabBar *bar, UITabBar *preview) {
    NSData *plain = png([UIImage systemImageNamed:@"heart"]), *filled = png([UIImage systemImageNamed:@"heart.fill"]);
    for (UITabBar *each in @[bar, preview]) {
        NSString *where = each == bar ? @"bar" : @"preview";
        UITabBarItem *own = nil;
        for (UITabBarItem *item in each.items) if ([item.title isEqualToString:SGHarnessOwnTabTitle]) own = item;
        if (!own.image.isSymbolImage || !own.selectedImage.isSymbolImage) HARNESS_FAIL(@"%@: the %@ gives the tab of the mod's own a drawing, not its symbol: %@ / %@", moment, where, own.image, own.selectedImage);
        if (![png(own.image) isEqual:plain]) HARNESS_FAIL(@"%@: the %@'s tab of the mod's own is not heart", moment, where);
        if (![png(own.selectedImage) isEqual:filled]) HARNESS_FAIL(@"%@: the %@'s tab of the mod's own is not heart.fill when selected", moment, where);
    }
    UITabBar *stock = [[UITabBar alloc] initWithFrame:bar.frame];
    stock.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    NSMutableArray<UITabBarItem *> *items = [NSMutableArray array];
    for (UITabBarItem *item in bar.items) {
        BOOL own = [item.title isEqualToString:SGHarnessOwnTabTitle];
        [items addObject:[[UITabBarItem alloc] initWithTitle:item.title image:own ? [UIImage systemImageNamed:@"heart"] : item.image tag:items.count]];
    }
    stock.items = items;
    stock.alpha = 0;
    [bar.superview addSubview:stock];
    [stock layoutIfNeeded];
    UIImageView *shown = shownGlyph(bar, SGHarnessOwnTabTitle), *expected = shownGlyph(stock, SGHarnessOwnTabTitle);
    [stock removeFromSuperview];
    if (!shown || !expected) HARNESS_FAIL(@"%@: no glyph shown for the tab of the mod's own (%@) or on the plain bar (%@)", moment, shown, expected);
    if (!CGSizeEqualToSize(shown.bounds.size, expected.bounds.size)) HARNESS_FAIL(@"%@: the tab of the mod's own shows its symbol at %@, a plain UITabBar at %@", moment, NSStringFromCGSize(shown.bounds.size), NSStringFromCGSize(expected.bounds.size));
    printf("PASS %s: the tab of the mod's own is heart, heart.fill selected, at %s as on a plain UITabBar\n", moment.UTF8String, NSStringFromCGSize(shown.bounds.size).UTF8String);
    fflush(stdout);
}

// stubs.m's SGOpenModSettings: how often a hold opened Mod Settings.
extern NSUInteger sgHarnessModSettingsOpens;
extern void SGHarnessHold(UIWindow *window, CGPoint point, NSTimeInterval seconds);

// `symbols hold`: Apple symbols on, the names hidden (main.m) and the tab of the mod's own wearing house, as Home does,
// drawn as the Music house for Home and the SF Symbol for the custom tab. A finger held on the tab of the mod's own, the bar's last, opens nothing; held on Home,
// its first, Mod Settings once.
static void expectHoldOpensHomeOnly(UIViewController *owner) {
    SGSetEnabled(SGRKeyNavbarSymbols, YES);
    layOutBar(owner.view);
    UITabBar *bar = barIn(owner.view);
    HARNESS_CHECK(bar && bar.items.count == spotifyTabs().count + 1);
    for (UITabBarItem *item in bar.items) if (item.title) HARNESS_FAIL(@"symbols hold: the bar names %@", item.title);
    HARNESS_CHECK(bar.items.firstObject.image && bar.items.lastObject.image);
    HARNESS_CHECK(![png(bar.items.firstObject.image) isEqual:png(bar.items.lastObject.image)]);
    // The tabs' buttons left to right, outside the copy UIKit draws lit under the selection's bubble.
    NSMutableArray<UIView *> *buttons = [NSMutableArray array];
    SGForEachView(bar, ^(UIView *view) {
        if (![view isKindOfClass:UIControl.class] || view == bar) return;
        for (UIView *up = view.superview; up && up != bar; up = up.superview) {
            if ([NSStringFromClass(up.class) containsString:@"SelectedContent"]) return;
        }
        [buttons addObject:view];
    });
    [buttons sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return [@([a convertPoint:CGPointZero toView:nil].x) compare:@([b convertPoint:CGPointZero toView:nil].x)];
    }];
    if (buttons.count != bar.items.count) HARNESS_FAIL(@"symbols hold: %lu buttons for %lu tabs", (unsigned long)buttons.count, (unsigned long)bar.items.count);
    UIWindow *window = bar.window;
    CGPoint (^middle)(UIView *) = ^CGPoint(UIView *button) {
        return [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:nil];
    };
    sgHarnessModSettingsOpens = 0;
    SGHarnessHold(window, middle(buttons.lastObject), 0.8);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (sgHarnessModSettingsOpens != 0) HARNESS_FAIL(@"symbols hold: a hold on the tab of the mod's own opened Mod Settings");
        SGHarnessHold(window, middle(buttons.firstObject), 0.8);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (sgHarnessModSettingsOpens != 1) HARNESS_FAIL(@"symbols hold: a hold on Home opened Mod Settings %lu times, not once", (unsigned long)sgHarnessModSettingsOpens);
            printf("PASS hold on Home only\n");
            fflush(stdout);
            exit(0);
        });
    });
}

static void holdForScreenshot(void) {
    printf("READY\n");
    fflush(stdout);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ exit(0); });
}

// `symbols`: the Tab bar page over the bar, with a tab of the mod's own on it. Apple symbols starts off, so the bar, the
// preview and the list show Spotify's glyphs; switched on from the page they show symbols at once, and switched off
// Spotify's glyphs again, the custom tab keeping its icon throughout. Home keeps the Music house when selected
// and Search keeps its magnifyingglass.
// `symbols show` holds the bar with the switch off (`on`: on), `symbols page` the page over it, switched on from the
// page with `on` and scrolled to the tabs with `list`, for a screenshot. Not `off`: that word switches the fade off.
void SGHarnessRunSymbols(SGHarnessChrome *chrome) {
    UIViewController *owner = (UIViewController *)chrome;
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    // What Navbar.x records off Spotify's bar and its list of tabs, which the harness does not compile: the mock's tabs
    // and the pages 9.1.90's list names for them. The list names the mod's own tab's name too, as it would a tab of
    // Spotify's the user's tab is named after, so only being the mod's own keeps its icon.
    SGRSetNavbarStock(spotifyTabs());
    NSDictionary<NSString *, NSString *> *stockURIs = @{@"Home": @"spotify:home", @"Search": @"spotify:find", @"Your Library": @"spotify:collection",
                                                        @"Create": @"spotify:internal:playlist-creation-container", SGHarnessOwnTabTitle: @"spotify:collection:tracks"};
    SGRSetNavbarStockURIs(stockURIs);
    NSMutableArray<NSDictionary *> *layout = [NSMutableArray array];
    for (NSString *title in spotifyTabs()) [layout addObject:@{SGRNavbarID: title, SGRNavbarTitle: title}];
    [layout addObject:@{SGRNavbarID: @"own", SGRNavbarTitle: SGHarnessOwnTabTitle, SGRNavbarURI: @"spotify:collection:tracks",
                        SGRNavbarIcon: SGHarnessOwnTabSymbol(), SGRNavbarIconSet: SGTabIconSetSymbols}];
    SGRSetNavbarLayout(layout);
    SGSetEnabled(SGRKeyNavbar, YES);
    if ([args containsObject:@"hold"]) {
        expectHoldOpensHomeOnly(owner);
        return;
    }
    BOOL on = [args containsObject:@"on"];
    if ([args containsObject:@"show"]) {
        SGSetEnabled(SGRKeyNavbarSymbols, on);
        layOutBar(owner.view);
        holdForScreenshot();
        return;
    }
    if (SGFlag(SGRKeyNavbarSymbols, NO)) HARNESS_FAIL(@"Apple symbols is on before it was switched on");
    layOutBar(owner.view);

    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:SGRNavbarSettingsPage()];
    nav.modalPresentationStyle = UIModalPresentationOverFullScreen;
    [owner presentViewController:nav animated:NO completion:nil];
    [nav.view layoutIfNeeded];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
    UITableView *table = ((UITableViewController *)nav.topViewController).tableView;
    UISwitch *toggle = switchNamed(table, @"Apple symbols");
    UITabBar *preview = barIn(previewIn(table.tableHeaderView));
    if (!toggle || toggle.on || !preview) HARNESS_FAIL(@"the Apple symbols switch %@, the preview's bar %@", toggle ? (toggle.on ? @"on" : @"off") : @"missing", preview);
    void (^flip)(BOOL) = ^(BOOL value) {
        toggle.on = value;
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
        if (SGFlag(SGRKeyNavbarSymbols, NO) != value) HARNESS_FAIL(@"the switch did not store %@", SGRKeyNavbarSymbols);
        layOutBar(owner.view);
        [table layoutIfNeeded];
    };
    if ([args containsObject:@"page"]) {
        if (on) flip(YES);
        if ([args containsObject:@"list"]) {
            [table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:table.numberOfSections - 3] atScrollPosition:UITableViewScrollPositionTop animated:NO];
        }
        holdForScreenshot();
        return;
    }

    // The tabs' rows, all on screen together, so the list is read as it shows them and not as rows made anew.
    NSIndexPath *first = nil;
    for (NSInteger section = 0; section < table.numberOfSections && !first; section++) {
        for (NSInteger row = 0; row < [table numberOfRowsInSection:section] && !first; row++) {
            NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
            UIListContentConfiguration *content = (UIListContentConfiguration *)[table.dataSource tableView:table cellForRowAtIndexPath:path].contentConfiguration;
            if ([content isKindOfClass:UIListContentConfiguration.class] && [content.text isEqual:@"Home"]) first = path;
        }
    }
    HARNESS_CHECK(first);
    [table scrollToRowAtIndexPath:first atScrollPosition:UITableViewScrollPositionTop animated:NO];
    [table layoutIfNeeded];

    UITabBar *bar = barIn(owner.view);
    HARNESS_CHECK(bar);
    NSDictionary *barOff = barGlyphs(bar, NO), *previewOff = barGlyphs(preview, NO), *listOff = listGlyphs(table);
    expectGlyphs(@"switch off", @"bar", barOff, NO, nil);
    expectGlyphs(@"switch off", @"preview", previewOff, NO, nil);
    expectGlyphs(@"switch off", @"list", listOff, NO, nil);
    expectOwnSymbol(@"switch off", bar, preview);

    flip(YES);
    expectGlyphs(@"switch on", @"bar", barGlyphs(bar, NO), YES, barOff);
    expectGlyphs(@"switch on", @"preview", barGlyphs(preview, NO), YES, previewOff);
    expectGlyphs(@"switch on", @"list", listGlyphs(table), YES, listOff);
    NSDictionary *barLit = barGlyphs(bar, YES), *barPlain = barGlyphs(bar, NO);
    if (![barLit[@"Home"] isEqual:barPlain[@"Home"]]) HARNESS_FAIL(@"switch on: Home lost the Music house when selected");
    if (![barLit[@"Search"] isEqual:barPlain[@"Search"]]) HARNESS_FAIL(@"switch on: Search's selected glyph is not magnifyingglass");
    printf("PASS switch on: Home keeps the Music house and Search keeps its magnifying glass\n");
    expectOwnSymbol(@"switch on", bar, preview);

    // The list read off the main thread naming Home's page for Search: once on it, the bar draws Search as Home.
    NSMutableDictionary<NSString *, NSString *> *moved = [stockURIs mutableCopy];
    moved[@"Search"] = stockURIs[@"Home"];
    readListOffMain(moved, @"Search moved to Home's page", ^{
        layOutBar(owner.view);
        if (![barGlyphs(bar, NO)[@"Search"] isEqual:barGlyphs(bar, NO)[@"Home"]]) HARNESS_FAIL(@"Search moved to Home's page: the bar does not draw Search as Home");
        readListOffMain(stockURIs, @"Search back on its page", ^{
            layOutBar(owner.view);
            if (![barGlyphs(bar, NO) isEqualToDictionary:barPlain]) HARNESS_FAIL(@"Search back on its page: the bar is not as it was");
            printf("PASS list read off the main thread: kept and laid out once on it\n");

            flip(NO);
            expectGlyphs(@"switch off again", @"bar", barGlyphs(bar, NO), NO, barOff);
            expectGlyphs(@"switch off again", @"preview", barGlyphs(preview, NO), NO, previewOff);
            expectGlyphs(@"switch off again", @"list", listGlyphs(table), NO, listOff);
            printf("PASS all symbols\n");
            fflush(stdout);
            exit(0);
        });
    });
}
