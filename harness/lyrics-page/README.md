# Lyrics page harness

The redesign's Lyrics page as `App/Pages.m` opens it (`Redesigned/Lyrics/LyricsLookSettings.m`): the preview
playing the sample song in the real lyrics view, the presets under it, the sliders' sheet, and one stand-in
section under them, on the real Settings/ framework. `../lyrics/stubs.m` stands in for the player.

    ./build.sh
    xcrun simctl install <udid> build/LyricsPageHarness.app
    xcrun simctl launch --console <udid> com.vojta.lyricspageharness -check 1
    xcrun simctl launch <udid> com.vojta.lyricspageharness -preset 4 -sheet 1
    xcrun simctl io <udid> screenshot shot.png

`main.m` lists the arguments. `-check 1` taps the presets, opens the sheet and moves a slider, and checks
what the preview, the presets and the sliders read after each.

`-pushCheck 1` pushes the page as Mod Settings does, with Apple Music, Vivid and a look of the sliders' own stored, and
samples the preset strip every frame: it must be where it rests (the chosen preset in sight, or the first at the card's
inset) from the first frame on screen, and a preset picked afterwards must still scroll there over several frames (issue #41).

`-textCheck 1` checks the Text sizes page's per-text looks (`LyricsText.m`, `LyricsTextSettings.m`): nothing stored
keeps the old fonts and brightness, stored values out of range read as the usual ones, a sung pronunciation's
composited brightness is the one asked for, and a tapped row opens its page with a pinned preview.
`-textPage N -textLook 1 -landscape 1` opens text N's page for a screenshot, turned on its side.

2026-10-05, iPhone 17 Pro on iOS 27.0: all checks pass; the sheet rests at half height under the preview,
which plays on undimmed.

What it does not cover: Spotify's navigation stack around the page, the other Lyrics rows, and a finger
on the sliders (the check sets their value as a drag would).
