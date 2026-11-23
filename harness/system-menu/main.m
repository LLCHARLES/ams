// Redesigned/ContextMenu/ContextMenu.x and Redesigned/Player/PlayerMenu.m run for real against a mock of
// Spotify's player ⋯ and its context menu sheet (its class name, a table of rows that are Encore-style ListRow
// controls and no didSelect, as on the phone), and the system menu checked as it comes up.
//
//     THEOS=$HOME/theos ./build.sh && xcrun simctl install <udid> build/SystemMenuHarness.app
//     xcrun simctl launch --console-pty <udid> com.retrine.systemmenuharness <scenario>
//
// The ⋯ is the mod's own pull-down button over Spotify's ⋯, and a tap on it is a finger's touch (../tabbar/touch.m),
// down and up, at its middle: UIKit opens the button's menu on the touch down. (Tapped with -performPrimaryAction
// before, the harness missed that a finger's touch on a button holding no menu yet opened nothing, 2026-10-06.)
// Every scenario taps at 1 s and prints PASS or FAIL lines, then `done` (README.md lists them). A pick or a
// submenu is opened the way a finger on the menu does it, through the menu view's own selection
// (_UIContextMenuView's _handleSelectionForElement:, the harness's only private call).
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import "Redesigned/ContextMenu/ContextMenu.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "../harness-fail.h"
#import "../background-work.h"

// The album footer is exercised by harness/album-queue and the Spotify simulator test. These
// player-menu fixtures do not provide an album page or the shared album footer.
void SGAlbumQueueInstall(UIViewController *menu) {}

void SGRPlayerMenuWatch(UIView *button);
void SGRPlayerMenuInTitleRow(UIView *title);
// The Kit around PlayerMenu.m: the title's white, and Star add button (below) on for the `star` scenario alone.
BOOL SGRStarAddOn(void);
UIColor *SGRPrimary(void) { return UIColor.whiteColor; }
// SGRRestyle.m is not built: the view under `root` with that identifier, looked for afresh each time.
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *cacheKey) {
    if ([root.accessibilityIdentifier isEqualToString:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = SGRFindByIdentifier(child, identifier, cacheKey);
        if (found) return found;
    }
    return nil;
}
// touch.m: a finger's touches, through UIKit's own recognizers.
extern void SGHarnessTap(UIWindow *window, CGPoint point);

// The real request owner, for supersession without replaying UIKit's still-dismissing menu animation.
// Other delayed scenarios exercise creation and release entirely through the real pull-down menu.
@interface SGRMenuSession : NSObject
@property (nonatomic) BOOL direct;
@property (nonatomic, weak) UIControl *spotify;
@property (nonatomic, weak) UIViewController *presented;
@property (nonatomic, weak) UIButton *anchor;
- (void)requestSheet;
- (void)menuEnded;
- (void)pollRows;
- (void)shown;
- (UIDeferredMenuElement *)deferredRows;
- (NSArray<UIMenuElement *> *)rowElements;
- (void)adoptSheet:(UIViewController *)sheet from:(UIViewController *)presenter completion:(dispatch_block_t)completion;
@end

static NSString *scenario(void) {
    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    return arguments.count > 1 ? arguments.lastObject : @"rows";
}

static BOOL is(NSString *run) {
    return [scenario() isEqualToString:run];
}

BOOL SGRStarAddOn(void) { return is(@"star"); }

static void check(BOOL ok, NSString *what) {
    if (!ok) HARNESS_FAIL(@"%@", what);
    NSLog(@"[harness] %@ %@", ok ? @"PASS" : @"FAIL", what);
}

static void after(NSTimeInterval seconds, dispatch_block_t block) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds * NSEC_PER_SEC)), dispatch_get_main_queue(), block);
}

// Runs `then` once `condition` holds, or after `limit` seconds whether or not it does; looks every 10 ms.
static void waitFor(BOOL (^condition)(void), NSTimeInterval limit, dispatch_block_t then) {
    if (condition() || limit <= 0) {
        then();
        return;
    }
    after(0.01, ^{ waitFor(condition, limit - 0.01, then); });
}

#pragma mark - what the menu's code calls

static double sg_speed = 1;
static float sg_pitch, sg_reverb;
static BOOL sg_follows = YES, sg_animated;
static NSInteger sg_background = 2;
double SGPlayerSpeed(void) { return sg_speed; }
BOOL SGPlayerSpeedAllowed(void) { return YES; }
void SGSetPlayerSpeed(double speed) { sg_speed = speed; NSLog(@"[harness] speed %.2f", speed); }
void SGPlayerShowSpeedPitchPanel(UIView *from) { NSLog(@"[harness] speed and pitch panel requested"); }
float SGPlayerPitch(void) { return sg_pitch; }
void SGSetPlayerPitch(float semitones) { sg_pitch = semitones; NSLog(@"[harness] pitch %.0f", semitones); }
BOOL SGPlayerPitchAvailable(void) { return YES; }
BOOL SGPlayerPitchFollowsSpeed(void) { return sg_follows; }
void SGSetPlayerPitchFollowsSpeed(BOOL follows) { sg_follows = follows; }
float SGPlayerReverb(void) { return sg_reverb; }
void SGPlayerSetReverb(float amount) { sg_reverb = amount; }
BOOL SGPlayerMenuOffersAnimatedArtwork(void) { return YES; }
BOOL SGPlayerMenuAnimatedArtwork(void) { return sg_animated; }
void SGPlayerMenuSetAnimatedArtwork(BOOL on) { sg_animated = on; NSLog(@"[harness] animated artwork %d", on); }
static NSUInteger sg_marked;
void SGPlayerMenuMarkPlayers(void) { sg_marked++; }
// Lyrics Source (LyricsSources.m, LyricsPick.m): every source off, so the menu offers no Lyrics Source, and the
// rest is never asked.
NSString *SGKaraokePlayingTrack(void) { return @"harness"; }
BOOL SGLyricsEnabled(void) { return NO; }
NSArray<NSString *> *SGLyricsOrder(void) { return @[]; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
NSString *SGLyricsCreditFor(NSString *trackID) { return nil; }
NSString *SGLyricsChosenSource(NSString *trackID) { return nil; }
NSDictionary<NSString *, SGLyricsResult *> *SGLyricsOffersSoFar(NSString *trackID, NSArray<NSString *> **asking) { return @{}; }
void SGLyricsChooseSource(NSString *trackID, NSString *key) {}
void SGLyricsChooseAutomatic(NSString *trackID) {}
void SGLyricsAskOffers(NSString *trackID) {}
NSNotificationName const SGLyricsOffersDidChangeNotification = @"harness.offers";
SGKaraokeTiming SGKaraokeLinesTiming(NSArray<SGKaraokeLine *> *lines) { return SGKaraokeTimingNone; }
void SGPresentPopover(UIViewController *panel, UIView *from) { HARNESS_FAIL(@"Unexpected lyrics popover"); }
// The player's background (Redesigned/Player/Player.h's SGRPlayerBackgroundKind): Fluid, so the menu offers
// Animated and the Visualizer; Show Animated Artwork switches it on.
NSInteger SGRPlayerBackground(void) { return sg_background; }
void SGRPlayerMenuSetBackground(NSInteger kind) { sg_background = kind; SGPlayerMenuSetAnimatedArtwork(kind == 3); }
@class SPTPlayerState;
SPTPlayerState *SGPlayerState(void) { return nil; }
NSString *SGURIString(id uri) { return nil; }
// Song blocking (ArtistBlock.m): with no track URI the menu never offers it here.
BOOL SGSongBlocked(NSString *uri) { return NO; }
void SGSetSongBlocked(NSString *uri, NSString *title, NSString *artist, BOOL blocked) {}
// A page's pinned ⋯ (Kit/SGRActionRow.m; its own claim is pinned-check.m's): tapped in `pinned`, its claim is what the
// sheet coming next reads, until the system menu has taken a sheet over for it. None in every other scenario.
static __weak UIView *sg_pinnedMore;
UIView *SGRPinnedMoreRecentButton(void) { return sg_pinnedMore; }
void SGRPinnedMoreTaken(void) { sg_pinnedMore = nil; }
void SGRAnimate(NSInteger motion, void (^animations)(void), void (^completion)(BOOL finished)) {
    [UIView animateWithDuration:0.2 animations:animations completion:completion];
}
// AudioEffectsPage.m is not built (harness/audio-effects-page has the page): the summary reads 2 effects, and
// Audio effects counts the sheet it is asked for, with the player's ⋯ as its source.
static NSUInteger sg_effectsSheets;
static __weak UIView *sg_effectsFrom;
NSString *SGDSPSummary(void) { return @"2 effects"; }
void SGDSPShowSettingsSheet(UIView *from) { sg_effectsSheets++; sg_effectsFrom = from; NSLog(@"[harness] audio effects sheet requested"); }
// LyricsTools.m is not built; no lyrics action is offered.
UIAction *SGRLyricsSearchAction(NSString *trackID) { return nil; }
// ShareCards.m is not built; with no track playing, the menu offers no song card.
void SGRShareSongCard(UIView *source) {}
NSString *SGLyricsPiPMenuTitle(void) { return @"Open lyrics Picture in Picture"; }
void SGLyricsPiPToggle(UIView *from) { NSLog(@"[harness] lyrics PiP"); }
// LyricsStyle.m and PlayerQueue.m are not built. Playing Next presents a real navigation panel, after the
// menu's transition, so the production menu handler exercises ContextMenu.x's presentation interception.
UIMenu *SGRLyricsStyleMenu(NSString *title) { return [UIMenu menuWithTitle:title children:@[]]; }
static __weak UIViewController *sg_modPanel;
void SGRPlayerShowQueue(UIView *from) {
    UIViewController *root = from.window.rootViewController;
    waitFor(^BOOL { return !root.presentedViewController && !root.transitionCoordinator; }, 1, ^{
        check(root != nil && !root.presentedViewController && !root.transitionCoordinator, @"the mod panel can present after the menu");
        UIViewController *content = [UIViewController new];
        content.view.backgroundColor = UIColor.systemBlueColor;
        UINavigationController *panel = [[UINavigationController alloc] initWithRootViewController:content];
        panel.modalPresentationStyle = UIModalPresentationPageSheet;
        sg_modPanel = panel;
        [root presentViewController:panel animated:NO completion:nil];
    });
}

// Every action and submenu the menu makes, by its title, so the harness can pick or open one.
static NSMutableDictionary<NSString *, UIMenuElement *> *sg_elements;
static IMP sg_actionWithTitle, sg_menuWithTitle;
static UIAction *recordAction(id self, SEL _cmd, NSString *title, UIImage *image, NSString *identifier, UIActionHandler handler) {
    UIAction *action = ((UIAction *(*)(id, SEL, NSString *, UIImage *, NSString *, UIActionHandler))sg_actionWithTitle)(self, _cmd, title, image, identifier, handler);
    if (title) sg_elements[title] = action;
    return action;
}
static UIMenu *recordMenu(id self, SEL _cmd, NSString *title, UIImage *image, NSString *identifier, UIMenuOptions options, NSArray *children) {
    UIMenu *menu = ((UIMenu *(*)(id, SEL, NSString *, UIImage *, NSString *, UIMenuOptions, NSArray *))sg_menuWithTitle)(self, _cmd, title, image, identifier, options, children);
    if (title.length) sg_elements[title] = menu;
    return menu;
}

#pragma mark - Spotify's sheet

// Whether the song plays in a playlist, whose sheet has Hide in this playlist (`playlist` switches it off between menus),
// and whether that row is grayed out (`stalecache`'s last menu).
static BOOL sg_inPlaylist, sg_hideGrayed;

// Rows as a playlist's sheet leaves them stored: Spotify's Like row and Hide in this playlist, enabled.
static void storePlaylistRows(void) {
    [NSUserDefaults.standardUserDefaults setObject:@[@[@{@"title": @"Add to Liked Songs", @"enabled": @YES, @"identifier": @"18"},
                                                       @{@"title": @"Hide in this playlist", @"enabled": @YES, @"identifier": @"7"},
                                                       @{@"title": @"Go to album", @"enabled": @YES, @"identifier": @"1"}]]
                                           forKey:@"spotifyglass.redesign.player.menuRows.track"];
}

// The rows of 9.1.78's player sheet, with their item numbers; Sleep timer last, below what the sheet shows.
static NSArray<NSArray<NSString *> *> *spotifyRows(void) {
    if (is(@"podcast")) return @[@[@"text.badge.plus", @"Add to queue", @"11"], @[@"square.stack", @"Go to show", @"40"], @[@"square.and.arrow.up", @"Share", @"9"]];
    NSMutableArray *rows = [@[@[@"plus.circle", @"Add to playlist", @"19"], @[@"text.badge.plus", @"Add to queue", @"11"],
                              @[@"square.and.arrow.up", @"Share", @"9"]] mutableCopy];
    // Spotify's own Like row (18), as 9.1.90's and 9.2.0's sheets have it for a song not saved yet; a saved one's
    // (titleitems') has none.
    if (!is(@"titleitems")) [rows addObject:@[@"heart", @"Add to Liked Songs", @"18"]];
    // Hide in this playlist (7), the X's action, as those sheets have it in a playlist.
    if (sg_inPlaylist) [rows addObject:@[@"eye.slash", @"Hide in this playlist", @"7"]];
    [rows addObjectsFromArray:@[@[@"square.stack", @"Go to album", @"1"], @[@"quote.bubble", @"Lyrics", @"28"]]];
    for (int i = 0; i < 8; i++) [rows addObject:@[@"circle", [NSString stringWithFormat:@"Row %d", i + 1], [NSString stringWithFormat:@"%d", 60 + i]]];
    [rows addObject:@[@"moon", @"Sleep timer", @"44"]];
    return rows;
}

// The titles of Spotify's rows the menu shows as rows (the quick row has the rest).
static NSArray<NSString *> *spotifyRowTitles(void) {
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSArray<NSString *> *row in spotifyRows()) {
        if (![@[@"Add to playlist", @"Add to queue", @"Share"] containsObject:row[1]]) [titles addObject:row[1]];
    }
    return titles;
}

