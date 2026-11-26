// Mod Settings' main page as App/ModSettings.x builds it, opened the way holding Home opens it
// (SGOpenModSettings), with the real App/Pages.m behind its Redesigned UI switch and the real Settings/
// framework and About page; stubs.m stands in for other pages and actions. The launch line sets the look up and then plays
// actions, one every 0.9 s from 1 s in; screenshot after.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/ModSettingsHarness.app
//     xcrun simctl launch <udid> com.retrine.modsettingsharness [setup...] [action...]
//
// Setup: redesign (Redesigned UI stored on), warning (a red environment row at the top), keep (the stored
// look stays; otherwise it is cleared first), system (the window in the system's appearance under a dark
// navigation stack, as Spotify's is; light-check.sh).
// Actions: toggle=<section>.<row> (that row's switch flipped the way a tap does), cancel (the alert that
// switch brings up closed with Later), bottom (scrolled to the end), dump (the rows of each section and
// what each reads beside its chevron, to the log), gated (a page of a switch, ten rows, a headed and noted
// section of twelve rows shown only while the switch is on, and a row that comes by itself), later (that row
// let come; the page's ticker brings it), top (scrolled to the start), layout (the scroll offset, and each
// section's rows and heading and note heights, to the log), needs (the Lock screen artwork section below iOS
// 26), tap=<section>.<row> (that row selected, and the alert it brings up logged), rows (the row the mod adds to
// Spotify's settings list and drawer, after each list is emptied of its subviews, counted to the log), alerts (a
// page of SGModPage's alerts) with info, lock and toggle=0.1 bringing each up, information (SGPresentInformation
// over the page), look (the controller on top, its appearance and its presentation's, and its frame, to the log).
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Core/SGCore.h"
#import "Settings/SGPage.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import <CoreText/SFNTLayoutTypes.h>
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Shared/Flags/Flags.h"
#import "Shared/Gestures/Gestures.h"
#import "App/About/About.h"
#import "../harness-fail.h"

// Spotify's page protocol, so SGRegisterPages finds one and the page is pushed as on the phone.
@protocol SPTPageController <NSObject>
@end

// Settings/SGSettingsIndex.m's search rules, tested without a search bar.
#import "Settings/SGSettingsIndex.h"
#import "Settings/SGSettingsSearch.h"

// A page of the search's own: rows whose titles stand in for real settings, and one row that opens a page under it.
// The real SGSettingsResults and the real UISearchController are what the checks drive.
@interface SGSearchFixturePage : SGModPage
@property(nonatomic,strong) UINavigationController *fallback;
@end
@implementation SGSearchFixturePage
- (void)presentViewController:(UIViewController *)page animated:(BOOL)animated completion:(void (^)(void))completion {
    if ([page isKindOfClass:UINavigationController.class]) self.fallback=(id)page;
    else [super presentViewController:page animated:animated completion:completion];
}
@end
static SGModPage *searchHarnessPage(void) {
    SGModRow *plain = SGModRow.new;
    plain.title = @"Plain row";
    plain.key = @"spotifyglass.harness.search.plain";
    SGModRow *under = SGModRow.new;
    under.title = @"Second row";
    under.key = @"spotifyglass.harness.search.second";
    SGModRow *page = SGPageRow(@"Live Activity", ^UIViewController *{ return nil; });
    page.searchIdentifier = @"page.liveactivity";
    SGModRow *foreign = SGPageRow(@"Pixie Download Manager", ^UIViewController *{
        UIViewController *result=[UIViewController new];result.title=@"Unregistered page";return result;
    });
    return [[SGSearchFixturePage alloc] initWithTitle:@"Search" intro:nil sections:@[
        SGSection(nil, @[plain]),
        SGSection(nil, @[page,foreign]),
    ] footer:nil];
}

