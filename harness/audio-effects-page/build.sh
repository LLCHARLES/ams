#!/bin/sh
# Builds the Audio effects page harness for the simulator: Shared/AudioEffects' page, the Settings/ framework,
# AudioEffectsSettings.m and the engine's curve math (SGDSPFilters.m) as they are in the tweak, stubs.m for
# the rest of the engine. sheet.m runs the page as the player's ⋯ opens it, with ../tabbar/touch.m's fingers.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
FX="$SRC/Shared/AudioEffects"
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/AudioEffectsPageHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$FX" -isysroot "$SDK" -Wall -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/sheet.m" "$(dirname "$0")/../scene.m" "$(dirname "$0")/../tabbar/touch.m" "$(dirname "$0")/stubs.m" \
    "$FX"/AudioEffectsSettings.m "$FX"/AudioEffectsPage.m "$FX"/SGDSPCurveView.m "$FX"/AudioEffectsLibraryPage.m "$FX"/SGDSPFilters.m \
    "$FX"/AudioEffectsPresets.m "$FX"/AudioEffectsPresetsPage.m "$FX"/AutoEq.m "$FX"/AudioEffectsFiles.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework IOKit -framework QuartzCore -framework CoreGraphics -framework UniformTypeIdentifiers -framework Accelerate -framework Foundation \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/AudioEffectsPageHarness.app/AudioEffectsPageHarness"

cat > "$OUT/AudioEffectsPageHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AudioEffectsPageHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.audioeffectspageharness</string>
<key>CFBundleName</key><string>AudioEffectsPageHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "built $OUT/AudioEffectsPageHarness.app"
