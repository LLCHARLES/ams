#!/bin/sh
# Builds the moving artwork harness for the Mac: SGMotionClip.m as the tweak compiles it, with the
# protobuf reader it uses, and main.m.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
sed '/^static void report/,$d' ../../tweak/Sources/Shared/Player/PlayerState.x > "$OUT/player-state.inc"
# Compile the Spotify ISRC reader, not the iOS Music Haptics hooks which follow it.
sed '/^#pragma mark - iOS$/,$d' ../../tweak/Sources/Shared/Haptics/SystemMusicHaptics.x > "$OUT/spotify-isrc.m"
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources \
    -DreadyForMoreMediaData=fixtureReady -DisReadyForMoreMediaData=isFixtureReady \
    -DrequestMediaDataWhenReadyOnQueue=fixtureRequestOnQueue -DappendSampleBuffer=fixtureAppend -DassetWriterWithURL=fixtureWriterWithURL \
    -c ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m -o "$OUT/shape.o"
xcrun clang -fobjc-arc -O2 -I ../../tweak/Sources \
    -framework Foundation -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework CoreGraphics \
    main.m "$OUT/shape.o" ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/motion"
# Count normalizations at the lyrics boundary while executing its real implementation.
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I ../../tweak/Sources -DSGLyricsSimplifiedTitle=fixtureSimplifiedTitle \
    -c ../../tweak/Sources/Shared/Lyrics/LyricsLanguage.m -o "$OUT/language.o"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -DSG_MOTION_TEST_STORE -I ../../tweak/Sources -I ../../tweak/Sources/Shared/Player -I "$OUT" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    -framework Network \
    state-check.m -I ../../tweak/Sources/Shared/Haptics "$OUT/spotify-isrc.m" ../../tweak/Sources/Shared/Haptics/SGHapticTrack.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionFollower.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m ../../tweak/Sources/Core/SGLog.m \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m "$OUT/language.o" -framework NaturalLanguage -Wl,-dead_strip \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    ../../tweak/Sources/Core/SGDataRoot.m -o "$OUT/state-check"
"$OUT/state-check"
relaunch=$(mktemp -d)
trap 'rm -rf "$relaunch"' EXIT
"$OUT/state-check" seed "$relaunch/album.plist"
"$OUT/state-check" relaunch "$relaunch/album.plist"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -fobjc-arc \
    -DSGBoundedRequestTask=fixtureHTTPTask -c ../../tweak/Sources/Shared/LyricsSources/SGBoundedRequest.m \
    -o "$OUT/transport.o"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I ../../tweak/Sources \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    sources-check.m ../../tweak/Sources/Shared/AnimatedArtwork/MotionSources.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m \
    "$OUT/transport.o" \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionClip.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m \
    -o "$OUT/sources-check"
"$OUT/sources-check"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I ../../tweak/Sources -framework UIKit -framework Foundation -framework AVFoundation -framework CoreMedia \
    store-check.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionStore.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m ../../tweak/Sources/Core/SGDataRoot.m -o "$OUT/store-check"
"$OUT/store-check" "$OUT/store-data"
"$OUT/store-check" missing-root