// The field's results table is the search's own: for an empty field (the recents' case) and an emptied one, the field
// must be showing it. UIKit's own rule, left on, takes it away whenever the text is empty.
static NSUInteger searchControllerChecks(void) {
    __block NSUInteger failures = 0;
    void (^check)(BOOL, NSString *) = ^(BOOL ok, NSString *what) {
        if (!ok) {
            failures++;
            fprintf(stderr, "[harness] search controller FAIL %s\n", what.UTF8String);
        }
    };
    // Two places to show on the empty field, stored the way the results would store them.
    SGSearchForgetRecents();
    SGSearchRememberPlace(@[@"page.liveactivity"]);
    SGSearchRememberPlace(@[@"spotifyglass.harness.search.plain"]);

    SGModPage *page = searchHarnessPage();
    page.searchable = YES;
    // The field is made in viewDidLoad, which the page needs a window for.
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:page];
    window.rootViewController = nav;
    window.hidden = NO;
    [page loadViewIfNeeded];
    [page viewDidAppear:NO];
    UISearchController *search = SGSettingsSearchField(page);
    check(search != nil, @"a searchable page heads itself with a field");
    check(search.searchResultsController != nil, @"the field shows the search's own results table");
    // UIKit's default is the field's automatic rule, which hides the results table until something is typed and takes
    // it away again when the text is cleared; the search takes the field off that rule when it attaches it.
    check(search.automaticallyShowsSearchResultsController == NO,
          @"the field's automatic results rule is off, so an empty field still shows the results");

    // An empty field, up: the recents' table is what shows, and it holds them.
    search.active = YES;
    check(search.showsSearchResultsController, @"an empty field up shows its results");
    UITableView *table = ((UITableViewController *)search.searchResultsController).tableView;
    [search.searchResultsController loadViewIfNeeded];
    NSInteger recents = [table.dataSource tableView:table numberOfRowsInSection:0];
    check(recents == 2, @"the empty field's results hold both stored places");

    id<UISearchResultsUpdating> updater = (id<UISearchResultsUpdating>)search.searchResultsController;
    // Typed, then cleared: the table stays, and the recents come back.
    search.searchBar.text = @"plain";
    [updater updateSearchResultsForSearchController:search];
    check(search.showsSearchResultsController && [table.dataSource tableView:table numberOfRowsInSection:1] == 1,
          @"a typed query shows its row");
    search.searchBar.text = @"";
    [updater updateSearchResultsForSearchController:search];
    check(search.showsSearchResultsController, @"an emptied field still shows its results");
    check([table.dataSource tableView:table numberOfRowsInSection:0] == 2, @"the recents are back on an emptied field");

    // Closing the field takes its table down with it (UIKit's own dismissal), and the search leaves it down until the
    // field is up again, so a page whose field was closed does not keep a table over it.
    search.showsSearchResultsController = NO;
    check(!search.showsSearchResultsController, @"a closed field shows no results");
    // Up again with nothing typed: the table comes back, the recents with it.
    search.showsSearchResultsController = YES;
    check([table.dataSource tableView:table numberOfRowsInSection:0] == 2, @"up again, the recents are shown once more");

    search.searchBar.text=@"Pixie Download Manager";
    [updater updateSearchResultsForSearchController:search];
    if ([table.dataSource tableView:table numberOfRowsInSection:1]==1) {
        [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
        [search.delegate didDismissSearchController:search];
        check(nav.topViewController==page && [((SGSearchFixturePage *)page).fallback.topViewController.title isEqual:@"Unregistered page"],
              @"nonconforming search destination is presented outside the host stack");
    }else check(NO,@"Pixie row is indexed");

    SGSearchForgetRecents();
    window.hidden = YES;
    fprintf(stderr, "[harness] search controller checks: %lu failure(s)\n", (unsigned long)failures);
    return failures;
}

