#!/bin/bash
# The artist's cut-out round Play and the Artists page's preview of it (cutout-check.m), in a Mac Catalyst app of its
# own: the real SGRPlayCapsule (Kit/SGRActionRow.m), SGRHeaderInfo (Kit/SGRHeaderInfo.m) and Artists page
# (Artist/ArtistSettings.m with Kit/SGRPagePreview.m and the Settings framework), the accent hook replaced by the
# check's own accent. Launched with the settings off, cut-out on, and cut-out and accent on. Exits nonzero on a failure.
#     bash harness/artist/cutout-check.sh [baseline]
# CUTOUT_PNG=<dir> writes every drawing it checks there.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-artist-cutout.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
APP="$OUT/CutOut.app"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>cutout-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.artist.cutout-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>CutOutScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -Wno-deprecated-declarations \
    "$HERE/cutout-check.m" \
    "$SRC/Redesigned/Kit/SGRActionRow.m" "$SRC/Redesigned/Kit/SGRHeaderInfo.m" "$SRC/Redesigned/Kit/SGRGlass.m" \
    "$SRC/Redesigned/Kit/SGRGlyph.m" "$SRC/Redesigned/Kit/SGRRestyle.m" "$SRC/Redesigned/Kit/SGRDownload.m" \
    "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Redesigned/Kit/SGRPalette.m" "$SRC/Redesigned/Kit/SGRPagePreview.m" \
    "$SRC/Redesigned/Kit/SGRRollingDigits.m" "$SRC/Redesigned/Kit/SGRRefinements.m" \
    "$SRC/Redesigned/Artist/ArtistSettings.m" \
    "$SRC/Settings/SGPage.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Settings/SGModPage.m" "$SRC/Settings/SGSettingsSearch.m" \
    "$SRC/Settings/SGSettingsIndex.m" "$SRC/Settings/SGGlowSwitch.m" "$SRC/Settings/SGSourcesPage.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGGlass.m" "$SRC/Core/SGViewTree.m" \
    "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGUIMode.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols -framework CoreText \
    -o "$APP/Contents/MacOS/cutout-check"
codesign -f -s - "$APP" > /dev/null 2>&1
CHECK="$APP/Contents/MacOS/cutout-check"
if [ "${1:-}" = baseline ]; then
    "$CHECK" baseline
    exit
fi
"$CHECK" off
"$CHECK" on -spotifyglass.redesign.artist.roundPlay YES -spotifyglass.redesign.artist.cutOutPlay YES
"$CHECK" accent -spotifyglass.redesign.artist.roundPlay YES -spotifyglass.redesign.artist.cutOutPlay YES \
    -spotifyglass.redesign.accentPlay YES
