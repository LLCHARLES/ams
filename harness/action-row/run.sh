#!/bin/sh
# Builds the action row harness (main.m says what it checks) and runs it in English, Korean and Russian on a simulator
# of its own (an iPhone 17 Pro, created for the run and deleted after it). SHOTS names a folder for the screenshots;
# SPOTIFY_IPA and HARNESS_SRC go to build.sh. Exits nonzero when a language fails.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/action-row.XXXXXX")
UDID=
cleanup() {
    if [ -n "$UDID" ]; then
        xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
        xcrun simctl delete "$UDID"
    fi
    rm -rf "$OUT"
}
trap cleanup EXIT
HARNESS_BUILD_DIR=$OUT/build sh "$HERE/build.sh"
UDID=$(xcrun simctl create retrine-action-row com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$OUT/build/ActionRowHarness.app"
[ -n "${SHOTS:-}" ] && mkdir -p "$SHOTS"
status=0
for language in en ko ru; do
    SIMCTL_CHILD_HARNESS_SHOTS=${SHOTS:-} xcrun simctl launch --console-pty "$UDID" com.retrine.actionrowharness \
        -AppleLanguages "($language)" > "$OUT/$language.log" 2>&1 || true
    grep -a '\[harness\]' "$OUT/$language.log" | sed 's/^.*\[harness\]/[harness]/'
    grep -aq 'all checks passed' "$OUT/$language.log" || { echo "[harness] action-row $language: FAILED"; status=1; }
done
exit $status