// A real search over the page Mod Settings makes: the places its rows are stored as are the rows' own names (their
// searchIdentifier, else their key), never their titles, so a place survives a language switch and a look switch.
static NSUInteger searchPlacesChecks(void) {
    __block NSUInteger failures = 0;
    void (^check)(BOOL, NSString *) = ^(BOOL ok, NSString *what) {
        if (!ok) {
            failures++;
            fprintf(stderr, "[harness] search places FAIL %s\n", what.UTF8String);
        }
    };
    SGSearchForgetRecents();
    // The page the app opens, over a navigation stack of the harness's own.
    UIViewController *home = [UIViewController new];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:home];
    UIWindow *window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    window.rootViewController = nav;
    window.hidden = NO;
    SGOpenModSettings(home.view);
    SGModPage *page = (SGModPage *)nav.topViewController;
    [page loadViewIfNeeded];
    SGSettingsIndex *index = [SGSettingsIndex new];
    NSArray *headings = @[SGL(@"settings.main.look.header", @"Look & navigation"), SGL(@"settings.main.screens.header", @"Screens"),
        SGL(@"settings.main.audio.header", @"Audio & playback"), SGL(@"settings.main.outside.header", @"Outside Spotify & devices"),
        SGL(@"settings.main.privacy.header", @"Privacy, network & downloads"), SGL(@"settings.main.advanced.header", @"Advanced & about")];
    NSMutableArray *namedSections = [NSMutableArray array];
    for (SGModSection *section in page.sections) if (section.title.length) [namedSections addObject:section.title];
    check([namedSections isEqual:headings], @"six root headings in navigation order");
    // Search the visible language, but keep the stored place independent of it. Reindex the same open
    // page after a look switch, as live search does when settings change.
    BOOL savedLook = SGRedesignedUIStored();
    for (NSNumber *look in @[@NO, @YES]) {
        SGSetEnabled(SGKeyRedesign, look.boolValue);
        [index startWithRoot:page];
        while (index.running) [index step];
        NSArray<SGSettingsHit *> *hits = [index hitsForQuery:SGL(@"settings.main.appearance.title", @"Appearance")];
        check(hits.count > 0 && hits.firstObject.place != nil, @"the main page's rows have places");
        BOOL titled = NO;
        for (SGSettingsHit *hit in [index hitsForQuery:SGL(@"settings.main.player.title", @"Player")]) {
            if (hit.place.count == 1 && [hit.place.firstObject isEqual:hit.title]) titled = YES;
        }
        check(!titled, @"no place is a row's title");
        NSArray *place = look.boolValue ? @[@"page.appearance.redesigned"] : @[@"page.appearance.native"];
        check([hits.firstObject.place isEqualToArray:place], @"the Appearance row's place names the stored look");
        NSArray *libraryPlace = look.boolValue ? @[@"page.search.redesigned", @"spotifyglass.redesign.library.hideChips"]
                                               : @[@"page.search.native", @"spotifyglass.adblock.searchVideos"];
        NSString *libraryQuery = look.boolValue ? SGL(@"settings.library.compact.title", @"Compact library")
                                                : SGL(@"settings.privacy.hide_search_carousel.title", @"Hide the video carousel in Search");
        check([[index hitsForQuery:libraryQuery].firstObject.place isEqual:libraryPlace], @"Search & Library indexes the selected look's settings");
        SGSearchForgetRecents();
        SGSearchRememberPlace(look.boolValue ? @[@"page.library.redesigned", @"spotifyglass.redesign.library.hideChips"]
                                             : @[@"page.ads", @"spotifyglass.adblock.searchVideos"]);
        check([index.recentHits.firstObject.place isEqual:libraryPlace], @"a saved Library or carousel result now leads to its new page");
        SGSearchRememberPlace(@[look.boolValue ? @"page.player.redesigned" : @"page.player.native", @"page.player.localfiles"]);
        check([index.recentHits.firstObject.place isEqual:@[@"page.playback", @"page.player.localfiles"]], @"the old Player recent opens Local files in Playback");
        SGSearchRememberPlace(@[@"page.mod", SGKeyShowCacheLimit]);
        check([index.recentHits.firstObject.place isEqual:@[@"page.mod", @"page.mod.storage", SGKeyShowCacheLimit]], @"the old cache setting resolves inside Mod Storage");
        NSArray *translation = @[look.boolValue ? @"page.lyrics.redesigned" : @"page.lyrics.native", @"page.lyrics.translation", @"spotifyglass.lyrics.translationPrompt"];
        if (look.boolValue)
            SGSearchRememberPlace(@[translation[0], translation[1], @"page.lyrics.gemini", translation[2]]);
        else
            SGSearchRememberPlace(translation);
        check([index.recentHits.firstObject.place isEqual:translation], @"both looks resolve the shared translation prompt");
    }
    SGSearchForgetRecents();
    SGSetEnabled(SGKeyRedesign, savedLook);
    window.hidden = YES;
    fprintf(stderr, "[harness] search places checks: %lu failure(s)\n", (unsigned long)failures);
    return failures;
}

BOOL SGHarnessWarning;

@interface SGSearchDestinationCheck : NSObject <UISearchControllerDelegate, UINavigationControllerDelegate>
@property (nonatomic, strong) UINavigationController *nav;
@property (nonatomic, strong) SGModPage *root;
@property (nonatomic) NSUInteger destination;
@property (nonatomic, weak) id<UISearchControllerDelegate> resultsDelegate;
@end

