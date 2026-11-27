#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-field-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -fobjc-arc -O0 -g -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" \
    "$HERE/field-check.m" "$SRC/Redesigned/Kit/SGRField.m" "$SRC/Redesigned/Kit/SGRFlow.m" \
    "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Core/SGLocalize.m" \
    "$SRC/Core/SGViewTree.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGGlass.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Symbols \
    -o "$OUT/field-check"
"$OUT/field-check"
xcrun clang -fobjc-arc -O0 -g -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" \
    "$HERE/fluid-steps-check.m" "$SRC/Redesigned/Kit/SGRFluid.m" "$SRC/Redesigned/Kit/SGRFluidGPU.m" \
    "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Metal \
    -o "$OUT/fluid-steps-check"
"$OUT/fluid-steps-check"
