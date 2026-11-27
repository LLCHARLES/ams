#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
SRC=${SRC:-"$HERE/../../tweak/Sources"}
OUT=${OUT:-"$HERE/build-readiness"}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -fmodules -DSGWG_TESTING -mmacosx-version-min=14.0 -Wall \
    -DSGWG_TEST_STATIC_ENGINE -I"$SRC" "$HERE/readiness.m" "$HERE/../../WireGuard/api.c" "$SRC/Shared/LyricsSources/LyricsHosts.m" -framework Foundation -framework Network -framework Security \
    -framework CoreFoundation -o "$OUT/readiness"
SGWG_TEST_ENABLED=0 "$OUT/readiness"
env -u SGWG_TEST_ENABLED "$OUT/readiness" --clear-credentials
SGWG_TEST_REPLAY=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_HOST=127.0.0.1 SGWG_TEST_PORT=1080 "$OUT/readiness" --external-proxy
SGWG_TEST_REPLAY=1 SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_HOST=127.0.0.1 SGWG_TEST_PORT=1080 "$OUT/readiness" --image-bursts
for delayed in "" SGWG_TEST_DELAY_ADMISSION=1; do
    env $delayed SGWG_TEST_REPLAY=1 SGWG_TEST_REFUSED=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 "$OUT/readiness" --external-proxy
done
SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_LOCKED_PROXY=1 "$OUT/readiness" --external-proxy
SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_LOCKED_PROXY=1 SGWG_TEST_TIMER_UNLOCK=1 "$OUT/readiness" --external-proxy
SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_SAVE_PASSWORD=1 "$OUT/readiness" --external-proxy
SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=socks5 SGWG_TEST_HOST=127.0.0.1 SGWG_TEST_PORT=1080 SGWG_TEST_ACTIVE_NOTICE=1 "$OUT/readiness" --external-proxy
SGWG_TEST_IMPORT_PROFILE=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 "$OUT/readiness" --delayed-admission
for success in "" SGWG_TEST_OLD_SUCCEEDS=1; do
    env $success SGWG_TEST_INFLIGHT_IMPORT=1 SGWG_TEST_IMPORT_PROFILE=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 "$OUT/readiness" --delayed-admission
done
SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
SGWG_TEST_INVALID=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
SGWG_TEST_FD_LIMIT=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
SGWG_TEST_SAME_PATH=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
SGWG_TEST_REFUSE_HANDOFF=1 SGWG_TEST_ENABLED=1 SGWG_TEST_KIND=wireguard SGWG_TEST_DELAY_ADMISSION=1 SGWG_TEST_PROFILE="$0" "$OUT/readiness" --delayed-admission
