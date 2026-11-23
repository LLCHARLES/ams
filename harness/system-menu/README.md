# System menu harness

`Redesigned/ContextMenu/ContextMenu.x` and `Redesigned/Player/PlayerMenu.m` run for real against a mock of
Spotify's player ⋯ and its context menu sheet (`ContextMenu_InternalImpl.ContextMenuViewController` under its
class name, inside a navigation controller): 15 rows, each an Encore-style ListRow control whose identifier is
Spotify's item number and which acts on touch up inside, no `didSelect`, Sleep timer last and below the sheet's
fold, as on the phone. Speed, pitch, reverb and Animated artwork are stubs that log. Playing Next presents
a UIKit navigation panel from the real player-menu handler.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/SystemMenuHarness.app
    xcrun simctl launch --console-pty <udid> com.retrine.systemmenuharness <scenario>

The header row is shaped like Spotify's (`trees/clean/player/01.txt`: a 402x48 row, the down arrow 48x48 at x 12
and the ⋯ 48x48 at the trailing edge), both put away as `PlayerHeader.x` leaves them; Spotify's ⋯ stays the action
that brings its sheet up. The title row is Spotify's stack (the title's element, the X's 24pt slot, hidden unless
Spotify offers it, and the add button's 48x48 one), laid out through `SGRPlayerMenuInTitleRow` as `PlayerLyrics.x`
does. The player's ⋯ is the mod's own pull-down button in the add button's slot, and a tap on it is a finger's
touch (`../tabbar/touch.m`), down and up at its middle: UIKit opens the button's menu on the touch down. (Until 2026-10-06 the harness tapped with `-performPrimaryAction`, which opens a button's menu
whether or not the button holds one yet, and so missed that a finger's touch on the mod's button, holding none
until asked, was taken and opened nothing: the phone's ⋯ did nothing.) Each run taps at 1 s and prints `PASS`
or `FAIL` lines, then `done`. A pick, or opening a submenu, goes through the menu view's own
selection (`_UIContextMenuView`'s `_handleSelectionForElement:`), the harness's only private call; the mod's own
lines (`SGLog`) go to the unified log.

The ordinary sheet scenarios first check the top level: the menu is on screen (within 1 s, the simulator's
first menu of a launch being slow), the mod's ⋯ takes touches, the quick row (Share, Add to Playlist, Add to
Queue) is in it, and its first level reads, in order, the quick row, the add button (Save to Your Library, where it
is sure to be: Spotify's rows held back, or a saved song's, with no Like row), Spotify's rows laid out in place (or
the loading row), then the player's own (Speed, Pitch & Reverb ... Show Animated Artwork), with no More submenu. "Shows" means a label on screen or an item laid out in the visible menu below the
screen's fold, the menu being taller than the screen; then that Spotify's ⋯ action ran once, from code, after the menu was up, that Speed and pitch was told the
sheet is the player's, and that the sheet is in the mod's window under the app's, unseen, with the menu still up.
The delayed and timeout scenarios instead hold the Spotify presentation while checking the real menu's
selection or dismissal, then deliver or withhold Spotify's sheet.

- `beside`: the mod's ⋯ takes the add button's slot in the title row, drawing the ⋯ glyph, the add button and the
  X put away (alpha 0, hidden from VoiceOver), VoiceOver reading it with Spotify's ⋯'s words; a touch in the slot
  reaches it, nothing opens before the finger, a finger sends its touch down and opens the menu, and the press
  holds while the menu is up and is let go as it ends.
- `star`: Star add button on (the harness's `SGRStarAddOn` is on for this scenario alone; the rest run with it off):
  the add button's slot stays drawn and read by VoiceOver, the X is put away, the ⋯ stands in the row's 48 pt end, and
  with the row's arranged views held in before it (as `PlayerTitle.x` holds them, which
  `harness/player/title-style-check.sh` checks) the add button ends where the ⋯ starts; a finger on the add button
  runs Spotify's add action and opens no menu, and the ⋯'s menu, Spotify's rows held back, has no add item.
- `titleitems`: a saved song out of a playlist with Spotify's X shown, its sheet with neither a Like row nor Hide in
  this playlist (as 9.1.90's and 9.2.0's): once Spotify's rows are in, the add button (Spotify's words "Added to
  playlist") is still in the menu as Change Where It's Saved, not checked, with Spotify's circled tick, beside the quick row's
  Add to Playlist, and Don't play this is a plain item; picking the X fires Spotify's X (not the add button) and the
  sheet goes.
