#!/bin/sh
# Runs the production Native helper on Foundation with mock view trees; no simulator or app.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-native-declutter.XXXXXX")
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
python3 "$HERE/album-rules.py" "$SRC" "$OUT/album-rules.inc"
xcrun clang -fobjc-arc -O0 -g -target $(uname -m)-apple-macos13.0 \
    -I "$HERE/shim" -I "$SRC" -I "$OUT" \
    "$HERE/check.m" "$HERE/view-doubles.m" "$SRC/Native/Declutter/Declutter.m" \
    -framework Foundation -framework CoreGraphics -o "$OUT/check"
"$OUT/check"
xcrun clang -fobjc-arc -O0 -g -target $(uname -m)-apple-macos13.0 \
    -I "$HERE/shim" -I "$SRC" "$HERE/backdrop-check.m" "$HERE/view-doubles.m" \
    -framework Foundation -framework CoreGraphics -o "$OUT/backdrop-check"
"$OUT/backdrop-check"