static NSString *sg_selected;
static NSUInteger sg_spotifyTaps;
static NSUInteger sg_selectionCount;
// Hold the presentation itself, not just its rows, until the menu has released its session.
static BOOL sg_sheetHeld;
static CFTimeInterval sg_sheetAskedAt;
// When the sheet got its rows, and when its presentation completed (`slowsheet`).
static CFTimeInterval sg_rowsGivenAt, sg_sheetCompletedAt;
// The sheet waits for the harness to give it its rows (sg_rowsAfter seconds after it loads, or never).
static BOOL sg_rowsHeld, sg_rowsNever;
static NSTimeInterval sg_rowsAfter;

// A row of the mod's own in the sheet's header, as Redesigned/Playlist/PlaylistMenu.x puts Sort there.
@interface SGHarnessSortRow : UIControl
@end
@implementation SGHarnessSortRow
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"arrow.up.arrow.down"]];
    glyph.frame = CGRectMake(16, 16, 24, 24);
    [self addSubview:glyph];
    self.accessibilityLabel = @"Sort";
    [self addTarget:self action:@selector(fired) forControlEvents:UIControlEventTouchUpInside];
    return self;
}
- (void)fired {
    UIViewController *sheet = nil;
    for (UIResponder *responder = self; responder && !sheet; responder = responder.nextResponder) {
        if ([responder isKindOfClass:UINavigationController.class]) sheet = (UIViewController *)responder;
    }
    sg_selected = @"Sort";
    [sheet.presentingViewController dismissViewControllerAnimated:YES completion:^{ NSLog(@"[harness] sort fired"); }];
}
@end

// Spotify's row: an Encore ListRow, a control whose identifier is the item number, acting on touch up inside.
@interface SGHarnessListRow : UIControl
@property (nonatomic, copy) NSString *title;
@end
@implementation SGHarnessListRow
@end

@class SGHarnessPlayer;
static SGHarnessPlayer *sg_player;

@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController <UITableViewDataSource>
@property (nonatomic, strong) UITableView *table;
@property (nonatomic) BOOL loaded, sleepOptions;
- (void)giveRows;
@end

@interface SGHarnessPlayer : UIViewController <UIPopoverPresentationControllerDelegate>
@property (nonatomic, strong) UIButton *more, *arrow, *add;
@property (nonatomic, strong) UIControl *ban;
@property (nonatomic, strong) UIView *header, *titleElement, *addElement, *banElement;
@property (nonatomic, strong) UIStackView *titleRow;
@property (nonatomic) NSUInteger arrowTaps, addTaps, banTaps, frontDowns, frontUps, frontCancels;
@property (nonatomic, weak) UINavigationController *sheet;
@property (nonatomic, weak) UIViewController *sleepSheet;
- (void)presentSleepOptions;
- (void)presentMenuSheet;
- (UIButton *)front;
@end

@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.loaded = self.sleepOptions || !sg_rowsHeld;
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.rowHeight = 64;
    self.table.dataSource = self;
    self.table.allowsSelection = NO;
    [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
    if (is(@"sort")) {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 100, 56)];
        SGHarnessSortRow *sort = [[SGHarnessSortRow alloc] initWithFrame:header.bounds];
        sort.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:sort];
        self.table.tableHeaderView = header;
    }
    [self.view addSubview:self.table];
    if (!self.loaded && !sg_rowsNever && sg_rowsAfter > 0) {
        __weak typeof(self) weakSelf = self;
        after(sg_rowsAfter, ^{ [weakSelf giveRows]; });
    }
}

- (void)giveRows {
    if (self.loaded) return;
    self.loaded = YES;
    sg_rowsGivenAt = CACurrentMediaTime();
    [self.table reloadData];
    NSLog(@"[harness] the sheet has its rows");
}

- (NSArray<NSArray<NSString *> *> *)rows {
    if (self.sleepOptions) return @[@[@"timer", @"1 minute", @"s1"], @[@"timer", @"5 minutes", @"s5"]];
    return spotifyRows();
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.loaded ? self.rows.count : 0;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row" forIndexPath:indexPath];
    for (UIView *old in cell.contentView.subviews) [old removeFromSuperview];
    NSArray<NSString *> *row = self.rows[indexPath.row];
    SGHarnessListRow *control = [[SGHarnessListRow alloc] initWithFrame:cell.contentView.bounds];
    control.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    control.accessibilityIdentifier = row[2];
    control.title = row[1];
    [control addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    UIImageView *glyph = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:row[0]]];
    glyph.frame = CGRectMake(16, 20, 24, 24);
    glyph.tintColor = UIColor.whiteColor;
    [control addSubview:glyph];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(56, 0, 280, 64)];
    title.text = row[1];
    // Lyrics grayed out, as for a track no source has them for.
    BOOL grayed = [row[1] isEqualToString:@"Lyrics"] || (sg_hideGrayed && [row[1] isEqualToString:@"Hide in this playlist"]);
    title.textColor = grayed ? [UIColor colorWithWhite:1 alpha:0.3] : UIColor.whiteColor;
    [control addSubview:title];
    [cell.contentView addSubview:control];
    cell.backgroundColor = UIColor.clearColor;
    return cell;
}

// Share opens a page of its own inside the sheet; Sleep timer opens its options, inside the sheet 0.3 s later
// (`sleep`) or as a context menu sheet of its own presented from the player (`sleeppresent`); every other row
// does its thing and closes the sheet.
- (void)rowTapped:(SGHarnessListRow *)row {
    sg_selectionCount++;
    sg_selected = row.title;
    NSLog(@"[harness] selected %@", row.title);
    UINavigationController *navigation = self.navigationController;
    if ([row.title isEqualToString:@"Share"] || ([row.title isEqualToString:@"Sleep timer"] && !is(@"sleeppresent"))) {
        after([row.title isEqualToString:@"Share"] ? 0 : 0.3, ^{
            UIViewController *page = [UIViewController new];
            page.title = [row.title stringByAppendingString:@" page"];
            page.view.backgroundColor = UIColor.darkGrayColor;
            [navigation pushViewController:page animated:YES];
        });
        return;
    }
    if ([row.title isEqualToString:@"Sleep timer"]) {
        // As on the phone: the card stays while Spotify presents the timer's own sheet from the player.
        after(0.3, ^{ [sg_player presentSleepOptions]; });
        return;
    }
    [navigation.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end

// A controller of Spotify's own presented in place of the sheet's navigation controller, which it puts the sheet
// into only as it appears (`wrapped`), as NavigationUI_SheetImpl.ContainerViewController does on the phone.
__attribute__((objc_runtime_name("NavigationUI_SheetImpl.ContainerViewController")))
@interface SGHarnessWrapper : UIViewController
@property (nonatomic, strong) UINavigationController *inner;
@end
@implementation SGHarnessWrapper
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.inner.parentViewController) return;
    [self addChildViewController:self.inner];
    self.inner.view.frame = self.view.bounds;
    self.inner.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.inner.view];
    [self.inner didMoveToParentViewController:self];
}
@end

