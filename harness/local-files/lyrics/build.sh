#!/bin/sh
# build.sh: builds the native look's lyrics page for a local file and the Imported LRC files page as the
# tweak compiles them into an app for the simulator and, given a booted simulator's UDID, runs it and saves
# a screenshot at each SHOT into ../build/lyrics/shots/. `settings` as the second argument shows the
# settings page instead of the lyrics page.
#
#     ./build.sh [<udid> [settings]]
set -eo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../../tweak/Sources" && pwd)
OUT=${OUT:-"$HERE/../build/lyrics"}   # harness/*/build/ is ignored
rm -rf "$OUT/LocalLyricsHarness.app"; mkdir -p "$OUT/LocalLyricsHarness.app" "$OUT/shots"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Native/LocalFiles/LocalLyricsButton.x" > "$OUT/footer.inc"
python3 "$HERE/../embedded-fixtures.py" "$OUT/tags"
cp "$OUT/tags/flac-plain" "$OUT/LocalLyricsHarness.app/tagged.flac"
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -Wall -Werror -Wno-deprecated-declarations \
    -I"$SRC" -I"$SRC/Native/LocalFiles" -I"$OUT" -isysroot "$SDK" \
    "$HERE/main.m" "$HERE/../../scene.m" "$HERE/footer.m" "$SRC/Native/LocalFiles/LocalLyricsPage.m" \
    "$SRC/Shared/LocalFiles/LocalLyricsPage.m" "$SRC/Shared/LocalFiles/LocalLyrics.m" "$SRC/Shared/LocalFiles/EmbeddedLyrics.m" "$SRC/Shared/LocalFiles/LyricRetirement.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/LyricsSources/SGTTML.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    "$SRC/Settings/SGPage.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Core/SGGlass.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGUIMode.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework UniformTypeIdentifiers -framework Foundation \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/LocalLyricsHarness.app/LocalLyricsHarness"
cat > "$OUT/LocalLyricsHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LocalLyricsHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.locallyricsharness</string>
<key>CFBundleName</key><string>LocalLyricsHarness</string>
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
echo "built $OUT/LocalLyricsHarness.app"
[ -n "$1" ] || exit 0
UDID=$1
xcrun simctl install "$UDID" "$OUT/LocalLyricsHarness.app"
python3 "$HERE/../../sim-launch.py" --live --terminate-running-process "$UDID" com.retrine.locallyricsharness "${2:-page}" capture-shots 2>&1 |
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
