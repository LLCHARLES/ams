#!/bin/sh
# Builds the listening stats harness for the Mac: SGPlayLog.m as the tweak compiles it, and main.m.
set -e
cd "$(dirname "$0")"
OUT=${BUILD_DIR:-build}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
xcrun clang -fobjc-arc -O2 -Wall -Werror -I ../../tweak/Sources -framework Foundation \
    main.m ../../tweak/Sources/Shared/ListeningStats/SGPlayLog.m ../../tweak/Sources/Shared/ListeningStats/SGTopCharts.m \
    ../../tweak/Sources/Shared/ListeningStats/SGRecap.m ../../tweak/Sources/Core/SGLocalize.m -o "$OUT/listening-stats"
SRC=$(cd ../../tweak/Sources && pwd)
SDK=$(xcrun --sdk macosx --show-sdk-path)
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/ListeningStats/ListeningStats.x" > "$OUT/ListeningStats.m"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -O2 -Wall -Werror \
    -I"$SRC" -I"$SRC/Shared/ListeningStats" recorder.m "$OUT/ListeningStats.m" \
    "$SRC/Shared/ListeningStats/SGPlayLog.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT/recorder"
# The recorder checks count plays from an empty log, so every run starts from an empty home. Without
# the daemon bypass, cfprefsd would write the "recorder" defaults to the real ~/Library/Preferences.
rm -rf "$OUT/recorder-home"
mkdir -p "$OUT/recorder-home"
__CFPREFERENCES_AVOID_DAEMON=1 CFFIXED_USER_HOME="$OUT/recorder-home" "$OUT/recorder"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -O2 -Wall -Werror \
    -I"$SRC" album-plays.m "$SRC/Redesigned/Album/AlbumPlays.m" \
    "$SRC/Shared/ListeningStats/SGPlayLog.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework Foundation -o "$OUT/album-plays"
"$OUT/album-plays"
