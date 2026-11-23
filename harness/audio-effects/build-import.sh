#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
FX="$SRC/Shared/AudioEffects"
OUT=${OUT:-"$HERE/build/import"}
APP="$OUT/ImportHarness.app"
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g \
    -isysroot "$SDK" -I"$SRC" -I"$FX" \
    "$HERE/import.m" "$HERE/../scene.m" "$FX/AudioEffectsSettings.m" \
    "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework Foundation -framework UniformTypeIdentifiers \
    -o "$APP/ImportHarness"
python3 - "$APP" <<'PY'
from pathlib import Path
import plistlib,sys
info={'CFBundleExecutable':'ImportHarness','CFBundleIdentifier':'dev.retrine.audio-import',
      'CFBundleName':'ImportHarness','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','UILaunchScreen':{},
      'UIApplicationSceneManifest':{'UISceneConfigurations':{'UIWindowSceneSessionRoleApplication':[
      {'UISceneConfigurationName':'Default','UISceneDelegateClassName':'SGRHarnessScene'}]}}}
(Path(sys.argv[1])/'Info.plist').write_bytes(plistlib.dumps(info))
PY
printf '%s\n' "$APP"
