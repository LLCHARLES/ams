#!/bin/sh
set -e
# The sources of the checkout this harness sits in, unless SRC names others (an older tree, to compare).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/TabBarHarness.app"

for f in Shared/Navigation/Links.x Redesigned/Navbar/TabBar.x Redesigned/Navbar/TabBarMinimize.x Redesigned/NowPlayingBar/NowPlayingBar.x Redesigned/NowPlayingBar/BarConnect.x; do
    name=$(basename "$f" .x)
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Navbar" -I"$SRC/Redesigned/NowPlayingBar" -I"$SRC/Redesigned/Kit" -I"$SRC/Shared/Navigation" -I"$OUT/gen" -isysroot "$SDK" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" "$(dirname "$0")/touch.m" "$(dirname "$0")/navsettings.m" "$(dirname "$0")/search.m" \
    "$OUT"/gen/*.m "$SRC"/Shared/Navigation/LinkURL.m "$SRC"/Shared/Navigation/InboundLinks.m \
    "$SRC"/Redesigned/Navbar/NavbarSettings.m "$SRC"/Shared/Navigation/AddTabSheet.m "$SRC"/Redesigned/Kit/SGRPagePreview.m "$SRC"/Redesigned/Kit/SGRPalette.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Settings/SGSourcesPage.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGLocalize.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRPress.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m "$SRC"/Settings/SGMarquee.m \
    "$SRC"/Redesigned/Navbar/NavbarLayout.m "$SRC"/Shared/Navigation/TabIcons.m \
    -framework UIKit -framework IOKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$OUT/TabBarHarness.app/TabBarHarness"

# iOS 27 ends an app without a scene delegate at launch, so the scene is named here.
cat > "$OUT/TabBarHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>TabBarHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.tabbarharness</string>
<key>CFBundleName</key><string>TabBarHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
codesign -f -s - "$OUT/TabBarHarness.app" >/dev/null 2>&1
echo "built $OUT/TabBarHarness.app"
