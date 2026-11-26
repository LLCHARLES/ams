#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT=${OUT:-"$HERE/build/output"}
APP="$OUT/OutputHarness.app"
mkdir -p "$OUT/gen" "$APP"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/SpeedPitch.x" > "$OUT/gen/SpeedPitch.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -O1 -g \
    -isysroot "$SDK" -I"$SRC" -I"$SRC/Shared/Player" -I"$OUT/gen" -Wno-deprecated-declarations \
    "$HERE/output.m" "$HERE/../scene.m" "$SRC/Shared/Player/SGTimePitch.m" \
    "$SRC/Core/SGRebind.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGFlagForce.m" \
    -framework UIKit -framework Foundation -framework AVFoundation -framework AudioToolbox -framework QuartzCore \
    -o "$APP/OutputHarness"
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib,sys
info={'CFBundleExecutable':'OutputHarness','CFBundleIdentifier':'dev.retrine.audio-output',
      'CFBundleName':'OutputHarness','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','UILaunchScreen':{},
      'UIApplicationSceneManifest':{'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[
      {'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SGRHarnessScene'}]}}}
(Path(sys.argv[1])/'Info.plist').write_bytes(plistlib.dumps(info))
PY
printf '%s\n' "$APP"
