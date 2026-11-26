# Appearance page harness

Mod Settings > Appearance as `App/Pages.m` builds it: either look's accent rows (`Native/Appearance/AppearanceSettings.m`,
`Redesigned/Kit/SGRAppearanceSettings.m`), the Font rows and their import (`Shared/Fonts/FontImport.m`) and the real
Settings/ framework (the pull-down menu row, the swatch, the color sheet), with `stubs.m` reading the accent and
font keys the way the Logos files do.

    ./build.sh
    xcrun simctl install <udid> build/AppearancePageHarness.app
    xcrun simctl launch --console <udid> com.vojta.appearancepageharness accent=123456 menu=1.0:0 dump menu=1.0:2 dump
    xcrun simctl io <udid> screenshot shot.png

Make a simulator of your own (`xcrun simctl create`) and address it by UDID. `main.m` lists the setup words
(`redesign`, `accent=`, `raccent=`, `font=`, `keep`) and the actions: a menu item picked, a row tapped, the
color sheet moved, confirmed or closed, a font file handed to the import as Files would, and `dump`, which logs the
stored keys, the color in effect, what the launch would register for the font and what every row reads.

2026-10-05, iPhone 17 Pro on iOS 27.0: an old Apple Music red reads Apple Music, an old #123456 reads Custom, nothing
stored reads Spotify (native) or Custom #37F200 (redesign); Custom → Spotify → Custom brings #123456 back; the sheet's
close keeps the color, its checkmark stores it as Custom; a text file named .ttf is refused with nothing stored;
Chalkduster.ttf (a face iOS already has) and then a Noto .otf import, the second replacing the first, and a deleted
file registers nothing.

What it does not cover: a finger on the pull-down (UIKit opens it only from a touch), the document picker itself,
and Fonts.x's hooks, which only Spotify can show.

`harness/fonts/build.sh` owns the offline, self-terminating font-selection regression using Chalkduster.
It pauses the real import at its worker copy, selects the real New York row, and verifies that import
completion registers/makes the family available without overriding the choice. Direct defaults removal
(reset) and replacement (restore) during an import must also survive completion. An unchanged stored
choice or unchanged absent preference must select Custom. Failures log and exit nonzero, never crash.
It also switches Avenir Next → Georgia through the actual More fonts row, changes a library identifier
without changing its enum, and requests a real restart while an unset-start import is pending.
Registration still completes during the restart delay, but auto-selection must not undo the reset.
The same run exercises the real free-font page with an offline download/installation double:
Nanum Gothic finishing must preserve a later San Francisco or already-installed Nanum Myeongjo choice,
remain available, and become selected when the choice was untouched. The real service remains in
use for interactive runs; this check does not download or validate library font bytes.
`BUILD_DIR` selects an isolated output directory for `harness/fonts/build.sh`; no simulator is needed.
