# Morph harness

`PlayerMorph.x` runs against a mock of `MainUI_TabBarUIImpl.CompactOverlayTransition`,
the player animator in Spotify 9.1.90 and 9.2.0.

From the repository root:

    sh harness/morph/check.sh

`compact.inc` models the compact transition's setup, stored `UIViewPropertyAnimator`, start/pause,
gesture-driven fraction, finish/reverse/continue, and Spotify-owned completion/cancellation. Production
`PlayerMorph.x` runs against real UIKit on an isolated iOS 26.5 iPhone simulator. No phone is used.

The default-off setting is enabled in one process and disabled in another. Checks cover the visible
mask edges and radius at p=0.55, 0.70, 0.80 and 1, dim/opacity, a paused drag beyond 0.9 seconds,
velocity-shaped release (fresh/stale, wrong direction, under 0.02 remaining and both duration clamps),
cancel restoration (including UIKit's reversed 0.9763 fraction after a 0.0237 drag), tap duration, owner
deallocation before completion, the linear geometry and 1.5× clock when off, and unchanged opening
and missing-card close. The card is measured at {{8,697},{374,56}}, independently of Spotify's snapshot
frame {{0,697},{390,64}}. There is no vertical offset. The unmodified animator lasts 0.30 seconds, as on
the device. UIKit continuation arguments are observed at the framework boundary.

An alternate owner fixture lacks the `overlayView` ivar. With the switch on it must retain the original
0.30-second duration both before and after setup, the original animator and the 1.5× follower path.

The script removes its app/builds and its own simulator, also on failure.

Not covered: Spotify's real player/list, its snapshot glass (`BarTransition.x`), actual gesture routing,
physical 120 Hz rendering, or visual/device acceptance. The sheet is black here.
