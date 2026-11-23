#!/bin/sh
# The fade under the bars (README, fade-check.sh) in an iOS simulator of the run's own, made for the run and deleted
# after it. Exits nonzero on the first failed check.
#     THEOS=$HOME/theos OUT=/tmp/<dir> ./fade-check.sh
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

launch() {
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.vojta.tabbarharness "$@" > "$OUT/run.log" 2>&1 || true
    cat "$OUT/run.log"
}

# A launch that ends itself: the line it must print.
run() {
    expected=$1
    shift
    launch "$@"
    grep -q "$expected" "$OUT/run.log" || { echo "FAILED: $*"; exit 1; }
}

run "PASS all fade" fade toggle
run "PASS all fade" fade toggle split
run "PASS all fade" fade toggle regular
run "PASS all navsettings" navsettings
echo "PASS tab bar fade checks"