@implementation SGSearchDestinationCheck
- (void)start {
    self.root = (SGModPage *)self.nav.topViewController;
    self.nav.delegate = self;
    SGSearchForgetRecents();
    [self search];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        HARNESS_FAIL(@"search did not finish opening destination %lu", (unsigned long)self.destination);
    });
}
- (void)search {
    UISearchController *search = SGSettingsSearchField(self.root);
    if (search.delegate != self) self.resultsDelegate = search.delegate;
    search.delegate = self;
    search.searchBar.text = self.destination == 0
        ? SGL(@"settings.main.audio_effects.title", @"Audio effects")
        : SGL(@"settings.main.all_flags.title", @"All flags");
    search.active = YES;
}
- (void)didPresentSearchController:(UISearchController *)search {
    [search.searchResultsUpdater updateSearchResultsForSearchController:search];
    UITableView *table = ((UITableViewController *)search.searchResultsController).tableView;
    HARNESS_CHECK([table.dataSource tableView:table numberOfRowsInSection:1] > 0);
    [table.delegate tableView:table didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:1]];
}
- (void)didDismissSearchController:(UISearchController *)search {
    if ([self.resultsDelegate respondsToSelector:_cmd]) [self.resultsDelegate didDismissSearchController:search];
}
- (void)navigationController:(UINavigationController *)nav didShowViewController:(UIViewController *)page animated:(BOOL)animated {
    if (page == self.root) {
        [self search];
        return;
    }
    NSString *expected = self.destination == 0 ? @"Audio effects" : @"All flags";
    if (![page.title isEqualToString:expected]) HARNESS_FAIL(@"expected %@, opened %@", expected, page.title);
    HARNESS_CHECK(![page isKindOfClass:SGModPage.class]);
    HARNESS_CHECK(!SGSettingsSearchField(self.root).active);
    if (++self.destination == 2) {
        SGSearchForgetRecents();
        NSLog(@"[harness] search destinations PASS");
        exit(0);
    }
    [nav popToViewController:self.root animated:YES];
}
@end

static void refactorChecks(void) {
    UITableViewController *gestures = (id)SGGesturesSettingsPage();
    UITableView *gestureTable = gestures.tableView;
    NSIndexPath *split = [NSIndexPath indexPathForRow:0 inSection:1];
    NSIndexPath *hold = [NSIndexPath indexPathForRow:0 inSection:3];
    for (NSNumber *enabled in @[@NO, @YES]) {
        SGSetEnabled(SGKeyGestures, enabled.boolValue);
        SGSetInt(SGKeyGestureSplit, 1);
        UITableViewCell *choice = [gestures tableView:gestureTable cellForRowAtIndexPath:split];
        HARNESS_CHECK(choice.userInteractionEnabled == enabled.boolValue);
        HARNESS_CHECK([gestures tableView:gestureTable cellForRowAtIndexPath:hold].userInteractionEnabled);
        [gestures tableView:gestureTable didSelectRowAtIndexPath:split];
        HARNESS_CHECK(SGGestureSplit() == (enabled.boolValue ? 0 : 1));
    }
    // The Mod page keeps its action's symbol when row decoration is shared with Settings.
    SGModPage *about = (SGModPage *)SGAboutPage();
    SGModRow *reset = nil, *storageLink = nil;
    for (SGModSection *section in about.sections) {
        for (SGModRow *row in section.rows) {
            if ([row.title isEqualToString:SGL(@"settings.mod.reset.title", @"Reset all settings")]) reset = row;
            if ([row.searchIdentifier isEqualToString:@"page.mod.storage"]) storageLink = row;
        }
    }
    HARNESS_CHECK([reset.symbol isEqualToString:@"trash"]);

    extern NSURL *SGHarnessStorageURI;
    HARNESS_CHECK(storageLink.page);
    SGModPage *hub = (id)storageLink.page();
    HARNESS_CHECK([hub.sections.lastObject.title isEqualToString:@"Retrine"] && hub.sections.lastObject.rows.count == 4);
    NSUInteger storage = [hub.sections indexOfObjectPassingTest:^BOOL(SGModSection *section, NSUInteger idx, BOOL *stop) {
        return [section.rows.firstObject.key isEqualToString:SGKeyShowCacheLimit];
    }];
    HARNESS_CHECK(storage != NSNotFound);
    SGModSection *group = hub.sections[storage];
    HARNESS_CHECK(group.rows.count == 2 && group.rows.firstObject.defaultOn && group.footer.length);
    UITableView *table = hub.tableView;
    table.frame = CGRectMake(0, 0, 375, 667);
    NSIndexPath *firstRow = [NSIndexPath indexPathForRow:0 inSection:storage];
    NSIndexPath *action = [NSIndexPath indexPathForRow:1 inSection:storage];
    [table reloadData];
    [table scrollToRowAtIndexPath:firstRow atScrollPosition:UITableViewScrollPositionTop animated:NO];
    [table layoutIfNeeded];
    UITableViewCell *toggleCell = [table cellForRowAtIndexPath:firstRow], *actionCell = [table cellForRowAtIndexPath:action];
    HARNESS_CHECK(toggleCell && actionCell && CGRectGetMaxY(toggleCell.frame) <= CGRectGetMinY(actionCell.frame));
    HARNESS_CHECK(CGRectGetMaxY(actionCell.frame) <= CGRectGetMinY([table rectForFooterInSection:storage]));
    [table.delegate tableView:table didSelectRowAtIndexPath:action];
    HARNESS_CHECK([SGHarnessStorageURI.absoluteString isEqualToString:@"spotify:config:storage"]);

    // A navigation controller reached through the source's parents includes itself in the search.
    UIViewController *home = [UIViewController new];
    UINavigationController *root = [[UINavigationController alloc] initWithRootViewController:home];
    SGOpenModSettings(home.view);
    HARNESS_CHECK([root.topViewController.title isEqualToString:@"Retrine"]);

    // A deeper stack in the first child's subtree wins over a shallower later sibling.
    UIViewController *container = [UIViewController new], *wrapper = [UIViewController new];
    UINavigationController *first = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    UINavigationController *later = [[UINavigationController alloc] initWithRootViewController:[UIViewController new]];
    [container addChildViewController:wrapper];
    [wrapper didMoveToParentViewController:container];
    [wrapper addChildViewController:first];
    [first didMoveToParentViewController:wrapper];
    [container addChildViewController:later];
    [later didMoveToParentViewController:container];
    SGOpenModSettings(container.view);
    HARNESS_CHECK([first.topViewController.title isEqualToString:@"Retrine"]);
    NSLog(@"[harness] refactor checks PASS");
}

