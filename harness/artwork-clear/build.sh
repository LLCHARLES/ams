#!/bin/sh
# Builds and runs the clear-artwork check on the Mac: the production store, catalog and settings row against a
# sandboxed Caches folder, an offline catalog and fake clip transfers. OUT=<directory> isolates the binary;
# STORE, CATALOG and SETTINGS name replacement copies of those three files.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
SRC=../../tweak/Sources
ART=$SRC/Shared/AnimatedArtwork
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi \
    -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I $SRC -I $ART \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    -framework Network -Wl,-undefined,dynamic_lookup \
    clear-check.m "${STORE:-$ART/SGMotionStore.m}" "${CATALOG:-$ART/SGMotionCatalog.m}" "${SETTINGS:-$ART/AnimatedArtworkSettings.m}" \
    "$SRC"/Shared/Lyrics/LyricsLanguage.m -framework NaturalLanguage -Wl,-dead_strip \
    $ART/SGMotionTicket.m $ART/SGMotionClip.m $SRC/Shared/AdBlock/Protobuf.m $SRC/Core/SGLog.m \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/artwork-clear-check"
"$OUT/artwork-clear-check"
