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
OUT="$work/build" sh "$here/build.sh"
udid=$(xcrun simctl create "SponsorBlock-tour-$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b >/dev/null
app="$work/build/OnboardingHarness.app"
xcrun simctl spawn "$udid" "$app/OnboardingHarness" environment-check
xcrun simctl install "$udid" "$app"
for language in 1 2; do
    xcrun simctl launch --console "$udid" com.retrine.onboardingharness old sponsorblock-check \
        -spotifyglass.language "$language" >"$work/result" 2>&1 || { cat "$work/result"; exit 1; }
    cat "$work/result"
    grep -q 'PASS SponsorBlock settings layout and tour opt-in' "$work/result"
done