static void findViews(UIView *root, Class kind, NSMutableArray *found) {
    if ([root isKindOfClass:kind]) [found addObject:root];
    for (UIView *sub in root.subviews) findViews(sub, kind, found);
}

// With `rows` on the launch line, Spotify's settings list controller and the side drawer's list by their own
// names, made before ModSettings.x's %ctor hooks them (constructor priorities hold within this binary).
static const char *const kDrawerClass = "_TtC23SideDrawer_ListPageImplP33_1D8CA7A9CC41E8D184AF8B9AAE4E684E28SideDrawerListCollectionView";
static const char *const kSettingsClass = "_TtC21Settings_PlatformImpl26SettingsListViewController";

__attribute__((constructor(101))) static void harnessClasses(void) {
    if (![NSProcessInfo.processInfo.arguments containsObject:@"rows"]) return;
    objc_registerClassPair(objc_allocateClassPair(UICollectionView.class, kDrawerClass, 0));
    objc_registerClassPair(objc_allocateClassPair(UIViewController.class, kSettingsClass, 0));
}

// The `gated` page: a switch, ten rows of filler, then a headed and noted section whose twelve rows show only
// while the switch is on, and a row that comes by itself once `later` is played.
static BOOL sg_later;
static NSString *const kGate = @"spotifyglass.harness.gate";

static UIViewController *gatedPage(void) {
    SGSetEnabled(kGate, NO);
    NSMutableArray<SGModRow *> *filler = [NSMutableArray array], *gated = [NSMutableArray array];
    for (int i = 0; i < 10; i++) [filler addObject:SGStatRow([NSString stringWithFormat:@"Filler %d", i + 1], ^NSString *{ return @"-"; })];
    for (int i = 0; i < 12; i++) {
        SGModRow *row = SGStatRow([NSString stringWithFormat:@"Gated %d", i + 1], ^NSString *{ return @"on"; });
        row.visible = ^BOOL { return SGFlag(kGate, NO); };
        [gated addObject:row];
    }
    SGModRow *later = SGStatRow(@"Came by itself", ^NSString *{ return @"later"; });
    later.visible = ^BOOL { return sg_later; };
    return [[SGModPage alloc] initWithTitle:@"Gated" intro:nil sections:@[
        SGSection(@"Gate", [@[SGOptionRow(@"Show the gated rows", nil, kGate)] arrayByAddingObjectsFromArray:filler]),
        SGNotedSection(@"Gated", gated, @"A note under the gated rows, which goes with them."),
        SGSection(@"Later", @[later]),
    ] footer:nil];
}

// The `alerts` page, for the alerts SGModPage itself brings up: a switch with an ⓘ (`info`) and a switch whose
// warning comes up as it is turned on (`toggle=0.1`); `lock` asks the page why a locked row will not move.
@interface SGModPage (HarnessAlerts)
- (void)explainLock;
@end

static UIViewController *alertsPage(void) {
    SGModRow *info = SGOptionRow(@"With an info button", nil, @"spotifyglass.harness.alerts.info");
    info.info = @"What the row does, read out under its title.";
    SGModRow *warned = SGOptionRow(@"Unstable", nil, @"spotifyglass.harness.alerts.warned");
    warned.warning = @"This one can misbehave.";
    SGSetEnabled(warned.key, NO);
    return [[SGModPage alloc] initWithTitle:@"Alerts" intro:nil sections:@[SGSection(nil, @[info, warned])] footer:nil];
}

static NSString *styleName(UIUserInterfaceStyle style) {
    return style == UIUserInterfaceStyleDark ? @"dark" : style == UIUserInterfaceStyleLight ? @"light" : @"unspecified";
}

