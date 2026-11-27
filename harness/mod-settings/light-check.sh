#!/bin/sh
# The alerts the mod brings up over Spotify's dark pages, with the phone in Light Mode and in Dark Mode. Spotify's
# Info.plist sets no appearance and its window takes the system's, only its navigation stacks are dark, so the
# harness's Info.plist key goes and the app runs with `system` (main.m). In a simulator of the run's own, deleted
# after it, each alert is brought up through the real SGModPage, Pages.m and SGPageStyle.m, screenshotted, and the
# frame `look` logs is judged: its mean luminance over 0-255 must stay under DARK_MAX, which a light alert's glass
# (about 150) is far over and a dark one's (about 30) far under. Exits nonzero on a light alert.
#     THEOS=$HOME/theos ./light-check.sh        LIGHT_SHOTS=<dir> keeps the screenshots
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mod-settings-light.XXXXXX")
SHOTS=${LIGHT_SHOTS:-$WORK/png}
DARK_MAX=80
mkdir -p "$SHOTS"
OUT="$WORK/build" "$HERE/build.sh" >/dev/null
APP="$WORK/build/ModSettingsHarness.app"
plutil -remove UIUserInterfaceStyle "$APP/Info.plist"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "ModSettingsLight-$$" "$TYPE" "$RUNTIME")
# Each step runs whatever the one before it did, so a failed shutdown never leaves the simulator behind.
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true; rm -rf "$WORK"' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$APP"

# name, then the launch line's actions; the Redesigned UI switch is the main page's first row.
SCENARIOS="info:alerts info
lock:alerts lock
warn:alerts toggle=0.1
restart:toggle=0.0
information:alerts information"
FAILED=0
for MODE in light dark; do
    xcrun simctl ui "$UDID" appearance "$MODE"
    echo "$SCENARIOS" | while IFS=: read -r NAME ACTIONS; do
        START=$(date '+%Y-%m-%d %H:%M:%S')
        # shellcheck disable=SC2086
        xcrun simctl launch --terminate-running-process "$UDID" com.retrine.modsettingsharness \
            -AppleLanguages '(en)' -AppleLocale en_US system $ACTIONS look >/dev/null
        # One action every 0.9 s from 1 s in (main.m), then the rows a switch moves and the alert's own animation.
        sleep $(( $(echo $ACTIONS | wc -w) + 6 ))
        xcrun simctl io "$UDID" screenshot "$SHOTS/$MODE-$NAME.png" >/dev/null 2>&1
        LOOK=$(xcrun simctl spawn "$UDID" log show --start "$START" --style compact \
            --predicate 'eventMessage CONTAINS "[harness] look"' | grep -o 'look .*' | tail -1)
        python3 - "$SHOTS/$MODE-$NAME.png" "$MODE $NAME" "$DARK_MAX" "$LOOK" <<'PY' || echo fail >> "$WORK/failed"
import re, sys
from PIL import Image
path, name, dark_max, look = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
m = re.search(r'look (\S+) controller (\S+) presentation (\S+) frame \{\{([-\d.]+), ([-\d.]+)\}, \{([\d.]+), ([\d.]+)\}\} window (\d+)', look)
if not m or m.group(1) != 'UIAlertController':
    print(f'{name}: FAIL no alert presented ({look!r})'); sys.exit(1)
image = Image.open(path).convert('L')
scale = image.width / float(m.group(8))
x, y, w, h = (float(v) * scale for v in m.group(4, 5, 6, 7))
crop = image.crop((int(x), int(y), int(x + w), int(y + h)))
mean = sum(crop.getdata()) / (crop.width * crop.height)
ok = mean < dark_max
print(f'{name}: {m.group(1)} controller {m.group(2)}, presentation {m.group(3)}, luminance {mean:.0f} {"dark" if ok else "FAIL light"}')
sys.exit(0 if ok else 1)
PY
    done
done
[ -f "$WORK/failed" ] && FAILED=1
[ "$FAILED" = 0 ] && echo "mod settings light: every alert dark"
exit "$FAILED"
