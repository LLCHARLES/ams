# Player harness

## Upcoming-track parsing without a simulator

Run `sh harness/player/upcoming-tracks-check.sh` from the repository root. It extracts
`SGURIString` and `SGPlayerUpcomingTracks` directly from the current `PlayerState.x` and
compiles them as plain Objective-C against Foundation and minimal Spotify data doubles.
The Logos observer hooks and UIKit are not compiled. Checks cover malformed state/future
values, track filtering, URI forms (including empty strings), ordering, duplicates, the
50-row early stop and an unlimited list. Temporary outputs are removed on exit.

The same script then compiles `Shared/Player/AudioQualityRules.m` as it ships with
`audio-quality-check.m`: each bitrateLevel's badge text (Low to Lossless 24-bit, nothing for 0, 7
and unknown levels), the redesign's words for each (Low Quality to Highest Quality, Lossless, with the
rate, a sentence and the footnote naming Spotify's tier), the lossless glyph for 5 and 6 only, nothing with the switch off, while another
device plays or for a podcast, an ad, a local file or no track, the source named for each strategy,
the sample rates as written, the details dismissed on a skip, on no tier or when the badge goes, and
a badge taking taps only while neither it nor a view above it is hidden or faded out.

## Repeat transitions without a simulator

Run `sh harness/player/repeat-check.sh` from the repository root. It extracts
`SGPlayerAdvanceRepeat` from the current `PlayerState.x` and runs it against a double that records
each command in order and answers with its own token. Checks cover all four flag combinations
(off → context, context → track, track → off then context), that the track flag wins when both are
set, that the track is cleared before the context, and that the caller gets the last command's answer
(including nil for no player). Temporary outputs are removed on exit.

## Player title type without a simulator

```sh
THEOS="$HOME/theos" harness/player/title-style-check.sh
```

Builds the **complete current `PlayerTitle.x`** through Logos into a temporary Mac Catalyst app, with the production
`SGCategoryCappedFont` and design tokens. The labels are shaped as Spotify's (the title a marquee view drawing through
a UILabel inside it, Korean text, Georgia standing in for Spotify's family) and Spotify's setters are called as Spotify
calls them. It checks 20 pt semibold over 20 pt regular in the secondary color, both kept through Spotify's own
`setFont:`, `setTextColor:` and attributed text, the intrinsic heights of the 20 pt lines, 17 over 17 with the lyrics
open, and Spotify's family kept when Spotify's font is the one drawn (`SGAppFontDrawn`). The player harness's
`stubs.m` stubs the title styling, so the adaptive runs do not cover it.

## Landscape title notifications without a simulator

From the repository root on an Apple Silicon Mac with Xcode and Theos:

```sh
THEOS="$HOME/theos" harness/player/title-notification-check.sh
```

`title-notification-check.sh` builds and runs a temporary, ad-hoc-signed Mac Catalyst app.
It compiles the **complete current `PlayerLandscape.x`** through Logos, plus the production
`SGMarqueeLabel` and design tokens/animation helpers. It creates the real
`SGRLandscapeLyricsController`, runs `viewDidLoad`, and posts both title notifications through
`NSNotificationCenter`; it does not extract helper bodies or call title handlers directly.
`SRC=/path/to/tweak/Sources` can select another source checkout. Build files are removed on exit;
a compile/runtime/assertion failure exits nonzero, and an in-app 15-second watchdog bounds execution.

The offline stubs provide player state with weak observers, cached title/artist answers,
artwork and karaoke views. `SGRedesignedUI()` is false only to skip automatic device-orientation
setup in the file's constructor; the controller's own notification registrations execute unchanged.
The title engine, lyric sources, AI providers, credentials and network clients are not linked.
No simulator is started. This focused check is independent of `build.sh` and its older missing
AI/lyrics symbols; it does not repair or validate the full simulator harness.

The assertions cover original metadata, asynchronous current-track title and artist updates
(including accessibility labels), no update before notification, irrelevant/malformed events,
an old track's delayed completion after a track switch,
NSURL and NSString track identities, settings disable/re-enable, paused playback, local/episode/invalid
URIs, and no player state. Title delivery leaves visible controls visible and hidden controls hidden.
Displayed labels are read directly: KVC's `title`
would resolve `UIViewController.title` instead of the marquee. Finally, weak references prove the
controller and label deallocate, the scheduled timer is invalidated, and both notifications after
deallocation are safe.

