#!/bin/sh
# Builds the presets and AutoEq check for the Mac: AudioEffectsPresets.m, AutoEq.m, AudioEffectsSettings.m and
# Core/SGPrefs.m as the tweak compiles them, shim/ standing in for SGCore.h's UIKit half.
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
FX=$SRC/Shared/AudioEffects
OUT=${OUT:-build/autoeq-check}
mkdir -p "$(dirname "$OUT")"
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target $(uname -m)-apple-macos13.0 -I shim -I "$SRC" -I "$FX" \
    check.m "$FX"/AudioEffectsPresets.m "$FX"/AutoEq.m "$FX"/AudioEffectsSettings.m "$FX"/AudioEffectsFiles.m \
    "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m \
    -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT"
echo "built $OUT"
