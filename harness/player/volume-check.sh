#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/connect-volume-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Player/PlayerConnectVolume.x" > "$OUT/Connect.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Redesigned/Player" \
    "$HERE/volume-check.m" "$OUT/Connect.m" -framework UIKit -framework Foundation \
    -o "$OUT/volume-check"
"$OUT/volume-check"
for signature in hook-return callback-argument callback-return; do
    BAD_SIGNATURE="$signature" "$OUT/volume-check"
done
