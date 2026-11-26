#!/bin/sh
# Builds the Mod Settings harness for the simulator: App/ModSettings.x run through Logos, App/Pages.m and the
# AboutSettings.m and Settings/ framework as they are in the tweak, stubs.m for other pages and actions.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=${OUT:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/ModSettingsHarness.app"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/App/ModSettings.x" > "$OUT/gen/ModSettings.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/App" -I"$SRC/Redesigned/Playlist" -I"$SRC/Redesigned/Search" -isysroot "$SDK" -Wall -Werror -Wno-deprecated-declarations -DSG_VERSION=\"1.0.0-harness\" \
    "$(dirname "$0")/main.m" "$(dirname "$0")/background-check.m" "$(dirname "$0")/information-check.m" "$(dirname "$0")/prompt-check.m" "$(dirname "$0")/../scene.m" "$(dirname "$0")/stubs.m" \
    "$OUT"/gen/ModSettings.m "$SRC"/App/Pages.m "$SRC"/App/About/Signing.m "$SRC"/App/About/AboutSettings.m "$SRC"/Shared/AnimatedArtwork/AnimatedArtworkSettings.m \
    "${APP_ICON_SOURCE:-$SRC/Shared/AppIcon/AppIcon.m}" "$SRC"/Shared/ArtistBlock/ArtistBlockSettings.m \
    "$SRC"/Settings/SGPage.m "${PAGE_STYLE_SOURCE:-$SRC/Settings/SGPageStyle.m}" "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m \
    "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Redesigned/Playlist/PlaylistSettings.m "$SRC"/Redesigned/Search/SearchSettings.m "$SRC"/Redesigned/Library/LibrarySettings.m \
    "$SRC"/Native/Home/HomeSettings.m "$SRC"/Native/Home/HomeGradientChoices.m \
    "$SRC"/Redesigned/Kit/SGRPagePreview.m "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m \
    "$SRC"/Redesigned/Kit/SGRAccentContext.m "$SRC"/Core/SGTopController.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    "${PROMPT_SOURCE:-$SRC/Shared/LyricsTranslation/TranslationPrompt.m}" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Security \
    -o "$OUT/ModSettingsHarness.app/ModSettingsHarness"

cat > "$OUT/ModSettingsHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ModSettingsHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.modsettingsharness</string>
<key>CFBundleName</key><string>ModSettingsHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>CFBundleIcons</key><dict><key>CFBundleAlternateIcons</key><dict><key>Fixture</key><dict><key>CFBundleIconFiles</key><array><string>Fixture</string></array></dict></dict></dict>
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
# The mod's translations, inside the app where cyan puts them in the IPA: launch with -AppleLanguages '(ko)' to read them.
cp -R "$SRC/../layout/Library/Application Support/Retrine.bundle" "$OUT/ModSettingsHarness.app/"
echo "built $OUT/ModSettingsHarness.app"
