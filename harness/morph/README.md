# Morph harness

`PlayerMorph.x` run for real against a mock of Spotify's `SPTBarOverlayPresentationTransition`: the
mock sets the player's frame, its alpha and the bar stand-in from `-setProgress:` the way 9.1.78 does
(0x109815464), driven by a display link on a spring, and makes the bar's stand-in the way Spotify
does (a snapshot view opening, a `renderInContext:` image closing). The bar, the player and the cover
are plain views standing in for Spotify's; the morph's inputs from `NowPlayingBar.x` and
`PlayerArtwork.x` are stubbed in `main.m`.

    export MORPH_OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-morph-preview.XXXXXX")
    THEOS=$HOME/theos sh harness/morph/build.sh
    xcrun simctl install booted "$MORPH_OUT/MorphHarness.app"
    xcrun simctl launch booted com.vojta.morphharness          # opens and closes once, then exits

Held at one progress, for a screenshot (the positions are logged as `MORPH` lines):

    SIMCTL_CHILD_MORPH_T=0.3 xcrun simctl launch --console-pty booted com.vojta.morphharness
    xcrun simctl io booted screenshot shot.png

A recording shows the move: `xcrun simctl io booted recordVideo -f run.mp4`, then
`ffmpeg -ss T -t 0.5 -i run.mp4 -vf "fps=24,scale=160:-1,tile=8x1" -frames:v 1 strip.png`.

The build defaults to a new temporary directory, printed when it finishes; it never removes an existing
build. Remove your preview output after use, shut down simulators and quit Simulator.app.

## Compact close checks (9.1.90)

From the repository root:

    sh harness/morph/check.sh

`compact.inc` models the compact transition's setup, stored `UIViewPropertyAnimator`, start/pause,
gesture-driven fraction, finish/reverse/continue, and Spotify-owned completion/cancellation. Production
`PlayerMorph.x` runs against real UIKit on an isolated iOS 26.5 iPhone simulator. No phone is used.

The default-off setting is enabled in one process and disabled in another. Checks cover the visible
mask edges and radius at p=0.55, 0.70, 0.80 and 1, dim/opacity, a paused drag beyond 0.9 seconds,
velocity-shaped release (fresh/stale, wrong direction, under 0.02 remaining and both duration clamps),
cancel restoration (including UIKit's reversed 0.9763 fraction after a 0.0237 drag), tap duration, owner
deallocation before completion, the old linear geometry and 1.5× clock when off, and unchanged opening
and legacy transitions, plus a missing-card close remaining untouched. The card is measured at {{8,697},{374,56}}, independently of Spotify's snapshot
frame {{0,697},{390,64}}. There is no vertical offset. The unmodified animator lasts 0.30 seconds, as on
the device. UIKit continuation arguments are observed at the framework boundary.

An alternate owner fixture lacks the `overlayView` ivar. With the switch on it must retain the original
0.30-second duration both before and after setup, the original animator and the 1.5× follower path.

The script removes its app/builds and its own simulator, also on failure.

Not covered: Spotify's real player/list, its snapshot glass (`BarTransition.x`), actual gesture routing,
physical 120 Hz rendering, or visual/device acceptance. The sheet is black here.
