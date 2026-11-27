// Player redesign: Playing Next, the tracks the player has to come (SPTPlayerState.future), as a dark sheet opened
// from the player's ⋯ menu (PlayerMenu.m), the footer's queue glyph where Spotify's row has no queue button
// (PlayerFooter.x) and the iPad mini player's queue button (NowPlayingBar.x), and as the iPad two column player's side
// column (PlayerLyrics.x). Spotify's own Queue button in the footer stays Spotify's, unless the Music app's queue style is
// picked (SGRKeyPlayerQueueStyle): then the footer's glyph opens the Music app's page in the player.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// The queue sheet's view after placement, nil as it leaves (never the embedded list).
extern NSNotificationName const SGRQueueSheetPlacedNotification;

// Opens the sheet over what `from` (the ⋯, a glyph) is in, once a menu it was picked from has gone; nothing while it is
// open already.
void SGRPlayerShowQueue(UIView *from);
// The same list for the two column player's side column (PlayerLyrics.x): no Close and no sheet, a pick skips ahead
// and the list stays. Added as a child of the player's controller by its caller.
UIViewController *SGRPlayerQueueList(void);
// The Music app's queue as a page in the player (SGRKeyPlayerQueueStyle, PlayerLyrics.x puts it under the cover's
// thumbnail): shuffle, repeat, sleep timer and AutoMix toggles over the list drawn its way, its songs to come moved by
// their grips. A pick skips ahead and the page stays.
// Added as a child of the player's controller by its caller.
UIViewController *SGRPlayerQueuePage(void);
// The page's room over its toggles, where the caller puts the player's thumbnail and title, and what is told how far the
// list has moved from where it rests (positive as it scrolls up) whenever it moves, so they ride with the list as the
// Music app's do. Called again whenever the room changes; the list goes back to rest for a new room.
void SGRPlayerQueuePageConfigure(UIViewController *page, CGFloat headHeight, void (^scrolled)(CGFloat shift));
