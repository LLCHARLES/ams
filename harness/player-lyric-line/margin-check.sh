#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
APP=$OUT/Margin.app
mkdir -p "$APP/Contents/MacOS"
# Isolate the always-on layout hooks from the optional lyric line, tap and playback machinery.
{
    printf '#import <UIKit/UIKit.h>\n#import <objc/runtime.h>\n#define SGLog(...) ((void)0)\n'
    sed -n '/^static const CGFloat SGRPlayerSideMargin =/p' "$SRC/Redesigned/Player/Player.h"
    sed -n '/^static char kMarginInsetKey/,/^void SGRPlayerHoldMargin/{p;}; /^void SGRPlayerHoldMargin/,/^}/{ /^void SGRPlayerHoldMargin/!p; }' "$SRC/Redesigned/Player/PlayerFooter.x"
    printf '#define watchPreviewTaps(v) ((void)0)\n#define SGRPlayerLyricLineOn() NO\n#define flushChip(v) ((void)0)\n#define placeLine() ((void)0)\n#define refreshEmptyStrip(v) ((void)0)\n'
    LINE="$SRC/Redesigned/Player/PlayerLyricLine.x"
    sed -n '/^static __weak UIView \*sg_host;/p; /^static void holdPreviewMargin(/,/^}/p' "$LINE"
    sed -n '/^\/\/ These two are there whether/,/^%hook .*NowPlayingViewController/{ /^%hook .*NowPlayingViewController/!p; }' "$LINE"
    sed -n '/^%hook .*NowPlayingViewController/,/^%end/{ /^%hook/p; /^- (void)viewDidLayoutSubviews/,/^%end/p; }' "$LINE"
} > "$OUT/margin.x"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/margin.x" > "$OUT/margin.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    "$HERE/margin-check.m" "$OUT/margin.m" -framework UIKit -framework Foundation \
    -framework CoreGraphics -o "$APP/Contents/MacOS/lyric-margin"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>lyric-margin</string>
<key>CFBundleIdentifier</key><string>com.retrine.player.lyricmargin</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
codesign -f -s - "$APP"
"$APP/Contents/MacOS/lyric-margin"
