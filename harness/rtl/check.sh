#!/bin/sh
# Builds check.m with the real Settings framework, Sing card and mic, and recap story into a temporary folder, then
# runs it left to right and right to left on a simulator of its own, shut down and deleted after; or on the booted
# simulator <udid> when one is given, which is left as it was.
#     THEOS=$HOME/theos sh harness/rtl/check.sh [udid]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/rtl-check.XXXXXX")
UDID=${1:-}
OWN=""
# The simulators this check makes are named by this prefix; no other simulator has it.
PREFIX=RetrineRTLCheck-
cleanup() {
    if [ -n "$OWN" ]; then xcrun simctl shutdown "$OWN" >/dev/null 2>&1 || true; xcrun simctl delete "$OWN" || true; fi
    rm -rf "$OUT"
}
trap cleanup EXIT
# A cancelled run (SIGTERM, then SIGKILL two seconds on) still goes through cleanup when it can.
trap 'exit 143' TERM INT
APP=$OUT/RTLCheck.app
mkdir -p "$OUT/gen" "$APP"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/ListeningStats/ListeningStats.x" > "$OUT/gen/ListeningStats.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -isysroot "$SDK" -Wall -Wno-deprecated-declarations \
    -Wno-undeclared-selector -I"$SRC" -I"$SRC/Shared/ListeningStats" "$HERE/check.m" \
    "$HERE/../sing/button/sing-stubs.m" "$HERE/../listening-stats/sim/stubs.m" "$OUT/gen/ListeningStats.m" \
    "$SRC"/Shared/Sing/SGSingCard.m "$SRC"/Settings/SGMarquee.m \
    "$SRC"/Redesigned/Lyrics/SGRSingButton.m "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRTokens.m \
    "$SRC"/Shared/ListeningStats/ListeningStatsPage.m "$SRC"/Shared/ListeningStats/SGPlayLog.m \
    "$SRC"/Shared/ListeningStats/SGTopCharts.m "$SRC"/Shared/ListeningStats/SGRecap.m \
    "$SRC"/Shared/ListeningStats/TopChartPage.m "$SRC"/Shared/ListeningStats/RecapStory.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m \
    "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    "$SRC"/Core/SGGlass.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGDataRoot.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework UniformTypeIdentifiers -framework Symbols \
    -o "$APP/RTLCheck"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>RTLCheck</string>
<key>CFBundleIdentifier</key><string>com.retrine.rtlcheck</string>
<key>CFBundleName</key><string>RTLCheck</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
if [ -z "$UDID" ]; then
    # What a killed run left behind: only simulators of this check's own name. One line, because
    # scripts/harness-plan.py audits each line of a registered script on its own.
    for stale in $(xcrun simctl list devices | sed -nE "s/^ *${PREFIX}[0-9]+ \(([0-9A-F-]+)\).*/\1/p"); do
        xcrun simctl shutdown "$stale" >/dev/null 2>&1 || true
        xcrun simctl delete "$stale"
    done
    OWN=$(xcrun simctl create "$PREFIX$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
    UDID=$OWN
    xcrun simctl boot "$UDID"
    xcrun simctl bootstatus "$UDID" -b >/dev/null
fi
xcrun simctl install "$UDID" "$APP"
status=0
for direction in ltr rtl; do
    set -- "$direction"
    [ "$direction" = rtl ] && set -- rtl -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES
    xcrun simctl launch --console --terminate-running-process "$UDID" com.retrine.rtlcheck "$@" > "$OUT/$direction.log" 2>&1 || true
    if grep -q "\[harness\] PASS $direction" "$OUT/$direction.log"; then echo "PASS $direction"
    else echo "FAIL $direction"; grep "\[harness\]" "$OUT/$direction.log" | tail -3; status=1; fi
done
xcrun simctl uninstall "$UDID" com.retrine.rtlcheck
exit $status
