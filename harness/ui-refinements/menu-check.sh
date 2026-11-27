#!/bin/sh
# Play counts In menu (Redesigned/Album/AlbumPlaysMenu.x and AlbumRows.x through Logos) against mocks of Spotify's ⋯
# sheet and an album track cell, as a Mac Catalyst app; no simulator. Needs Theos ($THEOS, else ~/theos). The build
# goes to a temporary folder (or OUT) and is removed on exit unless OUT is given.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/ui-refinements-menu.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
APP=$OUT/UIRefinementsMenuCheck.app
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Album/AlbumPlaysMenu.x" > "$OUT/AlbumPlaysMenu.m"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Album/AlbumRows.x" > "$OUT/AlbumRows.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Redesigned/Album" -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
    "$OUT/AlbumPlaysMenu.m" "$OUT/AlbumRows.m" "$HERE/menu-check.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Redesigned/Album/AlbumSpotifyCounts.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    "$SRC/Redesigned/Album/AlbumPlaysPlace.m" "$SRC/Redesigned/Album/AlbumPlaysText.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$APP/Contents/MacOS/ui-refinements-menu-check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ui-refinements-menu-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.uirefinements.menucheck</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>SGUIRefinementsMenuScene</string>
</dict></array>
</dict></dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
for SOURCE in 0 1; do
    ALBUM_COUNTS_CACHE="$OUT/cache-menu-$SOURCE" "$APP/Contents/MacOS/ui-refinements-menu-check" \
        -spotifyglass.redesign.album.playCounts.source "$SOURCE" -spotifyglass.redesign.album.playCounts.place 2 -AppleLanguages '(en)' -AppleLocale en_US
done
ALBUM_COUNTS_CACHE="$OUT/cache-row" "$APP/Contents/MacOS/ui-refinements-menu-check" \
    -spotifyglass.redesign.album.playCounts.source 1 -spotifyglass.redesign.album.playCounts.place 1 -AppleLanguages '(en)' -AppleLocale en_US
