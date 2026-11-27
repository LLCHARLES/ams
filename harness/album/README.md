# Album harness

`python3 harness/album/beside-check.py --screenshots <directory> --mutation` builds
both album and playlist fixtures in a temporary directory and uses disposable clones
of iPad Pro 13-inch (M5) and iPhone 17 Pro. It checks portrait, live landscape
rotation, large text with a long title, RTL, live setting changes, oversized-text
fallback, compact traits, and unchanged iPhone frames at 430/390/320 pt.
It saves iPad header screenshots after the page's reveal and rotation finish, deletes its clones/builds, and rejects a temporary
mutant with the action row displaced from the leading edge. No Spotify controller is replaced.
The existing Album faces and row more lane runs these cases too, without the
one-time mutation build.

The iPhone frame literals in `beside-check.h` were captured on an iPhone 17 Pro
clone (iOS 26.5, default text size, motion off) with the same fixtures at
430/390/320 pt against committed header sources from
`fdd69a3ada5cc04638aac73a9882484a8bf37355`: `SGRHeaderInfo.m`, `SGRActionRow.m`,
`AlbumHeader.x` and `PlaylistHeader.x`. Those files came from Git objects into
a scratch source tree selected by `HARNESS_SRC`, never by reverting the working
tree. Both setting states must match these independent captures, including the
info/hero frames and visible title, details, description and action frames.
The creator and details literals (and what they move: the info's height, the playlist title, the album's
row) were captured again the same way after the header took the Music app's sizes (creator Title 3 regular,
24 pt high and 111 pt wide for the fixture's name, against Body's 21 and 96; details Caption 1 semibold, 15 pt
against Footnote's 16); every other literal is unchanged.
The iPad playlist also checks Card cover restoration after switching beside off,
compact width and replacing the source cover, with both nil and existing masks.

`python3 harness/album/layout-check.py --screenshots <directory> [case ...]` (`layout-check.h`, `layout <case>` on the
launch line) runs the album header through the changes an open page lives through, on an iPhone 17 Pro and an iPad Pro
13-inch (M5) of its own: `text-size` opens the page at Extra Small, changes the simulator's text size to Extra Extra
Extra Large once the page says READY, and requires the title, artist and details at Title 2, Title 3 and Caption 1 at
Extra Large (the cap), an artist header's Large Title the same, and that header's content measured again onto its
bottom edge; `resize-card` narrows the iPad page to 68% with Spotify's square re-centred and requires the hero's square
on it, then held while Spotify's square shrinks at that width, then widens it to 84% with Spotify centring its square a
pass after the header's width and requires the hero's square there; `beside-scrim` turns Cover beside off over a Full
screen cover and requires the contrast gradient back; `beside-faces` gives the artist line, beside the cover with its
face, names that fit the column on one line but not after the face, and requires them wrapped, not cut, with the details
under them. Each of those writes `album-<case>.png` before its checks. `measure` (iPhone) counts `sizeThatFits:` on the
header info's labels and requires none over ten header and info passes with nothing changed, some once the artist's
name changes (the line then as wide as the new name), and none over ten passes after. `chrome-card` (iPhone, Card,
`-coverTop 76` putting Spotify's square at {77, 76, 248, 248} as a 402pt phone measured it) requires the pinned download
and ⋯ at {298, 62} and {342, 62}, the square and its shadow at {96, 114, 210, 210}, the same moved up 120pt with the
page scrolled that far, Spotify's square again with download gone (⋯'s circle alone) and the smaller one with it back;
`chrome-card-rtl` the same with the pair mirrored onto the left; `chrome-full` the Full screen cover the hero's top
{0, 0, 402, 402} square under the pair.

The side-column checks require a 28pt cover gap, leading text/actions (mirrored in
RTL), a description wrapped below the row, and action sizes identical to the
stacked header. The pale strip in the default album artwork is intentional:
`drawScannedSleeve` in `harness/album/cover-fixtures.h` paints its bottom 18 of 300 pixels.

Spotify's album page mocked under its own class names and accessibility identifiers
(from `trees/clean/album/03.txt`), so `Redesigned/Album/` can be laid out and looked at
on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/AlbumHarness.app
    xcrun simctl launch booted com.vojta.albumharness
    xcrun simctl io booted screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over the album's `.x` files and the redesign's AMOLED rule
(`Kit/SGRAmoled.x`, so the page is painted as on the phone: a low grey field shows black) and links them with the
real `Core/` and `Redesigned/Kit/` sources; `stubs.m` stands in for the two hook files the harness
does not compile (`SGRAccent.x`, `SGRRepaint.x`).