@interface SGInformationPresenter : UIViewController
@property (nonatomic, strong) UIAlertController *information;
@property (nonatomic) BOOL animated;
@property (nonatomic, copy) void (^completion)(void);
@end
@implementation SGInformationPresenter
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    self.information = (UIAlertController *)controller;
    self.animated = animated;
    self.completion = completion;
}
@end

static void pageStyleChecks(void) {
    SGInformationPresenter *presenter = [SGInformationPresenter new];
    SGPresentInformation(presenter, @"Information", @"Details");
    UIAlertController *alert = presenter.information;
    HARNESS_CHECK(alert.preferredStyle == UIAlertControllerStyleAlert &&
        [alert.title isEqual:@"Information"] && [alert.message isEqual:@"Details"] &&
        alert.actions.count == 1 && [alert.actions.firstObject.title isEqual:@"확인"] &&
        alert.actions.firstObject.style == UIAlertActionStyleCancel && presenter.animated && !presenter.completion);

    HARNESS_CHECK(UIContentSizeCategoryCompareToCategory(UIApplication.sharedApplication.preferredContentSizeCategory,
        UIContentSizeCategoryExtraSmall) == NSOrderedDescending);
    UIFont *capped = SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightBold, UIContentSizeCategoryExtraSmall);
    UITraitCollection *small = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryExtraSmall];
    HARNESS_CHECK(capped.pointSize == [UIFont preferredFontForTextStyle:UIFontTextStyleBody compatibleWithTraitCollection:small].pointSize &&
        (capped.fontDescriptor.symbolicTraits & UIFontDescriptorTraitBold));
    HARNESS_CHECK(SGCategoryCappedFont(UIFontTextStyleBody, UIFontWeightRegular, nil).pointSize ==
        [UIFont preferredFontForTextStyle:UIFontTextStyleBody].pointSize);

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 480)];
    table.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    table.contentSize = CGSizeMake(320, 1000);
    table.contentInset = UIEdgeInsetsMake(20, 3, 40, 5);
    table.contentOffset = CGPointMake(0, -20);
    UIView *header = [UIView new];
    [table addSubview:header];
    [table addSubview:[UIView new]];
    SGPositionPinnedPreview(table, header, 80);
    HARNESS_CHECK(table.contentOffset.y == -80 &&
        UIEdgeInsetsEqualToEdgeInsets(table.contentInset, UIEdgeInsetsMake(80, 3, 40, 5)) &&
        UIEdgeInsetsEqualToEdgeInsets(table.verticalScrollIndicatorInsets, table.contentInset) &&
        CGRectEqualToRect(header.frame, CGRectMake(0, -80, 320, 80)) && table.subviews.lastObject == header);
    table.contentOffset = CGPointMake(0, 200);
    SGPositionPinnedPreview(table, header, 100);
    HARNESS_CHECK(table.contentOffset.y == 200 && CGRectEqualToRect(header.frame, CGRectMake(0, 200, 320, 100)));
    NSLog(@"[harness] page style checks PASS");
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UINavigationController *nav;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"background-check"]) {
        extern void SGCheckSettingsBackground(void);
        SGCheckSettingsBackground();
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"page-style-check"]) {
        pageStyleChecks();
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"font-check"]) {
        UIFont *base = [UIFont systemFontOfSize:23.5 weight:UIFontWeightSemibold];
        UIFont *font = SGMonospacedDigitsFont(base);
        NSArray *features = [font.fontDescriptor objectForKey:UIFontDescriptorFeatureSettingsAttribute];
        HARNESS_CHECK(([features containsObject:@{
            UIFontFeatureTypeIdentifierKey: @(kNumberSpacingType),
            UIFontFeatureSelectorIdentifierKey: @(kMonospacedNumbersSelector)
        }]));
        HARNESS_CHECK(font.pointSize == 23.5);
        HARNESS_CHECK(SGMonospacedDigitsFont(nil) == nil);
        NSLog(@"[harness] tabular font checks PASS");
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"refactor-check"]) {
        refactorChecks();
        exit(0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"search-controller"]) {
        NSUInteger failures = searchControllerChecks();
        NSLog(@"[harness] search controller %@", failures ? @"failed" : @"passed");
        exit(failures ? 1 : 0);
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"search-places"]) {
        NSUInteger failures = searchPlacesChecks();
        NSLog(@"[harness] search places %@", failures ? @"failed" : @"passed");
        exit(failures ? 1 : 0);
    }
    NSLog(@"[harness] page protocol %@", NSStringFromProtocol(@protocol(SPTPageController)));
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    if (![args containsObject:@"keep"]) {
        SGSetEnabled(SGKeyRedesign, NO);
        SGSetEnabled(SGKeyRedesignUntested, NO);
    }
    NSMutableArray<NSString *> *actions = [NSMutableArray array];
    for (NSString *arg in [args subarrayWithRange:NSMakeRange(1, args.count - 1)]) {
        if ([arg isEqualToString:@"redesign"]) SGSetEnabled(SGKeyRedesign, YES);
        else if ([arg isEqualToString:@"warning"]) SGHarnessWarning = YES;
        else if (![arg isEqualToString:@"keep"] && ![arg isEqualToString:@"system"]) [actions addObject:arg];
    }

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    UIViewController *home = [UIViewController new];
    home.view.backgroundColor = UIColor.blackColor;
    self.nav = [[UINavigationController alloc] initWithRootViewController:home];
    // `system`: the window takes the system's appearance and only the navigation stack is dark, as in Spotify, whose
    // Info.plist sets no style (light-check.sh drops the harness's).
    if ([args containsObject:@"system"]) self.nav.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    else self.window.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.window.rootViewController = self.nav;
    [self.window makeKeyAndVisible];
    if ([args containsObject:@"information-check"]) {
        extern void SGCheckInformationAlerts(void);
        dispatch_async(dispatch_get_main_queue(), ^{ SGCheckInformationAlerts(); });
        return YES;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ SGOpenModSettings(home.view); });

    [actions enumerateObjectsUsingBlock:^(NSString *action, NSUInteger i, BOOL *stop) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1 + 0.9 * i) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"[harness] %@", action);
            [self run:action];
        });
    }];
    return YES;
}

