#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT=$(mktemp -d "${TMPDIR:-/tmp}/prefs-compat.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
for path in Shared/SpotifyPrefs/SpotifyPrefs Shared/Lossless/LosslessQuality; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$path.x" > "$OUT/${path##*/}.m"
done
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -fobjc-arc \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Shared/SpotifyPrefs" -I"$SRC/Shared/Lossless" \
    "$HERE/preference-compat.m" "$OUT/"*.m -framework UIKit -framework Foundation -o "$OUT/check"
for mode in supported missing-speed wrong-setter; do PREFS_CASE="$mode" "$OUT/check"; done
