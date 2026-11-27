#!/bin/sh
# Builds the now playing check for the Mac, as a Mac Catalyst tool: the two hooks of the now playing setter
# through Logos as the tweak builds them, Karaoke's timing, and main.m. Runs it with lock screen lyrics off
# and on.
set -e
# SRC may point at another checkout of tweak/Sources (an older commit, to see a bug before its fix).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen"

# In the tweak's order (its Makefile sorts the files), so the setter's hooks nest the same way.
for f in Shared/AnimatedArtwork/LockScreenMotion.x Shared/ArtistBlock/ArtistSkip.x Shared/LockScreenLyrics/LockScreenLyrics.x Shared/LockScreenLyrics/LyricsArtwork.x Shared/Player/NowPlayingExtras.x Shared/LiveActivity/LiveActivity.x; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$(basename "$f" .x).m"
done

# main.m first, so its constructor replaces the system's setter before the hooks wrap it.
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios26.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -O0 -Wall -I"$OUT/gen" -I"$SRC" -I"$SRC/Shared/ArtistBlock" -I"$SRC/Shared/LockScreenLyrics" -I"$SRC/Shared/AnimatedArtwork" -I"$SRC/Shared/LiveActivity" \
    "$(dirname "$0")/main.m" "$(dirname "$0")/artwork.m" "$(dirname "$0")/activity.m" "$(dirname "$0")/motion-dispatch-driver.m" \
    "$OUT/gen/ArtistSkip.m" "$(dirname "$0")/row-clock-driver.m" "$(dirname "$0")/art-clock-driver.m" "$(dirname "$0")/extras-clock-driver.m" "$(dirname "$0")/activity-clock-driver.m" \
    "$SRC/Shared/AnimatedArtwork/SGMotionFollower.m" "$SRC/Shared/AnimatedArtwork/SGMotionTicket.m" "$SRC/Core/SGOptionalWork.m" "$SRC/Core/SGLog.m" \
    "$SRC/Shared/Player/SGLastTrack.m" "$SRC/Core/SGFileHash.m" \
    "$SRC/Shared/LyricsBackground/LyricsBackground.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/Lyrics/Romanise.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework MediaPlayer -framework CoreGraphics -framework Accelerate -framework Network "$SRC/Core/SGDataRoot.m" -o "$OUT/now-playing"

"$OUT/now-playing"
LSL=1 "$OUT/now-playing"
OUT="$OUT/resend" sh "$(dirname "$0")/build-resend.sh"
OUT="$OUT/upgrade" sh "$(dirname "$0")/build-artwork-upgrade.sh"