#pragma mark - the player

static UIView *menuView(UIView *root) {
    // UIKit can keep the dismissed menu in its window at alpha zero; it is no longer an open menu.
    if (root.hidden || root.alpha == 0) return nil;
    if ([NSStringFromClass(root.class) isEqualToString:@"_UIContextMenuView"]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = menuView(child);
        if (found) return found;
    }
    return nil;
}

static UIView *openMenu(void) {
    for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
        for (UIWindow *window in scene.windows) {
            UIView *found = menuView(window);
            if (found) return found;
        }
    }
    return nil;
}

// Whether `element`, or an item laid out in it (not one in a submenu), has `title` or that subtitle.
static BOOL laidOut(UIMenuElement *element, NSString *title) {
    if ([element.title isEqualToString:title] || [element.subtitle isEqualToString:title]) return YES;
    if (![element isKindOfClass:UIMenu.class]) return NO;
    UIMenu *menu = (UIMenu *)element;
    if (menu.title.length && !(menu.options & UIMenuOptionsDisplayInline)) return NO;
    for (UIMenuElement *child in menu.children) if (laidOut(child, title)) return YES;
    return NO;
}

// Whether the open menu has an item reading exactly `title`: a label on screen, or an item of the menu laid out
// below the screen's fold (the player's menu, Spotify's rows in place, is taller than the screen).
static BOOL menuShows(NSString *title) {
    __block BOOL found = NO;
    UIView *menu = openMenu();
    if (menu) {
        [sg_player.front.contextMenuInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *visible) {
            found = laidOut(visible, title);
            return visible;
        }];
        if (found) return YES;
    }
    void (^walk)(UIView *);
    __block __weak void (^weakWalk)(UIView *);
    weakWalk = walk = ^(UIView *view) {
        if ([view isKindOfClass:UILabel.class] && !view.hidden && view.window && [((UILabel *)view).text isEqualToString:title]) found = YES;
        for (UIView *child in view.subviews) weakWalk(child);
    };
    if (menu) walk(menu);
    return found;
}

static BOOL menuShowsAll(NSArray<NSString *> *titles) {
    for (NSString *title in titles) if (!menuShows(title)) return NO;
    return YES;
}

static BOOL menuShowsAny(NSArray<NSString *> *titles) {
    for (NSString *title in titles) if (menuShows(title)) return YES;
    return NO;
}

// The open menu's first level in order, whether on screen or scrolled past: actions by title, a submenu by its title in
// brackets, an inline group's children in place, Spotify's rows not in yet as <loading>.
static void flatten(UIMenuElement *element, NSMutableArray<NSString *> *titles) {
    if ([element isKindOfClass:UIDeferredMenuElement.class]) {
        [titles addObject:@"<loading>"];
        return;
    }
    if ([element isKindOfClass:UIMenu.class]) {
        UIMenu *menu = (UIMenu *)element;
        if (menu.title.length && !(menu.options & UIMenuOptionsDisplayInline)) {
            [titles addObject:[NSString stringWithFormat:@"[%@]", menu.title]];
            return;
        }
        for (UIMenuElement *child in menu.children) flatten(child, titles);
        return;
    }
    [titles addObject:element.title ?: @""];
}

static NSArray<NSString *> *shownOrder(UIButton *front) {
    __block UIMenu *visible = nil;
    [front.contextMenuInteraction updateVisibleMenuWithBlock:^UIMenu *(UIMenu *menu) {
        visible = menu;
        return menu;
    }];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    if (visible) flatten(visible, titles);
    return titles;
}

// Whether `titles` holds each of `want`, in that order.
static BOOL inOrder(NSArray<NSString *> *titles, NSArray<NSString *> *want) {
    NSUInteger from = 0;
    for (NSString *title in want) {
        NSUInteger at = from < titles.count ? [titles indexOfObject:title inRange:NSMakeRange(from, titles.count - from)] : NSNotFound;
        if (at == NSNotFound) return NO;
        from = at + 1;
    }
    return YES;
}

static void pick(NSString *title) {
    UIView *menu = openMenu();
    UIMenuElement *element = sg_elements[title];
    NSLog(@"[harness] picking %@ (%@)", title, element ? @"made" : @"never made");
    if (menu && element) ((void (*)(id, SEL, id))objc_msgSend)(menu, NSSelectorFromString(@"_handleSelectionForElement:"), element);
}

@implementation SGHarnessPlayer

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.25 green:0.1 blue:0.2 alpha:1];
    // Spotify's header row (trees/clean/player/01.txt: HeaderElementsUnit's view is a 402x48 row holding the
    // down arrow, 48x48 at x 12, and the ⋯, 48x48 at the trailing edge). PlayerHeader.x puts both away and hands
    // the ⋯ over, whose action brings the sheet up.
    self.header = [[UIView alloc] initWithFrame:CGRectMake(0, 70, 402, 48)];
    [self.view addSubview:self.header];
    self.arrow = [self headerButton:@"chevron.down" at:12 identifier:@"now-playing-minimize-button" label:@"Minimize"];
    self.more = [self headerButton:@"ellipsis" at:342 identifier:@"Context menu" label:@"More options"];
    [self.more addTarget:self action:@selector(moreTapped) forControlEvents:UIControlEventTouchUpInside];
    // Spotify's title row (trees/clean, player-off-full-tree.txt:1886-1896): the title's element, then the X's (24pt
    // wide, hidden unless Spotify offers it) and the add button's (48x48), arranged in a stack 24pt in from the sides.
    self.titleRow = [[UIStackView alloc] initWithFrame:CGRectMake(24, 560, 354, 48)];
    self.titleRow.alignment = UIStackViewAlignmentCenter;
    [self.view addSubview:self.titleRow];
    self.titleElement = [UIView new];
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 25)];
    title.text = @"Paradise City";
    title.accessibilityIdentifier = @"now-playing-title-label";
    [self.titleElement addSubview:title];
    [self.titleElement.heightAnchor constraintEqualToConstant:44].active = YES;
    [self.titleElement setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    // The X is an Encore button, a UIControl that is no UIButton (9.2.0's tree: Encore.Button.Tertiary).
    self.banElement = [self titleButton:nil width:24 identifier:@"feedback_headunit_right_ban_button_accessibility_identifier" label:@"Don't play this"];
    self.ban = self.banElement.subviews.firstObject;
    [self.ban addTarget:self action:@selector(banTapped) forControlEvents:UIControlEventTouchUpInside];
    self.banElement.hidden = YES;
    // Spotify's words for its add button (9.2.0's tree), which say nothing of what a tap on a saved song's does.
    self.addElement = [self titleButton:@"plus.circle" width:48 identifier:@"Components.UI.AddToButton" label:@"Add to playlist"];
    self.add = self.addElement.subviews.firstObject;
    [self.add addTarget:self action:@selector(addTapped) forControlEvents:UIControlEventTouchUpInside];
    for (UIView *element in @[self.titleElement, self.banElement, self.addElement]) [self.titleRow addArrangedSubview:element];
    [self.view layoutIfNeeded];
    // The press the ⋯'s targets listen to: down, and up or drag out (not the cancel UIKit sends as the menu comes up,
    // which the mod's button turns into a touch up outside once the menu ends).
    [self.front addTarget:self action:@selector(frontDown) forControlEvents:UIControlEventTouchDown];
    [self.front addTarget:self action:@selector(frontUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchDragExit];
    [self.front addTarget:self action:@selector(frontCancel) forControlEvents:UIControlEventTouchCancel];
}

// As PlayerHeader.x does on every layout of Spotify's header unit, and PlayerLyrics.x on every one of its title row.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGRPlayerMenuWatch(self.more);
    SGRPlayerMenuInTitleRow(self.titleElement);
}

- (UIButton *)headerButton:(NSString *)symbol at:(CGFloat)x identifier:(NSString *)identifier label:(NSString *)label {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.frame = CGRectMake(x, 0, 48, 48);
    button.accessibilityIdentifier = identifier;
    button.accessibilityLabel = label;
    button.alpha = 0;
    [self.header addSubview:button];
    return button;
}

// A button of the title row in an element of its own, as Spotify's ElementView holds each: a UIButton drawing
// `symbol`, or with none a plain UIControl.
- (UIView *)titleButton:(NSString *)symbol width:(CGFloat)width identifier:(NSString *)identifier label:(NSString *)label {
    UIView *element = [UIView new];
    [element.widthAnchor constraintEqualToConstant:width].active = YES;
    [element.heightAnchor constraintEqualToConstant:48].active = YES;
    UIControl *button = symbol ? [UIButton buttonWithType:UIButtonTypeSystem] : [UIControl new];
    if (symbol) [(UIButton *)button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.frame = CGRectMake(0, 0, width, 48);
    button.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    button.accessibilityIdentifier = identifier;
    button.accessibilityLabel = label;
    [element addSubview:button];
    return element;
}

- (void)addTapped {
    self.addTaps++;
    NSLog(@"[harness] Spotify's add button action ran");
}

- (void)banTapped {
    self.banTaps++;
    NSLog(@"[harness] Spotify's X action ran");
}

- (void)frontDown {
    self.frontDowns++;
}

- (void)frontUp {
    self.frontUps++;
}

- (void)frontCancel {
    self.frontCancels++;
}

// A finger on `button`'s middle.
- (void)touch:(UIView *)button {
    CGPoint middle = [button convertPoint:CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds)) toView:nil];
    NSLog(@"[harness] a finger taps %@ at %@ (hit view %@)", button.accessibilityIdentifier, NSStringFromCGPoint(middle),
          NSStringFromClass([button.window hitTest:middle withEvent:nil].class));
    SGHarnessTap(button.window, middle);
}

