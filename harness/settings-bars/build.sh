#!/bin/sh
# Settings/SGPageStyle.m's SGInsetForBars against a window with a large mock view tree, on Mac Catalyst's UIKit.
# No simulator and no network: it runs as a Catalyst app that exits nonzero on failure.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${HARNESS_BUILD_DIR:-"$HERE/build"}
APP="$OUT/Check.app"
mkdir -p "$APP/Contents/MacOS" "$OUT/tmp"
export CFFIXED_USER_HOME="$OUT/tmp"
export TMPDIR="$OUT/tmp"
mkdir -p "$CFFIXED_USER_HOME/Library/Preferences"
SDK=$(xcrun --sdk macosx --show-sdk-path)
python3 "$HERE/audit-fixtures.py" "$SRC" "$OUT"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter \
    -Wno-deprecated-declarations -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I "$SRC" -I "$HERE/.." -I "$OUT" \
    "$HERE/check.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGGlass.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.retrine.settings-bars-check</string>
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
"$APP/Contents/MacOS/Check" -AppleLanguages '(en)'
