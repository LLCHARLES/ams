# Tab bar harness

The bottom of Spotify's main screen mocked under its own class names, so `Redesigned/Navbar/TabBar.x`
and `Redesigned/NowPlayingBar/NowPlayingBar.x` run for real over it on the Mac without the phone: the
tab bar container with Spotify's bar and its row of tabs, a page with a list on the tab's stack, the
now playing bar's page with its card, and Spotify's message bar (`LimitedExperienceIndicatorBar`, what
Offline and Private Session show) under the tab bar. It plays issue #33.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/TabBarHarness.app
    xcrun simctl launch <udid> com.vojta.tabbarharness shown
    xcrun simctl io <udid> screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over `TabBar.x` and `NowPlayingBar.x` from the
checkout it sits in and links them with the real `Core/` and `SGRTokens.m`; `SRC=<other tweak/Sources>
./build.sh` builds an older tree instead, to compare. `stubs.m` stands in for the accent and repaint
hooks, the tab bar's composition and Mod Settings. iOS 27 ends an app with no scene delegate at
launch, so the harness has one.

For issue #72, `bar-check.sh` also builds with `HARNESS_COMPOSED=1` to link the real `Navbar.x`.
The `launch` case begins with an unplaced Queue, hidden Create, and unpainted Home and Search.
It checks the first mirror's order and selection, sends 60 layout passes before the first glyph retry,
and inspects the image views UIKit displays after the stock URIs arrive. `launch late-ink` paints the
original icons after the first retry. `launch replace-search` checks the retry budget after Spotify replaces a source.
`launch reentrant` selects a replacement Search while Home's glyph is being drawn and checks that its retry renders
the new glyph. `launch unlabeled` starts Home and Search without names. `launch replace-bar` retains the detached
stock bar while the replacement is on screen and checks that only the visible bar can retry.

The layout is the one 9.1.78 makes in a compact width, with the addresses it was read from:

- `TabBarContainerImpl`'s view has a guide from 49 pt above its safe area's bottom to its bottom
  (`viewDidLoad`, 0x1008409a8); the stack holding the tab bar is as tall as the guide and stands on
  the view's bottom, and the tab bar is as tall as the stack (0x106fabb7c).
- The page on the tab's stack gets 49 pt of safe area on top of the container's (0x10707bde4). The now
  playing bar's share of the pages' inset comes another way in Spotify; here it is a stand-in of 64 pt
  on the page, so the list's end marks where Spotify thinks the bars begin.
- The chrome puts the tab bar container above the message bar, and the now playing bar's page (64 pt,
  its content 8 pt above its bottom, 0x105345190) on the container's guide's top, which is the bottom
  anchor `MainUIContainer` gives the chrome (0x100ae0178).
- The message bar is its message plus the safe area it pads the message by, 22 pt here.

Launch words: `none` no message bar; `shown` one sliding in at 1.5 s; `away` one there from the start,
sliding away at 1.5 s; `cycle` in at 1.5 s and out at 4.5 s, for a recording. At 2.5 s everything is
logged in window points, with the gap between the bottom of the now playing card and the top of the
glass bar's platter (8 pt is the redesign's own, on a Face ID phone with nothing under the bar), and
half way through a slide what the screen shows of the message bar, the tab bar and the now playing bar:

`split` after the first word makes Search a split tab (stubs.m answers `SGRTabIsApart` for it), so it
stands on a glass bar of its own, and the platters of both bars are logged. `pick` picks Search at 2 s and
Home at 4 s through the system bar's delegate, the mock tab repainting its label white as Spotify's does,
and logs which bar selects what after each: `xcrun simctl launch <udid> com.vojta.tabbarharness pick split`.
`lit` has Your Library stand in for a tab of the mod's own whose page is up (stubs.m answers `SGRNavbarLitTab`
with it) at 2 s, while Home's label stays white: the selection logged at 2.5 s should be Your Library. Home is
picked at 3.5 s, which forgets the lit tab, and the selection at 4.5 s should be Home.

    xcrun simctl spawn <udid> log show --last 1m --style compact --predicate 'eventMessage CONTAINS "[harness]" OR eventMessage CONTAINS "tab bar:"'

