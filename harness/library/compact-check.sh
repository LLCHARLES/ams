#!/bin/sh
# Compact library's checks (main.m `check`, settings-check.m) in an iOS simulator of the run's own, made for the run
# and deleted after it: Compact library off; on, with the list loading late, without a sort row and with a filter the
# menu has no clear chip for; on at the largest accessibility text size and right to left; the Library page of Mod
# Settings, left to right and right to left; on, with the top safe area changing under the folded chips, Spotify's
# passes setting the whole inset, the bottom first, or the stacked header's live height; and a header-only row move. SHOTS=<dir>
# keeps the screenshots the runs take. Exits nonzero on the first failed check.
#     THEOS=$HOME/theos ./compact-check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=${HARNESS_BUILD_DIR:-$HERE/build}
HARNESS_BUILD_DIR=$OUT sh "$HERE/build.sh"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "LibraryHarness-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$OUT/LibraryHarness.app"

# One launch: its words, then the line it must print.
run() {
    expected=$1
    shift
    xcrun simctl launch --console-pty --terminate-running-process "$UDID" com.vojta.libraryharness \
        -AppleLanguages '(en)' -AppleLocale en_US "$@" > "$OUT/run.log" 2>&1 || true
    cat "$OUT/run.log"
    if [ -n "${SHOTS:-}" ]; then
        mkdir -p "$SHOTS"
        sed -n 's/^SHOT //p' "$OUT/run.log" | tr -d '\r' | while read -r shot; do cp "$shot" "$SHOTS/"; done
    fi
    grep -q "$expected" "$OUT/run.log" || { echo "FAILED: $*"; exit 1; }
}

run "PASS all off" check
run "PASS all off" check wrapped
run "PASS all compact" check compact late
run "PASS all compact" check compact
run "PASS all nosort" check compact nosort
run "PASS all noclear" check compact noclear
run "PASS all compact" check compact wrapped
run "PASS all noclear" check compact noclear wrapped
run "PASS all safearea" check compact safearea
run "PASS all safearea" check compact wrapped safearea
run "PASS all safearea" check compact safearea bottomfirst
run "PASS all headerpass" check compact wrapped headerpass
run "PASS all safearea" check compact wrapped safearea liveinset
run "PASS all compact" check compact -tag large-text -UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL
run "PASS all compact" check compact -tag rtl -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES
run "PASS all settings" settings
run "PASS all settings" settings -tag rtl -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES

echo "PASS library compact checks"
