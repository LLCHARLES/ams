# Native player harness

The native look's player fixes on the simulator, without the phone: `Native/Player/PlayerScrub.x` and
`PlayerDeclutter.x` run through `logos.pl -c generator=internal` over mocks under Spotify's class names,
linked with the real `Core/`.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/NativePlayerHarness.app
    xcrun simctl launch --console <udid> com.vojta.nativeplayerharness
    xcrun simctl launch --console <udid> com.vojta.nativeplayerharness preview-hidden

`SRC=<another checkout>/tweak/Sources OUT=<dir> ./build.sh` builds it against other sources, for example
main before the fixes, to see the checks fail.

It checks, a line each with `ok` or `WRONG`:

- the scrub (issue #172): the player list's pan off while a mock of the progress bar's slider tracks, back
  at its end, at a cancel and when the slider leaves the window, a pan off already left off, and a sideways
  list between the slider and the player's list left alone.
- the cover's room (issue #77): with Lyrics preview shown nothing moves; with it hidden the preview takes
  no room and the cover is the centered square of the view it sits in, again after a later pass of
  Spotify's; a small cover and a tilt view outside the player's cover cell are left alone.

The `sponsorblock` launch argument runs `../sponsorblock/markers-check.m` over `PlayerScrub.x`'s marks hooks and
`Shared/SponsorBlock/SponsorBlockMarkers.m` on a mock of Spotify's 17 pt bar (see harness/player/README.md's
`sponsorblock`; no scrub step), ending `sponsorblock native checks: n of 15 right`; `sponsorblock-off` checks that
nothing is drawn with the switch off. `SIMCTL_CHILD_HARNESS_SHOTS=<dir>` receives `native-ltr.png` and `native-rtl.png`.
On the sources before the marks hooks it read 9 of 15.

Run both launches: the default checks scrubbing and the shown preview (`6 of 6 right -- PASS`);
`preview-hidden` checks the hidden preview and cover sizing (`5 of 5 right -- PASS`).
Each logs its result and exits 0 on success or 1 on failure, without crashing.
The preview preference is set before the product's constructors, which snapshot it for the launch.
Changing it between checks in one process cannot test both settings: switches require a restart.

What it does not cover: Spotify's real Auto Layout in the cover cell, its open and close transition, and
a real touch on the slider.

The `audit` launch argument runs the real `Player.x` and `PlayerGestures.x` hooks for the artwork regressions:
album-cover taps still inspect their artwork with player gestures enabled, player-cover taps are suppressed
only with that switch on, and an explicitly visible 64pt missing-artwork glyph clears both the displayed
backdrop and the cached sample. An empty/loading image or a hidden placeholder preserves the previous
backdrop; actual cover art takes precedence over a placeholder. It logs PASS and exits, or logs a failed
check and exits nonzero without crashing. Gesture attachment and audio/haptic services are stubbed.
