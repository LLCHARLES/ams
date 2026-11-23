#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-"$HERE/../../tweak/Sources"}
OUT=${OUT:-"$HERE/build-readiness"}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -fmodules -DSGWG_TESTING -mmacosx-version-min=14.0 -Wall \
    -I"$SRC" "$HERE/readiness.m" "$SRC/Shared/LyricsSources/LyricsHosts.m" -framework Foundation -framework Network -framework Security \
    -framework CoreFoundation -o "$OUT/readiness"
SGWG_TEST_ENABLED=0 "$OUT/readiness"
SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_HOST=127.0.0.1 SGWG_TEST_PORT=1080 "$OUT/readiness" --external-proxy
SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
