#!/bin/sh
# Build the requested executable only; analyzer and ring are manual modes.
set -e
cd "$(dirname "$0")"
OUT=${OUT:-build}
mkdir -p "$OUT"
case "${1:-track}" in
system)
SRC=../../tweak/Sources
SDK=$(xcrun --sdk macosx --show-sdk-path)
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${SYSTEM_HAPTICS:-$SRC/Shared/Haptics/SystemMusicHaptics.x}" > "$OUT/SystemMusicHaptics.m"
xcrun clang -fobjc-arc -target $(uname -m)-apple-ios18.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$OUT" -I"$SRC" -I"$SRC/Shared/Haptics" \
    system-check.m "$SRC/Shared/Haptics/SGHapticTrack.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework MediaPlayer -framework Foundation -o "$OUT/system"
"$OUT/system"
    ;;
analyzer)
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation -framework AudioToolbox \
    main.m ../../tweak/Sources/Shared/Haptics/SGMusicAnalyzer.m -o "$OUT/haptics"
    ;;
track)
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    track.m ../../tweak/Sources/Shared/Haptics/SGHapticTrack.m ../../tweak/Sources/Shared/AdBlock/Protobuf.m -o "$OUT/track"
    ;;
ring)
xcrun clang -fobjc-arc -O1 -g -Wall -Werror -fsanitize=thread -I ../../tweak/Sources -framework Foundation \
    ring.m -o "$OUT/ring"
    ;;
*) echo "usage: $0 [track|analyzer|ring|system]" >&2; exit 2 ;;
esac
