// The pinned ⋯'s claim (Kit/SGRActionRow.m, SGRPinnedMoreRecentButton and SGRPinnedMoreRecentPage): what tells the system
// menu (Redesigned/ContextMenu/ContextMenu.x) and the playlist's rows on Spotify's sheet (Redesigned/Playlist/PlaylistMenu.x)
// that the sheet coming up is the page's. The real SGRPinnedMore over a page holding a stand-in for Spotify's ⋯, in a Mac
// Catalyst window: a press let go off the button claims nothing, and a tap claims the button and its page before Spotify's
// ⋯ runs, so a sheet Spotify presents from that call finds the claim. Last, the ⋯ drawn in the header info beside the
// cover: its tap still claims the playlist's page, so once the system menu has taken the sheet over (the real
// SGRPinnedMoreTaken, which ContextMenu.x's takeOver calls) the real PlaylistMenu.x puts the page's Sort and Mix rows on
// it. pinned-check.sh builds and runs it; exits nonzero on the first failure (../harness-fail.h).
#import <UIKit/UIKit.h>
#import "../harness-fail.h"
#import "Core/SGCore.h"
#import "Redesigned/Kit/SGRActionRow.h"
#import "Redesigned/Kit/SGRHeaderInfo.h"
#import "Redesigned/Playlist/Playlist.h"

// Spotify's context menu sheet as PlaylistMenu.x finds it: its class, a table as its view.
@interface _TtC24ContextMenu_InternalImpl25ContextMenuViewController : UIViewController
@end
@implementation _TtC24ContextMenu_InternalImpl25ContextMenuViewController
- (void)loadView {
    self.view = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) style:UITableViewStylePlain];
}
@end

// PlaylistMenu.x as the tweak builds it (pinned-check.sh runs Logos on it), the redesign on.
#define SGRedesignedUI() YES
#include "PlaylistMenu.gen.m"
#undef SGRedesignedUI

#pragma mark - what the check does not build

// PlaylistRows.x: the curation row's page; this check hands PlaylistMenu.x none through a cell.
UIView *SGRPlaylistPageOf(UIView *view) { return nil; }

// The accent hook (SGRAccent.x): Spotify's green.
UIColor *SGRAccentColor(void) { return nil; }
BOOL SGMotionAppleMusicOn(void) { return YES; }
// Shared/AlbumQueue: the album's ⋯ records its album; no album here.
void SGAlbumQueueMarkSource(UIView *view) {}
// Shared/Player/SGLastTrack.m: no card here.
UIImage *SGPlaceholderArtwork(UIColor *tint) { return nil; }

#pragma mark - the check

// Spotify's ⋯: how often it ran, and the claim a sheet it presented from that call would have read. With sg_presents it
// presents its context menu sheet, which the system menu takes over as it comes (SGRPinnedMoreTaken).
static NSUInteger sg_spotifyTaps;
static UIView *sg_claimedButton, *sg_claimedPage;
static BOOL sg_presents;
static UIViewController *sg_sheet, *sg_root;

@interface PinnedCheckSpotify : NSObject
@end
@implementation PinnedCheckSpotify
+ (void)more {
    sg_spotifyTaps++;
    sg_claimedButton = SGRPinnedMoreRecentButton();
    sg_claimedPage = SGRPinnedMoreRecentPage();
    if (!sg_presents) return;
    sg_sheet = [_TtC24ContextMenu_InternalImpl25ContextMenuViewController new];
    SGRPinnedMoreTaken();
    [sg_root presentViewController:sg_sheet animated:NO completion:nil];
}
@end

// The words on the rows PlaylistMenu.x put in the sheet's table header, in order.
static NSArray<NSString *> *sheetRows(UIViewController *sheet) {
    [sheet.view setNeedsLayout];
    [sheet.view layoutIfNeeded];
    UIView *header = ((UITableView *)sheet.view).tableHeaderView;
    NSMutableArray<NSString *> *words = [NSMutableArray array];
    for (UIView *row in header.subviews) {
        if (!row.hidden && row.accessibilityLabel) [words addObject:row.accessibilityLabel];
    }
    return words;
}

