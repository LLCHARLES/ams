#!/bin/sh
# Run the real Hub hook on macOS; an optional source path supports isolated mutation checks.
set -eu
cd "$(dirname "$0")"
SRC=$(cd ../../tweak/Sources && pwd)
OUT=$(mktemp -d /tmp/retrine-adblock.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${1:-$SRC/Shared/AdBlock/AdHubs.x}" > "$OUT/AdHubs.m"
xcrun clang -fobjc-arc -O0 -Wall -Werror -I shim -I ../shared/foundation -I "$SRC/Shared/AdBlock" \
    check.m "$OUT/AdHubs.m" -framework Foundation -o "$OUT/adblock-check"
for ads in 0 1; do
    for upsells in 0 1; do
        HIDE_ADS=$ads HIDE_UPSELLS=$upsells "$OUT/adblock-check"
    done
done
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${ADSERVICES_SOURCE:-$SRC/Shared/AdBlock/AdServices.x}" > "$OUT/AdServices.m"
xcrun clang -fobjc-arc -fblocks -O0 -Wall -Werror -I "$OUT" -I shim -I "$SRC/Shared/AdBlock" \
    services-check.m -framework Foundation -o "$OUT/services-check"
for ads in 0 1; do
    for upsells in 0 1; do
        HIDE_ADS=$ads HIDE_UPSELLS=$upsells "$OUT/services-check"
        SPOTIFY_920=1 HIDE_ADS=$ads HIDE_UPSELLS=$upsells "$OUT/services-check"
    done
done
python3 dj-check.py
sh network-build.sh
sh offline-build.sh
python3 -B audit-check.py ../../scripts/audit-ad-services.py
sh settings-check.sh
