#!/bin/sh
# Builds the lyrics PiP text harness for the Mac: LyricsPiPText.m as the tweak compiles it, with
# KaraokeTiming.m and Protobuf.m to link. Lyrics.h imports UIKit, so build for Mac Catalyst.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=${OUT:-$HERE/build}
mkdir -p "$OUT"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/SpeedPitchMenu.x" > "$OUT/SpeedPitchMenu.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall \
    -I"$SRC" -I"$SRC/Shared/Player" -I"$OUT" \
    "$HERE/main.m" "$SRC/Shared/LyricsPiP/LyricsPiPText.m" "$SRC/Shared/LyricsPiP/LyricsPiPFrame.m" \
    "$SRC/Shared/LyricsPiP/LyricsPiPStyle.m" "$HERE/typography.m" \
    "$SRC/Shared/LyricsPiP/LyricsPiPBackground.m" "$HERE/background.m" \
    "$HERE/lifecycle.m" "$HERE/native-menu.m" "$HERE/redesign-menu.m" \
    "$SRC/Shared/Player/SpeedPitchSongs.m" \
    "$SRC/Shared/AudioEffects/AudioEffectsSettings.m" \
    "$HERE/settings.m" "$SRC/Shared/LyricsPiP/LyricsPiPSettings.m" \
    "$SRC/Shared/LyricsBackground/LyricsBackgroundSettings.m" \
    "$SRC/Shared/LyricsBackground/LyricsBackground.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Core/SGViewTree.m" "$HERE/../page-style-with-presenter-stubs.m" \
    -framework UIKit -framework Foundation -framework CoreText -framework ImageIO -framework CoreGraphics -framework Accelerate \
    -framework AVKit -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework QuartzCore \
    -o "$OUT/lyrics-pip"