- `playlist`: a song not saved yet in a playlist with the X shown, its sheet with Add to Liked Songs (18) and Hide in
  this playlist (7), held back: both title row items are in the menu until the rows come, then go, Spotify's two rows
  standing for them. A second menu leaves them out at once from the stored rows; its live rows, out of the playlist,
  have no Hide, so Don't play this comes back after the quick row (Save to Your Library stays out for the Like row),
  and picking it fires Spotify's X.
- `stalecache`: a song not saved yet out of a playlist with the X shown, the rows stored from a playlist's sheet
  (Like and Hide in this playlist) and the live ones held back: the menu opens as the last one did, the stored Hide
  standing for the X. Picking the stored Hide shows Spotify's sheet once the live rows come without Hide, and again
  in a second menu whose rows never come (after 4 s); neither the X, the add button nor a row fires. In a third menu
  left up with no rows coming, Don't play this comes back after the quick row once they are given up on. In a
  fourth, in a playlist whose Hide is grayed out, the X's item stays once the live rows are in.
- `popover`: Spotify's sheet a popover from its ⋯ in the app's window, as on an iPad (kept a popover at any width):
  it is up in the mod's window, unseen, and the menu lays out its rows as `rows` does; picking Go to album taps
  Spotify's row. Without the source moved into the mod's window, UIKit drops the popover and the sheet never comes up.
- `notup`, `notup-stored`: the sheet taken into the mod's window but never up there (a popover anchored by a source
  item, which UIKit drops): within the three-second request window the loading row gives way to "Spotify's options did
  not load" (`notup`) and Save to Your Library and Don't play this are in the menu, also where stored Like and Hide
  rows stood for them (`notup-stored`); picking Don't play this fires Spotify's X.
- `slowsheet`: Add to Queue picked while Spotify's sheet is up in the mod's window but its presentation's completion
  comes 3.5 s late and its rows 3.4 s after it loads, both past the request window: the pick still waits for its row
  and fires Spotify's Add to queue once, the sheet never shown.
- `timing`: one cold opening and one warm opening after the menu and backing sheet dismiss.
  Checks the one-second cold and 250 ms warm limits, without repeated screenshot/timing rehearsals.
