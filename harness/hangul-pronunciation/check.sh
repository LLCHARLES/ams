#!/bin/bash
# macOS Foundation test of the shipping transforms; no simulator, network or saved defaults.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-hangul.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
xcrun --sdk macosx clang -fobjc-arc -Wall -I"$SRC" \
    "$HERE/check.m" "${ROMANISE_SOURCE:-$SRC/Shared/Lyrics/Romanise.m}" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -I"$SRC/Shared/Lyrics" -framework Foundation -o "$OUT/hangul-pronunciation-check"
"$OUT/hangul-pronunciation-check"