// What Spotify's ⋯ does: build its sheet and present it, animated.
- (void)moreTapped {
    sg_spotifyTaps++;
    sg_sheetAskedAt = CACurrentMediaTime();
    NSLog(@"[harness] Spotify's ⋯ action ran");
    if (!sg_sheetHeld) [self presentMenuSheet];
}

- (void)presentMenuSheet {
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:[_TtC24ContextMenu_InternalImpl25ContextMenuViewController new]];
    self.sheet = navigation;
    if (is(@"popover")) {
        // As on an iPad (9.2.0): a popover from Spotify's ⋯, in the app's window, kept a popover at any width.
        navigation.modalPresentationStyle = UIModalPresentationPopover;
        navigation.popoverPresentationController.sourceView = self.more;
        navigation.popoverPresentationController.sourceRect = self.more.bounds;
        navigation.popoverPresentationController.delegate = self;
    }
    if (is(@"notup") || is(@"notup-stored")) {
        // A popover anchored to the ⋯ as a source item, not a source view, which the mod does not move: UIKit drops it
        // from the mod's window as it did Spotify's iPad popover, so the sheet is taken and never up.
        navigation.modalPresentationStyle = UIModalPresentationPopover;
        navigation.popoverPresentationController.sourceItem = self.more;
        navigation.popoverPresentationController.delegate = self;
    }
    if (is(@"wrapped") || [scenario() hasPrefix:@"delayed-wrapped-"]) {
        SGHarnessWrapper *wrapper = [SGHarnessWrapper new];
        wrapper.inner = navigation;
        [self presentViewController:wrapper animated:YES completion:nil];
        return;
    }
    [self presentViewController:navigation animated:YES completion:nil];
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller
                                                               traitCollection:(UITraitCollection *)traits {
    return UIModalPresentationNone;
}

- (void)presentSleepOptions {
    _TtC24ContextMenu_InternalImpl25ContextMenuViewController *options = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    options.sleepOptions = YES;
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:options];
    self.sleepSheet = navigation;
    NSLog(@"[harness] Spotify presents the sleep timer's own sheet");
    [self presentViewController:navigation animated:YES completion:nil];
}

// The ⋯ beside the title: the mod's button in the title row.
- (UIButton *)front {
    for (UIView *view in self.titleRow.subviews) if ([NSStringFromClass(view.class) isEqualToString:@"SGRMenuFront"]) return (UIButton *)view;
    return nil;
}

// A finger's tap on the ⋯, which opens its menu on the touch down, as UIKit opens any button's menu. The time from
// the touch down to the menu on screen, looked at every 10 ms.
- (void)tap:(void (^)(CFTimeInterval took))up {
    CFTimeInterval tapped = CACurrentMediaTime();
    [self touch:self.front];
    waitFor(^BOOL { return openMenu() != nil; }, 3, ^{
        CFTimeInterval took = CACurrentMediaTime() - tapped;
        NSLog(@"[harness] the menu view is on screen %.0f ms after the touch down", took * 1000);
        if (up) up(openMenu() ? took : -1);
    });
}

- (UIWindow *)sheetWindow {
    return self.sheet.viewIfLoaded.window;
}

- (CGFloat)sheetAlpha {
    UIViewController *outer = self.sheet;
    while (outer.parentViewController) outer = outer.parentViewController;
    UIView *container = outer.presentationController.containerView;
    return container ? container.alpha : -1;
}

// Seen: in the app's window, or in the mod's window raised over it, its container opaque.
- (BOOL)sheetShown {
    UIWindow *window = self.sheetWindow;
    return window && self.sheetAlpha == 1 && (window == self.view.window || window.windowLevel > self.view.window.windowLevel);
}

- (BOOL)sheetGone {
    return !self.sheet.viewIfLoaded.window;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    static BOOL started;
    if (started) return;
    started = YES;
    after(1, ^{ [self run:scenario()]; });
}

static NSArray<NSString *> *quickTitles(void) {
    return @[@"Share", @"Add to Playlist", @"Add to Queue"];
}

- (_TtC24ContextMenu_InternalImpl25ContextMenuViewController *)mockSheet {
    return (id)self.sheet.viewControllers.firstObject;
}

