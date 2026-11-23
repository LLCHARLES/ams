#import "tests.h"
#import "../../tweak/Sources/Redesigned/Player/PlayerMenu.m"

// ContextMenu.x's button beside the title, kept with the items it was handed; the title row's buttons are not under test.
// The button stands in the player's window, as Spotify's ⋯ (the test source) does. It is not put in the row: UIKit
// would take the source's stand-in window for a real one as it adds it.
@interface TestMenuButton : UIButton
@property (nonatomic, weak) UIView *spotify;
@end
@implementation TestMenuButton
- (UIWindow *)window { return self.spotify.window; }
@end
static SGRMenuItems menuItems;
static SGRMenuKind menuKind;
UIButton *SGRSystemMenuButtonIn(UIView *host, UIView *spotify, SGRMenuItems lead, SGRMenuItems items, SGRMenuKind kind) {
    static TestMenuButton *button;
    if (!button) button = [TestMenuButton buttonWithType:UIButtonTypeSystem];
    button.spotify = spotify;
    menuItems = [items copy]; menuKind = [kind copy];
    return button;
}
NSString *SGRFireControl(UIControl *control) { return @"not fired"; }
UIView *SGRFindByIdentifier(UIView *root, NSString *identifier, const void *key) { return nil; }
UIColor *SGRPrimary(void) { return UIColor.labelColor; }
BOOL SGRStarAddOn(void) { return NO; }
UIAction *SGRLyricsSearchAction(NSString *track) {
    return [UIAction actionWithTitle:@"Search Lyrics" image:nil identifier:nil handler:^(UIAction *action) {}];
}
// LyricsStyle.m and PlayerQueue.m: the lyrics style submenu and Playing Next, whose own items are not under test.
UIMenu *SGRLyricsStyleMenu(NSString *title) { return [UIMenu menuWithTitle:title children:@[]]; }
void SGRPlayerShowQueue(UIView *from) {}
// Audio effects owns its settings sheet; this lane exercises the lyrics menu.
void SGDSPShowSettingsSheet(UIView *from) {}
NSString *SGDSPSummary(void) { return @"Off"; }
// ShareCards.m and ArtistBlock.m: the song card and the song block, offered for a song, are not under test.
void SGRShareSongCard(UIView *source) {}
BOOL SGSongBlocked(NSString *uri) { return NO; }
void SGSetSongBlocked(NSString *uri, NSString *title, NSString *artist, BOOL blocked) {}
// Source selection is covered by lyrics-sources' state check; keep the real menu entry in this integration check.
BOOL SGLyricsEnabled(void) { return YES; }
void SGLyricsAskOffers(NSString *track) {}
NSDictionary *SGLyricsOffersSoFar(NSString *track, NSArray **asking) { if (asking) *asking = @[]; return @{}; }
NSString *SGLyricsChosenSource(NSString *track) { return nil; }
void SGLyricsChooseSource(NSString *track, NSString *key) {}
void SGLyricsChooseAutomatic(NSString *track) {}
NSArray *SGLyricsOrder(void) { return @[]; }
SGLyricsProvider *SGLyricsProviderFor(NSString *key) { return nil; }
NSNotificationName const SGLyricsOffersDidChangeNotification = @"harness.offers";
void SGPresentPopover(UIViewController *panel, UIView *from) {}
SGRPlayerBackgroundKind SGRPlayerBackground(void) { return SGRPlayerBackgroundFluid; }
void SGRPlayerMenuSetBackground(SGRPlayerBackgroundKind kind) {}

static void tap(UIAction *action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button addAction:action forControlEvents:UIControlEventTouchUpInside];
    [button sendActionsForControlEvents:UIControlEventTouchUpInside];
}
void SGTestRedesignMenu(void) {
    UIView *source = SGTestSourceView();
    SGRPlayerMenuWatch(source);
    // The title row the ⋯ is put in, as PlayerLyrics.x hands it over, before the menu's items are asked for.
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
    UIView *title = [UIView new];
    [row addSubview:title];
    SGRPlayerMenuInTitleRow(title);
    SGTestAssert(menuItems != nil, @"redesign ⋯ is put in the title row with the player's items");
    SGTestPiPState(NO, NO, NO);
    NSArray *items = menuItems();
    // Sound, Audio effects, the song's card and block, PiP, Playing Next, Search Lyrics, Lyrics Style, then the two backgrounds the
    // player is not showing.
    SGTestAssert(items.count == 11 && [((UIAction *)items.lastObject).title isEqual:@"Lyrics Source"] && [((UIAction *)items[0]).title isEqual:@"Speed, Pitch & Reverb"]
        && [((UIAction *)items[1]).title isEqual:@"Audio effects"]
        && [((UIAction *)items[2]).title isEqual:@"Share Song Card"] && [((UIAction *)items[5]).title isEqual:@"Playing Next"]
        && [((UIAction *)items[6]).title isEqual:@"Search Lyrics"] && [items[7] isKindOfClass:UIMenu.class]
        && [menuKind() isEqual:@"track"],
        @"redesign preserves sound, queue, lyric search, lyric style and alternate artwork items");
    UIAction *pip = items[4];
    SGTestAssert([pip.title isEqual:@"Open lyrics Picture in Picture"] && !(pip.attributes & UIMenuElementAttributesDisabled),
        @"redesign exposes enabled action even when launch flag is off");
    NSUInteger alerts = SGTestDisabledAlerts();
    tap(pip);
    SGTestAssert(SGTestDisabledAlerts() == alerts + 1, @"redesign disabled entry explains activation");
    SGTestPiPState(YES, NO, NO);
    tap(menuItems()[4]);
    SGTestAssert(SGLyricsPiPStarting(), @"redesign open invokes user-started shared engine");
    pip = menuItems()[4];
    SGTestAssert([pip.title isEqual:@"Close lyrics Picture in Picture"], @"redesign rebuild labels pending start as close");
    tap(pip);
    SGTestAssert(!SGLyricsPiPStarting(), @"redesign close cancels starting session");
    SGTestPiPState(YES, YES, NO);
    SGTestAssert([((UIAction *)menuItems()[4]).title isEqual:@"Close lyrics Picture in Picture"], @"redesign active entry is close");
    SGTestSetTrack(@"spotify:episode:episode", nil);
    SGTestAssert(menuItems().count == 6 && [menuKind() isEqual:@"episode"], @"podcast keeps PiP and Playing Next, and still excludes lyric search and style");
    SGTestPiPState(NO, NO, NO);
}
