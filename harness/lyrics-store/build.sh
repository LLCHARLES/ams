#!/bin/sh
# Production store, lyric models and credit registry, without Spotify or home-folder data.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
BUILD=${HARNESS_BUILD_DIR:-$(mktemp -d /tmp/fix-offline-lyrics.XXXXXX)}
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
SDK=$(xcrun --sdk macosx --show-sdk-path)
python3 - "$SRC/Shared/LyricsSources/LyricsSources.m" "$BUILD/credit-registry.inc" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
models = source[source.index("@implementation SGLyricsLink"):source.index("@implementation SGLyricsQuery")]
registry = source[source.index("// The credits that carry links"):source.index("void SGLyricsOpenCreditLinks")]
pathlib.Path(sys.argv[2]).write_text(models + registry)
PY
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -I"$SRC" -I"$SRC/Shared/Lyrics" -I"$BUILD" \
    "$HERE/main.m" "${LYRICS_STORE_SOURCE:-$SRC/Shared/Lyrics/LyricsStore.m}" "$SRC/Shared/LyricsSources/LyricsRequest.m" "$SRC/Core/SGFileHash.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework Foundation -framework UIKit "$SRC/Core/SGDataRoot.m" -o "$BUILD/lyrics-store"
"$BUILD/lyrics-store"