`mini` minimizes the bar at 1 s through `SGRSetTabBarMinimized`, logs at 2.5 s and expands it again at 3.5 s,
logging at 5 s. Minimized, the platters should be two 62 pt circles 21 pt in from each side, the card
between them 8 pt from each, centered on them, and a touch at the card's middle should land in the now
playing bar (through the hook on the page's `TouchPassthroughView`); expanded again, all as `none` has
it. Every report also gives the frame of the fade under the bars. The mock card's labels have fixed
frames, so how Spotify's own content takes the narrower card is not shown here.

`names` logs every title the glass bars show and whether UIKit cut it short ("CUT", against the width the text
needs at the smallest size its label may shrink to): at rest, as the bar starts to expand from minimized, mid-way,
once expanded, after four turns 0.1 s apart, after a minimize and an expand with no animation (the player opening
and closing), and after another layout pass. Each line ends with how many are cut, which should be 0; with `strict`
a cut name fails the run and the last report ends it with `PASS all names`. `split2`
sets Create apart as well as Search, `five` adds a fifth tab and `long` gives two tabs long names (`names split2`,
`names split five long`). The log is read most reliably from the console:
`xcrun simctl launch --console-pty <udid> com.vojta.tabbarharness names split2`.

2026-10-06, iPhone 17 Pro on iOS 27.0, before the fix: every name read "…" while the bar grew (8 cut), Search and Your Library stayed cut after the minimize and expand with no animation, and with two
split tabs their names stayed "Sea…" and "Cre…" at rest for good. A split Search (32 pt for 35) and long names
were cut at rest. After it, 0 everywhere, except a name that does not fit even at 8 pt ("Your Library and
Downloads" beside a split tab), which UIKit still cuts.

`touch.m` makes touches the way a finger's arrive (a `UITouch` and the touches event with the IOHIDEvent
UIKit's gesture recognizers read, the private calls KIF makes), so the scenarios below tap the glass bar and
fling the list through UIKit's own recognizers and scrolling. Checked on iOS 27.0 in the simulator only.

`tap` minimizes the bar at 1 s, logs at 2.5 s what a finger on the leading circle lands on (and with `split`
on the trailing one), and taps it. Both should land on a `_UITabButton` of their own glass bar, and after
the tap at 3.5 s and 5 s the bar should be expanded with Home selected, as `none` has it. 2026-10-06, iPhone
17 Pro on iOS 27.0, before the fix: the leading circle's touch landed on the now playing bar's container
view (a plain `UIView` here), which the hook on `TouchPassthroughView` handed it because that view keeps the
screen's width when the card is narrowed into the row; the bar stayed minimized. After it, `_UITabButton`,
and the bar expanded.

`turns` flings the list for real: down from its top to minimize, back up and down again half way through
that, back up with a finger stopping the list, and four turns 0.15 s apart. `nested` minimizes the bar from
inside a property animator left paused a third of the way (as a header that follows the scroll keeps one)
and expands it inside a 3 s animation block. Each check says whether the bar and the card agree (the
circle 21 pt in and the card in its row, or the whole platter and the card above it), what the screen
shows, how many animations are left, and IN STEP or OUT OF STEP. 2026-10-06, iPhone 17 Pro on iOS 27.0,
before the fix: `nested` stopped with the circle at x 107 on its way along the row and the card 22 of its
67 pt down, 50 animations held, the phone's screenshot of a bar left half minimized; the expand took
the block's 3 s. After it, every check IN STEP with one animation (UIKit's own), at rest at once.

`motion` samples what the screen shows (the presentation layers) every 1/60 s: the main bar's platter, its
leftmost glyph, the split bar's platter and the card's glass, across six stretches of 1 s: a minimize, an
expand, each of them turned back 0.15 s in, a minimize again, and four turns 0.1 s apart. Each logs the largest
change in x, y, width or height from one frame to the next (a frame the simulator skipped counts as that many)
and how often the view watched was a new one, then a check and the names. `timeline` logs every sample. The
stretches run one after another and time their turns from their own start: dispatch_after may run a block a
tenth of its delay late, so steps timed from the launch, as `names` times its quick turns and `tap` its tap and
the report after it, can fall together (one `tap` run in three reported the bar before the tap's touch-up).
A critically damped spring moving the platter's 298 pt peaks at some 50 pt a frame over 0.34 s; more is a jump.
A single sample off its neighbors at a turn is one read in the turn's own run loop pass, before its animations
are committed.

2026-10-06, iPhone 17 Pro on iOS 27.0. Before the fix, every minimize laid the circle's one item out in the
full bar first: the platter went from 360 pt wide at x 21 to 100 pt at x 145 in one frame (259.7 pt) and the
Home glyph from x 40 to 183 (142.7 pt), then slid back to the leading end; an expand turned back jumped 108 pt
and four quick turns 191.6 pt. The tabs' titles were made again after the spring had started. After it: the
largest step 49 pt for the platter (36 with a split tab), 16 for the card (27), 3.8 for the glyph away from the
turns, no title cut at any point, every check IN STEP. Under Reduce Motion (`defaults write
com.apple.Accessibility ReduceMotionEnabled` in the simulator) the bar and the card change in the same frame.

`minimize-check.c` runs the scroll's steps (`MinimizeStep.h`) on the Mac:

    cc -I../../tweak/Sources/Redesigned/Navbar minimize-check.c -o build/minimize-check && build/minimize-check

`reparent-drag` moves a scroll view's wrapper onto and off the tab page before separate drags; only the
on-page drag should minimize the bar. `reparent-fling` starts outside the page and moves the wrapper
onto it during deceleration; further travel on the page should minimize the bar without a new touch.

`jam` plays a Jam: a strip under the class name of Spotify's (a SwiftUI hosting view of
`Jam_AttachmentsImpl.JamHatElement`, 44 pt) over the card, both in a view painted the album color too,
the bar 44 pt taller, and the strip gone again at 3.5 s. The log then lists the bar's glass panes. The
card's glass should be the track card's (386x56), the strip's pane 36 pt above it with a 4 pt gap, and
once the Jam is over the card's glass should still be 386x56 and the strip's pane should have no effect.
Before the fix the card's glass was the painted view around both, cut to 80 pt, over the strip and
the top 36 pt of the track. How Spotify really nests the strip is not known; this is one way the spec's description
allows.

Before the fix the gap was -26 pt with nothing under the bar on an iPhone SE, and with the message bar
up on any phone: UIKit's glass bar is 83 pt, Spotify's bar was its 49 pt row with no inset under it,
and the glass bar stood the difference above it, over the now playing bar.

`glass-check.py` checks the listener's glass (Redesigned/Kit/SGRGlass.h) in a simulator of its own, over rows in color
with the fade off: `glass` reads the glass of every platter shown and of the now playing card against literals given at
launch (`-harness.wantMaterial`, `-harness.wantTint`, `-harness.wantInteractive`), expanded and minimized, each held for
a screenshot, then taps Your Library's tab and a button on the card, which must both work. It runs Regular and None,
Clear, Clear and Dark (also with `split`) and touch response off, and asks each platter and the card to look different
on the screen in Clear, and in Clear and Dark, from Regular and None: a platter's material is read from its
`_UIViewGlass`, the card's only shows on the screen, since an effect view hands its glass back as Regular.
2026-11-23, iPhone 17 Pro on iOS 26.5: platters 14.6 to 56.3 and the card 14.6 to 66.7 per channel apart, and Regular
and None with touch response off 0.0 apart from UIKit's own glass at rest. Needs Pillow.

`fade-check.sh` checks the fade under the bars (`spotifyglass.redesign.navbar.fade`) in a simulator of its own:
`fade toggle` (and `fade toggle split`) switches it off and on live the way the Tab bar page does, and asserts one
`SGRBarFade` behind the glass from `SGRBarFadeAbovePt` over the glass bar's top to the tab bar container's foot and
across its whole width, taking no touches (a finger in its band lands on the page), none at all when off, none
kept alive after 20 turns, the same minimized and with the bar hidden, and Spotify's own `TabBarGradientView` left
clear throughout. `fade toggle regular` does it over Spotify's regular width bar, 8 pt in and 648 of the
container's 1016 pt as 9.2.0 lays it out on an iPad Pro 13-inch and 16 pt above the container's foot as on an
iPad Pro 11-inch (`regular` lays the bar out so everywhere), minimized left out since that bar never minimizes.
2026-11-19, before the fix: the fade was only as wide as that bar, which an iPad showed as a dark rectangle with
hard sides behind the glass. 2026-11-22, before the fix (issue #38): the fade ended at the bar's foot, 16 pt short
of the container's, so the page showed undimmed in a strip under the half black, a hard edge across the screen.

`ipad-check.sh` runs in an iPad simulator of its own (the harness app is built for both device families):
`names strict` and `names strict regular`, then `fade toggle regular` and `panel regular`. The panel check
scrubs the container from 1194 to 786.5 pt while its stack moves from x 8 to 78.5 and the bar shrinks
from 784 to 629.5 pt, then slowly scrubs back. At each tenth and at rest the fade's two presentation-layer
edges must match the container's in window coordinates within 0.5 pt. 2026-11-22, iPad Pro 11-inch on iOS 26.5,
before the fix: an iPad's bar sets each name beside its glyph, and the names were cut ("Search" 24 pt for 42,
"Your Library" 24 for 72, "Create" 24 for 40; "홈" 4 for 10.5 and "만…" in Spotify itself), since UIKit gave each tab
its width as the bar took the items, before they had their glyphs. A split tab's own bar is a circle there too
and shows its glyph alone, so `split` is not part of the check. `fade`, `fade off` and
`fade mini` hold the page in color for a screenshot, and `navsettings` opens the Tab bar page over the bar
(navsettings.m): its fade switch starts on, the preview reads the fade, and the switch takes the fade off the real
bar at once. It does so through the switch's own path in the product (`SGRRefreshBarFade`, TabBar.x): stubs.m's
`SGRRefreshTabBar` lays out nothing, as Navbar.x's would with no bar composed, so a switch that relied on it fails.
That scenario also checks Icons only, Custom tab bar and hiding Home through the page controls,
without screenshot pauses.

`bar-check.sh` runs the tabs' glyphs and the now playing card's edges in a simulator of its own, `audit` and `search`.
`glyphs` makes the tabs' icons Encore's glyph view (a mock under its name that draws a ring for an outline icon
and a solid shape for its `-active` variant, which the tab's view is handed when it is selected, its `isActive`
changing only colors) and asserts the selected tab's filled glyph and every other tab's outline at launch, after
picking Search and Home again, minimized and expanded on the spring, and after Home's view is handed another
icon (a square), which must replace Home's old glyph. `glyphs swift` does the same with the icon held as 9.1.90
holds it: a reference Objective-C cannot read to one icon carrying both glyphs, which the view keeps selected or
not, its `isActive` picking the filled one. `symbols` (navsettings.m) checks Apple symbols (`spotifyglass.redesign.navbar.symbols`) in `glyphs`' mock, with a tab of
the mod's own (a mock under Navbar.x's `SGRTabItemView`, its icon `heart` from `SGTabIconView`) after Spotify's
four, whose pages it hands TabBar.x as Navbar.x reads them off Spotify's list of tabs on 9.1.90 (`SGRSetNavbarStockURIs`).
With the Tab bar page over the bar it asserts, on the bar, the page's preview and its list: off, Spotify's tabs show the
mock's rings; switched on from the page, each of Spotify's four has a picture of its own, none its ring, Home keeps its Music house
and Search keeps its magnifying glass when selected; the list
read twice at once off the main thread, naming Home's page for Search and then Search's own, lays the bar out never off
the main thread and once on it (stubs.m's `SGRRefreshTabBar` counts), and the bar draws Search as Home and then as
before; switched off again, the rings as before; the tab of the mod's own the same picture throughout, and with the
switch off and on its item on the bar and the preview the symbol itself (heart, heart.fill selected), shown at the size
a plain `UITabBar` shows a tab given heart (28.7x25 pt on an iPhone 17 Pro, iOS 26.5). `symbols hold` (and `symbols hold rtl`, right to left) gives the tab of
the mod's own the house SF Symbol, hides the names and switches Apple symbols on. A finger held on the custom tab
opens nothing, and a hold on Home opens Mod Settings once (stubs.m's
`SGOpenModSettings` counts). stubs.m's `SGRRefreshTabBar` lays out
nothing, so after each flip the check lays the bar out the way Navbar.x's does. `symbols show` holds the bar with the
switch off and `symbols show on` with it on, and `symbols page` (`on`, and `list` scrolled to the tabs) the page over it,
for a screenshot.
`edges` (after `none`, `split`, `split2` or `jam`, with
`regular` or `rtl`) asserts the card's sides: above the bar at the expanded platters' outer edges as UIKit drew
them (with Search split the main platter is centered narrower than its bar, x 27 on an iPhone 17 Pro), minimized
in the row 8 pt from the circles, back after a minimize turned back mid-spring, above the bar while a Jam's strip
is up, and Spotify's 8 pt in a regular width and right to left.

`search` (search.m, issue #34) makes the row Home, Your Library, Create, Liked Songs and Search, the last of five as
the issue keeps it (`middle` puts Search third), and hands TabBar.x the pages of Spotify's tabs as Navbar.x reads them
off Spotify's list: Search as `spotify:search` (9.2.0), with `find` as `spotify:find` (9.1.90). Spotify's
tab change is played too: a tap on a mock tab tells the container (`setSelectedViewController:`), whose hook brings
the bar back. It minimizes on Home and asserts Home on the leading circle, which says it shows all tabs, Search on a
trailing circle on a 104 pt bar at the trailing edge (a split tab's), its item named Search with its glyph for the large
content viewer, a finger on it landing on its bar, and the card in its slot, 8 pt from each circle; then expands, a
minimize and an expand each turned back 0.12 s in, minimizes and expands on Search (Home leading, Search selected on
the trailing circle), and taps the trailing circle for real: Search picked, the bar expanded. Every frame of each move,
the tap's expansion too, is sampled: Search drawn exactly once (its buttons on either bar and the pictures of buttons
that went, each glyph counted by the share of it the screen shows clearly: the part left inside every view above it
that clips, by its bounds or its mask, and outside the glass platter, a capsule, of every bar standing over its own in
the bars' host, times its opacity, drawn above 2%) and that one shown at 90% or more, so a glyph clipped by its platter
or blurred under another bar's glass is not counted as drawn; its glyph moving no more than a spring does (50 pt a frame), the trailing
circle drawn on Search's glyph the first frame it shows, and no platter partly faded. `labels` shows the tabs' names.
With `middle labels` it also
taps the circle 0.15 s into an expand, 8 pt in from its drawn left side, and asserts the tab picked is the one the
expanded row picks for a tap at that point (before the fix the circle, drawn over the row for the expand, took the
touch and nothing was picked). `splitcreate` makes Create a split tab, `nosearch` hides Search, `own` hides it and adds a tab of the mod's own named
Search: the minimized bar as before, Create's circle or none, the card to 21 pt in. `leaves` hides Spotify's Search
in its row while the bar is minimized and shows it again, as Spotify's list of tabs changing does: the trailing circle
goes and comes, and the card takes the slot each time (290 pt without the circle, 220 pt beside it).
`keepgoing` prints each failed check and goes on, so each case's own failure shows;
built from the tree before the change (`SRC=`), 2026-11-21 on an iPhone 17 Pro, iOS 26.5, every Search case failed
there (no trailing circle, Search not drawn at all once the bar minimized, the card to the edge, nothing to tap), while
`splitcreate`, `nosearch` and `own`, which keep the bar as it was, passed. A first version that hid the circle's
Search at once on expanding failed the visible-share count (no Search drawn for 6 or 7 frames of each expand, the row's
glyph still clipped by the growing platter), and one whose card followed only the expanded row's edges failed `leaves`
(the card kept 220 pt with the circle gone). With the glass counted, the tree whose circle went under the main bar at
once on expanding failed every expand (the growing platter's glass over the circle's Search for 1 to 3 frames, a
screen recording showing a faint ring there). After the change all pass; Search moves some 32 pt a frame at most across
the row with `middle`.

Issue #35 (a darker disc on the row's end through most of each expand): Search's glyph now goes back into the row as
a view of its own over the bars. Each expand also checks, every frame, that the travelling glyph (the one glyph drawn
outside the bars) has the image and color of the glyph the row shows for Search, its lit copy's when Search is
selected; that while the bar expands no glass is drawn over or under the growing row's (`kOverlapSlackPt`) and, in an
expand from rest, the circle's glass is drawn as long as the row's has not reached it (TabBar.x times it by the
expand's own spring, which an expand turning a minimize back shares with what is left of the minimize's, so there it
may go a frame early); and at rest after every move, that
nothing but the bars is left among them, every tab's glyph and every glass on screen is drawn in full and every bar on
screen takes touches. `expand turned back late` turns an expand back 0.25 s in, once the row has reached the circle:
the circle comes out of the row again. `expand again inside an expand` expands, minimizes 0.08 s in and expands again
0.16 s in; just after the first expand's spring ends, the second's glyph must still travel and the circle's glass be
drawn exactly while the row has not reached it (the first expand's end once took the second one's hand over half way:
no glyph travelling, Search drawn 0 times in 2 frames). 2026-11-21, iPhone 17 Pro on iOS 26.5: built from the tree before the change
(`SRC=`), every expand failed with the circle's glass on the row's in 2 to 12 frames, the circle still drawn 0.25 s
into the late turn; with the circle's glass taken away at once it failed `gone before the expanding row reached it`
in 3 to 5 frames of every expand, and with the travelling glyph drawn from the row's plain copy `expand from Search`
failed `unlike the row's`. After the change all pass, also under Reduce Motion.

Issue #41: the same frame sampler also checks that the returning Search circle, while drawn, stays within
0.5 pt of the row platter's vertical center. Before the fix, `search labels` on an iPhone 17 Pro simulator
(iOS 26.5) failed `expand from Home: returning circle off the row's vertical center by 5.0 pt`.
It did not reproduce the iOS 27 recording's late disappearance: in `search capture labels` the circle was
last visible at frame 004, gone at 005, and Search's name appeared progressively from 006, before the
last moving frame (016). The glass overlap check remains in force with and without names.

`states` checks what an earlier state leaves on the bar (`bar-check.sh` runs both). Alone: the bar minimized in a compact
width, then the window made regular (an iPad's narrow window widened) with no tab changed, and Spotify's bar laid out
again: the bar is expanded with every tab on it. With `split`: Search, the only split tab, picked on its bar; Home chosen
from elsewhere (Spotify repaints its labels and tells its container, as a link or the side drawer does, with no tap on the
glass bar); the bar minimized and a finger on Search's circle: Spotify's Search is tapped. `hold` after either prints
READY and keeps the screen four seconds for a screenshot. 2026-11-22, iPhone 17 Pro on iOS 26.5, before the fix: the
widened bar stayed minimized (1 of 4 tabs on it), and the finger on Search's circle only expanded the bar, Spotify's
Search not tapped, the split bar still holding Search as the item it last showed selected. After it both pass.

`capture.sh` records one expand off the screen of a simulator of its own (`search capture`: the bar minimized at once,
then expanded), for a review frame by frame of what no presentation layer shows, such as the glass UIKit draws:
`capture/expand-NNN.png` under `OUT`, the bottom 520 px of each frame the screen drew, NNN its 1/60 s from the last
still frame, and `capture/sheet.png` with all of them. `selected`, `labels` and `middle` after the script go to the
scenario. `capture-frames.py` (Python 3 with Pillow) cuts the expand out of the recording.

    THEOS=$HOME/theos OUT=/tmp/<dir> ./capture.sh selected labels

What it does not cover: Spotify's own chrome, which is Swift with no symbols (the constraints above
are read from its code, not run), the real now playing bar's content and its page's inset, the tab
bar hidden by a page, the player's open and close over the bars, and a regular width beyond the bar's narrower
width (its fixed 76 pt height, the now playing capsule beside it).
