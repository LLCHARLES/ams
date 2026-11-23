#!/bin/sh
# The page headers' scroll veil, top-bar clip and Play (hero-veil-check.h, ../artist/main.m verifyPlay) on the album,
# playlist and artist harnesses: builds the three into OUT, installs them on the booted simulator UDID, and runs each
# with the veil on and off, the album and the playlist with it on their square covers too, and the artist's Play as a
# capsule in the page's color and round in the accent. The screenshots the runs ask for land in OUT as
# <page>-<veil|veil-card|veil-off>-<d|mid>.png. Exits 1 if any run fails.
#
#     THEOS=$HOME/theos harness/album/veil-check.sh <UDID> [OUT]
set -e
UDID=$1
OUT=${2:-/tmp/retrine-veil-check}
HARNESS=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
for page in album playlist artist; do
    HARNESS_BUILD_DIR="$OUT/build-$page" sh "$HARNESS/$page/build.sh" > /dev/null
    xcrun simctl install "$UDID" "$OUT/build-$page"/*.app
done

status=0
# run <bundle id> <the PASS line it has to log> <launch arguments...>
run() {
    id=$1 expected=$2
    shift 2
    log="$OUT/$(echo "$id $*" | tr -c 'A-Za-z0-9.\n-' '_').log"
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" "$id" "$@" 2>&1 | tr -ud '\r' | while IFS= read -r line; do
        echo "$line"
        case "$line" in *"[harness] SHOT "*) xcrun simctl io "$UDID" screenshot "$OUT/${line##*SHOT }.png" > /dev/null 2>&1 ;; esac
    done > "$log"
    if grep -q '\[harness\] FAIL' "$log" || ! grep -q "$expected" "$log"; then
        echo "FAILED: $id $*"
        grep '\[harness\]' "$log" | tail -n 5
        status=1
    else
        grep -o '\[harness\] PASS.*' "$log"
    fi
}

VEIL="-spotifyglass.redesign.hero.scrollVeil YES"
for page in album playlist artist; do
    # shellcheck disable=SC2086
    run "com.vojta.${page}harness" "PASS $page veil:" veil $VEIL
    run "com.vojta.${page}harness" "PASS $page veil off" veil-off
done
# Square covers; the album's without its animated cover, which fills the whole hero over a square as well.
# shellcheck disable=SC2086
run com.vojta.albumharness "PASS album veil-card:" veil-card $VEIL -spotifyglass.redesign.album.fullCover NO \
    -spotifyglass.redesign.album.motion NO
# shellcheck disable=SC2086
run com.vojta.playlistharness "PASS playlist veil-card:" veil-card $VEIL -spotifyglass.redesign.playlist.fullCover NO
run com.vojta.artistharness "PASS artist play capsule in the page's color" verify-play
run com.vojta.artistharness "PASS artist play round in the accent" verify-play \
    -spotifyglass.redesign.artist.roundPlay YES -spotifyglass.redesign.playInPageColour NO
exit $status