This checks title notification behavior on Catalyst,
not phone layout/rotation or translation-provider correctness; the separate translation suite is
not rerun here.

## Simulator harness

Run `/usr/bin/lockf -k /tmp/vitrine-build.lock python3 harness/player/ui-check.py preview-tap`
for issue #36. With Full screen cover on tap off, a synthesized finger taps Spotify's
mock lyric preview inside a selectable cover cell. While the redesigned line masks the
preview, UIKit selects the cell and lyrics stay closed. When the line gives the preview
back, a tap opens lyrics without another selection. The runner uses a disposable simulator
and temporary build; `SRC=/path/to/tweak/Sources` selects alternative production sources.
`preview-pending` holds the lyrics until after that tap and checks a second touch, a track
change and a close/reopen each discard the request, while an uninterrupted tap still opens lyrics.

`python3 harness/player/ui-check.py settings automix` builds once and runs both assertion
scenarios on one owned simulator, then shuts down/deletes it and removes the build.
The individual `settings-check.sh` and `automix-check.sh` entry points select one scenario.
Settings holds clip and image replies until the stale-track or dismissal boundary; screenshot
rehearsals are not part of either run.
Presentation and dismissal advance from UIKit completions, and delayed last-song artwork
advances from a held reply and the displayed image, not a one-second download allowance.
Chip text is laid out before checking its bounds.

`python3 harness/player/ui-check.py share share-system` links the real `ShareCards.m` and
`LyricCardPicker.m`. It shares a song card, shares a lyric card through the picker's action,
and launches a fresh process for a plain UIKit text share. It checks card pixel dimensions
and off-main drawing, and logs renderer time, UIKit initialization, synchronous presentation,
presentation completion and main-run-loop heartbeat gaps. Presentation latency is measured,
not asserted against a machine-dependent threshold. The runner owns and removes its simulator
and temporary build; no existing simulator is used. This is a manual scenario, not a separately
registered `harness-plan.py` entry.

Spotify's full screen player mocked under its own class names and accessibility identifiers
(from `trees/clean/player/01.txt`), so the redesign's player can be laid out, animated and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/PlayerHarness.app
    SIMCTL_CHILD_HARNESS_SCENARIO=artwork xcrun simctl launch --console-pty <udid> com.vojta.playerharness
    xcrun simctl io <udid> screenshot shot.png

