#!/bin/sh
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=${HARNESS_BUILD_DIR:-$(mktemp -d /tmp/retrine-home-tiles.XXXXXX)}
mkdir -p "$OUT/HomeTilesHarness.app"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Home" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" \
    "${HOME_TILES_SOURCE:-$SRC/Redesigned/Home/HomeTiles.m}" "$SRC/Redesigned/Home/HomeShelves.m" \
    "$SRC/Redesigned/Kit/SGRRestyle.m" "$SRC/Redesigned/Kit/SGRTokens.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Core/SGLocalize.m" \
    "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGGlass.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -o "$OUT/HomeTilesHarness.app/HomeTilesHarness"
cat > "$OUT/HomeTilesHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HomeTilesHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.hometilesharness</string>
<key>CFBundleName</key><string>HomeTilesHarness</string>
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
echo "built $OUT/HomeTilesHarness.app"
