#!/bin/sh
# Builds the AirPods gestures simulator harness: HeadGestures.x through Logos, its page, the detector and
# the Settings/ framework as they are in the tweak, main.m standing in for Spotify and the headphones.
set -e
SRC=$(cd "$(dirname "$0")/../../../tweak/Sources" && pwd)
OUT=${OUT:-$(dirname "$0")/../build/sim}
mkdir -p "$OUT/gen" "$OUT/HeadGesturesSim.app"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/HeadGestures/HeadGestures.x" > "$OUT/gen/HeadGestures.m"

# The repeat transition as PlayerState.x has it, so HeadGestures.x links the real one; the Logos observer
# hooks in that file are not compiled here (main.m stands in for SGPlayer, the state and the observers).
python3 - "$SRC/Shared/Player/PlayerState.x" "$OUT/gen/player-state-repeat.inc" <<'PY'
import pathlib
import re
import sys

source = pathlib.Path(sys.argv[1]).read_text()
name = "SGPlayerAdvanceRepeat"
matches = re.findall(r"^[^\n]*\b" + name + r"\([^\n]*\) \{\n.*?^\}", source, re.M | re.S)
if len(matches) != 1:
    raise SystemExit(f"expected one complete definition of {name}, found {len(matches)}")
pathlib.Path(sys.argv[2]).write_text(matches[0] + "\n")
PY

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Shared/HeadGestures" -I"$OUT/gen" -isysroot "$SDK" -Wall -Werror -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/player-state-repeat.m" "$(dirname "$0")/../../scene.m" "$OUT/gen/HeadGestures.m" \
    "$SRC"/Shared/HeadGestures/HeadGesturesSettings.m "${TEACH_SOURCE:-$SRC/Shared/HeadGestures/HeadGesturesTeach.m}" \
    "$SRC"/Shared/HeadGestures/SGHeadDetector.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework CoreMotion -framework AudioToolbox -framework AVFoundation \
    -o "$OUT/HeadGesturesSim.app/HeadGesturesSim"

cat > "$OUT/HeadGesturesSim.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>HeadGesturesSim</string>
<key>CFBundleIdentifier</key><string>com.retrine.headgesturessim</string>
<key>CFBundleName</key><string>HeadGesturesSim</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>NSMotionUsageDescription</key><string>The harness reads made-up head motion.</string>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "built $OUT/HeadGesturesSim.app"