Launch it on a simulator by UDID; it has a scene delegate (`../scene.m`), so the iOS 27 runtime runs it
too. `SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other
sources, for example an older commit, to see a bug before its fix.

`build.sh` runs `logos.pl -c generator=internal` over `PlayerLyrics.x`, `PlayerArtwork.x`,
`PlayerControls.x`, `PlayerFooter.x`, `PlayerScroll.x`, `PlayerField.x`, `PlayerHeader.x` (the glass circles of
the down arrow and the ⋯, in a mocked `HeaderElementsUnit`, and their press), `DJPlayer.x` and the Kit's `SGRBridges.x`, and links them with
the real `Core/`, `Redesigned/Kit/`, `SGRKaraokeView`, `Settings/`, the Player page and the Visualizer (`PlayerVisualiser.m`, `SGRSpectrum.m`). `stubs.m` stands in for the hooks the harness
does not compile (the Kit's accent and repaint, the rest of the player, the lyrics store, the haptics,
Sing's mic) and plays a mock player: `SGRHarnessSetTrack` reports a track, with the image ids Spotify's
metadata carries, to every state observer. A song of ten timed lines plays on from launch. `main.m` also answers
for i.scdn.co through an `NSURLProtocol` handed to every session, so each picture the Kit fetches can
come late, out of order, or not at all.

`HARNESS_SCENARIO` picks what the harness does:

- `lyrics` (default) opens the lyrics at 2 s, closes them at 6 and opens them again at 10.
- `cancel-dismissal` drives both outcomes of an interactive transition with the lyrics scrolled.
  `late-wide` on a regular-width iPad with `HARNESS_NO_ARTWORK=1` delivers the first artwork after layout,
  then checks that the two-column queue glyph stays level with Lyrics with and without space for the Agent prompt.
- `look` plays one track, then a track from another album at 8 s, whose picture reaches the screens
  0.4 s later. It shows the field, the moving background and its crossfade, and the footer row, with Spotify
  9.2.0's plain view over the strip under the bottom stack. At 3 s it checks that touches at the middle and 8 pt
  under it of the queue and AirPlay glyphs on the lowered footer row (issue #54) reach the row. From 10 s it
  switches to a podcast episode's player (a footer unit of its own in its own bottom stack, its row not hanging
  out) and back as Spotify does, its views taken out and put back on top, twice and then once with no layout of
  the episode's row between: the episode leaves no band in the player and its Lyrics takes its touch, and each
  track after it takes those touches again with one band. Lyrics stays on the row both when the footer grows
  to fit the Agent prompt and when it shrinks back. The log ends with `look checks: n of 25 right -- PASS`
  or `FAIL`, and the app exits with it; on the sources before the fix it read 6 of 23.
- `artwork` is issue #58. Tracks change while the covers on screen lag behind (3.5 s late, past the
  Kit's last look), two skips come in a row with the older picture answering last, and one track plays
  offline. Each step checks by color that the Kit and the field show that track's picture, and the log
  ends with `artwork checks: n of 4 right -- PASS` or `FAIL`. Before the fix it read 1 of 4.
- `landscape` turns the lyrics sideways at 3 s, puts a line's meanings over them (the real
  `MeaningSheet.m`) at 4 s and takes them away at 9, then pauses at 14.5 and resumes at 15.5. Each step
  logs whether the controls are up and whether a touch on the lines lands on the lines or on the shield
  that brings the controls back, with `ok` or `WRONG`. At 6 s it logs the sheet's frame: a card inside
  the safe area with a grabber, where the sheet before it covered the whole screen. It also logs that the
  window comes up clear and fades in, dark, that every button has a label and 44pt, and at 22 s that
  VoiceOver's escape takes the screen away and gives the key back to the player.
- `scroll` moves the list up and down in code and logs whether it stayed at its top, then scrubs a mock of
  the progress bar's slider in code (issue #172): the list's pan off while it tracks, back at its end, at a
  cancel and when the slider leaves the window, and a pan that was off already left off. The log ends
  with `scrub checks: ... -- PASS` or `FAIL`.
- `controls` checks the shared ordinary/DJ glyph helpers: owner/key identity, centering and the DJ offset,
  autoresizing, front ordering and reparenting. Then, with shuffle and repeat both hidden (switched on at launch and
  off again before it exits), a mock of the controls row (five holders, Spotify's identifiers, a 366 pt stack in a 390 pt
  unit): previous and next a third of the room between the 32 pt margins ((390 - 64) / 3 pt) either side of play, still there after repeat is taken out and the controls lay out, after a new
  repeat is put in (hidden at once), and with repeat's end swapped for a bare placeholder and then a new holder; the
  emptied ends take no touches, so a touch on next where it lies over repeat's end is next's; right to left mirrored; in
  landscape and for a podcast's row in the same holders, Spotify's places and the ends' touches back. The log ends with
  `controls checks: n of 18 right -- PASS` or `FAIL`; it exits with the result, as does `scroll`.
- `cover` is issue #27. The cover is checked untouched first, drawn as the Music app's (24 pt in from the
  sides, its top 33 pt under the safe area, on a 402 pt iPhone), taking touches where it is drawn (5 pt under its
  top, through the header row, the stack of elements inside it and the stack holding it, as 9.2.0's are) with VoiceOver's frame and activation point there; with
  Hide where it plays from switched off through the Player page's row, under the header row, which keeps its
  touches, and under where the row is now as its stack is moved 8 and 48 pt lower and back with no layout of the
  row (never below Spotify's own place), and no longer under it once it is moved out of the player within the window,
  and back at the Music app's top once switched on again; then given Spotify's layout for a track with lyrics, a
  smaller cover over the lyric preview, which keep Spotify's sizes with the cover's top where the Music app's is, as
  the Kit reports. A control shown in the put-away row over the cover (an iPad side panel's button) takes its
  touches, the row's band on the cover goes to the cover, and beside or over the cover stays the row's. Last, with
  nothing of Spotify's switched off: the row moved to another stack in the player and out
  of it leaves the stacks it left taking the strip as before, and back it lets the strip through again; another
  ordinary header put in its stack, beside the old one and after it, lets the strip through; that one released and
  the AI DJ's header put in the same stack, its row and button take their touches; the row put back, the strip is the
  cover's. Moving the artwork band back up 135 pt without resizing the tilt must leave the cover at its original
  window position. The log ends with `cover checks: n of 15 right -- PASS` or `FAIL`.
- `immersive` selects Keep the title, opens the lyrics and waits past the rest: only the bottom stack under the title row
  (progress bar, buttons, volume row, footer) fades, the lines grow down only, a touch where the buttons
  were lands on the lines, the thumbnail takes its own, and the lines' tap is off. Then the tap that
  wakes them (fired in code), a scroll that hides them again, and another wake before the thumbnail closes the lyrics.
  Reopened with the default (Everything), a sheet keeps the controls up past the rest. Once it has
  gone, the title and thumbnail fade too and the lines grow up and down. Sing's mic still takes its own touch, and a finger held on the player (its
  touch watcher driven in code) keeps the controls up until it lifts. The log ends with
  `immersive checks: n of 17 right -- PASS` or `FAIL`.
- `badge` shows the hold's 2× badge on the cover by hand, holds again while it fades out and lets go.
  The log ends with `badge checks: n of 3 right -- PASS` or `FAIL`.
- `lyric-line` and `lyric-line-clip` switch Lyrics Line on (PlayerLyricLine.x; off in every other scenario) with
  one sung line and no chip over the title. Both check the compact slot above the title,
  the live change from the preview font to 17 pt and back, with and without a translation.
  `lyric-line-switch` uses the same clip fixture and checks clip → cover → clip without changing the words.
  `cover-empty-strip` uses the same retained strip with the line off, `lyric-line-empty-strip` with it on but no synced lines. The shown switch keeps the native
  319 pt tilt; hiding it fills the 345 pt column at the same top without moving the rows; other material
  fading in or reattached in the strip restores 319 without laying out the floating unit. `cover-strip-preview`
  keeps Spotify's native 273 pt square while its lyric preview shows below it, including when the preview returns.
  `lyric-line-owner` and `lyric-line-owner-clip` reproduce the 393×852 Spotify 9.2.0 field trace:
  two seconds after opening, the bottom stack grows 40 pt around a 32 pt floating unit and the native
  345 pt square becomes a top-aligned 319 pt square. The identified button has a clear child drawing
  a layer-backed pill and a hidden sibling. The checks cover the 8 pt gap, the reserved artwork with and
  without translation, the final hidden branch in the bounded diagnostic, unit alpha zero and chip removal.
  The real VideoSwitch hook detaches the button while the fixture retains its strip; the reserved cover
  must keep its no-line top both during playback and under a live header. `video-native`, `video-default`,
  then `video-relaunch` check the two unset defaults, stock, and an explicit show across launches.
  `lyric-line-chip` and `lyric-line-chip-clip` compare chip clearance and the restored preview slot for
  one row, two rows and translations, including the video switch's inset label and a material-only
  switch whose hosted pixels are not exposed as layer contents. Hidden, masked, transparent,
  collapsed and out-of-area switches must not raise the line. `lyric-line-chip-live`
  changes chip opacity, position and visibility without driving player layout. With `HARNESS_QUEUE_SHEET=1`
  it expands the real Queue sheet over the line and checks the stopped clock and the words on dismissal. `lyric-line-chip-record`
  reads the process log after a tick-only backing-layer change, 100 translations of the unit and an
  off-pill shape mask; it checks the final reported frames as well as the lyric slot.
  `lyric-line-long` and `lyric-line-vo` check the first
  long lyric before the view has a frame, and opening lyrics by accessibility activation.
  `lyric-line-clip` is Animated artwork as in `motion` (it needs a portrait `HARNESS_CANVAS_FILE`) and checks
  the same preview frame over the clip. Both are run by hand; the log ends with
  `lyric-line passed`, or the failed check and a nonzero exit.

  `settings` checks that Size immediately follows Lyrics Line and offers just 19 and 17 pt.
  Set `HARNESS_SIZE_SCREENSHOT=1` to stop on the two rows instead of continuing the settings suite.

- `motion` is Animated artwork. The clip, `HARNESS_CANVAS_FILE` (any mp4, `harness/fluid-clip` writes one),
  is served as the track's Canvas before the player's background has laid out; then the background lays
  out, the lyrics open and close, the background is built again, and the ⋯ menu's switch goes off, on, and
  off with the player out of its window. Each step is checked (the clip on the field, the cover hidden, the
  poster under the video and the Fluid field held under it, the foot and the blur, the thumbnail, the clip
  and the cover crossing over half way through the switch). Then the song pauses and plays (the clip's rate
  0, then 1), a mock of Spotify's video unit attaches and detaches its video (the clip goes and comes back),
  a track comes with no Canvas and then again with one (the clip comes in late), and a skip to a track whose
  clip is in the store keeps the last clip until the new one is over it, the cover hidden throughout. The clip's
  dim is checked over the clip and 0.15 darker under the lyrics, with the rule at its ends; `HARNESS_DIM` is the
  dim the clip should get (`ffmpeg -f lavfi -i "color=c=white:s=360x640:d=4"` gives 0.54, black 0.10). Uninstall
  the app between clips, or the store answers with the last one. Then Low Power Mode, which the process is made
  to report (the simulator has none; Reduce Motion takes the same path), takes the clip away for the cover over
  Fluid and gives it back once off. Reported Serious heat also clears the clip, and cooling to Nominal brings it
  back. A track change with the app made to report the background takes the clip
  away at once, with no fade. The foot checks retain the seam-to-bottom geometry and require opaque
  colors. A synthetic poster with green above its last 3% of rows and a red left half and blue right half in
  those rows checks that the real motion view renders a foot red at its left edge and blue at its right,
  blended across the middle (issue #39) rather than meeting in a hard edge as stretched pixel columns would
  (issue #40), and with nothing of the green above. A gray poster checks that the picture gets darker from
  where the dim is whole down to the bottom, never lighter than the dim alone. The band at the top is checked
  with where it plays from hidden (whole to the window's safe area top, the status bar) and shown (over the
  header's row), and the stored switch is put back. `HARNESS_MOTION_SCREENSHOT=1` stops after those checks,
  with the clip as it opened, for a screenshot (store `spotifyglass.redesign.player.hideContext` NO in the
  app's defaults first to show where it plays from).
  The log ends with `motion checks: n of 30 right -- PASS` or `FAIL`.
  `HARNESS_CANVAS_FAILS=n` fails the first n requests for the clip on the way: with 1 the store tries again and
  every check passes, with 2 the clip never comes.
- `catalog` is Apple Music's catalog (`SGMotionCatalog.m`) behind a stub of its search: the names searched
  without their edition, an album search for "Midnights (3am Edition)" asking "Taylor Swift Midnights" and taking
  the edition of that same name before the standard album, then a 429 and the next album finding nothing at once
  with nothing asked. The log ends with `catalog checks: n of 5 right -- PASS` or `FAIL`.

- `settings` opens the redesign's Player page (`PlayerSettings.m`, with the real `Settings/` framework) over the
  player at 3 s, with the clip of `motion` in. It checks the card leads the page with the five backgrounds'
  segmented control under it, every name whole, the Mini player section's three rows are on the page, and then,
  as the control picks each in turn, that the card shows Animated (the clip, the sources and Low Data Mode's rows
  in), Fluid, Colors, Still, Visualizer (the hills over Fluid held still) and Animated again, with a note for
  each and the header the same height throughout. The log ends with `settings checks: n of 8 right -- PASS` or
  `FAIL`.
- `preview` opens the Player page with the background Still at launch, so the player looks up no clip, and picks
  Animated on it. The card looks the track's clip up itself: nothing is asked for before the page or while Still
  shows, the card is Fluid while the clip comes (`HARNESS_CANVAS_DELAY`, 2 s), then the clip is in it with its
  poster and the field held, the player still without one, and the file in the store, where `SGMotionFile` finds
  it without asking the server again. Fluid and then Animated again bring it back at once. The clip's address is
  the run's own, so the store never has it from a run before. The log ends with
  `preview checks: n of 7 right -- PASS` or `FAIL`; on the sources before the fix it read 5 of 7.
- `card` plays nothing and opens the Player page at 1 s, then logs the card's title, artist and cover size: with
  no track ever played, Not Playing over the accent's gradient; with `HARNESS_LAST=1`, a last track played with a
  long title (gliding), its cover from the picture server and a Canvas of the run's own (`HARNESS_CANVAS_FILE`).
  `HARNESS_BACKGROUND` is the background's index, Fluid if unset. For screenshots: 2026-10-06 on an iPhone 17 Pro,
  iOS 27.0, the card read Not Playing over a dim green field, and Holocene with its cover over Fluid.
- `visualiser` plays the Visualizer background, fed by `stubs.m`'s stand-in for the audio effects' reader: a song
  of its own at 120 beats a minute, handed over in buffers of 1024 at 48 kHz. It checks the hills stand on the
  Fluid field held still with the reader on and the link at up to 60 fps, blur behind the lyrics with the link at
  30, settle and stop with the reader off on a pause, come back on play, and go and come back through the ⋯
  menu's switch to Fluid and back. The log ends with `visualizer checks: n of 7 right -- PASS` or `FAIL`.

- `header` is the header as the Music app's (`PlayerHeader.x`): Spotify's down arrow and ⋯, each a `UIControl` under
  Spotify's identifier, are put away (alpha 0, hidden from VoiceOver, a touch at their middle reaching neither) and
  the ⋯ is handed to the menu; the grabber is the Music app's 60x4 pill 7pt under the safe area's top, centered, a
  button VoiceOver reads with the arrow's words, whose whole touch area of at least 44x44 takes touches (each corner
  and its middle hit-tested in the window), and its activation, its escape and a finger's tap at the area's top edge
  (`../tabbar/touch.m`) each close the player by the arrow's action. The grabber stands in the player apart from the
  row: with the row moved one row height lower with no layout of the header, as Spotify 9.2.0 moves it by its top
  constraint (a pill in the row rode along to 114pt, where the phone had it), the pill stays, sits in the middle of
  its 44pt touch area and a finger on it closes the player. With the lyrics up and left alone (Everything), the
  pill fades with the row and takes no touch, and the waking tap brings it back in the same turn as the row. A row
  Spotify still holds that leaves its player takes the grabber with it, with no layout of the header: taken out of
  the window it leaves no close button, put back it has the grabber again, and moved straight into another view of
  the same window the old player at once routes nothing (no touch, no activation) and loses the grabber by the next
  layout. The log ends with `header checks: n of 19 right -- PASS` or `FAIL`, and the app exits with it. The ⋯ beside
  the title is the menu's button, which this harness does not build; `harness/system-menu`'s `beside` run covers it.
- `header-inset`, run on an iPad (whose window has a top inset only while its status bar shows), is the `header` run
  up to the touch area, then hides the status bar and shows it again with no layout of the header reaching the
  redesign: with no inset the pill is 7pt under the player's top and the whole 44pt touch area, the pill in it, is
  in the player (each corner hit-tested) and a finger at its top edge closes the player; with the inset back the pill
  is back under it. `header checks: n of 11 right`.
- `header-noroute` is the same header with an arrow that has no action to close by: the arrow stays drawn, read by
  VoiceOver and touched, the ⋯ is still put away, and the grabber is only drawn (not read, not touched, its
  activation and escape answering NO). `header checks: n of 6 right`.

- `timerow` is the time row under the progress bar (`PlayerControls.x`, `Shared/Player/AudioQuality.x`) on a mock
  of Spotify's bar (trees/clean: a 17pt slider, 11pt digits in 15.33pt Encore labels), Spotify reporting High. It
  checks the digits at least 12pt under the bar and the badge at least 8pt under it with its text on the times'
  baseline (the Music app's player: 14pt and 9.5pt), the badge's words (High Quality), its shape and fill as the
  Music app's (18.33pt tall, circular corners a capsule's are not, light 17 of 255; issue #27, 12 of 13 before it)
  and a more opaque fill under Increase Contrast, the bar's fill and track
  translucent (opacity 0.5–0.7 and 0.15–0.25), the fill lit whole and the times a step lower while a finger scrubs
  (the badge staying put) and back after, the details (glyph, tier, About 160 kbps, a sentence, the footnote naming
  Spotify's High), and the native look's badge as it was (Spotify's word, centered on the times). The log ends with
  `timerow checks: n of 13 right -- PASS` or `FAIL`; on the sources before the time row's change it read 3 of 10.

- `sponsorblock` is SponsorBlock's marks on the `timerow` mock of Spotify's bar as the redesign draws it
  (`PlayerControls.x`, `Shared/SponsorBlock/SponsorBlockMarkers.m`), run by `../sponsorblock/markers-check.m`: the
  engine's real session plays a song and two fixture episodes, and the drawn window is compared with the same bar
  unmarked. It checks each mark's color and extent on Spotify's episode bar and on the slider's own track, the Off
  and too-short segments left out, a next episode and a longer duration on the notification alone, a narrower bar,
  right to left, the scrubbed track's height, touches and accessibility unchanged, and nothing left by a song.
  `sponsorblock-off` checks that nothing is drawn with the switch off. `HARNESS_SHOTS=<dir>` (as
  `SIMCTL_CHILD_HARNESS_SHOTS`) receives `redesign-ltr.png` and `redesign-rtl.png`. The log ends with
  `sponsorblock redesign checks: n of 17 right -- PASS` or `FAIL`.

- `volumebar` is the volume row (`PlayerVolume.m`) beside the progress bar as the redesign draws it (the `timerow`
  mock), the Music app's two bars alike. On the row's Connect slider at half (the simulator does not draw
  MPVolumeView's) it checks the track 7pt as the progress bar's, the same fill and track colors, the fill's end square
  (its last columns as tall as its middle, drawn at 2x) inside round track ends, left to right and right to left, and
  a finger held on the fill's end (`../tabbar/touch.m`) thickening the track to 12pt with the fill lit, as a scrub does
  the progress bar's, and back after; MPVolumeView must hold the same track images and an empty thumb. Drags
  (`../tabbar/touch.m`) from the track's far end, left to right and right to left, move the volume by the finger's
  distance over the track (half to a quarter, and back), thickening it too; a tap there moves nothing, and a drag of
  the fill's end moves it once, with the finger. Halfway through a drag, a level from elsewhere (the Connect device's
  report; a hardware button's, on a stand-in for MPVolumeView's slider) stays, the drag going on from it, while a late
  report of the drag's own starting level changes nothing; and the Connect device going mid-drag leaves this iPhone's
  volume where it was and ends the drag's look. Run it with `python3 harness/player/ui-check.py volumebar`; the log ends
  with `volumebar checks: n of 17 right -- PASS` or `FAIL`.

- `seek` is the tap around the progress bar (`PlayerControls.x`): a mock slider with Spotify's identifier and
  the two times beside it. It checks that a tap counts below the bar and up to 12 pt past its ends, not on the
  thumb or the times, that the ends of the thumb's travel are the song's start and end, that a tap is played
  to the slider as touch down, value changed and touch up with the slider still tracking, that a drag nobody
  seeks for is seeked directly after a second, and that the slider lets go once the position is there. The
  log ends with `seek checks: n of 9 right -- PASS` or `FAIL`.

- `options` is the Player page's look switches and Fluid's Grain (`PlayerHeader.x`, `PlayerFooter.x`, `DJPlayer.x`,
  `PlayerSettings.m`, `SGRFluid.m`, `SGRFluidGPU.m`). It builds a mock of the AI DJ's header and footer units too (their
  mangled `Endless_DJMusicImpl` names) and the queue's `SPTEncoreIconView`, starts with Fluid drawn Smooth and every
  switch at its standard, and leaves layout to UIKit (no once-a-second pass), so a switch has to reach the open player
  by itself. It checks the glass circles in the AI DJ's header (the ordinary player's arrow and ⋯ put away, its
  header the grabber's alone, in either state), the Music app's Connect and queue glyphs over Spotify's, the
  quote bubble on Lyrics in both footers, the list on the AI DJ's Queue and the DJ button as a waveform over its masked
  disc; then, with the Player page over the player, flips Header glass and Music app icons off through their switches
  and checks the circles gone with the buttons' touches, grabber and accessibility kept, Spotify's own Connect glyphs and
  the queue's own colors back, Spotify's Encore microphone and queue glyphs (a mock `SPTEncoreIcon`, drawn by symbols of its
  own) on Lyrics and the AI DJ's Queue in their symbols' colors, the disc unmasked and no waveform, and a new device
  glyph Spotify draws while off left alone; then both on again. In both states, with the share button and its holder
  given their alpha and touches back as Spotify does (the holder over the DJ button in the mock), a touch on each of the
  AI DJ's four glyphs lands on its own control and nothing of the share button is drawn; a tap on Queue asks for
  spotify:now-playing:queue, and, off, two taps on Lyrics open and close the lyrics. Grain's
  row shows only while Smooth draws. Then what Spotify sets while the stand-ins show comes back exactly when they go:
  Connect cleared to nil and handed an image with no bitmap, the queue's two colors reset to nil, and a value set while
  they were out is not replaced by the record from the time before. With the song paused it reads the field's top band
  at Grain 0, 100 and 200 on Smooth (more grain each time, a visible one at 200) and on Light at 100, a second after
  the switch from Smooth, then 0 and 200 (all three the same pixels). The steps run one after another, each its delay
  after the last one ran: scheduled all at once from launch, `dispatch_after`'s leeway let two fire together with no
  layout pass between. Each state a screenshot is asked for (`options: screenshot <name> now`) holds two seconds or
  more. The log ends with `options checks: n of 25 right -- PASS` or `FAIL`, and the app exits with it.
- `renderer` is the switch from Smooth to Light on its own, five times with the song paused: the field read about 0.2,
  0.5, 1 and 2 s after it (each read's own time logged, with whether Smooth shows, the Metal layers in the field and
  the Light copies hidden), compared with the band read about 4 s after; the read a second after must match it. It
  uses only Kit API the committed renderer has too, so it also runs with HEAD's `SGRFluid.m` and `SGRFluidGPU.m` copied
  into a source tree (`SRC=`). The log ends with `renderer checks: n of 5 right -- PASS` or `FAIL`.

- `automix` is AutoMix's transitions in the player (`PlayerMix.x`, with `PlayerControls.x`, `PlayerQueue.m` and
  `PlayerArtwork.x`) and the AutoMix page's preview card (`Shared/AutoMix/AutoMixSettings.m`, `AutoMixPreview.m`), in
  `automix-scenario.m`. `stubs-automix.m` stands in for AutoMix's facts (the scenario makes them and posts their
  notification) and Spotify's three playback settings (posting their change as AutoMix.x's setter hooks do) and the
  upcoming tracks; the player's position runs on the clock.
  It checks the progress bar's bands on a mock of Spotify's slider (a known window from the knob at its start to the
  bar's end and behind every part of the slider, flat at the track's thickness in a faint white and rounded only at
  the bar's own end, unchanged by a seek, nothing for unknown times, an inverted window or no facts, the next song's
  incoming window after a blend and gone once passed, none after a skip), Playing Next's line over its first row
  (each kind's text and what VoiceOver reads, the secondary label's white at the regular footnote size, a change of
  facts that makes no row again, another pair, no facts, the option off, a row's tap still skipping), the page's card
  (off with a gray divider, beat-matched with its corners on the beats and rounded, crossfade at 1, 12 and 5 s with
  equal fades, changed while away and in Spotify's page while it shows with no facts changing, its rows, no setting
  written) and the stage over the cover (held back with the option off, its start, an edgeless cross-dissolve, done as
  the window ends, handed back on a seek back, the player hidden, faded or moved off screen, a new next song, facts
  whose times are no longer known or gone, another song, a pause and the player closing, back once it is still, the
  next song's cover held and given up 3 s after the window, held back by the lyrics, an inactive app, the wide layout,
  the player off screen, Reduce Motion, the AI DJ and unknown times, and no stage kept once the player is gone).
  `automix-check.sh` runs it in a simulator of its own; the log ends with
  `automix checks: n of n right -- PASS` or `FAIL`. `automix-mutation-check.py` breaks a rule of each area (two for
  the stage) in a copy of the sources and expects the check that guards it to say WRONG; it runs by hand when the
  check or the rule it guards changes, not in CI.

`stubs-tickets.m` stands in for `MotionSources.m`'s `SGMotionRequestClip` and is compiled only where the sources have
`Shared/AnimatedArtwork/SGMotionTicket.m`.

`HARNESS_VOLUME=0` leaves out the volume row that the phone has and the tree does not.

A screen recording is the way to see a move:

    xcrun simctl io <udid> recordVideo -f run.mp4      # ^C to stop
    ffmpeg -ss 7.4 -t 2.2 -i run.mp4 -vf "fps=5,scale=180:-1,tile=11x1" -frames:v 1 strip.png

It also lays every unit out once a second, which is what the transforms on Spotify's title row and the
narrowed marquee labels have to survive.

What it does not cover: the real element framework's autolayout, Spotify's own scrolled layout, the
player's open and close transition, and Spotify's real image loading.