The mock is the page as Spotify builds it: the color wash behind the header, the header itself down
its four stack views, the metadata row as a real collection view with its own cells, the action row of
explore, add, download and more, the two controls Spotify floats over the page outside the scroll
(shuffle and play), and a list of track cells followed by the footer Spotify sends — the album's own
line, the copyright, and the headings and carousels of more by, videos, merch and you might also like,
each with the 16pt spacer between them.

At 1.5 s it measures the footer the way the page's collection does, asking every cell
`preferredLayoutAttributesFittingAttributes:` and stacking the answers: that is where `AlbumSections.x`
answers 0 for what it drops, and the log says how much footer was left (108pt of 1489pt, the album's
own line and its copyright). A switch is turned off from the launch line, as an argument default, and
brings its section back: `-spotifyglass.redesign.album.hide.merch NO` measures 374pt, `.moreBy` 371pt,
`.videos` 412pt, `.youMightLike` 370pt, and `.other` 367pt for Fans also like, the section no switch names.

Since 2026-09-18 the header is the Kit's `SGRHeaderInfo` over Spotify's blanked column, so what follows no
longer tests anything the redesign moves; it still shows Spotify's column staying blank. The metadata row's
cells arrive after the header's pass, which is what `AlbumHeader.x`'s re-read answers.

`late` on the launch line (`xcrun simctl launch booted com.vojta.albumharness late`) opens the album the way a
first open has it, with no add in the row, and adds it at 2.5 s as an arranged subview of the row, which lays out
nothing above the row. At 3 s the log says what the row shows on Play's right: "Add" once `AlbumHeader.x` watches
the row, "Download" before it did (issue #19).

At 3.5 s it puts Spotify's own frames back on the title block, its stack and the action row and asks
both groups for a layout pass, which is what the redesign's `SGRObserveLayout` watches have to survive.
The log says what the redesign answered with.

`motion` on the launch line, with `SIMCTL_CHILD_HARNESS_CANVAS_FILE` set to any mp4, hands the hero that clip at
2 s the way Apple Music's catalog would. The log says the clip was added at opacity 0 and not yet fading, that by
2.5 s its first frame was ready and it had faded in and was playing, and that taken out of the window at 4.5 s it
stopped and put back it played again.

`bash harness/album/motion-visibility.sh` creates a temporary CI simulator; locally pass the booted Vitrine UUID. With
Pillow and ffmpeg it builds a numbered 720px clip. The host samples the composited album and artist
headers through a cancelled and completed interactive pop, a held seek, failed seek and delayed AV surface;
the resumed video itself must match the crop, number and scrim seen before the push. It also exercises
replacement, failed capture, warnings, backgrounding, clipping, coverage, Reduce Motion and the Fluid
layer and clip's response to thermal and Low Power Mode changes posted off main. The final reading
compares the same five stacked pages with and without their stills and checks queue and output teardown.

`SGLog` goes to the unified log rather than stdout, so the redesign's own lines are read with

    xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "spotifyglass"' --style compact

What it does not cover: the real element framework's autolayout and the heights it measures, the page
scrolling (Spotify fades the header out by alpha as it goes, which the mock does not), and the flags
`AlbumField.x` forces.

`download` on the launch line plays the download button's states instead of the header's (issue #65), from
`../download-mock.h`: Spotify's button drawn by Lottie with no image view, its state in its accessibility
identifier and in a mock of the Encore object behind it (`currentState`, `progress`), and shuffle's "on" dot.
None, waiting, downloading (held at 50%), downloaded, shuffle on, removed with shuffle off, error, each held a
few seconds and announced with a `[harness] state:` line to take a screenshot on. Nothing in it lays anything
out, as on the phone.

The track rows carry Spotify's explicit badge on some of them and two guests the header does not explain (one named
in the title with no "feat.", one not at all). At 2.5 s the log says, row by row, whether its artist line was
dropped, how far the title moved and where the badge was drawn against the end of the title's text; at 4 s the first
row is prepared for reuse and has to come back as Spotify drew it, then be dropped again by its next pass. At 3 s
the log also says the first card of each carousel, painted the base surface, was cleared and the gray one was not.

The artist row's picture (an `Encore.ImageView`) gets its image at 1.5 s, after the header has laid out. At 2.2 s the
log says where the redesign drew it: a round face a line and a point across just before the name, 8pt off it, the two
centered together (`{{138, 370.33}, {22, 22}}` and the name at `{{168, 371}, {96, 21}}` on an iPhone 17 Pro).

`faces-more-check.sh` (`python3 scripts/harness-plan.py run --names "Album faces and row more"`, after `build.sh`) runs
two scenarios of this harness in a simulator of its own and asserts them. `faces` (`faces-check.h`) builds the artist
row again for one to four artists, a hidden face, one under a hidden view and a square badge after the names, pictures
that land late or are emptied, pictures landing in views hidden since the header's pass, a row whose name is only its
accessibility label with a square badge after the faces (no faces), five layouts that change nothing (no cut-ring
path made again), the header reused for another album, and the rows the phone dumped
(`.mixdog/review-shots/phone-v100/trees/*-artist-parent-annotated.txt`: Trio, Love for Sale and 21, each face a 24pt
square avatar holding its initial letter and a clipped image view, Trio's last one 32x24, the names in one label after
them; every artist's face must show, and with Dolly's picture or the square clipping it hidden while her initial
shows, the other two), and checks the Albums page's Artist picture
(`spotifyglass.redesign.album.artistPicture`) against the spec: at most three faces in the row's order, each
min(ceil(line height) + 1, 22) across, round(0.85 x that) apart, 8pt before the name, centred with it, a clear 1.5pt
ring around each face cut out of the next (read off the drawn pixels), a tap on them the line's (Spotify's row fired
once), not accessibility elements; switched off live, the name alone centred with no room kept. It runs left to right,
right to left (`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`) and at the largest text size, where the
22pt cap holds. `more` (`more-check.h`, on `-coverFixture colourful`) gives track rows a baked white ⋯, Spotify's template
symbol, one that lands late, one replaced by another picture, none, one under a mask of its own and one reused as no
track row, and reads the drawn glyph in OKLab: lightness 0.80 (0.88 with Increase Contrast, set on the simulator), the
page's hue, chroma at most min(page's, 0.08) and at least half that; white and unmasked where it is to be left alone; ⋯'s action and what VoiceOver
reads unchanged. `SHOTS=<dir>` keeps
`album-faces-two-on.png`, `album-faces-two-off.png`, `album-faces-trio.png` and `album-more.png` (and the variants, suffixed).

