# Mod Settings harness

Mod Settings' main page as `App/ModSettings.x` builds it, opened through `SGOpenModSettings` and pushed onto a
navigation stack as on the phone, with the real `App/Pages.m` behind the Redesigned UI switch, the real Mod
page in `App/About/AboutSettings.m`, and the real `Settings/` framework. `build.sh` runs `ModSettings.x` through `logos.pl -c generator=internal`; its hooks on
Spotify's settings list and side drawer find no class here and do nothing. `stubs.m` stands in for other pages
rows open (an empty page of that name), feature values beside the chevrons (Off) and update checks.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/ModSettingsHarness.app
    xcrun simctl launch --console-pty <udid> com.retrine.modsettingsharness redesign warning dump
    xcrun simctl io <udid> screenshot shot.png

Make a simulator of your own (`xcrun simctl create`) and address it by UDID. `main.m` lists the setup words
(`redesign`, `warning`, `keep`) and the actions: `toggle=<section>.<row>` flips a switch the way a tap does,
`cancel` closes the alert it brings up, `bottom` scrolls to the end, and `dump` logs the rows of every section.

`gated` pushes a page of `SGModPage` itself: a switch over ten rows, then a section with a heading and a note
whose twelve rows show only while the switch is on, then a row that `later` lets come by itself. `layout` logs
the scroll offset and each section's rows, heading and note heights; `top` scrolls back up.

    xcrun simctl launch --console-pty <udid> com.retrine.modsettingsharness gated layout toggle=0.0 layout later dump layout top toggle=0.0 layout

2026-10-06, iPhone 17 Pro on iOS 27.0: with the switch off the gated section has 0 pt of heading and note; the
switch brings it in with its 38 pt heading and 28 pt note and scrolls 362 pt, half the 724 pt of room; the
ticker brings the later row within a second without moving the page; the switch off takes the heading and note
away again.

`rows` on the launch line makes Spotify's settings list controller and the side drawer's list class under their own
names before the hooks are set, then lays a drawer list out and a settings list out under its controller, empties
each of its subviews as Spotify can, and lays it out again. It logs how many Mod Settings rows each has: 1 and 1 for
both. With main's ModSettings.x before the fix it read 0 and 0 for the drawer and 1 then 0 for the settings list.

The pure initials and matching cases live with the index, keywords and recents in
`harness/settings-search/check.m`, which runs offline through `harness/settings-search/build.sh`.

`search-controller` drives the real `UISearchController` of a searchable page and its real results table: an empty
field up shows the table with the two stored places on it, a typed query shows its row, and clearing the text brings
the recents back — the field is off UIKit's automatic rule, which would take the table away on an empty field. A
closed field shows no results, and up again the recents are there. It logs `search controller passed` and exits 0,
or logs the failures and exits 1.

`search-destinations` runs after the scene connects (use `redesign search-destinations`), presents the real
search controller, and selects Audio effects and All flags through its results table. Their stubs are `SGPage`,
not `SGModPage`, matching the production destinations. It waits for navigation's completed transition and checks
the destination and closed search field; a missing push fails after a bounded deadline. Run in English
(`-AppleLanguages '(en)' -spotifyglass.language 1`) and Korean (`(ko)` and `2`).

`needs` pushes the Lock screen page's artwork section as iOS 18 to 25 get it (the real
`AnimatedArtworkSettings.m`'s `SGLockScreenArtworkNeedsRow`), and `tap=<section>.<row>` selects a row and logs the
alert it brings up: "Full-screen artwork", "Needs iOS 26", and an alert naming the iOS version.

2026-10-06, iPhone 17 Pro on iOS 27.0: the warning row leads; then Redesigned UI (glowing, with its ⓘ), Appearance
and Tab bar; Player, Lyrics, Albums and Artists (Home & Library in the native look); Sing, Spatial voice, Audio
effects, Vibrations, Live Activity, AirPods gestures and Listening stats; Lock screen and Premium, ads & privacy; Labs and
All flags; Mod with the version. Flipping Redesigned UI on in the native look offers the restart and swaps Home &
Library for Albums and Artists in place.

`App/About/Signing.m` is the real one. A free Apple ID's "Signed until" row joins the top section once the
.app holds an `embedded.mobileprovision` whose `ExpirationDate` is under eight days after its `CreationDate`; the
parser takes a plain XML plist as well as a signed one, so one written by hand will do (copy it in after
`build.sh`, before `simctl install`).

What it does not cover: other feature pages, the row the mod adds to Spotify's settings list and side drawer
in Spotify's real lists (`rows` uses stand-ins of the same names), and iOS below 26, where the switch warns first.

`prompt-check` navigates the production Lyrics/Translation & AI row declarations and uses the real prompt
editor, while unrelated feature rows and the lyrics preview remain stubs. Launch with
`-AppleLanguages '(en)' -spotifyglass.language 1 redesign prompt-check`, or `(ko)` and `2` for Korean.
It checks the visible value and disclosure chevron, pushes through the real row selection, checks Spotify's
page protocol, Save/pop/value refresh, back-navigation draft discard, the enabled back gesture,
Restore default, overlong drafts, keyboard clearance, Dynamic Type and accessibility labels, then exits
with PASS or a nonzero FAIL. It writes `prompt-row.png` and `prompt-editor.png` into the
harness app's Documents directory; these window captures omit the system keyboard window. Use a disposable
simulator clone and copy screenshots before the next language run overwrites them.
`PROMPT_SOURCE` can select an isolated source mutation; removing the row's page must fail the visible
value-plus-chevron check without crashing the app.

`light-check.sh` brings the mod's alerts up as Spotify shows them: its Info.plist sets no appearance, so the
harness's key is removed and `system` leaves the window in the system's appearance under a dark navigation stack.
In a simulator of its own, in Light Mode and then Dark Mode, `alerts` with `info`, `lock` and `toggle=0.1` brings up
SGModPage's three alerts, `toggle=0.0` Pages.m's restart alert, and `information` SGPresentInformation's; `look`
logs the alert's frame, and its screenshot there must be dark (mean luminance under 80; a light alert's glass reads
about 165, a dark one's about 30). `LIGHT_SHOTS=<dir>` keeps the screenshots.

2026-11-24, iPhone 17 Pro on iOS 26.5: before the alerts went through `SGPresentDark`, the four in Light Mode read
165 to 173 and showed white glass; after, every alert reads under 40 in both modes.

`refactor-check` runs offline and exits: the real About page's Reset row keeps its trash symbol, opening
Mod Settings finds a navigation controller through the source's parents, and a deeper first-child stack
wins over a shallower later sibling. About's external actions remain stubs.

`font-check` checks the shared tabular-digit font's descriptor feature, unchanged point size and nil handling,
then exits. `PAGE_STYLE_SOURCE` can select an isolated `SGPageStyle.m` mutation for this check.

`information-check` (launch with `-AppleLanguages '(en)'`) exercises the real empty-artist, unsupported
lock-screen artwork and failed-app-icon actions. It checks their messages, presenters, OK action and
main-thread presentation; UIKit's icon-change operation fails offline from a worker queue. The check
exits on completion. `APP_ICON_SOURCE` can select an isolated app-icon mutation.
