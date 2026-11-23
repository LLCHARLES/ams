#!/bin/sh
# Builds the Presets page's Save-dialog lifetime check (sim/presets-page.m) for the simulator: the real
# AudioEffectsPresetsPage.m with the Settings/ framework and AudioEffectsSettings.m, the page harness's stubs.m
# standing in for the engine.
#   THEOS=$HOME/theos ./build-presets-page.sh
set -e
cd "$(dirname "$0")"
SRC=$(cd ../../tweak/Sources && pwd)
FX="$SRC/Shared/AudioEffects"
OUT=${OUT:-build/presets-page}
mkdir -p "$OUT/PresetsPageHarness.app"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$FX" -isysroot "$SDK" -Wall -Wno-deprecated-declarations \
    sim/presets-page.m ../scene.m ../audio-effects-page/stubs.m \
    "$FX"/AudioEffectsSettings.m "$FX"/AudioEffectsPage.m "$FX"/SGDSPCurveView.m "$FX"/AudioEffectsLibraryPage.m "$FX"/SGDSPFilters.m \
    "$FX"/AudioEffectsPresets.m "$FX"/AudioEffectsPresetsPage.m "$FX"/AutoEq.m "$FX"/AudioEffectsFiles.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework UniformTypeIdentifiers -framework Accelerate -framework Foundation \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/PresetsPageHarness.app/PresetsPageHarness"
cat > "$OUT/PresetsPageHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PresetsPageHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.presetspageharness</string>
<key>CFBundleName</key><string>PresetsPageHarness</string>
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
echo "built $OUT/PresetsPageHarness.app"
