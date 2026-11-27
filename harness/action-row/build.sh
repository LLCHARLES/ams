#!/bin/sh
# Builds ActionRowHarness.app for the simulator (main.m says what it checks). SPOTIFY_IPA (default ipa/Spotify-9.2.0.ipa)
# gives Spotify's strings bundle, the words for Play and Pause; HARNESS_SRC a tweak source tree other than this one's;
# HARNESS_BUILD_DIR where the app goes (default build/ here).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
SRC=${HARNESS_SRC:-$ROOT/tweak/Sources}
OUT=${HARNESS_BUILD_DIR:-$HERE/build}
IPA=${SPOTIFY_IPA:-$ROOT/ipa/Spotify-9.2.0.ipa}
APP=$OUT/ActionRowHarness.app
rm -rf "$OUT"
mkdir -p "$APP"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -isysroot "$SDK" \
    -I"$SRC" -Wall -Wno-unused-function -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../scene.m" "$HERE/stubs.m" "$HERE/../page-style-with-presenter-stubs.m" \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m \
    "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m \
    "$SRC"/Redesigned/Kit/SGRHeroVeil.m "$SRC"/Redesigned/Kit/SGRedesign.m "$SRC"/Redesigned/Kit/SGRPress.m \
    "$SRC"/Redesigned/Kit/SGRCoverViewer.m "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m \
    -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreImage \
    -framework Foundation -framework Symbols -framework CoreText \
    -o "$APP/ActionRowHarness"

unzip -q -o "$IPA" 'Payload/Spotify.app/SPTStrings.bundle/*' -d "$OUT/ipa"
mv "$OUT/ipa/Payload/Spotify.app/SPTStrings.bundle" "$APP/"
rm -rf "$OUT/ipa"
# The languages the harness runs in: the app's preferred localization is the one SGRSpotifyControlWords reads.
for language in en ko ru; do
    mkdir -p "$APP/$language.lproj"
    echo '"CFBundleName" = "ActionRowHarness";' > "$APP/$language.lproj/InfoPlist.strings"
done

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ActionRowHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.actionrowharness</string>
<key>CFBundleName</key><string>ActionRowHarness</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
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
codesign -f -s - "$APP" >/dev/null 2>&1
echo "built $APP"
