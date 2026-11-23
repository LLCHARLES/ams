// The redesign's now playing bar: the glass card it becomes (NowPlayingBar.x), on an iPad of regular width a capsule
// with shuffle, repeat, lyrics and queue buttons (no switch; Redesigned/Player/Player.h's SGRPlayerIPadRegular), Spotify's device button
// on that card hidden on request (BarConnect.x), glass behind the bar's and the tab bar's stand-ins while
// the player opens and closes (BarTransition.x), and the bar's rows in Mod Settings
// (NowPlayingBarSettings.m). The redesign keeps its own copy of the hide switch and its own key; the
// native look's lives in Native/NowPlayingBar/.
#import <UIKit/UIKit.h>

@class SGModRow;

// The device button on the card, hidden until switched back on (BarConnect.x), as the Music app's mini player has none.
// The minimized row's own choice (SGRKeyBarInlineConnect) wins there.
#define SGRHideBarConnect @"spotifyglass.redesign.hide.barConnect"
// Whether the card is in the minimized tab bar's row with its device button kept there (NowPlayingBar.x tuckExtras).
BOOL SGRBarRowKeepsConnect(void);
// The device button hidden while SGRHideBarConnect is on and the row does not keep it (SGRBarRowKeepsConnect), and
// shown again otherwise, only where this hid it (BarConnect.x). Run on every layout of Spotify's bar and by tuckExtras
// as the card goes into the row or leaves it, so both read the same state in one pass.
void SGRBarPlaceConnect(UIView *bar);
// Whether `view` stands in one of Spotify's sheets (the DJ request one has the bar's class at its top), where the bar is
// Spotify's own and the redesign leaves it as it is (NowPlayingBar.x).
BOOL SGRBarInSheet(UIView *view);
// Spotify's own flag for the card's add button. Without an override (the Mini player section's row stores one either
// way, the All flags page may too) the redesign answers it off at launch (NowPlayingBarSettings.m), so the card ends
// in play and Next as the Music app's does; a reset to stock shows it.
#define SGRBarAddFlag @"ios-feature-nowplayingbar.add_button"
// Whether the add button is left out: the override's answer where there is one, else hidden unless reset to stock.
BOOL SGRBarAddHidden(void);
// The device button kept on the card in the minimized tab bar's row (NowPlayingBar.x), off unless set: by
// default the row has the cover, the title and play alone, as the Music app's. Read each time the card goes
// into the row, so a change shows the next time the bar minimizes.
#define SGRKeyBarInlineConnect @"spotifyglass.redesign.nowPlayingBar.inlineConnect"
// The artists on a second line under the title in that row, off unless set, and only when both lines fit the
// bar's height (NowPlayingBar.x SGRBarText). A change lays the bar out again at once.
#define SGRKeyBarInlineArtist @"spotifyglass.redesign.inlinePlayer.artist"
// A Next button after play on the full card, as the Music app's mini player has, on until switched off
// (NowPlayingBar.x SGRBarNextButton). The minimized row keeps play alone. A change lays the bar out again at once.
#define SGRKeyBarNextButton @"spotifyglass.redesign.nowPlayingBar.nextButton"
// The cover's shape on the card, Circle unless set; the player's open and close morph from it. A change lays the
// bar out again at once.
typedef NS_ENUM(NSInteger, SGRBarArtworkShape) {
    SGRBarArtworkShapeRoundedSquare = 0,
    SGRBarArtworkShapeCircle = 1,
};
#define SGRKeyBarArtworkShape @"spotifyglass.redesign.nowPlayingBar.artworkShape"

// The bar's rows, the Mini player section of the Player page (Redesigned/Player/PlayerSettings.m): Apple
// Music style (the tab bar's Minimize on scroll, Redesigned/Navbar/Navbar.h), the device button in that
// row, the artists under the title in that row, the Next button, the artwork's shape, and the device button
// hidden on the full card.
NSArray<SGModRow *> *SGRNowPlayingBarRows(void);

// The bar's glass card in `host`'s coordinates, with its corner radius; CGRectNull before the bar has
// been styled or while it is out of a window (NowPlayingBar.x). The bar keeps its geometry while
// Spotify hides it for the player's open and close.
CGRect SGRNowPlayingCardFrameIn(UIView *host, CGFloat *radius);
// The artwork on that card in `host`'s coordinates, with its corner radius; CGRectNull when none was found.
CGRect SGRNowPlayingArtworkFrameIn(UIView *host, CGFloat *radius);
// Lays the bar out again at once, into the minimized tab bar's slot or back above the bar
// (Navbar.h's SGRTabBarInlineSlot); TabBar.x calls it inside its own animation.
void SGRNowPlayingBarFollowTabBar(void);
