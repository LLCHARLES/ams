#!/bin/sh
# Source-tree override also permits isolated mutations. All binaries go in a unique temporary directory.
set -eu
cd "$(dirname "$0")"
SRC=${SRC:-../../tweak/Sources}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/lyrics-regression.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
OUT=${OUT:-$WORK/shots}
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations -I "$SRC" \
    -DCTLineCreateTruncatedLine=SGLyricsHarnessTruncatedLine -DCTFrameDraw=SGLyricsHarnessDrawFrame -DCGBitmapContextCreate=SGLyricsHarnessCreateContext \
    -DSGLyricsBackgroundCreate=SGLyricsHarnessBackground -Dmalloc=SGLyricsHarnessMalloc \
    -Dfree=SGLyricsHarnessFree -DCGImageCreateWithImageInRect=SGLyricsHarnessCrop -DCGImageRelease=SGLyricsHarnessRelease \
    -c "$SRC/Shared/LockScreenLyrics/SGLyricsClip.m" -o "$WORK/renderer.o"
xcrun clang -fobjc-arc -O2 -Wno-deprecated-declarations ${BASELINE_FLAGS:-} -I "$SRC" \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreImage \
    -framework CoreText -framework CoreGraphics -framework ImageIO -framework Accelerate -framework AppKit \
    regression.m "$WORK/renderer.o" "$SRC/Shared/LyricsBackground/LyricsBackground.m" \
    -o "$WORK/regression"
"$WORK/regression" "$OUT" "$WORK/leased.mp4"
