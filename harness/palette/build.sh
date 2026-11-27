#!/bin/sh
# Builds the palette check for the Mac (Mac Catalyst, for UIKit): Redesigned/Kit/SGRPalette.m as the tweak compiles it.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=${OUT:-build/palette-check}
mkdir -p "$(dirname "$OUT")"
xcrun clang -fobjc-arc -O0 -g -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -isystem "$SDK/System/iOSSupport/usr/include" \
    -I"$SRC" check.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m \
    "$SRC"/Settings/SGPageStyle.m "$SRC"/Core/SGLocalize.m \
    "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGGlass.m \
    -framework UIKit -framework CoreImage -framework CoreGraphics -framework QuartzCore -o "$OUT"
echo "built $OUT"