static void runCheck(UIWindow *window) {
    sg_root = window.rootViewController;
    UIView *page = [[UIView alloc] initWithFrame:window.bounds];
    [window.rootViewController.view addSubview:page];
    UIButton *spotify = [UIButton systemButtonWithImage:[UIImage systemImageNamed:@"ellipsis"] target:PinnedCheckSpotify.class action:@selector(more)];
    spotify.frame = CGRectMake(300, 400, 44, 44);
    [page addSubview:spotify];
    static char key;
    SGRMirrorButton *more = SGRPinnedMore(page, &key, spotify);
    if (!more.window || more.hidden) HARNESS_FAIL(@"the pinned ⋯ is not on the page");

    // A finger pressed on the ⋯, dragged off it and lifted: UIKit sends the touch down, then a touch up outside.
    [more sendActionsForControlEvents:UIControlEventTouchDown];
    [more sendActionsForControlEvents:UIControlEventTouchUpOutside];
    if (sg_spotifyTaps || SGRPinnedMoreRecentButton() || SGRPinnedMoreRecentPage()) {
        HARNESS_FAIL(@"a press let go off the pinned ⋯ claims the next sheet: Spotify's ⋯ ran %lu times, claim button %@, page %@",
                     (unsigned long)sg_spotifyTaps, SGRPinnedMoreRecentButton(), SGRPinnedMoreRecentPage());
    }
    NSLog(@"[harness] PASS a press let go off the pinned ⋯ claims nothing");

    // A tap.
    [more sendActionsForControlEvents:UIControlEventTouchDown];
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (sg_spotifyTaps != 1 || sg_claimedButton != more || sg_claimedPage != page) {
        HARNESS_FAIL(@"a tap on the pinned ⋯: Spotify's ⋯ ran %lu times and read the claim of button %@ and page %@",
                     (unsigned long)sg_spotifyTaps, sg_claimedButton, sg_claimedPage);
    }
    NSLog(@"[harness] PASS a tap on the pinned ⋯ claims it and its page before Spotify's ⋯ runs");

    // The playlist's page: Spotify's Sort in its header (SGRPlaylistTakeSort) and the curation row with Mix on it. In a
    // regular width with the cover beside the title, SGRHeaderInfo draws the ⋯ in itself (SGRHeaderInfo.m), and the
    // page lays out again without taking it back.
    UIButton *sort = [UIButton buttonWithType:UIButtonTypeSystem];
    sort.accessibilityLabel = @"Sort";
    [page addSubview:sort];
    SGRPlaylistTakeSort(page, sort);
    UIView *curation = [[UIView alloc] initWithFrame:CGRectMake(0, 500, 390, 44)];
    curation.accessibilityIdentifier = SGRPlaylistCurationIdentifier;
    UIButton *mix = [UIButton buttonWithType:UIButtonTypeSystem];
    mix.accessibilityIdentifier = @"ListPlatform.ToolbarActions.MixButton";
    mix.accessibilityLabel = @"Mix";
    [curation addSubview:mix];
    [page addSubview:curation];
    SGRHeaderInfo *info = [[SGRHeaderInfo alloc] initWithFrame:CGRectMake(0, 100, 390, 300)];
    [page addSubview:info];
    [info addSubview:more];
    if (SGRPinnedMore(page, &key, spotify) != more || more.superview != info) HARNESS_FAIL(@"the pinned ⋯ left the header info");
    sg_presents = YES;
    [more sendActionsForControlEvents:UIControlEventTouchDown];
    [more sendActionsForControlEvents:UIControlEventTouchUpInside];
    if (sg_spotifyTaps != 2 || !sg_sheet) {
        HARNESS_FAIL(@"a tap on the ⋯ in the header info: Spotify's ⋯ ran %lu times, sheet %@", (unsigned long)sg_spotifyTaps, sg_sheet);
    }
    if (SGRPinnedMoreRecentButton()) HARNESS_FAIL(@"the sheet taken over, the pinned ⋯ still claims the next one");
    NSArray<NSString *> *rows = sheetRows(sg_sheet);
    if (![rows isEqualToArray:(@[@"Sort", @"Mix"])]) {
        HARNESS_FAIL(@"the ⋯ in the header info: the taken sheet has rows %@, wanted the playlist's Sort and Mix", rows);
    }
    NSLog(@"[harness] PASS the ⋯ in the header info claims the playlist's page, whose Sort and Mix rows are on the taken sheet");
    printf("[harness] PASS pinned ⋯ claim\n");
    fflush(stdout);
    exit(0);
}

@interface PinnedCheckApp : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation PinnedCheckApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, 390, 844)];
    self.window.rootViewController = [UIViewController new];
    // Once SGRHarnessScene has put the window in its scene and made it key.
    __block id key = [NSNotificationCenter.defaultCenter addObserverForName:UIWindowDidBecomeKeyNotification
        object:self.window queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [NSNotificationCenter.defaultCenter removeObserver:key];
        runCheck(self.window);
    }];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ HARNESS_FAIL(@"timed out"); });
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(PinnedCheckApp.class));
    }
}
