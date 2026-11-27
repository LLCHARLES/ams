#!/bin/sh
# The player's title and artist styling, the complete PlayerTitle.x through Logos, on Mac Catalyst; no simulator.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
OUT=$(mktemp -d /tmp/player-title-style-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
APP=$OUT/Check.app
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Player/PlayerTitle.x" > "$OUT/PlayerTitle.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Redesigned/Player" -I"$HERE" -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
    "$OUT/PlayerTitle.m" "$HERE/title-style-check.m" \
    "$SRC/Settings/SGPageStyle.m" "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.retrine.player.titlestylecheck</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/Check"
