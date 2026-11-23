#!/bin/sh
# SGLosslessEngine.m's capture under AddressSanitizer, as a Mac Catalyst tool (capture-race.m); no simulator.
# ENGINE=<file> checks another copy of the engine (a fail-before run). The build goes to a temporary folder.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/lossless-capture-race.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
MAIN=$HERE/capture-race.m
ONLY=
if [ -n "${ENGINE:-}" ]; then
    # An older engine has no capture count to wait on: only the fill guard is checked against it.
    sed "s#../../tweak/Sources/Shared/Lossless/SGLosslessEngine.m#$ENGINE#" "$MAIN" > "$OUT/capture-race.m"
    MAIN=$OUT/capture-race.m
    ONLY=-DONLY_GUARD
fi
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -g -O1 -fsanitize=address -fno-omit-frame-pointer \
    -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Shared/Lossless" -I"$SRC/Shared/Player" -Wall -Wno-unused-function $ONLY \
    "$MAIN" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGDataRoot.m" \
    -framework UIKit -framework Foundation -framework AudioToolbox -framework Accelerate -o "$OUT/capture-race"
"$OUT/capture-race"
