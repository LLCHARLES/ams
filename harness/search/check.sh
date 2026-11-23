#!/bin/sh
# The Browse page's sections (main.m, Redesigned/Search/SearchSections.x), built and run in an iOS simulator of its own,
# made for the run and deleted after it. SHOTS=<dir> keeps search-top.png and search-end.png. Exits nonzero on a failed
# check.
#     THEOS=$HOME/theos ./check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${HARNESS_BUILD_DIR:-$HERE/build}
APP=$OUT/SearchHarness.app
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$APP"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Search/SearchSections.x" > "$OUT/gen/SearchSections.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Search" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/stubs.m" "$OUT/gen/SearchSections.m" \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m "$SRC"/Redesigned/Kit/SGRPress.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m \
    "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m \
    "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m "$SRC"/Redesigned/Kit/SGRedesign.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols -framework Metal -framework CoreText -framework IOKit \
    -o "$APP/SearchHarness"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SearchHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.searchharness</string>
<key>CFBundleName</key><string>SearchHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "SearchHarness-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch --console-pty "$UDID" com.vojta.searchharness > "$OUT/run.log" 2>&1 || true
cat "$OUT/run.log"
if [ -n "${SHOTS:-}" ]; then
    mkdir -p "$SHOTS"
    sed -n 's/.*\[harness\] SHOT //p' "$OUT/run.log" | tr -d '\r' | while read -r shot; do cp "$shot" "$SHOTS/"; done
fi
grep -q "PASS search" "$OUT/run.log" || { echo "FAILED: search"; exit 1; }
