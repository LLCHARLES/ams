#!/bin/sh
# Builds the line under the cover's fit and clock (PlayerLyricFit.m) for the Mac Catalyst and runs the checks.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${OUT:-$HERE/build}
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -Wextra \
    -Wno-unused-parameter -I"$SRC" -I"$HERE/.." \
    "$HERE/main.m" "$SRC/Redesigned/Player/PlayerLyricFit.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework Foundation \
    -o "$OUT/player-lyric-line"
"$OUT/player-lyric-line"