- (void)run:(NSString *)run {
    if ([run isEqual:@"background"]) {
        sg_rowsHeld = sg_rowsNever = YES;
        SGRMenuSession *session = [SGRMenuSession new];
        UIButton *anchor = [[NSClassFromString(@"SGRMenuAnchor") alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
        [self.view addSubview:anchor];
        session.anchor = anchor;
        _TtC24ContextMenu_InternalImpl25ContextMenuViewController *sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
        [session shown];
        [session adoptSheet:sheet from:self completion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        SGHarnessBeginBackgroundWork();
        [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        check(SGHarnessLiveTimers() == 1, @"unresolved rows arm one poll");
        // Capture UIKit's deferred-provider boundary; the provider and row lifecycle remain production code.
        Method factory = class_getClassMethod(UIDeferredMenuElement.class, @selector(elementWithUncachedProvider:));
        IMP original = method_getImplementation(factory);
        __block void (^provider)(void (^)(NSArray<UIMenuElement *> *));
        IMP replacement = imp_implementationWithBlock(^id(id cls, void (^supplied)(void (^)(NSArray<UIMenuElement *> *))) {
            provider = [supplied copy];
            return ((id (*)(id, SEL, id))original)(cls, @selector(elementWithUncachedProvider:), supplied);
        });
        method_setImplementation(factory, replacement);
        [session deferredRows];
        method_setImplementation(factory, original);
        imp_removeBlock(replacement);
        __block NSArray<UIMenuElement *> *received;
        __block NSUInteger completions = 0;
        provider(^(NSArray<UIMenuElement *> *elements) { received = elements; completions++; });
        [center postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        check(SGHarnessLiveTimers() == 0, @"resign-active stops row polling before app state changes");
        sg_testAppState = UIApplicationStateBackground;
        [session pollRows];
        check(SGHarnessLiveTimers() == 0, @"background cannot restart row polling");
        sg_testAppState = UIApplicationStateActive;
        [center postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        check(SGHarnessLiveTimers() == 1, @"foreground resumes unresolved rows");
        NSTimer *poll = sg_testTimers.lastObject;
        for (NSUInteger attempt = 0; attempt < 50; attempt++) [poll fire];
        check(SGHarnessLiveTimers() == 0, @"unresolved rows exhaust a finite polling budget");
        BOOL completedAtExpiry = completions == 1 && received.count > 0;
        provider(^(NSArray<UIMenuElement *> *elements) { received = elements; completions++; });
        BOOL completedAfterExpiry = completions == 2 && received.count > 0;
        [sheet giveRows];
        [sheet viewDidLayoutSubviews];
        BOOL shareArrived = NO;
        for (UIMenu *group in [session rowElements])
            for (UIAction *action in group.children)
                if ([action.title isEqual:@"Share"]) shareArrived = YES;
        NSLog(@"[harness] expiry fallback %d, late Share %d, completions %lu",
              completedAtExpiry, shareArrived, (unsigned long)completions);
        check(completedAtExpiry && completedAfterExpiry && shareArrived && completions == 2 && SGHarnessLiveTimers() == 0,
              @"expiry completes deferred rows; late layout accepts Spotify rows without polling or duplicate completion");
        SGHarnessEndBackgroundWork();
        NSLog(@"[harness] background PASS");
        exit(0);
        });
        }];
        return;
    }
    void (^finish)(void) = ^{
        NSLog(@"[harness] done");
        exit(0);
    };
    // A page's pinned ⋯ tapped: Spotify's sheet for it is taken over and its menu opens from the ⋯. Closed, a track's ⋯
    // tapped well within the claim's window (SGRPinnedMoreWindow): its sheet is Spotify's, not the page's menu again.
    if ([run isEqualToString:@"pinned"]) {
        UIButton *pinned = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"ellipsis"] target:nil action:nil];
        pinned.frame = CGRectMake(self.view.bounds.size.width - 60, 62, 44, 44);
        [self.view addSubview:pinned];
        sg_pinnedMore = pinned;
        CFTimeInterval tapped = CACurrentMediaTime();
        [self presentMenuSheet];
        waitFor(^BOOL { return openMenu() != nil; }, 3, ^{
            check(openMenu() && !self.sheetShown, @"the pinned ⋯'s sheet is taken over: its menu is up, the sheet unseen");
            UIButton *anchor = nil;
            for (UIView *view in pinned.subviews) if ([NSStringFromClass(view.class) isEqualToString:@"SGRMenuAnchor"]) anchor = (UIButton *)view;
            [anchor.contextMenuInteraction dismissMenu];
            waitFor(^BOOL { return self.sheetGone && !openMenu(); }, 4, ^{
                check(self.sheetGone && !openMenu(), @"closed with no pick, the menu and its sheet went");
                NSLog(@"[harness] the track's ⋯ comes %.1f s after the pinned ⋯'s tap", CACurrentMediaTime() - tapped);
                [self presentMenuSheet];
                waitFor(^BOOL { return self.sheetShown || openMenu(); }, 2, ^{
                    dispatch_block_t verdict = ^{
                        check(self.sheetShown && !openMenu(), [NSString stringWithFormat:@"a track's ⋯ then shows Spotify's sheet, not the page's menu (sheet shown %d, menu up %d)",
                                                               self.sheetShown, openMenu() != nil]);
                        finish();
                    };
                    // HARNESS_HOLD in the environment: READY, and the screen held three seconds for a screenshot first.
                    if (!getenv("HARNESS_HOLD")) {
                        verdict();
                        return;
                    }
                    printf("READY\n");
                    fflush(stdout);
                    after(3, verdict);
                });
            });
        });
        return;
    }
    sg_rowsHeld = is(@"loading") || is(@"quick") || is(@"quicklate") || is(@"podcast") || is(@"stored") || is(@"playlist") || is(@"stalecache")
               || is(@"slowsheet") || is(@"star");
    sg_rowsNever = is(@"quicklate");
    sg_rowsAfter = is(@"quick") ? 1.2 : is(@"loading") || is(@"podcast") ? 1.5 : is(@"slowsheet") ? 3.4 : 0;

    if ([run hasPrefix:@"delayed-"] || [run hasPrefix:@"request-timeout-"] || is(@"request-superseded")) {
        sg_sheetHeld = YES;
        BOOL selection = [run hasSuffix:@"pick"];
        BOOL modPanel = [run hasSuffix:@"mod-panel"];
        BOOL timeout = [run hasPrefix:@"request-timeout-"];
        [self tap:^(CFTimeInterval took) {
            check(took >= 0, @"the menu opened before Spotify presents");
            __weak id session = [self.front valueForKey:@"session"];
            check(session != nil, @"the open menu owns its session");
            waitFor(^BOOL { return sg_spotifyTaps == 1; }, 1, ^{
                check(sg_spotifyTaps == 1 && !self.sheet, @"Spotify was asked once but has not presented");
                if (selection) pick(@"Add to Queue");
                else if (modPanel) pick(@"Playing Next");
                else [self.front.contextMenuInteraction dismissMenu];
                waitFor(^BOOL { return [self.front valueForKey:@"session"] == nil; }, 1, ^{
                    check([self.front valueForKey:@"session"] == nil, @"the ended menu released its session");
                    // Let menuEnded's queued block finish: neither the harness nor an anchor owns the request.
                    after(0.15, ^{
                        if (!modPanel) check(session != nil, @"an outstanding request survives the menu ending");
                        check(sg_selectionCount == 0, @"no action runs before the sheet arrives");
                        if (modPanel) {
                            waitFor(^BOOL { return sg_modPanel.viewIfLoaded.window == self.view.window; }, 1, ^{
                                UIViewController *panel = sg_modPanel;
                                check(panel != nil && panel.viewIfLoaded.window == self.view.window,
                                      @"the picked mod panel is visible in the app window");
                                check(self.presentedViewController == panel && panel.presentationController.containerView.alpha == 1,
                                      @"the mod panel is not hidden or dismissed");
                                check(CACurrentMediaTime() - sg_sheetAskedAt < 3, @"the late Spotify sheet is released within the request window");
                                [self presentMenuSheet];
                                after(4.3, ^{
                                    check(self.sheetGone && sg_selectionCount == 0, @"only the late Spotify sheet is discarded without firing a row");
                                    check(self.presentedViewController == panel && panel.viewIfLoaded.window == self.view.window
                                          && panel.presentationController.containerView.alpha == 1 && !panel.isBeingDismissed,
                                          @"the mod panel stays visible after the late Spotify sheet");
                                    check(session == nil, @"the adopted request releases its session after the late sheet goes");
                                    finish();
                                });
                            });
                            return;
                        }
                        if (timeout) {
                            after(3.2, ^{
                                check(session == nil, @"a timed-out request releases its session");
                                check(sg_selectionCount == 0, @"a timed-out request fires no action");
                                finish();
                            });
                            return;
                        }
                        if (is(@"request-superseded")) {
                            __weak SGRMenuSession *newer;
                            @autoreleasepool {
                                SGRMenuSession *replacement = [SGRMenuSession new];
                                replacement.direct = YES;
                                replacement.spotify = self.more;
                                [replacement requestSheet];
                                [replacement menuEnded];
                                newer = replacement;
                            }
                            after(0.15, ^{
                                check(sg_spotifyTaps == 2, @"the newer session requested Spotify's sheet");
                                check(session == nil, @"superseding releases the old request immediately");
                                check(newer != nil, @"the newer request survives its menu ending");
                                [self presentMenuSheet];
                                after(4.3, ^{
                                    check(newer == nil && self.sheetGone, @"the newer cancelled menu drops its sheet and releases its session");
                                    check(sg_selectionCount == 0, @"superseded and cancelled requests fire no actions");
                                    finish();
                                });
                            });
                            return;
                        }
                        [self presentMenuSheet];
                        // Beyond both timeout callbacks and the picked row's settle timer: no double fire or leak.
                        after(4.3, ^{
                            check(sg_selectionCount == (selection ? 1 : 0), selection
                                  ? @"the early selection fires exactly once" : @"the early dismissal fires no action");
                            if (selection) check([sg_selected isEqualToString:@"Add to queue"], @"the selected Spotify action runs");
                            check(self.sheetGone, selection ? @"the selected action dismisses the late sheet"
                                                          : @"the early dismissal drops the late sheet");
                            check(session == nil, @"the adopted request releases its session after the sheet goes");
                            finish();
                        });
                    });
                });
            });
        }];
        return;
    }

    if (is(@"stored-disabled")) {
        sg_rowsHeld = YES;
        [NSUserDefaults.standardUserDefaults setObject:@[@[@{@"title": @"Lyrics", @"enabled": @YES}]]
                                               forKey:@"spotifyglass.redesign.player.menuRows.track"];
        [self tap:^(CFTimeInterval took) {
            check(took >= 0, @"menu opened with stored actions");
            waitFor(^BOOL { return menuShows(@"Lyrics") && self.mockSheet != nil; }, 2, ^{
                check(menuShows(@"Lyrics"), @"the previously enabled Lyrics action is offered");
                pick(@"Lyrics");
                after(0.5, ^{
                    [self.mockSheet giveRows];
                    waitFor(^BOOL { return self.sheetShown; }, 2, ^{
                        check(!sg_selected && self.sheetShown, @"disabled live Lyrics is not fired; its sheet is shown");
                        finish();
                    });
                });
            });
        }];
        return;
    }
    if ([run isEqualToString:@"beside"]) {
        // The ⋯ beside the title, where the Music app has it: in the add button's slot of the title row, the add button
        // and the X drawn by nothing and read by nothing, VoiceOver reading it with Spotify's ⋯'s words; a finger there
        // reaches it, and its touch down opens the menu.
        UIView *front = self.front;
        check(front.superview == self.titleRow && CGRectEqualToRect(front.frame, self.addElement.frame),
              [NSString stringWithFormat:@"the ⋯ in the add button's slot (%@, the slot %@)", NSStringFromCGRect(front.frame), NSStringFromCGRect(self.addElement.frame)]);
        // Spotify gives the add button its alpha back as it redraws its state; it stays put away.
        self.add.alpha = 1;
        [self.view layoutIfNeeded];
        check(self.addElement.alpha == 0 && self.addElement.accessibilityElementsHidden && self.banElement.alpha == 0 && self.banElement.accessibilityElementsHidden,
              @"the add button and the X are put away, their slots not drawn and not read, whatever alpha Spotify gives the button");
        check(front.isAccessibilityElement && [front.accessibilityLabel isEqualToString:@"More options"], [NSString stringWithFormat:@"VoiceOver reads it as Spotify's ⋯ (%@)", front.accessibilityLabel]);
        UIImage *glyph = [(UIButton *)front imageForState:UIControlStateNormal];
        check([glyph.description containsString:@"ellipsis"], @"it draws the ⋯");
        CGPoint slot = [self.titleRow convertPoint:CGPointMake(CGRectGetMidX(self.addElement.frame), CGRectGetMidY(self.addElement.frame)) toView:nil];
        check([self.view.window hitTest:slot withEvent:nil] == front, @"a touch in the slot reaches the ⋯");
        after(0.3, ^{
            check(self.frontDowns == 0 && !openMenu() && sg_spotifyTaps == 0, @"nothing opened before the finger");
            [self tap:^(CFTimeInterval took) {
                check(took >= 0, @"a finger on the ⋯ opens the menu");
                check(self.frontDowns == 1, [NSString stringWithFormat:@"the mod's ⋯ sent its touch down (%lu)", (unsigned long)self.frontDowns]);
                // The finger lifted 0.08 s after the touch down; the press holds while the menu is up.
                after(0.5, ^{
                    check(self.frontUps == 0, [NSString stringWithFormat:@"with the menu up the press holds: no touch up yet (canceled %lu)", (unsigned long)self.frontCancels]);
                    [self.front.contextMenuInteraction dismissMenu];
                    waitFor(^BOOL { return self.frontUps > 0; }, 2, ^{
                        check(self.frontUps == 1, [NSString stringWithFormat:@"the menu's end lets the press go (%lu)", (unsigned long)self.frontUps]);
                        finish();
                    });
                });
            }];
        });
        return;
    }
    if ([run isEqualToString:@"star"]) {
        // Star add button on (issue #44): Spotify's add button stays on the row, drawn and read, its tap Spotify's, the X
        // put away and the ⋯ in the row's end. The harness holds the row's arranged views in before the ⋯ by its width,
        // as PlayerTitle.x does (harness/player/title-style-check.sh checks that). Spotify's rows held back, the menu,
        // which would have the add button's item then, has none: the button is on the row.
        UIView *front = self.front;
        CGRect bounds = self.titleRow.bounds;
        check(front.superview == self.titleRow && fabs(CGRectGetMaxX(front.frame) - CGRectGetMaxX(bounds)) < 0.5 && front.frame.size.width == 48,
              [NSString stringWithFormat:@"the ⋯ in the row's end (%@, the row %@)", NSStringFromCGRect(front.frame), NSStringFromCGRect(bounds)]);
        self.titleRow.layoutMarginsRelativeArrangement = YES;
        self.titleRow.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(0, 0, 0, front.frame.size.width);
        [self.view layoutIfNeeded];
        check(self.addElement.alpha == 1 && !self.addElement.accessibilityElementsHidden && self.banElement.alpha == 0 && self.banElement.accessibilityElementsHidden,
              @"the add button stays on the row, drawn and read; the X is put away");
        check(CGRectGetMaxX(self.addElement.frame) <= CGRectGetMinX(front.frame) + 0.5,
              [NSString stringWithFormat:@"the add button ends where the ⋯ starts (%@, ⋯ %@)", NSStringFromCGRect(self.addElement.frame), NSStringFromCGRect(front.frame)]);
        [self touch:self.addElement];
        after(0.3, ^{
            check(self.addTaps == 1 && !openMenu() && self.frontDowns == 0, @"a finger on the add button runs Spotify's add action, not the menu");
            [self tap:^(CFTimeInterval took) {
                check(took >= 0 && menuShowsAll(quickTitles()), @"a finger on the ⋯ opens the menu");
                check(!menuShowsAny(@[@"Save to Your Library", @"Change Where It's Saved"]), @"the menu has no add item, the add button being on the row");
                finish();
            }];
        });
        return;
    }

    if ([run isEqualToString:@"titleitems"]) {
        // A saved song, Spotify offering its X.
        self.add.selected = YES;
        self.add.accessibilityLabel = @"Added to playlist";
        self.banElement.hidden = NO;
        [self.view layoutIfNeeded];
    }
    if ([run isEqualToString:@"playlist"]) {
        // A song not saved yet, in a playlist, Spotify offering its X.
        sg_inPlaylist = YES;
        self.banElement.hidden = NO;
        [self.view layoutIfNeeded];
    }
    if ([run isEqualToString:@"stalecache"]) {
        // A song not saved yet out of a playlist, Spotify offering its X, the rows stored from a playlist's sheet.
        storePlaylistRows();
        self.banElement.hidden = NO;
        [self.view layoutIfNeeded];
    }
    if ([run hasPrefix:@"notup"]) {
        // Spotify's sheet taken into the mod's window but never up there, its rows never read: no rows stored
        // (`notup`), or a playlist's (`notup-stored`) standing for the add button and the X.
        sg_rowsHeld = sg_rowsNever = YES;
        if (is(@"notup-stored")) storePlaylistRows();
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:@"spotifyglass.redesign.player.menuRows.track"];
        self.banElement.hidden = NO;
        [self.view layoutIfNeeded];
    }

    if ([run isEqualToString:@"timing"]) {
        [self tap:^(CFTimeInterval cold) {
            check(cold >= 0 && cold < 1, @"cold finger-down opens the menu within one second");
            [self.front.contextMenuInteraction dismissMenu];
            waitFor(^BOOL { return !openMenu() && self.sheetGone; }, 3, ^{
                check(!openMenu() && self.sheetGone, @"cold menu and backing sheet dismissed");
                [self tap:^(CFTimeInterval warm) {
                    check(warm >= 0 && warm < 0.25, @"warm finger-down opens the menu within 250 ms");
                    finish();
                }];
            });
        }];
        return;
    }

    [self tap:^(CFTimeInterval took) {
        // The simulator's first menu of a launch is slow (UIKit loading its menu classes); `timing` measures the rest.
        check(took >= 0 && took < 1, [NSString stringWithFormat:@"the menu is on screen %.0f ms after the tap", took * 1000]);
        check(self.front.userInteractionEnabled, @"the mod's ⋯ takes touches");
        check(menuShowsAll(quickTitles()), @"the quick row has Share, Add to Playlist and Add to Queue");
        // The song's actions first, laid out (no More), the player's own after them.
        NSArray<NSString *> *order = shownOrder(self.front);
        NSUInteger rows = [order indexOfObjectPassingTest:^BOOL(NSString *title, NSUInteger index, BOOL *stop) {
            return [title isEqualToString:@"<loading>"] || [spotifyRowTitles() containsObject:title];
        }];
        // The add button named for what its tap does (titleitems' song is saved), where it is sure to be: Spotify's
        // rows held back, or with no Like row (titleitems'). Rows that come at once with Spotify's Like row take it
        // out, as do rows stored with it (stalecache's).
        NSString *add = [run isEqualToString:@"titleitems"] ? @"Change Where It's Saved"
                      : sg_rowsHeld && ![run isEqualToString:@"stalecache"] && ![run isEqualToString:@"notup-stored"] ? @"Save to Your Library" : nil;
        NSMutableArray<NSString *> *want = [quickTitles() mutableCopy];
        if (add) [want addObject:add];
        if (rows != NSNotFound) [want addObjectsFromArray:@[order[rows], @"Speed, Pitch & Reverb", @"Show Animated Artwork"]];
        check(rows != NSNotFound && inOrder(order, want) && ![order containsObject:@"[More]"],
              [NSString stringWithFormat:@"the quick row, the add button, Spotify's rows, then the player's own: %@", [order componentsJoinedByString:@" | "]]);
        if ([run hasPrefix:@"notup"]) {
            [self run:run finish:finish];
            return;
        }
        // Spotify's sheet is asked for once the menu is up, into the mod's window, under the app's.
        waitFor(^BOOL { return self.sheetWindow != nil; }, 2, ^{
            check(sg_spotifyTaps == 1, [NSString stringWithFormat:@"Spotify's ⋯ action ran once, from code (%lu)", (unsigned long)sg_spotifyTaps]);
            check(sg_marked == 1, @"Speed and pitch was told the sheet is the player's");
            check(self.sheetWindow && self.sheetWindow != self.view.window && self.sheetWindow.windowLevel < self.view.window.windowLevel,
                  @"Spotify's sheet is in the mod's window, under the app's");
            check(!self.sheetShown, @"Spotify's sheet is not seen");
            check(openMenu() != nil, @"the menu is still up");
            [self run:run finish:finish];
        });
    }];
}

