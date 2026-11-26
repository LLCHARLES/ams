#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT=${OUT:-"$HERE/build-upgrade"}
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
cc() {
    xcrun clang -fobjc-arc -target $(uname -m)-apple-ios26.0-macabi -isysroot "$SDK" \
        -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"${HEADERS:-$SRC}" -I"$SRC" \
        -I"$SRC/Shared/AnimatedArtwork" "$@"
}
cc -DSGMigrateKey=HarnessMigrateKey -c "$SRC/Core/SGPrefs.m" -o "$OUT/prefs.o"
cc "$HERE/artwork-upgrade.m" "$SRC/Shared/AnimatedArtwork/AnimatedArtworkSettings.m" "$OUT/prefs.o" \
    -Wl,-dead_strip -Wl,-undefined,dynamic_lookup -framework Foundation -framework UIKit -o "$OUT/artwork-upgrade"
"$OUT/artwork-upgrade"
