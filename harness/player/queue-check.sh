#!/bin/sh
# Compile the complete queue controller, with Spotify as the only behavioral double.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/player-queue-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
APP=$OUT/Check.app
mkdir -p "$APP/Contents/MacOS"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" \
    -Wno-deprecated-declarations \
    "$SRC/Redesigned/Player/PlayerQueue.m" "$HERE/queue-check.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
    -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.retrine.player.queuecheck</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/Check"
