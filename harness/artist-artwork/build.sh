#!/bin/bash
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d /tmp/retrine-artist-artwork.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
FLAGS=(-target arm64-apple-ios17.0-macabi -isysroot "$SDK"
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks"
    -fobjc-arc -I ../../tweak/Sources
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo)
xcrun -sdk macosx clang "${FLAGS[@]}" -DSG_MOTION_TEST_STORE main.m ../album-notes/catalog-boundary.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m \
    ../../tweak/Sources/Shared/Lyrics/LyricsLanguage.m -framework NaturalLanguage -Wl,-dead_strip \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    ../../tweak/Sources/Core/SGDataRoot.m -o "$OUT/retrine-artist-artwork-check"
RETRINE_TEST_ROOT="$OUT/catalog" "$OUT/retrine-artist-artwork-check" fixtures/catalog.json
xcrun -sdk macosx clang "${FLAGS[@]}" late-check.m ../../tweak/Sources/Redesigned/Artist/ArtistArtwork.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/retrine-artist-late-check"
"$OUT/retrine-artist-late-check"
xcrun -sdk macosx clang "${FLAGS[@]}" header-check.m ../../tweak/Sources/Redesigned/Artist/ArtistArtwork.m \
    ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/retrine-artist-header-check"
"$OUT/retrine-artist-header-check"
xcrun -sdk macosx clang "${FLAGS[@]}" download-check.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionStore.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m \
    ../../tweak/Sources/Core/SGDataRoot.m -o "$OUT/retrine-artist-download-check"
RETRINE_TEST_ROOT="$OUT/downloads" "$OUT/retrine-artist-download-check"