- (UITableView *)table {
    return ((UITableViewController *)self.nav.topViewController).tableView;
}

- (NSIndexPath *)pathFrom:(NSString *)text {
    NSArray<NSString *> *at = [text componentsSeparatedByString:@"."];
    return [NSIndexPath indexPathForRow:at[1].integerValue inSection:at[0].integerValue];
}

- (void)run:(NSString *)action {
    if ([action isEqualToString:@"search-destinations"]) {
        SGSearchDestinationCheck *check = [SGSearchDestinationCheck new];
        check.nav = self.nav;
        [check start];
        return;
    }
    if ([action isEqualToString:@"prompt-check"]) {
        extern void SGCheckTranslationPromptUI(UINavigationController *);
        SGCheckTranslationPromptUI(self.nav);
        return;
    }
    NSArray<NSString *> *parts = [action componentsSeparatedByString:@"="];
    NSString *verb = parts.firstObject, *value = parts.count > 1 ? parts[1] : @"";
    UITableView *table = self.table;
    if ([verb isEqualToString:@"toggle"]) {
        NSMutableArray<UIControl *> *controls = [NSMutableArray array];
        findViews([table cellForRowAtIndexPath:[self pathFrom:value]].accessoryView, UIControl.class, controls);
        UIControl *toggle = nil;
        for (UIControl *control in controls) if ([control respondsToSelector:@selector(setOn:animated:)]) toggle = control;
        if (!toggle) { NSLog(@"[harness] no switch at %@", value); return; }
        [(id)toggle setOn:![(id)toggle isOn] animated:YES];
        [toggle sendActionsForControlEvents:UIControlEventValueChanged];
    } else if ([verb isEqualToString:@"cancel"]) {
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if (![alert isKindOfClass:UIAlertController.class]) return;
        NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
        [alert dismissViewControllerAnimated:YES completion:nil];
    } else if ([verb isEqualToString:@"bottom"]) {
        [table setContentOffset:CGPointMake(0, MAX(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.size.height + table.adjustedContentInset.bottom)) animated:NO];
    } else if ([verb isEqualToString:@"gated"]) {
        [self.nav pushViewController:gatedPage() animated:NO];
    } else if ([verb isEqualToString:@"alerts"]) {
        [self.nav pushViewController:alertsPage() animated:NO];
    } else if ([verb isEqualToString:@"info"]) {
        // The ⓘ beside the first row's switch, tapped.
        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        findViews([table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]].accessoryView, UIButton.class, buttons);
        [buttons.firstObject sendActionsForControlEvents:UIControlEventTouchUpInside];
    } else if ([verb isEqualToString:@"lock"]) {
        [(SGModPage *)self.nav.topViewController explainLock];
    } else if ([verb isEqualToString:@"information"]) {
        SGPresentInformation(self.nav.topViewController, @"Information", @"An alert the mod presents through SGPresentDark.");
    } else if ([verb isEqualToString:@"look"]) {
        UIViewController *shown = self.window.rootViewController;
        while (shown.presentedViewController) shown = shown.presentedViewController;
        NSLog(@"[harness] look %@ controller %@ presentation %@ frame %@ window %.0f", NSStringFromClass(shown.class),
              styleName(shown.traitCollection.userInterfaceStyle), styleName(shown.presentationController.traitCollection.userInterfaceStyle),
              NSStringFromCGRect([shown.view convertRect:shown.view.bounds toView:nil]), self.window.bounds.size.width);
    } else if ([verb isEqualToString:@"rows"]) {
        // The row ModSettings.x adds to Spotify's settings list and to the side drawer's list, each emptied of its
        // subviews afterward as Spotify can do, then laid out again.
        NSUInteger (^count)(UIView *) = ^NSUInteger(UIView *list) {
            NSUInteger n = 0;
            for (UIView *sub in list.subviews) n += [NSStringFromClass(sub.class) isEqualToString:@"SGModSettingsRow"];
            return n;
        };
        void (^empty)(UIView *) = ^(UIView *list) {
            for (UIView *sub in [list.subviews copy]) [sub removeFromSuperview];
            [list setNeedsLayout];
            [list layoutIfNeeded];
        };
        UICollectionView *drawer = [[NSClassFromString(@(kDrawerClass)) alloc] initWithFrame:CGRectMake(0, 0, 390, 600)
                                                                         collectionViewLayout:[UICollectionViewFlowLayout new]];
        [self.window addSubview:drawer];
        [drawer layoutIfNeeded];
        NSUInteger drawerFirst = count(drawer);
        empty(drawer);
        UIViewController *settings = [NSClassFromString(@(kSettingsClass)) new];
        UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) collectionViewLayout:[UICollectionViewFlowLayout new]];
        [settings.view addSubview:list];
        [settings viewDidLayoutSubviews];
        [list layoutIfNeeded];
        NSUInteger settingsFirst = count(list);
        empty(list);
        NSLog(@"[harness] rows: drawer %lu on its first layout, %lu after it was emptied; settings %lu, %lu after it was emptied",
              (unsigned long)drawerFirst, (unsigned long)count(drawer), (unsigned long)settingsFirst, (unsigned long)count(list));
        [drawer removeFromSuperview];
    } else if ([verb isEqualToString:@"needs"]) {
        [self.nav pushViewController:[[SGModPage alloc] initWithTitle:@"Lock screen" intro:nil sections:@[
            SGSection(@"Lock screen artwork", @[SGLockScreenArtworkNeedsRow()]),
        ] footer:nil] animated:NO];
    } else if ([verb isEqualToString:@"tap"]) {
        NSIndexPath *path = [self pathFrom:value];
        [table.delegate tableView:table didSelectRowAtIndexPath:path];
        UIAlertController *alert = (UIAlertController *)self.nav.presentedViewController;
        if ([alert isKindOfClass:UIAlertController.class]) NSLog(@"[harness] alert \"%@\": %@", alert.title, alert.message);
    } else if ([verb isEqualToString:@"top"]) {
        [table setContentOffset:CGPointMake(0, -table.adjustedContentInset.top) animated:NO];
    } else if ([verb isEqualToString:@"later"]) {
        sg_later = YES;
    } else if ([verb isEqualToString:@"layout"]) {
        UIEdgeInsets inset = table.adjustedContentInset;
        NSLog(@"[harness] offset %.0f of room %.0f", table.contentOffset.y + inset.top, table.bounds.size.height - inset.top - inset.bottom);
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSLog(@"[harness] section %ld: %ld rows, heading %.0f pt, note %.0f pt", (long)section, (long)[table numberOfRowsInSection:section],
                  [table rectForHeaderInSection:section].size.height, [table rectForFooterInSection:section].size.height);
        }
    } else if ([verb isEqualToString:@"dump"]) {
        NSLog(@"[harness] Redesigned UI stored %d", SGRedesignedUIStored());
        for (NSInteger section = 0; section < table.numberOfSections; section++) {
            NSMutableArray<NSString *> *rows = [NSMutableArray array];
            for (NSInteger row = 0; row < [table numberOfRowsInSection:section]; row++) {
                NSIndexPath *path = [NSIndexPath indexPathForRow:row inSection:section];
                UITableViewCell *cell = [table.dataSource tableView:table cellForRowAtIndexPath:path];
                NSMutableArray<UILabel *> *labels = [NSMutableArray array];
                findViews(cell.accessoryView, UILabel.class, labels);
                NSString *text = [(UIListContentConfiguration *)cell.contentConfiguration text];
                [rows addObject:labels.count ? [NSString stringWithFormat:@"%@ [%@]", text, labels.firstObject.text] : text];
            }
            NSLog(@"[harness] section %ld: %@", (long)section, [rows componentsJoinedByString:@", "]);
        }
    }
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
