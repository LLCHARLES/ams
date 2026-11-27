#!/bin/sh
# Real UIKit on Mac Catalyst, no simulator; all build artifacts stay in this harness.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=${HARNESS_BUILD_DIR:-"$HERE/.build"}
APP="$OUT/Check.app"
mkdir -p "$APP/Contents/MacOS" "$OUT/tmp"
export TMPDIR="$OUT/tmp"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    "$SRC/Redesigned/Lyrics/AutoTranslationSettings.m" "$SRC/Settings/SGPage.m" \
    "$SRC/Redesigned/Lyrics/AutoTranslatorName.m" \
    "$SRC/Core/SGLocalize.m" "$HERE/check.m" \
    -framework UIKit -framework QuartzCore -framework Foundation \
    -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.retrine.auto-translation-settings-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>CheckScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/Check" -AppleLanguages '(en)'
