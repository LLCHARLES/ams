#!/bin/sh
# OUT must be a caller-owned temporary directory. Optional source override is for mutation checks.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
: "${OUT:?Set OUT to a temporary build directory}"
mkdir -p "$OUT"
ENGINE=${ENGINE_SOURCE:-"$SRC/Shared/Sing/SGSingEngine.m"}
xcrun clang -fobjc-arc -O2 -Wall -Werror -target $(uname -m)-apple-macos15.0 \
    -I "$SRC" -I "$SRC/Shared/Sing" -I "$HERE/shim" \
    "-DSG_SING_ENGINE_SOURCE=\"$ENGINE\"" \
    "$HERE/render-regressions.m" "$SRC/Shared/Sing/SGSingSeparator.m" \
    -framework Foundation -framework AudioToolbox -framework Accelerate -framework CoreML \
    -o "$OUT/render-regressions"
"$OUT/render-regressions"
