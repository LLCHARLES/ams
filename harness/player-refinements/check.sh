#!/bin/sh
# Rolling time digits and Star add button with Plain checkmark (Redesigned/Kit/SGRRefinements.h) as a Mac Catalyst
# app; no simulator. SGRPlainCheck.x goes through Logos. Needs Theos ($THEOS, else ~/theos). Runs three times, the
# settings as launch arguments: `both` (Plain checkmark's old switch and Star add button on), `plain` (the old switch
# alone, Saved mark unset) and `dot` (Saved mark's Dot stored beside the old switch). The
# build goes to a temporary folder (or OUT) and is removed on exit unless OUT is given.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/player-refinements.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
APP=$OUT/PlayerRefinementsCheck.app
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Kit/SGRPlainCheck.x" > "$OUT/SGRPlainCheck.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Redesigned/Kit" -Wall -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    "$OUT/SGRPlainCheck.m" "$HERE/check.m" "$HERE/../scene.m" \
    "$SRC/Redesigned/Kit/SGRRefinements.m" "$HERE/rolling-under-check.m" "$SRC/Redesigned/Kit/SGRRestyle.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -o "$APP/Contents/MacOS/player-refinements-check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>player-refinements-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.playerrefinements.check</string>
<key>CFBundleVersion</key><string>1</string>
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
codesign -f -s - "$APP" >/dev/null 2>&1
"$APP/Contents/MacOS/player-refinements-check" -harness.mode both \
    -spotifyglass.redesign.plainCheck YES -spotifyglass.redesign.player.starAdd YES
"$APP/Contents/MacOS/player-refinements-check" -harness.mode plain \
    -spotifyglass.redesign.plainCheck YES
"$APP/Contents/MacOS/player-refinements-check" -harness.mode dot \
    -spotifyglass.redesign.plainCheck YES -spotifyglass.redesign.savedMark 2
