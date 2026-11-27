#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT=$(mktemp -d "${TMPDIR:-/tmp}/local-hooks.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/LocalFiles/LocalFileInfo.x" > "$OUT/hooks.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -fobjc-arc \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Shared/LocalFiles" \
    "$HERE/hook-compat.m" "$OUT/hooks.m" -framework MediaPlayer -framework UIKit -framework Foundation -o "$OUT/check"
"$OUT/check"
