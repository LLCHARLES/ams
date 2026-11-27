#!/bin/sh
# The production top-controller resolver (Core/SGTopController.m) run against real UIKit controller trees on Mac
# Catalyst: a custom container with two children of which only one covers it, a hidden sibling Search page, a
# presented player overlay, and an alert presented over that. The same trees are read the way the phone driver's
# `state` reads them — path, presented, top — so the driver and the keyboard are checked to get one answer.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
if [ -n "${HARNESS_BUILD_DIR:-}" ]; then OUT=$HARNESS_BUILD_DIR; else
    OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-keyboard-top-controller.XXXXXX"); trap 'rm -rf "$OUT"' EXIT HUP INT TERM; fi
APP="$OUT/RetrineKeyboardTopController.app"
mkdir -p "$APP/Contents/MacOS" "$OUT/tmp"
export TMPDIR="$OUT/tmp"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    "$SRC/Core/SGTopController.m" "$HERE/retrine-keyboard-top-controller-check.m" "$HERE/../scene.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.retrine.keyboard-top-controller-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/Check"
