#!/bin/sh
# Transport-boundary check; an isolated source copy supports mutation testing.
set -eu
cd "$(dirname "$0")"
SRC=$(cd ../../tweak/Sources && pwd)
OUT=$(mktemp -d /tmp/retrine-adnetwork.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${ADNETWORK_SOURCE:-$SRC/Shared/AdBlock/AdNetwork.x}" > "$OUT/AdNetwork.m"
xcrun clang -fobjc-arc -fblocks -O0 -finstrument-functions -Wall -Werror -I "$OUT" -I shim -I ../shared/foundation -I "$SRC/Shared/AdBlock" \
    network-check.m -framework Foundation -o "$OUT/network-check"
for ads in 0 1; do
    for premium in 0 1; do
        HIDE_ADS=$ads FAKE_PREMIUM=$premium "$OUT/network-check"
    done
done
for ads in 0 1; do
    HIDE_ADS=$ads FAKE_PREMIUM=0 REAL_SESSION=1 "$OUT/network-check"
done
