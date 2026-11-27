#!/bin/sh
# The glass bar in an iPad's regular width (README, ipad-check.sh), in an iPad simulator of the run's own, made for
# the run and deleted after it: every tab's name whole beside its glyph, and the fade down to the container's foot.
# Exits nonzero on the first failed check.
#     THEOS=$HOME/theos OUT=/tmp/<dir> ./ipad-check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${OUT:-$HERE/build}
OUT=$OUT sh "$HERE/build.sh"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/^iPad Pro 11-inch.*(\(com.apple.CoreSimulator.SimDeviceType.[^)]*\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "TabBarHarness-iPad-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$OUT/TabBarHarness.app"

# A launch that ends itself: the line it must print.
run() {
    expected=$1
    shift
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.vojta.tabbarharness "$@" > "$OUT/run.log" 2>&1 || true
    grep '\[harness\] \(PASS\|FAIL\)' "$OUT/run.log" || true
    grep -q "$expected" "$OUT/run.log" || { echo "FAILED: $*"; exit 1; }
}

run "PASS all names" names strict
run "PASS all names" names strict regular
run "PASS all fade" fade toggle regular
run "PASS panel fade edges" panel regular
echo "PASS tab bar iPad checks"
