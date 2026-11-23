#!/bin/sh
# Builds the glass choices harness for the iOS simulator into OUT (default build/): main.m over the real
# Redesigned/Kit/SGRGlass.m, SGRPlainCheck.x (through Logos), SGRRefinements.m, Core/SGGlass.m and Core/SGPrefs.m, with
# the finger of ../tabbar/touch.m. check.py runs it. Needs THEOS for logos.pl (default ~/theos).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=${OUT:-"$HERE/build"}
APP="$OUT/GlassChoicesHarness.app"
rm -rf "$APP" "$OUT/gen"
mkdir -p "$APP" "$OUT/gen"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Kit/SGRPlainCheck.x" > "$OUT/gen/SGRPlainCheck.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -fobjc-arc -g -O0 -isysroot "$SDK" \
    -I"$SRC" -iquote "$SRC/Redesigned/Kit" -Wall -Werror -Wno-deprecated-declarations -Wno-unused-parameter \
    "$HERE/main.m" "$HERE/../scene.m" "$HERE/../tabbar/touch.m" "$OUT/gen/SGRPlainCheck.m" \
    "$SRC/Redesigned/Kit/SGRGlass.m" "$SRC/Redesigned/Kit/SGRRefinements.m" \
    "$SRC/Core/SGGlass.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework IOKit \
    -o "$APP/GlassChoicesHarness"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>GlassChoicesHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.glass-choices-harness</string>
<key>CFBundleName</key><string>GlassChoicesHarness</string>
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
</dict></array></dict></dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
echo "built $APP"
