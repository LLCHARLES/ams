#!/bin/sh
set -e
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build-browser}
mkdir -p "$OUT"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Connect/Connect.x" > "$OUT/Connect.m"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/PlayerState.x" > "$OUT/PlayerState.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios26.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -O0 -Wall -I"$OUT" -I"$SRC" -I"$SRC/Shared/Connect" -I"$SRC/Shared/Player" \
    "$(dirname "$0")/browser.m" "$OUT/PlayerState.m" "$SRC/Shared/Connect/SGConnectRelay.m" "$SRC/Shared/Connect/SGMDNS.m" "$SRC/Core/SGLog.m" \
    -framework UIKit -framework Network -o "$OUT/browser"
"$OUT/browser"
