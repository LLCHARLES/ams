#!/bin/sh
# The now playing bar's text split (Redesigned/NowPlayingBar/NowPlayingBar.x placeText) as a Mac Catalyst app; no
# simulator. NowPlayingBar.x goes through Logos and is included in check.m, which plays Spotify's pages (with and
# without a device line, titles with and without " • ", the current track, a neighbor in the pager, a track the
# player does not know) over a player state double. Needs Theos ($THEOS, else ~/theos). The build goes to a
# temporary folder (or OUT) and is removed on exit unless OUT is given.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/now-playing-bar.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
APP=$OUT/NowPlayingBarCheck.app
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "$SRC/Redesigned/NowPlayingBar/NowPlayingBar.x" > "$OUT/NowPlayingBar.gen.m"
# The device button on the full card (SGRBarPlaceConnect), checked with the minimized row's tuck.
"$LOGOS" -c generator=internal "$SRC/Redesigned/NowPlayingBar/BarConnect.x" > "$OUT/BarConnect.gen.m"
python3 - "$SRC/Shared/Player/PlayerState.x" "$OUT/repeat.inc" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index("id SGPlayerAdvanceRepeat(")
pathlib.Path(sys.argv[2]).write_text(text[start:text.index("\nstatic NSHashTable", start)])
PY
if [ "${SIMULATOR:-0}" = 1 ]; then
    SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
    TARGET=arm64-apple-ios17.0-simulator
    FRAMEWORKS=
else
    SDK=$(xcrun --sdk macosx --show-sdk-path)
    TARGET=arm64-apple-ios17.0-macabi
    FRAMEWORKS="-iframework $SDK/System/iOSSupport/System/Library/Frameworks"
fi
xcrun clang -target "$TARGET" -fobjc-arc -g -O0 -isysroot "$SDK" $FRAMEWORKS \
    -I"$SRC" -I"$SRC/Redesigned/NowPlayingBar" -I"$OUT" -Wall -Werror -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations \
    "$HERE/check.m" "$HERE/../scene.m" "$HERE/stubs.m" "$OUT/BarConnect.gen.m" \
    "$SRC/Settings/SGMarquee.m" "$SRC/Redesigned/Kit/SGRTokens.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGGlass.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -o "$APP/Contents/MacOS/now-playing-bar-check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>now-playing-bar-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.nowplayingbar.check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
</dict></array>
</dict></dict>
</dict></plist>
PLIST
if [ "${SIMULATOR:-0}" = 1 ]; then
    cp "$APP/Contents/Info.plist" "$APP/Info.plist"
    mv "$APP/Contents/MacOS/now-playing-bar-check" "$APP/now-playing-bar-check"
    exit 0
fi
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/now-playing-bar-check"
