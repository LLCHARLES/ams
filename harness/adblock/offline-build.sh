#!/bin/sh
# Execute production host hooks and Pixie's exported transformer in a late-loaded dylib.
set -eu
cd "$(dirname "$0")"
SRC=$(cd ../../tweak/Sources && pwd)
PIXIE=$(cd ../../NativeDownloads/src && pwd)
OUT=$(mktemp -d /tmp/retrine-offline-attributes.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${ADNETWORK_SOURCE:-$SRC/Shared/AdBlock/AdNetwork.x}" > "$OUT/AdNetwork.m"
xcrun clang -c -fobjc-arc -fblocks -fvisibility=hidden -std=gnu11 \
    -I "$PIXIE" -I "$PIXIE/Public" -I "$PIXIE/Spotify" -I "$PIXIE/Generated" \
    "${OFFLINE_CONFIG_SOURCE:-$PIXIE/Spotify/OfflineConfig.m}" -o "$OUT/OfflineConfig.o"
xcrun clang -dynamiclib -fobjc-arc -fblocks -fvisibility=hidden -std=gnu11 \
    -I "$PIXIE/Public" -I "$PIXIE/Spotify" -I "$SRC/Shared/AdBlock" \
    offline-companion.m "$OUT/OfflineConfig.o" "$PIXIE/Spotify/WireProto.m" \
    -framework Foundation -o "$OUT/SpotifyAudioProbe.dylib"
xcrun clang -fobjc-arc -fblocks -O0 -Wall -Werror -I "$OUT" -I shim -I ../shared/foundation \
    -I "$SRC" -I "$SRC/Shared/AdBlock" offline-check.m "${PREMIUM_SOURCE:-$SRC/Shared/AdBlock/Premium.m}" \
    "$SRC/Shared/AdBlock/OfflineCompanion.m" "$SRC/Shared/AdBlock/Protobuf.m" -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT/offline-check"
for premium in ${OFFLINE_PREMIUM_CASES:-0 1}; do
    FAKE_PREMIUM=$premium CFFIXED_USER_HOME="$OUT" "$OUT/offline-check" "$OUT/SpotifyAudioProbe.dylib"
    if [ -z "${REVIEW_REGRESSIONS:-}${RECHECK_REGRESSIONS:-}" ]; then
        RECHECK_REGRESSIONS=1 FAKE_PREMIUM=$premium CFFIXED_USER_HOME="$OUT" "$OUT/offline-check" "$OUT/SpotifyAudioProbe.dylib"
    fi
done
if [ -z "${REVIEW_REGRESSIONS:-}" ]; then
    cp "$OUT/SpotifyAudioProbe.dylib" "$OUT/Unrelated.dylib"
    FOREIGN_COMPANION=1 FAKE_PREMIUM=0 CFFIXED_USER_HOME="$OUT" "$OUT/offline-check" "$OUT/Unrelated.dylib"
    mkdir "$OUT/old"
    xcrun clang -dynamiclib -fobjc-arc -fblocks -fvisibility=hidden -std=gnu11 \
        -I "$PIXIE/Public" -I "$PIXIE/Spotify" -I "$SRC/Shared/AdBlock" \
        offline-companion.m "$OUT/OfflineConfig.o" "$PIXIE/Spotify/WireProto.m" \
        -Wl,-exported_symbol,_SAPRewriteOfflineAccountAttributes \
        -Wl,-exported_symbol,_SGTestSetAdmitted -Wl,-exported_symbol,_SGTestSetAdmissionObserver \
        -framework Foundation -o "$OUT/old/SpotifyAudioProbe.dylib"
    OLD_COMPANION=1 FAKE_PREMIUM=0 CFFIXED_USER_HOME="$OUT" "$OUT/offline-check" "$OUT/old/SpotifyAudioProbe.dylib"
fi
