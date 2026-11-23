#!/bin/sh
# Builds the onboarding harness for the simulator: the welcome tour (Tour.m) and the What's new sheet
# (WhatsNew.m, with App/About/Update.m's parser), with generated notes isolated in OUT.
set -e
cd "$(dirname "$0")"
SRC=$(cd ../../tweak/Sources && pwd)
OUT=${OUT:-build}
VERSION=${1:-0.20.0}
rm -rf "$OUT"; mkdir -p "$OUT/OnboardingHarness.app"
mkdir -p "$OUT/onboarding"
cp "$SRC/App/Onboarding/WhatsNew.m" "$OUT/onboarding/WhatsNew.m"
ALLOW_UPSTREAM=1 ../../scripts/whats-new.sh "$VERSION" ../../CHANGELOG.md "$OUT/onboarding/SGWhatsNewNotes.h"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/App/Onboarding" -isysroot "$SDK" -Wno-deprecated-declarations -DSG_VERSION="\"$VERSION\"" \
    main.m sponsorblock-check.m "$SRC"/App/Onboarding/Tour.m "$OUT"/onboarding/WhatsNew.m "$SRC"/App/Onboarding/Environment.m \
    "$SRC"/App/About/Update.m \
    "$SRC"/Shared/SponsorBlock/SponsorBlockSettings.m "$SRC"/Shared/SponsorBlock/SponsorBlockPrefs.m \
    "$SRC"/Shared/SponsorBlock/SponsorBlockModel.m \
    "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGSettingsSearch.m "$SRC"/Settings/SGSettingsIndex.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$OUT/OnboardingHarness.app/OnboardingHarness"

# A stand-in for EeveeSpotify's dylib, which the install check finds by its name alone.
echo 'void sg_stand_in(void) {}' | xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" \
    -x c - -dynamiclib -o "$OUT/OnboardingHarness.app/EeveeSpotify.dylib"

cat > "$OUT/OnboardingHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>OnboardingHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.onboardingharness</string>
<key>CFBundleName</key><string>OnboardingHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>Scene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
cp -R "$SRC/../layout/Library/Application Support/Retrine.bundle" "$OUT/OnboardingHarness.app/"
codesign -f -s - "$OUT/OnboardingHarness.app" >/dev/null 2>&1
echo "built $OUT/OnboardingHarness.app"