// `stalecache`'s next menu, a second after the last and its sheet went, on rows stored from a playlist's sheet again;
// `then` once Spotify's sheet is in the mod's window (its view loaded, so rows given then are kept).
- (void)nextStaleMenu:(dispatch_block_t)then {
    waitFor(^BOOL { return self.sheetGone && !openMenu(); }, 3, ^{
        check(self.sheetGone && !openMenu(), @"the last menu and its sheet went");
        after(1, ^{
            storePlaylistRows();
            [self tap:^(CFTimeInterval took) {
                check(took >= 0, @"the next menu opened");
                waitFor(^BOOL { return self.sheetWindow != nil; }, 2, then);
            }];
        });
    });
}

// Waits for the sheet and the menu to go, then reports.
- (void)gone:(NSString *)what selected:(NSString *)selected from:(CFTimeInterval)from finish:(dispatch_block_t)finish {
    waitFor(^BOOL { return self.sheetGone && !openMenu(); }, 6, ^{
        check(self.sheetGone, [NSString stringWithFormat:@"%@: Spotify's sheet went, %.2f s later", what, CACurrentMediaTime() - from]);
        if (selected) check([sg_selected isEqualToString:selected], [NSString stringWithFormat:@"Spotify's %@ was selected (%@)", selected, sg_selected]);
        check(self.front.userInteractionEnabled, @"the mod's ⋯ still takes touches");
        finish();
    });
}

