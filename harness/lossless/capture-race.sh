#!/bin/sh
# SGLosslessEngine.m's capture under AddressSanitizer, as a Mac Catalyst tool (capture-race.m); no simulator.
# ENGINE=<file> runs the same checks against another engine. ONLY_GUARD=1 selects the historical
# capture-fill-only check for engines predating capture quiescence and epoch-aware fill.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/lossless-capture-race.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
MAIN=$HERE/capture-race.m
ONLY=
if [ -n "${ENGINE:-}" ]; then
    sed "s#../../tweak/Sources/Shared/Lossless/SGLosslessEngine.m#$ENGINE#" "$MAIN" > "$OUT/capture-race.m"
    MAIN=$OUT/capture-race.m
fi
if [ "${ONLY_GUARD:-0}" = 1 ]; then ONLY=-DONLY_GUARD; fi
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O1 -fsanitize=address -fno-omit-frame-pointer \
    -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Shared/Lossless" -I"$SRC/Shared/Player" -Wall -Wno-unused-function $ONLY \
    "$MAIN" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGDataRoot.m" \
    -framework UIKit -framework Foundation -framework AudioToolbox -framework Accelerate -o "$OUT/capture-race"
ffmpeg -v error -f lavfi -i 'aevalsrc=0.25*gte(t\,10)|-0.25*gte(t\,10):s=44100:d=32' -sample_fmt s32 "$OUT/long.flac"
"$OUT/capture-race" "$OUT/long.flac"
