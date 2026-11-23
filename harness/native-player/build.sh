#!/bin/sh
set -e
# SRC may point at another checkout of tweak/Sources (an older commit, to see a bug before its fix).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/NativePlayerHarness.app"

for f in Native/Player/PlayerScrub.x Native/Player/PlayerDeclutter.x Native/Player/Player.x Native/Player/PlayerGestures.x; do
    [ -f "$SRC/$f" ] || continue
    name=$(basename "$f" .x)
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Native/Player" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/player-stubs.m" "$(dirname "$0")/../scene.m" "$OUT"/gen/*.m \
    "$(dirname "$0")/../sponsorblock/markers-check.m" "$SRC"/Shared/SponsorBlock/SponsorBlockMarkers.m \
    "$SRC"/Shared/SponsorBlock/SponsorBlockModel.m "$SRC"/Shared/SponsorBlock/SponsorBlockPrefs.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m \
    "$SRC"/Shared/Gestures/GestureHold.m \
    "$SRC"/Native/Declutter/Declutter.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$OUT/NativePlayerHarness.app/NativePlayerHarness"

cat > "$OUT/NativePlayerHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>NativePlayerHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.nativeplayerharness</string>
<key>CFBundleName</key><string>NativePlayerHarness</string>
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
echo "built $OUT/NativePlayerHarness.app"
