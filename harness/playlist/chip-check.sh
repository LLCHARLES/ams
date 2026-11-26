#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
{
    printf '#import <UIKit/UIKit.h>\n#import <objc/runtime.h>\n#import "Core/SGViewTree.h"\n'
    sed -n '/^#pragma mark - Spotify.s chip row/,/^%end/p' "$SRC/Redesigned/Playlist/PlaylistRows.x"
} > "$OUT/chip.x"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/chip.x" > "$OUT/chip.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" \
    "$HERE/chip-check.m" "$OUT/chip.m" "$SRC/Core/SGViewTree.m" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -o "$OUT/playlist-chip"
"$OUT/playlist-chip"
