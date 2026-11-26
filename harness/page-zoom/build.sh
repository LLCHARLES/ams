#!/bin/sh
set -eu
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$HARNESS_BUILD_DIR
mkdir -p "$OUT/PageZoomHarness.app"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
perl "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Navigation/PageZoom.x" > "$OUT/PageZoom.x.m"
xcrun --sdk iphonesimulator clang -target $(uname -m)-apple-ios26.0-simulator -fobjc-arc -isysroot "$SDK" \
    -I"$SRC" -I"$SRC/Redesigned/Navigation" \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" \
    "$SRC/Redesigned/Navigation/PageZoom.m" "$OUT/PageZoom.x.m" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -o "$OUT/PageZoomHarness.app/PageZoomHarness"
cat > "$OUT/PageZoomHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.retrine.pagezoomharness</string>
<key>CFBundleExecutable</key><string>PageZoomHarness</string>
<key>CFBundleName</key><string>PageZoomHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
</dict></array>
</dict></dict>
</dict></plist>
PLIST
