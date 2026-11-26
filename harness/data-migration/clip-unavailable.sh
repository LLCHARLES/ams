#!/bin/bash
# The now-playing harness supplies the player and MediaPlayer boundary, including its video request handler.
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
src=$(cd ../../tweak/Sources && pwd)
np=../now-playing
mkdir -p "$out/gen" "$out/clip-home" "$out/clip-temp"
for f in Shared/AnimatedArtwork/LockScreenMotion.x Shared/ArtistBlock/ArtistSkip.x Shared/LockScreenLyrics/LockScreenLyrics.x Shared/LockScreenLyrics/LyricsArtwork.x Shared/Player/NowPlayingExtras.x Shared/LiveActivity/LiveActivity.x; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$src/$f" > "$out/gen/$(basename "$f" .x).m"
done
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios26.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I"$out/gen" -I"$src" -I"$src/Shared/ArtistBlock" -I"$src/Shared/LockScreenLyrics" \
    -I"$src/Shared/AnimatedArtwork" -I"$src/Shared/LiveActivity" clip-main.m clip-unavailable.m "$np/activity.m" \
    "$out"/gen/{LockScreenMotion,ArtistSkip,LockScreenLyrics,LyricsArtwork,NowPlayingExtras}.m "$np/activity-clock-driver.m" \
    "$src/Shared/AnimatedArtwork/SGMotionFollower.m" "$src/Shared/AnimatedArtwork/SGMotionTicket.m" \
    "$src/Core/SGOptionalWork.m" "$src/Core/SGLog.m" "$src/Core/SGFileHash.m" "$src/Core/SGDataRoot.m" \
    "$src/Shared/Player/SGLastTrack.m" "$src/Shared/LyricsBackground/LyricsBackground.m" "$src/Shared/Lyrics/KaraokeTiming.m" "$src/Shared/Lyrics/Romanise.m" \
    "$src/Shared/AdBlock/Protobuf.m" -framework UIKit -framework MediaPlayer -framework CoreGraphics -framework Accelerate -framework Network \
    -o "$out/clip-unavailable"
__CFPREFERENCES_AVOID_DAEMON=1 CFFIXED_USER_HOME="$out/clip-home" TMPDIR="$out/clip-temp" LSL=1 "$out/clip-unavailable"
