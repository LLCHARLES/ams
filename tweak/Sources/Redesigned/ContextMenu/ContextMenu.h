// The redesign's ⋯ opens the system menu instead of Spotify's sheet, the way the Music app's does: the
// player's ⋯ and the ⋯ every redesigned entity page pins to its corner (playlist, album, artist and the
// pages that share their templates). Always on in the redesign; no setting.
//
//     ContextMenu.x   the takeover: Spotify's sheet presented unseen, its rows read into a UIMenu shown from
//                     the ⋯, a pick fired on the sheet, and the sheet itself as the fallback
//     FireControl.m   a control of Spotify's fired from code as a tap would, and which tap events it has actions for
//
// Spotify's rows come from Swift item factories with nothing to read them from but the cells they fill, so
// the sheet is still Spotify's and still made, unseen.
//
// The player's ⋯ is a pull-down button of the mod's, beside the title as the Music app has it (PlayerMenu.m places
// it), which opens the menu on touch down, as UIKit opens any button's menu, so it waits on nothing of Spotify's.
// Share, Add to playlist and Add to queue (Spotify's items 9, 19 and 11, or found by title) are a row of three at
// its top, as the last sheet of this kind had them, then the player's lead items (its title row's own buttons, but
// those whose action Spotify's rows offer), then the rest of Spotify's rows, laid out in the menu itself: the last complete set stored, at once, or the
// system's loading row the first time, put right in place as the live rows come. The player's own items follow.
// Once the menu is up, Spotify's ⋯ action is run from code; its sheet is presented in a window of the mod's under
// the app's (the menu, a presentation of UIKit's from the player, leaves no room for another there), read, and used
// to run a pick. A pick made before the live rows are in waits up to 4 s for them, else the sheet is shown.
//
// A page's ⋯ is the other way round: its tap opens Spotify's sheet, presented without animation in a container
// at alpha 0 from its first frame, and the menu opens over it from an invisible anchor button inside the ⋯, its
// rows a deferred element that waits for them.
//
// A pick closes the menu and then selects that row on the sheet, so what it does stays Spotify's; a pick that
// leaves the sheet up (a row opening a page of its own) shows the sheet. Rows the mod puts in the sheet's
// header or footer (Sort and Mix on a playlist, Edit info for a local file) are read the same way and fired the
// same way. Closing the menu without a pick dismisses the sheet.
//
// A page's anchor takes touches only while its menu is up, so every other tap reaches the ⋯ under it, and the
// menu is opened with -[UIControl performPrimaryAction] (iOS 17.4), else UIContextMenuInteraction's private
// _presentMenuAtLocation:, each checked with respondsToSelector:. When neither is there, or the menu does not
// come up, Spotify's sheet shows at once instead, with nothing waited out.
//
// Threading: main thread only.
#import <UIKit/UIKit.h>

// Items of the mod's own for the menu `button` opens, built afresh every time it opens. A lead item that does what
// a row of Spotify's does has that row's identifier (its accessibility identifier, Spotify's item number) as its
// UIAction identifier: the menu leaves it out while it shows that row enabled, the stored rows' until the live ones
// are read, and puts it back if the live rows lack it, have it grayed out or do not come. A pick of the stored row
// is that of any stored row: the live row of its title, or Spotify's sheet; never this item.
typedef NSArray<UIMenuElement *> *(^SGRMenuItems)(void);
// What the sheet the ⋯ opens now is for ("track", "episode"...). The menu remembers which quick items the last
// sheet of each kind had, so the quick row is right before this sheet has its rows.
typedef NSString *(^SGRMenuKind)(void);

// The player's ⋯: a pull-down button of the mod's, one kept in `host`, that opens the system menu itself: the quick
// row, `lead`, Spotify's rows, then `items`. `spotify` is Spotify's own ⋯ (a UIControl, shown or not), whose action
// is run from code once the menu is up so its sheet can be read. The caller places the button and draws in it. Called
// on every layout of the ⋯'s place, and whenever Spotify's ⋯ is laid out: it replaces `spotify`, `lead`, `items` and
// `kind`, which may be nil. The pinned ⋯ of the entity pages needs no call: the Kit records its taps
// (SGRPinnedMoreRecentButton).
UIButton *SGRSystemMenuButtonIn(UIView *host, UIView *spotify, SGRMenuItems lead, SGRMenuItems items, SGRMenuKind kind);

// A target of the mod's on a control of Spotify's that only watches its touches (PlayerHeader.x's press on the header
// buttons, which listens for a touch up inside), so is no action of the control's.
@protocol SGRControlWatcher
@end
// The events `control` has handlers for, SGRControlWatcher targets left out: which of them a tap fires.
UIControlEvents SGRControlActionEvents(UIControl *control);
// Fires a control as a tap on it would: its primary action's handlers if it has any, else its touch up inside ones,
// else its accessibility activation. What it did, for the log.
NSString *SGRFireControl(UIControl *control);
