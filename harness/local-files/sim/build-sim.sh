#!/bin/sh
# build-sim.sh: builds the Edit info harness for the simulator (EditInfoMenu.x and LocalFiles.m as the
# tweak compiles them) and, given a booted simulator's UDID, installs it, runs it and saves a screenshot
# at each SHOT into ../build/sim/shots/. `large` as a second argument runs it once at the largest accessibility
# text size and sets the size back after.
#
#     THEOS=$HOME/theos ./build-sim.sh [<udid> [large]]
set -eo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../../tweak/Sources" && pwd)
OUT=${OUT:-"$HERE/../build/sim"}   # harness/*/build/ is ignored
LOCAL=${LOCAL:-"$SRC/Shared/LocalFiles"}
rm -rf "$OUT/gen" "$OUT/EditInfoHarness.app"; mkdir -p "$OUT/gen" "$OUT/EditInfoHarness.app" "$OUT/shots"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$LOCAL/EditInfoMenu.x" > "$OUT/gen/EditInfoMenu.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -Wall \
    -I"$SRC" -I"$SRC/Shared/LocalFiles" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../../scene.m" "$OUT/gen/EditInfoMenu.m" "$LOCAL/LocalFiles.m" "$LOCAL/LocalInfoLookup.m" "$LOCAL/LocalInfoReview.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGGlass.m" "$SRC/Core/SGViewTree.m" \
    "$SRC/Settings/SGPageStyle.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework UniformTypeIdentifiers -framework Foundation -framework ImageIO \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/EditInfoHarness.app/EditInfoHarness"
cat > "$OUT/EditInfoHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>EditInfoHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.editinfoharness</string>
<key>CFBundleName</key><string>EditInfoHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
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
echo "built $OUT/EditInfoHarness.app"
[ -n "$1" ] || exit 0
UDID=$1
xcrun simctl install "$UDID" "$OUT/EditInfoHarness.app"
if [ "$2" = large ]; then
    xcrun simctl ui "$UDID" content_size accessibility-extra-extra-extra-large
    trap 'xcrun simctl ui "$UDID" content_size large' EXIT
fi

python3 "$HERE/../../sim-launch.py" --live --terminate-running-process "$UDID" com.retrine.editinfoharness "${2:-editor}" capture-shots 2>&1 |
while IFS= read -r line; do
    echo "$line"
    case "$line" in
        *"[harness] CAPTURE "*)
            capture=${line##*CAPTURE }
            shot=${capture%% *}
            ack=${capture#* }
            xcrun simctl io "$UDID" screenshot "$OUT/shots/$shot.png" >/dev/null
            touch "$ack"
            ;;
    esac
done
