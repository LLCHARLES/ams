#!/bin/sh
# build.sh: the redesign's lyrics view (Redesigned/Lyrics/SGRKaraokeView.m) for the simulator, to hold a line: the
# menu it opens, Copy's pasteboard, Share's text and VoiceOver's actions. ../lyrics/stubs.m stands in for the player.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
APP=$HERE/build/LyricsHoldHarness.app
rm -rf "$HERE/build"; mkdir -p "$APP"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Lyrics" -isysroot "$SDK" -Wall -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../scene.m" "$HERE/../lyrics/stubs.m" "$HERE/../sing/button/sing-stubs.m" \
    "$SRC"/Redesigned/Lyrics/SGRKaraokeView.m "$SRC"/Redesigned/Lyrics/LyricsText.m "$SRC"/Redesigned/Lyrics/LyricsLook.m \
    "$SRC"/Redesigned/Lyrics/LyricsStyle.m "$SRC"/Redesigned/Lyrics/SGRSingButton.m "$SRC"/Redesigned/Lyrics/MeaningSheet.m \
    "$SRC"/Redesigned/Lyrics/AutoTranslatorName.m "$SRC"/Redesigned/Lyrics/AutoTranslation.m \
    "$SRC"/Redesigned/Lyrics/TranslationStatusView.m "$SRC"/Redesigned/Lyrics/SongLanguage.m \
    "$SRC"/Shared/Lyrics/KaraokeTiming.m "$SRC"/Shared/Lyrics/Romanise.m "$SRC"/Shared/Lyrics/LyricsLanguage.m \
    "$SRC"/Shared/LyricsMeanings/Meanings.m "$SRC"/Shared/LyricsSources/SongMatch.m "$SRC"/Shared/AdBlock/Protobuf.m \
    "$SRC"/Shared/LyricsSources/SGTTML.m "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRGlass.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -framework NaturalLanguage -framework Symbols -o "$APP/LyricsHoldHarness"

cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>LyricsHoldHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.lyricsholdharness</string>
<key>CFBundleName</key><string>Lyrics hold</string>
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
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1
echo "built $APP"
