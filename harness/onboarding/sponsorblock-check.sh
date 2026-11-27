#!/bin/sh
# Both translations, production settings rows and the welcome switch, on an isolated simulator.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/retrine-tour.XXXXXX")
udid=""
cleanup() {
    if [ -n "$udid" ]; then xcrun simctl shutdown "$udid"; xcrun simctl delete "$udid"; fi
    rm -rf "$work"
}
trap cleanup EXIT
trap 'exit 143' TERM INT
OUT="$work/build" sh "$here/build.sh"
udid=$(xcrun simctl create "SponsorBlock-tour-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
app="$work/build/OnboardingHarness.app"
xcrun simctl spawn "$udid" "$app/OnboardingHarness" environment-check
xcrun simctl install "$udid" "$app"
launch() {
    expected=$1; shift
    status=0
    python3 "$here/../sim-launch.py" --timeout 240 "$udid" com.retrine.onboardingharness "$@" >"$work/result" 2>&1 || status=$?
    cat "$work/result"
    if [ "$status" -ne 0 ] || ! grep -Fq "$expected" "$work/result"; then
        echo "[harness] FAIL $*: launch status $status, expected '$expected'" >&2
        # Preserve scene/termination diagnostics before deleting the device.
        xcrun simctl spawn "$udid" log show --last 5m --style compact --info --predicate 'process == "OnboardingHarness" OR (process IN {"SpringBoard", "runningboardd"} AND eventMessage CONTAINS[c] "com.retrine.onboardingharness")' | tail -40 >&2
        exit 1
    fi
}
launch 'PASS kept cleanup size, delete action and dark environment alerts' kept-cleanup -spotifyglass.language 1
for language in 1 2; do
    launch 'PASS SponsorBlock settings layout and tour opt-in' old sponsorblock-check -spotifyglass.language "$language"
done
