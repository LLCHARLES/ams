#!/bin/bash
# Both production badge hooks, independently gated, with exact Spotify view identities.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-explicit-badge.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
APP="$OUT/BadgeCheck.app"
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "${NATIVE_BADGE:-$SRC/Native/Appearance/ExplicitBadge.x}" > "$OUT/Native.m"
"$LOGOS" -c generator=internal "$SRC/Native/Appearance/Repaint.x" > "$OUT/Repaint.m"
"$LOGOS" -c generator=internal "${REDESIGN_BADGE:-$SRC/Redesigned/Kit/SGRExplicitBadge.x}" > "$OUT/Redesign.m"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Kit/SGRRepaint.x" > "$OUT/SGRRepaint.m"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Native/Appearance" -I"$SRC/Redesigned/Kit" \
    "$HERE/badge-check.m" "$OUT/Native.m" "$OUT/Repaint.m" "$OUT/Redesign.m" "$OUT/SGRRepaint.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Core/SGViewTree.m" -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$APP/Contents/MacOS/check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>check</string>
<key>CFBundleIdentifier</key><string>com.retrine.badgecheck</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict><key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>BadgeScene</string>
</dict></array></dict></dict></dict></plist>
PLIST
codesign -f -s - "$APP"
"$APP/Contents/MacOS/check"
LOOK=redesign "$APP/Contents/MacOS/check"
