#!/bin/sh
# The album header's artist faces (faces-check.h) and the track rows' ⋯ in the page's colour (more-check.h), in a
# simulator of its own, made for the run and deleted after it, on the album harness build.sh built (in build/, or
# HARNESS_BUILD_DIR): the faces left to right, right to left and at the largest text size, the ⋯ with and without
# Increase Contrast. Exits nonzero on any failure.
# SHOTS=<dir> keeps the screenshots the runs ask for (album-faces-two-on/-off, album-faces-trio, album-more, suffixed
# for the variants).
#     THEOS=$HOME/theos sh harness/album/build.sh && THEOS=$HOME/theos sh harness/album/faces-more-check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP=${HARNESS_BUILD_DIR:-$HERE/build}/AlbumHarness.app
THEOS=${THEOS:-$HOME/theos}
export THEOS
WORK=$(mktemp -d "${TMPDIR:-/tmp}/album-faces-more.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
SHOTS=${SHOTS:-}

SOURCE=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; print(next(d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == "iPhone 17 Pro"))')
UDID=$(xcrun simctl clone "$SOURCE" "AlbumFacesMore-$$")
trap 'xcrun simctl delete "$UDID"; rm -rf "$WORK"' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" > /dev/null
xcrun simctl ui "$UDID" content_size large
xcrun simctl ui "$UDID" increase_contrast disabled
xcrun simctl install "$UDID" "$APP"

RUN="python3 $HERE/run-scenario.py $UDID"
RTL="-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES"
COLOURED="-coverFixture colourful -spotifyglass.redesign.album.motion NO"
status=0
# shellcheck disable=SC2086
$RUN "PASS album faces ltr" --shots "$SHOTS" -- faces || status=1
# shellcheck disable=SC2086
$RUN "PASS album faces rtl" --shots "$SHOTS" --suffix=-rtl -- $RTL faces || status=1
xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
# shellcheck disable=SC2086
$RUN "capped at 22" --shots "$SHOTS" --suffix=-largest -- faces || status=1
xcrun simctl ui "$UDID" content_size large
# shellcheck disable=SC2086
$RUN "PASS album more: ⋯ at L 0.80" --shots "$SHOTS" -- $COLOURED more || status=1
xcrun simctl ui "$UDID" increase_contrast enabled
# shellcheck disable=SC2086
$RUN "PASS album more: ⋯ at L 0.88" --shots "$SHOTS" --suffix=-contrast -- $COLOURED more || status=1
xcrun simctl ui "$UDID" increase_contrast disabled

if [ "$status" -eq 0 ]; then
    xcrun simctl shutdown "$UDID"
    python3 "$HERE/beside-check.py" --screenshots "${SHOTS:-$WORK/ipad}" || status=1
fi

exit $status