The pinned download and ⋯ are watched from the first frame the page draws: after every Core Animation commit while the
field's veil is up and a second past it, ⋯ must have glass behind it, its own or download's capsule with download
right under ⋯ in the page, nothing (the veil) between the two. "PASS pinned hold: N frames, M under the veil" or
"FAIL pinned hold" with the page's top subviews at the first bare frame; `verify-actions` checks it and logs then exits nonzero on failure. `rtl` lays the page
out right to left (its `semanticContentAttribute`), and `verify-actions` then expects ⋯ 16pt in from the left edge,
download on its right, the 88x44 capsule the left-to-right one mirrored ("pinned frames rtl" against "pinned frames
ltr"). `freeze` pauses the veil's fade and holds the main thread 4 s on the first frame under the veil, for a
screenshot of what a page opening shows.

`veil` on the launch line, with `-spotifyglass.redesign.hero.scrollVeil YES`, checks the page headers' scroll veil
(`Redesigned/Kit/SGRHeroVeil.h`, `hero-veil-check.h`): the blur's radius and the dim's alpha at the spec's distances,
the picture's parallax and pull zoom, the dim in the page's color and the header fading in over the 14pt under the top
bar; `veil-card`, with `-spotifyglass.redesign.album.fullCover NO -spotifyglass.redesign.album.motion NO` as well,
checks the same blur and dim on the square's picture alone, the square left where it is; `veil-off`, without the
setting, checks that the artwork has no blur or dim and does not move, while the album text still clips under the
top bar and is unclipped at rest. Each holds d = 0, 190 and 400 (with the veil on, "mid" too: the title half
under the bar) for screenshots first, then exits 0 or logs a FAIL and exits 1. `veil-check.sh <UDID> [OUT]` builds this, the playlist and the artist harness and runs all of
it, the artist's Play checks too (`../artist/README.md`), with the screenshots in OUT.

`cover-check.sh` checks the picture-aware cover (`-spotifyglass.redesign.album.adaptiveCover`, Full screen only;
`Redesigned/Kit/SGRCoverRead.h`, the hero in `Redesigned/Album/AlbumHeader.x`) as Mac Catalyst programs, no simulator
(`python3 scripts/harness-plan.py run --names "Album cover"`). The covers are drawn in code (`cover-fixtures.h`).
The hero builds compile the redesign's AMOLED rule (`Kit/SGRAmoled.x`) as `build.sh` does.
`cover-read-check.m` reads each: solid dark, light and red sleeves with centred art, the same sleeve broken along 8% of
its border (still solid) and with art over 72% of it (not), a tiny logo on black, a dark cover with a large orange
accent, the old rectangle portrait (confirmed to produce zero real Vision faces) with an injected face box through
the foot to check exclusion, a softened drawn face detected by real Vision with a sharp boundary below it,
colourful bands, Vision failing, a transparent
and a too narrow cover, the same picture twice (the cache's reading), and page colours brought into sRGB by chroma
alone. `cover-hero-check.m` draws five of them in the album's hero on a page with its field: the field in the read
colour, the cover itself down to where the spec lets it stop being sharp, the drawing over it from there continuous with
it and ending in the colour the field paints just under the hero (read off the rendered field, the hero's gradients
composited over the drawing; at most 2 levels apart), and the title's area held to L 0.58 over 90% of it. One of them is
Adele's 21 as the phone showed it (`darkPortraitCover`, `dark-portrait`): a black-and-white portrait reading #0D0C0C,
which the AMOLED rule paints black. The scanned sleeve checks the
pale border and reflected square edge, including the actual layer composition: adjacent-row mean absolute linear
sRGB luminance difference must not exceed 0.02 within 24pt of the edge. The layer composition also checks
24pt above the scanned sleeve's stripe at 94% through the square's extension; the drawing must be opaque.
`rebuilt` hands the hero a replacement artwork view and requires the retired one's later pictures ignored, then rebuilds
a header under the page's own header pass: the cover element gone for one pass, then back with the replacement still
under the lookup's 80pt. A picture landing in the retired view after either pass is ignored, and the replacement's is
taken once it is sized and filled on passes of its own, with no header or page pass between.
`still-swap` reuses a hero from A with a clip to B without one: both an installed still and late poster/read replies
must leave B blue. A -> B -> A reuses the identical clip URL and checks both delayed stages against the new album
lifetime, then accepts its current still. Media lookup, poster delivery and player readiness are test doubles;
the field and hero are real. `cache-reuse` aliases only the address prefix of cache keys after the first source
deallocates; a mirrored cover with identical size, page colour and geometry must draw blue, not the old magenta.
`motion-identifiers` gives the page controller an album URI. An identifier clip starts immediately; only a
confirmed miss opens the title search and then the candidate rows. An unanswered request stays still.
A still edition can move only if the year-restricted title search returns a clip. `motion-verified` checks
that a downloaded clip verified for this URI wins over a conflicting cached answer for the same title.
`Kit/SGRCoverRead` is not modified.
The blur reaches its maximum over 40pt rather than 80pt: 80pt left a measured 19/255 step at the scanner border.
Also checked: a cover replaced mid read whose
colour never reaches the page; and, with the setting off, the hero written to a PNG. `BASELINE=<rev>` draws that
revision's off hero too and requires the same bytes.

`-coverFixture colourful|portrait|darkAccent|solidLight|solidDark|darkPortrait` on this harness's launch line shows one of those
covers instead of the scanned sleeve (`portrait` uses the real-Vision drawn face), and `cover-stats` logs the process's memory footprint and its peak at 6 s with a
`[harness] SHOT album-cover-<cover>-<on|off>` line; the hero's own log says how long the read and the drawing took.
The drawing log separates queue wait from rendering and reports canvas, blur, colour mix and title measurement
times on the utility queue. The transition image is capped at 2x; the sharp cover stays at native display scale.
The radius bands use Gaussian blur rather than an all-white variable-blur mask: the latter did no spatial
masking but consumed 2249ms of a measured 2404ms warm dark-accent render.
`cover-stats` also writes the unmodified fixture to the app's Documents/cover-fixture.png for pixel comparisons.
`cover-profile -spotifyglass.redesign.album.adaptiveCover YES -spotifyglass.redesign.album.motion NO` changes
through the five fixtures in one process, so stage timings include the normal reused CIContext, not only cold
application launches. It exits after the final cover; timings are in the unified log.
Use `-spotifyglass.redesign.album.motion NO` for fixture screenshots, otherwise the album's fetched animated
artwork can replace the fixture before the screenshot marker.

`stubs.m` also stands in for `SGRegisterCustomFont`, which `Shared/Fonts/Fonts.x` calls and which lives in a file
that pulls in the settings rows.
