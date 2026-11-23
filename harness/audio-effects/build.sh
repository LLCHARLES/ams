#!/bin/sh
# Builds the audio effects harness for the Mac: the engine (tweak/Sources/Shared/AudioEffects) as the tweak
# compiles it, the third-party C it uses (vendor/audio, made here first) and main.m.
#   ./build.sh            build/audio-effects
#   ./build.sh thread     build/audio-effects-thread, under ThreadSanitizer
#   ./build.sh address    build/audio-effects-address, under AddressSanitizer
#   ./build.sh route      build/route-check, the corrections remembered per output (route.m)
#   ./build.sh presets    build/preset-files-check, preset files written and read (preset-files.m)
#   ./build.sh pcm        build/pcm-read-check, shared PCM reads and exact buffer layout (C only)
#   ./build.sh format     build/audio-format-check, exact audio-format diagnostic strings
set -e
cd "$(dirname "$0")"
if [ "$1" = format ]; then
    OUT=${OUT:-build/audio-format-check}
    mkdir -p "$(dirname "$OUT")"
    xcrun clang -fobjc-arc -O2 -Wall -Werror -target arm64-apple-macos13.0 -I ../../tweak/Sources \
        audio-format.m -framework Foundation -o "$OUT"
    echo "built $OUT"
    exit
fi
if [ "$1" = pcm ]; then
    OUT=${OUT:-build/pcm-read-check}
    mkdir -p "$(dirname "$OUT")"
    xcrun clang -O2 -Wall -Werror -target arm64-apple-macos13.0 -I ../../tweak/Sources \
        pcm-read.c -o "$OUT"
    echo "built $OUT"
    exit
fi
if [ "$1" = presets ]; then
    SRC=../../tweak/Sources
    FX=$SRC/Shared/AudioEffects
    OUT=${OUT:-build/preset-files-check}
    mkdir -p "$(dirname "$OUT")"
    xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 -I ../autoeq/shim -I "$SRC" -I "$FX" \
        preset-files.m "$FX"/AudioEffectsPresets.m "$FX"/AutoEq.m "$FX"/AudioEffectsSettings.m "$FX"/AudioEffectsFiles.m "$SRC"/Core/SGPrefs.m \
        "$SRC"/Core/SGLocalize.m -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT"
    echo "built $OUT"
    exit
fi
if [ "$1" = route ]; then
    SRC=../../tweak/Sources
    FX=$SRC/Shared/AudioEffects
    OUT=${OUT:-build/route-check}
    mkdir -p "$(dirname "$OUT")"
    xcrun clang -fobjc-arc -O0 -g -Wall -Werror -target arm64-apple-macos13.0 -I ../autoeq/shim -I "$SRC" -I "$FX" \
        route.m "$FX"/AudioEffectsPresets.m "$FX"/AutoEq.m "$FX"/AudioEffectsSettings.m "$FX"/AudioEffectsFiles.m "$SRC"/Core/SGPrefs.m \
        "$SRC"/Core/SGLocalize.m -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT"
    echo "built $OUT"
    exit
fi
VENDOR=../../vendor/audio
ENGINE=../../tweak/Sources/Shared/AudioEffects
SANITIZE=$1
MAIN=main.m
if [ "$1" = regression ]; then
    MAIN=regression.m
    SANITIZE=
fi
make -s -C "$VENDOR" PLATFORM=mac ${SANITIZE:+SANITIZE=$SANITIZE} -j8
OUT=${OUT:-build/audio-effects${SANITIZE:+-$SANITIZE}}
mkdir -p "$(dirname "$OUT")"
xcrun clang -fobjc-arc -O2 -g -Wall -Werror -target arm64-apple-macos13.0 ${SANITIZE:+-fsanitize=$SANITIZE -O1 -fno-omit-frame-pointer} \
    -I ../../tweak/Sources -isystem "$VENDOR/libbs2b" -isystem "$VENDOR/eel2-parser" -isystem "$VENDOR/wdl/eel2" \
    "$MAIN" "$ENGINE"/SGDSPEngine.m "$ENGINE"/SGDSPFilters.m "$ENGINE"/SGDSPConvolver.m "$ENGINE"/SGDSPTone.m "$ENGINE"/SGDSPDynamics.m \
    "$ENGINE"/SGDSPCrossfeed.m "$ENGINE"/SGDSPReverb.m "$ENGINE"/SGDSPLiveprog.m "$VENDOR/build/mac${SANITIZE:+-$SANITIZE}/libsgaudio.a" \
    -framework Foundation -framework AudioToolbox -framework Accelerate -o "$OUT"
echo "built $OUT"