- `rows`: the menu lays out Go to album, the grayed-out Lyrics and Sleep timer (below the sheet's fold), not the
  rows the quick row has; picking Go to album taps Spotify's row and the sheet goes.
- `loading`: the first menu ever, its rows 1.5 s late: the system's loading row stands in their place, then the
  rows come into the open menu, and Go to album fires.
- `stored`: a first menu reads and stores the rows and is closed with no pick (its sheet goes); a second menu's
  sheet holds its rows back: the menu shows the stored rows at once, a pick on them waits, and fires once the live
  rows come.
- `quick`: Add to Queue is picked at once; the rows come 1.2 s after the sheet, and the pick waits for them.
- `quicklate`: Add to Playlist is picked and the rows never come: after 4 s Spotify's sheet is shown.
- `podcast`: a sheet with no Add to playlist row: once its rows are in, the quick row drops Add to Playlist while
  the menu is up, and the menu lays out Go to show.
- `close`: closing the menu with no pick takes the hidden sheet away within 1 s, and a second tap opens again.
- `subpage`: the quick Share taps Spotify's Share, which pushes a page inside the sheet: the sheet is shown over
  the player, on that page; closed, the mod's window goes back under the app's.
- `sleep`: Sleep timer pushes its options page 0.3 s later: the same.
- `sleeppresent`: Sleep timer presents a context menu sheet of its own from the player, as on the phone:
  that sheet shows as Spotify's, in the app's window, no menu comes up for it, Spotify's ⋯ action ran once, and
  the card it came from goes unseen.
- `sort`: a row of the mod's own in the sheet's header (as the playlist's Sort) is among Spotify's rows and fires.
- `animated`: Show Animated Artwork switches it on and the sheet goes.
- `effects`: Audio effects is in the menu with the effects' summary under it (a stub), its pick asks for the
  Audio effects sheet once from the player's ⋯ (a stub that counts; `harness/audio-effects-page` has the page),
  and Spotify's sheet goes.
- `wrapped`: Spotify presents a controller of its own that puts the sheet in only as it appears
  (NavigationUI_SheetImpl.ContainerViewController on the phone); the rows and a pick work the same.
- `delayed-pick`, `delayed-close`: hold Spotify's presentation until after a selection or dismissal has
  ended the menu and released its anchor's session. The pending request keeps the session alive.
  Add to Queue runs exactly once on arrival after a selection; after dismissal the late sheet is
  discarded without firing anything. Weak references verify session deallocation after the sheet
  goes, beyond both timeout callbacks.
- `delayed-wrapped-pick`, `delayed-wrapped-close`: the same delayed presentation with a wrapper that
  adds the sheet only in `viewWillAppear:`, using Spotify's wrapper class identity.
- `delayed-mod-panel`, `delayed-wrapped-mod-panel`: pick Playing Next through the real menu while
  Spotify's sheet is held. The panel is presented normally and stays visible in the app window:
  it cannot satisfy the pending request. Releasing Spotify's late sheet discards that sheet,
  then releases the session.
- `request-timeout-pick`, `request-timeout-close`: no sheet ever arrives; after an early selection or
  dismissal, the request keeps the session alive until timeout, then releases it without firing an action.
- `request-superseded`: dismiss a menu whose request is pending, then start and end a newer real
  session directly before timeout. This isolates request supersession from UIKit's liquid menu
  animation (reopening during its dismissal traps inside UIKit on iOS 26.5). The newer request replaces
  the single pending slot and releases the old session. The newer cancelled session survives until
  its late sheet is discarded, then is released; neither request fires an action.

- `pinned`: a page's pinned ⋯ tapped (a stand-in button: the Kit's claim is stubbed here as `SGRPinnedMoreRecentButton`,
  ended by `SGRPinnedMoreTaken`): Spotify's sheet for it is taken over and its menu opens from the ⋯; closed with no pick,
  a track's ⋯ well within the claim's three seconds shows Spotify's sheet, not the page's menu again. With
  `SIMCTL_CHILD_HARNESS_HOLD=1` it prints READY and holds the screen three seconds before that last check. 2026-11-22,
  iPhone 17 Pro on iOS 26.5, before the fix: the track's sheet was taken over and opened as the page's menu.

`pinned-check.sh` (pinned-check.m) is the Kit's half on the Mac, no simulator: the real `SGRPinnedMore` over a page with a
stand-in for Spotify's ⋯. A press let go off the ⋯ (touch down, then touch up outside) claims nothing; a tap claims the
button and its page before Spotify's ⋯ runs, so a sheet presented from that call finds them. Before the fix the press
claimed both, on its touch down. Last, the ⋯ drawn in an `SGRHeaderInfo` (the cover beside the title) is tapped and Spotify
presents its sheet, which the real `SGRPinnedMoreTaken` ends the button's claim for, as `ContextMenu.x`'s takeover does:
the real `PlaylistMenu.x` (through Logos) puts the playlist's Sort and Mix rows on it. With the header info claimed as the
page instead, the sheet had no rows.

Only Spotify's context sheet or its known lazy wrapper can satisfy the pending request; a mod panel cannot.
There is deliberately no presenter-ancestry restriction: Spotify 9.1.90 can present its lazy wrapper from
NowPlayingOverlayContainer, outside the requesting controller's ancestor chain.

Known limitation: cancellation still discards the **next Spotify sheet** within the pending request's
three-second window, not a request-identified sheet. A newer request replaces that single slot. Overlapping
A/B deliveries (including same-presenter A-before-B delivery) and a page ⋯ gesture within the recency
window remain ambiguous; an unrelated Spotify context sheet can satisfy the slot. A sheet arriving after
the request window is not adopted or suppressed by that request. These are documented debt, not guarantees
of request correlation.

Use a unique temporary output directory for checks:

    HARNESS_BUILD_DIR=$(mktemp -d /tmp/fix-menu-session.XXXXXX)
    export HARNESS_BUILD_DIR
    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> "$HARNESS_BUILD_DIR/SystemMenuHarness.app"
    xcrun simctl launch --console-pty <udid> com.retrine.systemmenuharness delayed-pick

For the ownership mutation check, make a temporary copy of `ContextMenu.x`, change only
`static SGRMenuSession *sg_requesting;` back to `static __weak SGRMenuSession *sg_requesting;`,
and pass its absolute path as `CONTEXT_MENU_SOURCE` to `build.sh` with a separate temporary output
directory. `delayed-pick` must fail because the outstanding request no longer survives menu ending.
For presentation recognition, restore the any-non-alert predicate: `delayed-mod-panel` must fail its panel
visibility check. For the title row items, drop the line in `leadGroup` that leaves out an item whose identifier
is a shown row's: `playlist` must fail; make `fireTitle:` fire the first lead item that carries an identifier where
its live rows lack the title, or drop `refreshLead` where the row poll gives up: `stalecache` must fail. For the
iPad popover, skip moving its source into the mod's window in `adoptSheet:`: `popover` must fail; let the request
window's timeout end with adoption again (`if (!session || sg_requesting != session) return;`): `notup` and
`notup-stored` must fail; let `titleRowItems` offer the add button's item with Star add button on: `star` must
fail; drop the request window's branch for a sheet still being presented (its presenting
controller set): `slowsheet` must fail. Mutate only a temporary source copy, never the working source.
Remove only those temporary build/source directories after the runs.
