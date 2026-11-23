# Playlist harness

The shared `python3 harness/album/beside-check.py --screenshots <directory> --mutation`
also exercises this header's cover-beside layout, live setting, resize, RTL and
Dynamic Type fallback. It builds and runs both fixtures on disposable simulator
clones and keeps only the requested screenshots.
Card mode additionally checks exact restoration of Spotify's cover layer mask,
hidden state, interaction and accessibility after beside mode ends or the cover
is reused. `HARNESS_SRC` selects a scratch source tree for committed-frame captures;
the shared album harness documents their provenance.

Spotify's playlist page mocked under its own class names and accessibility identifiers
(from `trees/clean/playlist/01.txt`), so `Redesigned/Playlist/` can be laid out and looked at
on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/PlaylistHarness.app
    xcrun simctl launch booted com.vojta.playlistharness
    xcrun simctl io booted screenshot shot.png

`build.sh` runs `logos.pl -c generator=internal` over the three `.x` files and links them with the
real `Core/` and `Redesigned/Kit/` sources; `stubs.m` stands in for the two hook files the harness
does not compile (`SGRAccent.x`, `SGRRepaint.x`).

Two seconds after launch the mock puts Spotify's own frames back on the column and the action row
and asks both for a layout pass, which is what the redesign's `SGRObserveLayout` watch has to survive.

The page opens mid load, with the cover smaller and the block higher than they settle at, so the
picture has to grow to its final height and then hold it. Then it plays the three states the header is ever in, with the frames Spotify sets in each
(`trees/continuous/1.txt`, `2.txt` and `4.txt`): at rest at 4 s, collapsed at 8 s, pulled down past the
top at 12 s (block moved down and grown, as on the phone). Each logs where the hero landed in the window; collapsed it belongs off the top of the
screen, not pinned to it. At 16 s it fades Spotify's cover square and color wash back in the way a
scroll does, with nothing laid out, and reports what the redesign's scroll pass made of them.
Back at rest the hero must be the height it had at 4 s: a hero that kept its pulled height is clipped by the plane and loses its dissolve.

What it does not cover: the real element framework's autolayout, and the flags `PlaylistField.x` forces.

`rows-check.sh` runs `PlaylistRows.x`'s row pass on a 402x64 track row with its 48pt artwork, as a plain executable in a
simulator of its own: the separator runs from 12pt after the artwork to 16pt short of the trailing edge, left to right
76..386 and right to left, with the artwork on the right, 16..326.

`veil` / `veil-off` check the scroll veil as on the album (`../album/README.md`, `../album/hero-veil-check.h`) instead
of the scripted states: the list scrolls from its adjusted top inset and the header goes up with it. The playlist's
hero already stretches with its plane on a pull, so the veil adds no zoom there. `veil-card`, with
`-spotifyglass.redesign.playlist.fullCover NO`, checks the blur and the dim on the picture in Spotify's own square,
which the veil does not move.

`other` on the launch line makes it someone else's playlist (save on Play's right instead of download, and a
description with an HTML entity); the header controller's view model is mocked from the device's values (2026-09-18).

`other late` opens it with no save in the row, the way a first open has it, and adds save at 2.5 s as an arranged
subview of HeaderActionsRow, which lays out nothing above the row. At 3 s the log says what the row shows on Play's
right: "Like" once `PlaylistHeader.x` watches the row, "Download" before it did (issue #19). The scripted states
from 4 s on lay the header out and would hide the difference, so read it before then.

`other saved` gives save the Encore object behind it (`../download-mock.h`), so the redesign can read whether the
playlist is saved, and plays save turning into download. Each change is heard through the header controller's
`-update`, with nothing laid out, as on the phone. The log reads, on Play's right: "Save to Your Library" at 2 s,
"Download" once saved, "Save to Your Library" once removed, and "Remove from Your Library" (save's checkmark) when
it is saved again with Spotify's download button disabled, as for an account that cannot download.

`mix` on the launch line builds a playlist Spotify makes (Indie Rock Mix), from `trees/continuous/4.txt`
(2026-09-20): no cover square anywhere, and in its place a `HeaderFullbleedCentralView` holding the picture,
the fade under it and Spotify's own 45pt title. Before any other pass it runs the one the page opens with,
where the block has no width yet and that view is the only child of the layout wide enough to be taken for
it — which is what used to conceal the picture for good and leave the hero black.

`liked` on the launch line (`xcrun simctl launch booted com.vojta.playlistharness liked`) builds Liked Songs
instead, from `trees/continuous/1.txt` (2026-09-18): no cover, a 238pt header, the count in a stack of its own,
the play button 80x48, and `LiquidGlass.gradientContainer`, which it fades in at 3 s as a scroll does.

`download` on the launch line plays the download button's states instead of the header's (issue #65), from
`../download-mock.h`: Spotify's button drawn by Lottie with no image view, its state in its accessibility
identifier and in a mock of the Encore object behind it (`currentState`, `progress`), and shuffle's "on" dot.
None, waiting, downloading (held at 50%), downloaded, shuffle on, removed with shuffle off, error, each held a
few seconds and announced with a `[harness] state:` line to take a screenshot on. Nothing in it lays anything
out, as on the phone.

`rebuilt` on the launch line rebuilds the curation row at 4.5 s, before the ⋯ sheet opens at 5 s: the row the page
was handed leaves the window and a new one, in a cell the redesign never hears about, takes its place. The sheet's
log line has to read "Mix (rebuilt)" and the fired pill has to be "still on screen: yes". Before the sheet looked
again, it fired the old row's Mix ("still on screen: no").

The extender paint line at 3 s also covers a recommendations heading mounted the way This Is playlists have it,
a plain UICollectionViewCell straight in the list: "plain heading a=0" once the list's pass has cleared it.

The owner's picture is an image view inside the creator button's facepile, filled at 1.5 s, after the header has
laid out. At 2.2 s the log line "owner picture" says where the redesign drew it: round, a line high, just before
the name, the two centered together. "none" means the late image was missed.

"pinned hold" lines, in every mode with a ⋯: after every Core Animation commit from the first frame until a second past
the veil, ⋯ has glass behind it, its own or download's capsule with download right under ⋯ in the page and the veil
under both; `verify-actions` checks it and logs then exits nonzero on failure. `rtl` lays the page out right to left, and `verify-actions` then expects ⋯
16pt in from the left edge and, with download pinned (`other`, `mix`), the 88x44 capsule the left-to-right one
mirrored. `freeze` pauses the veil's fade and holds the first frame under it 4 s, for a screenshot.

"whole page" lines, in every mode: just after launch the page is under the field's veil, below the pinned ⋯, and at
3 s there is "no veil". The redesign's own line says why it lifted (`log stream`, "page shown whole"): "its artwork
was read" for a playlist and a mix, "it has no artwork" for Liked Songs, a few tens of ms after its title.