- (void)run:(NSString *)run finish:(dispatch_block_t)finish {
    if ([run hasPrefix:@"notup"]) {
        // Never up, the sheet has no rows to give: the wait for them ends with the request window (3 s from Spotify's
        // ⋯ action), the loading row (`notup`) gives way, and the add button and the X are in the menu, also where
        // stored rows stood for them (`notup-stored`); the X's item fires the X.
        BOOL stored = [run isEqualToString:@"notup-stored"];
        check(stored ? menuShows(@"Hide in this playlist") && !menuShowsAny(@[@"Save to Your Library", @"Don't play this"])
                     : [shownOrder(self.front) containsObject:@"<loading>"],
              stored ? @"the stored Like and Hide stand for the add button and the X at first" : @"the loading row stands for Spotify's rows at first");
        waitFor(^BOOL { return menuShowsAll(@[@"Save to Your Library", @"Don't play this"]) && ![shownOrder(self.front) containsObject:@"<loading>"]; }, 5, ^{
            NSArray<NSString *> *order = shownOrder(self.front);
            CFTimeInterval waited = CACurrentMediaTime() - sg_sheetAskedAt;
            check(![order containsObject:@"<loading>"] && (stored || [order containsObject:@"Spotify's options did not load"]),
                  [NSString stringWithFormat:@"the loading row is gone %.1f s after Spotify's sheet was asked for: %@", waited, [order componentsJoinedByString:@" | "]]);
            check(menuShowsAll(@[@"Save to Your Library", @"Don't play this"]) && waited < 4,
                  [NSString stringWithFormat:@"the add button and the X are in the menu within the request window (%.1f s)", waited]);
            check(sg_spotifyTaps == 1 && !self.sheetWindow, @"Spotify's sheet was asked for once and never came up");
            check(openMenu() != nil && sg_selectionCount == 0, @"the menu is still up, nothing fired");
            pick(@"Don't play this");
            waitFor(^BOOL { return self.banTaps == 1; }, 2, ^{
                check(self.banTaps == 1 && self.addTaps == 0, @"picking the X's item fired Spotify's X");
                finish();
            });
        });
        return;
    }
    if ([run isEqualToString:@"rows"] || [run isEqualToString:@"sort"] || [run isEqualToString:@"wrapped"] || [run isEqualToString:@"popover"]) {
        after(0.3, ^{
            waitFor(^BOOL { return menuShows(@"Go to album"); }, 3, ^{
                check(menuShowsAll(@[@"Go to album", @"Lyrics", @"Sleep timer"]), @"the menu lays out the rest of Spotify's rows, Sleep timer below the sheet's fold too");
                check(!menuShowsAny(@[@"Add to playlist", @"Add to queue"]), @"it leaves out the rows the quick row has");
                if ([run isEqualToString:@"sort"]) check(menuShows(@"Sort"), @"the mod's row in the sheet's header is among them");
                after(0.3, ^{
                    NSString *title = [run isEqualToString:@"sort"] ? @"Sort" : @"Go to album";
                    pick(title);
                    [self gone:[@"picked " stringByAppendingString:title] selected:title from:CACurrentMediaTime() finish:finish];
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"loading"]) {
        // The first menu ever: the system's loading row in place of Spotify's rows until they come, 1.5 s after the sheet.
        after(0.3, ^{
            check(openMenu() && !menuShows(@"Go to album"), @"no rows before the sheet has them");
            waitFor(^BOOL { return menuShows(@"Go to album"); }, 4, ^{
                check(menuShows(@"Go to album"), @"Spotify's rows came into the open menu");
                after(0.3, ^{
                    pick(@"Go to album");
                    [self gone:@"picked Go to album" selected:@"Go to album" from:CACurrentMediaTime() finish:finish];
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"stored"]) {
        // A second menu, its sheet's rows held back: it shows the first one's rows at once, and a pick on them
        // waits for the live ones.
        after(0.6, ^{
            check(!menuShows(@"Go to album"), @"the first menu has no stored rows: it waits for the live ones");
            [self.mockSheet giveRows];
            waitFor(^BOOL { return menuShows(@"Go to album"); }, 3, ^{
                [self.front.contextMenuInteraction dismissMenu];
                waitFor(^BOOL { return self.sheetGone && !openMenu(); }, 3, ^{
                    check(self.sheetGone, @"the first menu closed with no pick took its sheet with it");
                    after(1, ^{
                        [self tap:^(CFTimeInterval took) {
                            check(took >= 0 && took < 0.5, [NSString stringWithFormat:@"the second menu is on screen %.0f ms after the tap", took * 1000]);
                            after(0.15, ^{
                                check(menuShowsAll(@[@"Go to album", @"Sleep timer"]), @"the menu shows the stored rows at once, the live ones not in yet");
                                check(!self.mockSheet.loaded, @"(the live rows are not in)");
                                pick(@"Go to album");
                                after(0.8, ^{
                                    check(!self.sheetGone && ![sg_selected isEqualToString:@"Go to album"], @"the pick waits for the live rows");
                                    [self.mockSheet giveRows];
                                    [self gone:@"picked Go to album from the stored rows" selected:@"Go to album" from:CACurrentMediaTime() finish:finish];
                                });
                            });
                        }];
                    });
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"slowsheet"]) {
        // Add to Queue picked while the sheet, up in the mod's window but its presentation not done, has no rows; the
        // request window ends (3 s) before the rows (3.4 s after the sheet loads) and the presentation's completion
        // (3.5 s late): the pick still waits for its row and fires it once, the sheet never shown.
        pick(@"Add to Queue");
        waitFor(^BOOL { return sg_selectionCount > 0 || self.sheetShown; }, 6, ^{
            check([sg_selected isEqualToString:@"Add to queue"] && !self.sheetShown,
                  [NSString stringWithFormat:@"the pick fired Spotify's Add to queue once its row came (%@), the sheet not shown (%d)", sg_selected, self.sheetShown]);
            check(sg_rowsGivenAt - sg_sheetAskedAt > 3, [NSString stringWithFormat:@"(the rows came %.1f s after the sheet was asked for, past the request window)",
                                                         sg_rowsGivenAt - sg_sheetAskedAt]);
            after(2, ^{
                check(sg_sheetCompletedAt - sg_sheetAskedAt > 3, @"(the sheet's presentation completed after the request window)");
                check(sg_selectionCount == 1 && !self.sheetShown, [NSString stringWithFormat:@"it fired once (%lu), nothing shown after the late completion",
                                                                   (unsigned long)sg_selectionCount]);
                check(self.sheetGone && !openMenu(), @"the sheet and the menu are gone");
                finish();
            });
        });
        return;
    }
    if ([run isEqualToString:@"quick"] || [run isEqualToString:@"quicklate"]) {
        BOOL late = [run isEqualToString:@"quicklate"];
        pick(late ? @"Add to Playlist" : @"Add to Queue");
        CFTimeInterval picked = CACurrentMediaTime();
        after(0.5, ^{ check(!self.sheetShown && !self.sheetGone, @"the sheet stays hidden while the pick waits for its row"); });
        if (!late) {
            [self gone:@"Add to Queue picked before the rows (they came 1.2 s after the sheet)" selected:@"Add to queue" from:picked finish:finish];
            return;
        }
        waitFor(^BOOL { return self.sheetShown; }, 6, ^{
            check(self.sheetShown, [NSString stringWithFormat:@"with no rows in 4 s Spotify's sheet is shown (%.1f s after the pick)", CACurrentMediaTime() - picked]);
            check(!sg_selected, @"nothing was selected");
            finish();
        });
        return;
    }
    if ([run isEqualToString:@"podcast"]) {
        waitFor(^BOOL { return !menuShows(@"Add to Playlist"); }, 4, ^{
            check(!menuShows(@"Add to Playlist"), @"once the rows are in, the quick item this sheet has no row for is gone");
            check(menuShowsAll(@[@"Share", @"Add to Queue"]), @"the other quick items are still there");
            waitFor(^BOOL { return menuShows(@"Go to show"); }, 3, ^{
                check(menuShows(@"Go to show"), @"the menu lays out the podcast's other rows");
                after(0.3, ^{
                    pick(@"Go to show");
                    [self gone:@"picked Go to show" selected:@"Go to show" from:CACurrentMediaTime() finish:finish];
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"close"]) {
        after(0.3, ^{
            [self.front.contextMenuInteraction dismissMenu];
            CFTimeInterval closed = CACurrentMediaTime();
            // The sheet timed alone: the simulator's menu takes a second and more to fade out on its own.
            __block CFTimeInterval took = -1;
            waitFor(^BOOL { if (took < 0 && self.sheetGone) took = CACurrentMediaTime() - closed; return self.sheetGone && !openMenu(); }, 4, ^{
                check(self.sheetGone && took < 1, [NSString stringWithFormat:@"closing with no pick took the hidden sheet away, %.2f s later", took]);
                check(!sg_selected, @"nothing was selected");
                [self tap:^(CFTimeInterval took) {
                    check(took >= 0 && took < 0.5, [NSString stringWithFormat:@"a second tap opens the menu again, %.0f ms after it", took * 1000]);
                    finish();
                }];
            });
        });
        return;
    }
    if ([run isEqualToString:@"subpage"] || [run isEqualToString:@"sleep"]) {
        BOOL sleep = [run isEqualToString:@"sleep"];
        after(0.3, ^{
            waitFor(^BOOL { return !sleep || menuShows(@"Sleep timer"); }, 3, ^{
                pick(sleep ? @"Sleep timer" : @"Share");
                waitFor(^BOOL { return self.sheetShown && [self.sheet.topViewController.title hasSuffix:@"page"]; }, 4, ^{
                    check([sg_selected isEqualToString:sleep ? @"Sleep timer" : @"Share"], [NSString stringWithFormat:@"Spotify's row was tapped (%@)", sg_selected]);
                    check(self.sheetShown, @"the sheet is shown, over the player");
                    check([self.sheet.topViewController.title hasSuffix:@"page"], [NSString stringWithFormat:@"on the page the row pushed (%@)", self.sheet.topViewController.title]);
                    waitFor(^BOOL { return !openMenu(); }, 3, ^{
                        check(!openMenu(), @"the menu is gone");
                        // Closed, the mod's window goes back under the app's.
                        [self.sheet.presentingViewController dismissViewControllerAnimated:NO completion:nil];
                        after(0.6, ^{
                            check(self.view.window.windowLevel > [self.front.window windowLevel] - 1 && !self.sheetWindow, @"the sheet closed, nothing of the mod's stays over the player");
                            UIWindow *host = nil;
                            for (UIWindow *window in self.view.window.windowScene.windows) if ([NSStringFromClass(window.class) isEqualToString:@"SGRSheetWindow"]) host = window;
                            check(host.windowLevel < self.view.window.windowLevel, [NSString stringWithFormat:@"the mod's window is back under the app's (level %.0f)", host.windowLevel]);
                            finish();
                        });
                    });
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"sleeppresent"]) {
        after(0.3, ^{
            waitFor(^BOOL { return menuShows(@"Sleep timer"); }, 3, ^{
                pick(@"Sleep timer");
                waitFor(^BOOL { return self.sleepSheet.viewIfLoaded.window && !self.sleepSheet.isBeingPresented; }, 4, ^{
                    UIViewController *sleepSheet = self.sleepSheet;
                    check(sleepSheet.viewIfLoaded.window == self.view.window && sleepSheet.presentingViewController == self,
                          @"Spotify's sleep timer sheet is up, from the player, in the app's window");
                    UIView *container = sleepSheet.presentationController.containerView;
                    check(container.alpha == 1 && container.userInteractionEnabled, @"and it is seen and takes touches, as Spotify's");
                    waitFor(^BOOL { return !openMenu(); }, 3, ^{
                        check(!openMenu(), @"no menu came up for it (the picked one faded out)");
                        check(sg_spotifyTaps == 1, @"Spotify's ⋯ action ran only once");
                        after(1, ^{
                            check(self.sheetGone, @"the card it came from is gone, unseen");
                            check(sleepSheet.viewIfLoaded.window != nil, @"the sleep timer sheet is still up");
                            finish();
                        });
                    });
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"titleitems"]) {
        // The title row's buttons as items, after the quick row: a saved song's add button named for what its tap does
        // (not Spotify's "Added to playlist", nor a Liked Songs checkmark), drawn as Spotify's circled tick, beside the quick row's
        // playlist picker; and Spotify's X while Spotify shows it; a pick fires the button. Out of a playlist, a saved
        // song's sheet has neither a Like row nor Hide in this playlist, so both stay once Spotify's rows are in.
        waitFor(^BOOL { return menuShows(@"Go to album"); }, 3, ^{
            UIMenuElement *add = sg_elements[@"Change Where It's Saved"], *ban = sg_elements[@"Don't play this"];
            check(menuShows(@"Go to album") && menuShowsAll(@[@"Change Where It's Saved", @"Don't play this"]) && !menuShows(@"Added to playlist")
                  && !menuShows(@"Save to Your Library"), @"with Spotify's rows in, the saved song's add button and the X are in the menu");
            check([add isKindOfClass:UIAction.class] && ((UIAction *)add).state == UIMenuElementStateOff && [((UIAction *)add).image.description containsString:@"checkmark.circle.fill"],
                  [NSString stringWithFormat:@"the saved song's add button: not checked, Spotify's circled tick (%@)", ((UIAction *)add).image]);
            check(menuShows(@"Add to Playlist"), @"the quick row's playlist picker stays its own");
            check([ban isKindOfClass:UIAction.class] && ((UIAction *)ban).state == UIMenuElementStateOff, @"the X is a plain item");
            pick(@"Don't play this");
            check(self.banTaps == 1 && self.addTaps == 0, [NSString stringWithFormat:@"picking the X fired Spotify's X (%lu, add %lu)", (unsigned long)self.banTaps, (unsigned long)self.addTaps]);
            [self gone:@"picked the X" selected:nil from:CACurrentMediaTime() finish:finish];
        });
        return;
    }
    if ([run isEqualToString:@"playlist"]) {
        // In a playlist Spotify's rows have the add button's action (Add to Liked Songs) and the X's (Hide in this
        // playlist): their items go once the rows are in, and the next menu leaves them out at once from the stored
        // rows. Out of the playlist the live rows have no Hide, and the X's item comes back and fires the X.
        check(menuShowsAll(@[@"Save to Your Library", @"Don't play this"]), @"before Spotify's rows are in, both items are in the menu");
        [self.mockSheet giveRows];
        waitFor(^BOOL { return menuShows(@"Hide in this playlist") && !menuShowsAny(@[@"Save to Your Library", @"Don't play this"]); }, 3, ^{
            check(menuShowsAll(@[@"Add to Liked Songs", @"Hide in this playlist"]) && !menuShowsAny(@[@"Save to Your Library", @"Don't play this"]),
                  [NSString stringWithFormat:@"with Spotify's rows in, Spotify's Like and Hide rows stand for the add button and the X: %@",
                   [shownOrder(self.front) componentsJoinedByString:@" | "]]);
            [self.front.contextMenuInteraction dismissMenu];
            waitFor(^BOOL { return self.sheetGone && !openMenu(); }, 3, ^{
                check(self.sheetGone, @"the first menu closed with no pick took its sheet with it");
                after(1, ^{
                    [self tap:^(CFTimeInterval took) {
                        check(took >= 0, @"the second menu opened");
                        after(0.15, ^{
                            check(!self.mockSheet.loaded && menuShowsAll(@[@"Add to Liked Songs", @"Hide in this playlist"])
                                  && !menuShowsAny(@[@"Save to Your Library", @"Don't play this"]),
                                  @"before its live rows, the stored rows' Like and Hide stand for the add button and the X");
                            sg_inPlaylist = NO;
                            [self.mockSheet giveRows];
                            // The menu's views follow the update with an animation, the old row's label going with it.
                            waitFor(^BOOL { return menuShows(@"Don't play this") && !menuShows(@"Hide in this playlist"); }, 3, ^{
                                check(menuShows(@"Don't play this") && !menuShows(@"Hide in this playlist"),
                                      @"out of the playlist the live rows have no Hide: the X's item is back");
                                check(menuShows(@"Add to Liked Songs") && !menuShows(@"Save to Your Library"), @"Spotify's Like row still stands for the add button");
                                check(inOrder(shownOrder(self.front), @[@"Add to Queue", @"Don't play this", @"Add to Liked Songs"]),
                                      [NSString stringWithFormat:@"the X's item is back after the quick row: %@", [shownOrder(self.front) componentsJoinedByString:@" | "]]);
                                pick(@"Don't play this");
                                check(self.banTaps == 1 && self.addTaps == 0, [NSString stringWithFormat:@"picking it fired Spotify's X (%lu, add %lu)",
                                                                               (unsigned long)self.banTaps, (unsigned long)self.addTaps]);
                                [self gone:@"picked the X" selected:nil from:CACurrentMediaTime() finish:finish];
                            });
                        });
                    }];
                });
            });
        });
        return;
    }
    if ([run isEqualToString:@"stalecache"]) {
        // Rows stored from a playlist's sheet, the song now out of one: the stored Hide in this playlist stands for the
        // X until the live rows are in, so the menu opens as the last one did. Picked, it is any stale stored row:
        // Spotify's sheet is shown once the live rows come without Hide, or once they never come, and the X is never
        // fired for it; with the menu up and no rows coming, the X's item comes back; and a live Hide grayed out
        // leaves the X's item in.
        check(menuShowsAll(@[@"Add to Liked Songs", @"Hide in this playlist"]) && !menuShowsAny(@[@"Save to Your Library", @"Don't play this"]),
              @"before the live rows, the stored Like and Hide rows stand for the add button and the X");
        pick(@"Hide in this playlist");
        after(0.3, ^{
            check(self.banTaps == 0 && sg_selectionCount == 0, @"the stored Hide waits for the live rows");
            [self.mockSheet giveRows];
            waitFor(^BOOL { return self.sheetShown; }, 3, ^{
                check(self.sheetShown && self.banTaps == 0 && self.addTaps == 0 && sg_selectionCount == 0,
                      [NSString stringWithFormat:@"the live rows have no Hide: Spotify's sheet is shown, neither the X (%lu) nor the add button (%lu) nor a row (%lu) fired",
                       (unsigned long)self.banTaps, (unsigned long)self.addTaps, (unsigned long)sg_selectionCount]);
                [self.sheet.presentingViewController dismissViewControllerAnimated:NO completion:nil];
                [self nextStaleMenu:^{
                    pick(@"Hide in this playlist");
                    waitFor(^BOOL { return self.sheetShown; }, 6, ^{
                        check(self.sheetShown && self.banTaps == 0 && self.addTaps == 0 && sg_selectionCount == 0,
                              [NSString stringWithFormat:@"no live rows in time: Spotify's sheet is shown, neither the X (%lu) nor the add button (%lu) fired",
                               (unsigned long)self.banTaps, (unsigned long)self.addTaps]);
                        [self.sheet.presentingViewController dismissViewControllerAnimated:NO completion:nil];
                        [self nextStaleMenu:^{
                            check(!menuShows(@"Don't play this"), @"the next menu opens as the last did, the stored Hide standing for the X");
                            waitFor(^BOOL { return menuShows(@"Don't play this"); }, 6, ^{
                                check(menuShows(@"Don't play this") && inOrder(shownOrder(self.front), @[@"Add to Queue", @"Don't play this", @"Add to Liked Songs"]),
                                      [NSString stringWithFormat:@"the rows given up on, the X's item is back after the quick row: %@",
                                       [shownOrder(self.front) componentsJoinedByString:@" | "]]);
                                pick(@"Don't play this");
                                check(self.banTaps == 1, @"picking it fired Spotify's X");
                                sg_inPlaylist = sg_hideGrayed = YES;
                                [self nextStaleMenu:^{
                                    [self.mockSheet giveRows];
                                    // The menu's views follow the update with an animation, the stored rows' labels going with it.
                                    waitFor(^BOOL { return menuShowsAll(@[@"Don't play this", @"Hide in this playlist"]); }, 3, ^{
                                        check(menuShowsAll(@[@"Don't play this", @"Hide in this playlist"]) && !menuShows(@"Save to Your Library"),
                                              [NSString stringWithFormat:@"a live Hide grayed out leaves the X's item in; the enabled Like row still stands for the add button: %@",
                                               [shownOrder(self.front) componentsJoinedByString:@" | "]]);
                                        pick(@"Don't play this");
                                        check(self.banTaps == 2 && sg_selectionCount == 0, @"picking it fired Spotify's X, no row of Spotify's");
                                        [self gone:@"picked the X" selected:nil from:CACurrentMediaTime() finish:finish];
                                    });
                                }];
                            });
                        }];
                    });
                }];
            });
        });
        return;
    }
    if ([run isEqualToString:@"animated"]) {
        pick(@"Show Animated Artwork");
        check(sg_animated, @"Show Animated Artwork switched it on");
        [self gone:@"picked Show Animated Artwork" selected:nil from:CACurrentMediaTime() finish:finish];
        return;
    }
    if ([run isEqualToString:@"effects"]) {
        check(menuShowsAll(@[@"Audio effects", @"2 effects"]), @"Audio effects is in the menu with the effects' summary under it");
        pick(@"Audio effects");
        check(sg_effectsSheets == 1 && sg_effectsFrom == self.front, @"Audio effects asks for the page's sheet once, from the player's ⋯");
        [self gone:@"picked Audio effects" selected:nil from:CACurrentMediaTime() finish:finish];
        return;
    }
    check(NO,[NSString stringWithFormat:@"no scenario %@", run]);
    finish();
}

@end

@interface SGHarnessApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation SGHarnessApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    if (is(@"slowsheet")) {
        // Over ContextMenu.x's own hook (installed before launch): Spotify's sheet presented in the mod's window goes up at
        // once, attached and with its presenting controller, but its presentation's completion comes 3.5 s late, after
        // the request window.
        Method present = class_getInstanceMethod(UIViewController.class, @selector(presentViewController:animated:completion:));
        __block IMP hooked = NULL;
        hooked = method_setImplementation(present, imp_implementationWithBlock(^(UIViewController *from, UIViewController *presented, BOOL animated, void (^completion)(void)) {
            void (^done)(void) = completion;
            if (completion && [NSStringFromClass(from.viewIfLoaded.window.class) isEqualToString:@"SGRSheetWindow"] && presented == sg_player.sheet) {
                done = ^{
                    after(3.5, ^{
                        sg_sheetCompletedAt = CACurrentMediaTime();
                        NSLog(@"[harness] the sheet's presentation completes, %.1f s after it was asked for", sg_sheetCompletedAt - sg_sheetAskedAt);
                        completion();
                    });
                };
            }
            ((void (*)(id, SEL, id, BOOL, id))hooked)(from, @selector(presentViewController:animated:completion:), presented, animated, done);
        }));
    }
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    sg_player = [SGHarnessPlayer new];
    self.window.rootViewController = sg_player;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

// Before every %ctor, so the redesign's gate reads on; and no rows stored from an earlier run.
__attribute__((constructor(101))) static void sgr_harnessDefaults(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setBool:YES forKey:@"spotifyglass.redesign"];
    for (NSString *key in defaults.dictionaryRepresentation.allKeys) {
        if ([key hasPrefix:@"spotifyglass.redesign.player.menuRows"]) [defaults removeObjectForKey:key];
    }
    sg_elements = [NSMutableDictionary dictionary];
    Method make = class_getClassMethod(UIAction.class, @selector(actionWithTitle:image:identifier:handler:));
    sg_actionWithTitle = method_setImplementation(make, (IMP)recordAction);
    Method menu = class_getClassMethod(UIMenu.class, @selector(menuWithTitle:image:identifier:options:children:));
    sg_menuWithTitle = method_setImplementation(menu, (IMP)recordMenu);
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SGHarnessApp.class));
    }
}
