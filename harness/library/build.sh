#!/bin/sh
set -e
# The sources of the checkout this harness sits in, unless SRC names others (an older tree, to compare).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${HARNESS_BUILD_DIR:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/LibraryHarness.app"

for f in Redesigned/Library/LibraryHeader.x; do
    name=$(basename "$f" .x)
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -DSG_DRIVER=1 \
    -I"$SRC" -I"$SRC/Redesigned/Library" -I"$OUT/gen" -isysroot "$SDK" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/kit-check.m" "$(dirname "$0")/settings-check.m" "$(dirname "$0")/stubs.m" \
    "$(dirname "$0")/../tabbar/touch.m" \
    "$OUT"/gen/*.m \
    "$SRC"/Redesigned/Library/LibraryMenu.m "$SRC"/Redesigned/Library/LibrarySettings.m "$SRC"/Redesigned/Kit/SGRPagePreview.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Settings/SGSourcesPage.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m "$SRC"/Redesigned/Kit/SGRPress.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m \
    "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m \
    "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols -framework Metal -framework CoreText -framework IOKit \
    -o "$OUT/LibraryHarness.app/LibraryHarness"

cat > "$OUT/LibraryHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LibraryHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.libraryharness</string>
<key>CFBundleName</key><string>LibraryHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/LibraryHarness.app"
