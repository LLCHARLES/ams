#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/retrine-backup.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
APP="$BUILD/Backup.app"
mkdir -p "$APP/Contents/MacOS" "$BUILD/export"
# Exercise the actual pre-hook flag conversions without installing hooks in the Catalyst host.
sed '/^%hook/,$d' "$SRC/Shared/Flags/Flags.x" > "$BUILD/flag-conversions.inc"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -Os -Wl,-dead_strip -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$BUILD" -I"$SRC/Shared/Flags" -DSG_VERSION=\"test\" \
    "$HERE/check.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGGlass.m" \
    "$HERE/../scene.m" -framework UIKit -framework Foundation -framework OSLog -framework UniformTypeIdentifiers -o "$APP/Contents/MacOS/Backup"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Backup</string>
<key>CFBundleIdentifier</key><string>com.retrine.backup-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict><key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
</dict></array></dict></dict></dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null
trap 'chmod 700 "$BUILD/export"; rm -rf "$BUILD"' EXIT
EXPORT_DIR="$BUILD/export" "$APP/Contents/MacOS/Backup"
