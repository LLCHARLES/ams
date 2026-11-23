#!/bin/sh
# One expand of the minimized bar with Search on its trailing circle (README, `capture`), recorded off the screen of an
# iOS simulator of the run's own, made for the run and deleted after it, and cut into PNGs of the screen's bottom
# 520 px: $OUT/capture/expand-NNN.png, NNN the 1/60 s from the last still frame before the expand to the one it settles
# on, each frame the screen drew once, and sheet.png with all of them. Words after the script go to the scenario:
# `selected` (Search the tab selected), `labels`, `middle`.
#     THEOS=$HOME/theos OUT=/tmp/<dir> ./capture.sh selected
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-$HERE/build}
OUT=$OUT sh "$HERE/build.sh"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "TabBarHarness-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$OUT/TabBarHarness.app"

FRAMES=$OUT/capture
rm -rf "$FRAMES"
mkdir -p "$FRAMES/all"
xcrun simctl io "$UDID" recordVideo --codec h264 --force "$OUT/capture.mov" >/dev/null 2>&1 &
RECORDER=$!
xcrun simctl launch --terminate-running-process "$UDID" com.vojta.tabbarharness search capture "$@" >/dev/null
# The scenario expands some 3 s after its launch (search.m) and settles 0.26 s later; the app stays up until the
# recording has stopped, so its end is not in it.
sleep 6
kill -INT "$RECORDER"
wait "$RECORDER"
xcrun simctl terminate "$UDID" com.vojta.tabbarharness

ffmpeg -loglevel error -i "$OUT/capture.mov" -vf "fps=60,crop=iw:520:0:ih-520" "$FRAMES/all/%05d.png"
python3 "$HERE/capture-frames.py" "$FRAMES/all" "$FRAMES"
rm -rf "$FRAMES/all" "$OUT/capture.mov"
echo "frames in $FRAMES"
