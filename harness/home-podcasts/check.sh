#!/bin/sh
# Podcasts and audiobooks on Home (Redesigned/Home/HomeHeader.x) as a Mac Catalyst app; no simulator. HomeHeader.x goes
# through Logos and check.m includes its output and plays Spotify's filter chips over it. Needs Theos ($THEOS, else ~/theos). The build goes to a temporary folder (or OUT) and is
# removed on exit unless OUT is given. SRC points at another copy of tweak/Sources.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/home-podcasts.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
APP=$OUT/HomePodcastsCheck.app
mkdir -p "$APP/Contents/MacOS"
"$LOGOS" -c generator=internal "$SRC/Redesigned/Home/HomeHeader.x" > "$OUT/HomeHeader.gen.m"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Redesigned/Home" -I"$HERE/.." -I"$OUT" -Wall -Werror -Wno-unused-parameter -Wno-unused-function -Wno-deprecated-declarations \
    "$HERE/check.m" "$HERE/../scene.m" "$HERE/stubs.m" \
    "$SRC/Redesigned/Kit/SGRRestyle.m" "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Core/SGLocalize.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -o "$APP/Contents/MacOS/home-podcasts-check"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>home-podcasts-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.homepodcasts.check</string>
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
"$APP/Contents/MacOS/home-podcasts-check"
sh "$HERE/shelves.sh"
