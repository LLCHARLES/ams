# Artist harness

**Hold Play (live Spotify, not the mock).** With Premium enabled on iOS 26.5, holding Play from a paused
album on The Weeknd's page (9.1.90) and Queen's page (9.2.0) changed `SGPlayerState().contextURI` to
the displayed artist's popular-release context and set `options.shufflingContext`. A tap paused; holding
with shuffle already on resumed. Repeating the hold while playing did not pause, including after turning
shuffle off manually. Holding for 0.8 s then dragging outside before lift left playback and shuffle alone.
Neither artist header offered a Smart Shuffle step. On 9.2.0 the Korean custom action `셔플` was invoked
through its registered target and selector; it declined a missing or disabled source and started shuffled
playback with both sources available. This was not a spoken VoiceOver or physical vibration test.
An unrecognized control state leaves the hold inactive.

Spotify's artist page mocked under its own class names and accessibility identifiers (from
`trees/clean/artist/01.txt` and `05.txt`, recorded 2026-09-16), so `Redesigned/Artist/` can be laid out and
looked at on the Mac without the phone.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install booted build/ArtistHarness.app
    xcrun simctl launch booted com.vojta.artistharness            # at rest
    xcrun simctl launch booted com.vojta.artistharness collapsed  # the header scrolled into its 100pt bar

The Music list is a real self-sizing collection view holding the sections in the order the tree has them,
the two video sections included, so `ArtistSections.x` drops them the way it does on the phone: the shelf
first, then its heading and spacer once the list lays out again. At 2 s the log lists every cell's height.

`logo` on the launch line, with `-spotifyglass.redesign.artist.logo NO` after it so Apple Music's own logo does
not arrive as well, hands the header a logo at 2.5 s and takes it away at 4.5 s, with the page on screen. The log
says, before, as each arrives or leaves and a second later, where the logo and the name are and whether they are
fading and moving: the two cross over, the logo grows out of the name's place, and gone, the logo is hidden.

`veil` / `veil-off` check the scroll veil as on the album (`../album/README.md`, `../album/hero-veil-check.h`).
`verify-play` checks the row's Play: unset, the white capsule 48pt tall in the page's color with 48pt buttons 16pt
off it; with `-spotifyglass.redesign.artist.roundPlay YES` a 64pt white circle centered on the page with its glyph
alone and "Play" as its VoiceOver name, 44pt buttons 20pt off and level with it; with
`-spotifyglass.redesign.playInPageColour NO` the glyph in the accent (Spotify's green here) instead; round with
`-spotifyglass.redesign.artist.cutOutPlay YES` too, the glyph unpainted and cut out of the circle by its mask, white or
with `-spotifyglass.redesign.accentPlay YES` the accent. It logs a PASS line and a SHOT for a screenshot, or a FAIL and
exits 1.

`verify-title` checks the artist's name the way the Music app has it on iOS 26: Large Title bold capped at Extra Large,
centered on the page with the listeners line centered under it and clear of the row, a long name wrapped centered in two
lines at most, and a logo handed over for the name centered in its place. `rtl` with the right-to-left pseudolanguage
arguments asserts the page took that direction; `HARNESS_ARTIST` names the artist. It logs a SHOT 1.5 s ahead of the
checks, then a PASS line, or a FAIL and exits 1. `THEOS=$HOME/theos python3 harness/artist/title-check.py
[--screenshots <dir>]` runs it for a short and a long name, left to right and right to left, round and capsule Play, on
a simulator of its own that it deletes afterwards, keeping each case's screenshot as `artist-title-<case>.png`.

`cutout-check.sh` (`python3 scripts/harness-plan.py run --names "Artist cut-out Play"`) checks the cut-out Play itself,
in a Mac Catalyst app of its own: the capsule over slanted stripes, read back pixel by pixel against the stripes alone
and the capsule painted -- Play and Pause, the capsule with its word and a new font, another size, another fill, on and
off, no glyph yet, a disabled source, VoiceOver and a press -- that the mask is not drawn again when nothing changed,
that only round Play is cut out and the album's capsule is not, and the Artists page's card. `CUTOUT_PNG=<dir>` writes
every drawing it reads there; `baseline` only draws the album's capsule and round Play, to compare with another build.

What it does not cover: the repaint hook (so the mock's cells are left unpainted), the real z-order of the
pinned header bar against the list, and the element framework's own sizing.

`verify-listeners` checks the real header/section hooks. Run it with the listeners option off, on,
and on with About hidden:

    THEOS=$HOME/theos python3 harness/artist/listeners-check.py

The check allocates an isolated build directory and a simulator and runs all three cases. It removes
its builds and simulator afterwards. Existing `harness/artist/build/` is untouched.

With the option on, the header drops the listeners line from its first layout, for every artist; with
About hidden too it keeps the line, since nothing else on the page would show the count. The page's
cells are never inspected: Spotify's artist list is a Swift diffable data source that never calls the
Objective-C cell provider an earlier receipt design hooked (iPhone 13 Pro, 1.0.0). No About UI or
native localized listener count is changed.
