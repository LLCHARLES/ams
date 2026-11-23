#!/bin/sh
# Run the buffering hook in isolation with Spotify's three view classes on Catalyst.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/player-buffering-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
{
    printf '#import <UIKit/UIKit.h>\n#define SGRedesignedUI() YES\n'
    sed -n '/^#pragma mark - Podcast buffering$/,/^#pragma mark - Duration hooks$/{p;}' "$SRC/Redesigned/Player/PlayerControls.x"
} > "$OUT/buffering.x"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/buffering.x" > "$OUT/buffering.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    "$HERE/buffering-check.m" "$OUT/buffering.m" -framework UIKit -framework Foundation \
    -framework QuartzCore -framework CoreGraphics -o "$OUT/check"
"$OUT/check"
