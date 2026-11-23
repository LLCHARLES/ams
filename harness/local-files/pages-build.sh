#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT=${BUILD_DIR:?Set BUILD_DIR to an isolated output directory}
SDK=$(xcrun --sdk macosx --show-sdk-path)
mkdir -p "$OUT/home"
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -Wno-deprecated-declarations -I"$SRC" "$HERE/pages-check.m" "$SRC/Shared/LocalFiles/LocalMusicIndex.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    "$SRC/Shared/LocalFiles/LocalMusicCache.m" "$SRC/Shared/LocalFiles/LocalMusicPlaybackRules.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework ImageIO -framework AVFoundation -framework CoreMedia "$SRC/Core/SGDataRoot.m" -o "$OUT/pages"
CFFIXED_USER_HOME="$OUT/home" "$OUT/pages"
[ $# -gt 0 ] || exit 0
APP="$OUT/LocalPagesHarness.app"
mkdir -p "$APP" "$OUT/shots"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
    -fobjc-arc -g -Wall -Werror -Wno-deprecated-declarations -I"$SRC" \
    "$HERE/sim/pages-main.m" "$SRC/Shared/LocalFiles/LocalMusicIndex.m" "$SRC/Shared/LocalFiles/LocalMusicStore.m" \
    "$SRC/Shared/LocalFiles/LocalMusicPages.m" "$SRC/Shared/LocalFiles/LocalFiles.m" "$SRC/Shared/LocalFiles/LocalAudioImport.m" \
    "$SRC/Shared/LocalFiles/LocalMusicCache.m" "$SRC/Shared/LocalFiles/LocalMusicShelf.m" "$SRC/Shared/LocalFiles/LocalMusicPlaybackRules.m" \
    "$SRC/Settings/SGPage.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Core/SGGlass.m" "$SRC/Core/SGViewTree.m" \
    "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGLog.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework AVFoundation -framework CoreMedia \
    "$SRC/Core/SGDataRoot.m" -o "$APP/LocalPagesHarness"
python3 - "$APP" "$1" "$OUT" <<'PY'
import pathlib, plistlib, subprocess, sys, threading
app, device, out = sys.argv[1:]
with open(pathlib.Path(app) / "Info.plist", "wb") as f:
    plistlib.dump({
        "CFBundleExecutable": "LocalPagesHarness", "CFBundleIdentifier": "com.retrine.localpagesharness",
        "CFBundleName": "LocalPagesHarness", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
        "UILaunchScreen": {}, "UIUserInterfaceStyle": "Dark",
        "UIApplicationSceneManifest": {"UIApplicationSupportsMultipleScenes": False,
            "UISceneConfigurations": {"UIWindowSceneSessionRoleApplication": [
                {"UISceneConfigurationName": "Default", "UISceneDelegateClassName": "PagesScene"}]}}
    }, f)
subprocess.run(["xcrun", "simctl", "install", device, app], check=True)
process = subprocess.Popen(["xcrun", "simctl", "launch", "--console", device, "com.retrine.localpagesharness"],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
passed = False
timed_out = threading.Event()
def stop_stalled():
    timed_out.set()
    subprocess.run(["xcrun", "simctl", "terminate", device, "com.retrine.localpagesharness"], check=True)
    process.terminate()
timer = threading.Timer(40, stop_stalled)
timer.start()
try:
    for line in process.stdout:
        print(line, end="", flush=True)
        if "[harness] SHOT " in line:
            name = line.split("[harness] SHOT ", 1)[1].strip()
            subprocess.run(["xcrun", "simctl", "io", device, "screenshot", str(pathlib.Path(out) / "shots" / (name + ".png"))], check=True)
        if "[harness] SHOT " in line or "[harness] NEXT" in line:
            subprocess.run(["xcrun", "simctl", "spawn", device, "notifyutil", "-p", "com.retrine.localpages.next"], check=True)
        if "[harness] PASS local pages navigation" in line:
            passed = True
    result = process.wait()
    if result or not passed or timed_out.is_set():
        sys.exit("local pages simulator check failed")
finally:
    timer.cancel()
    timer.join()
    if process.poll() is None:
        process.terminate()
        process.wait()
PY
