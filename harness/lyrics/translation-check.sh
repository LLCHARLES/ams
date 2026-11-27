#!/bin/sh
# translation-check.sh: the lyrics menu's translation checks (translation-check.m) built for Mac Catalyst and run on
# the Mac, no simulator. Prints PASS and FAIL lines and exits with the number of failures.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${HARNESS_SOURCE_DIR:-$(cd "$HERE/../.." && pwd)/tweak/Sources}
OUT=${HARNESS_BUILD_DIR:-$(mktemp -d /tmp/lyrics-translation-check.XXXXXX)}
trap 'rm -rf "$OUT"' EXIT
APP=$OUT/Check.app
mkdir -p "$APP/Contents/MacOS"
SDK=$(xcrun --sdk macosx --show-sdk-path)
# As build.sh: main.m drives the real Keep screen on row, which stubs.m includes from here.
sed -n '/^#pragma mark - Keep screen on/,$p' "$SRC/Redesigned/Lyrics/LyricsTools.m" > "$OUT/awake-row-under-check.inc"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$OUT" -I"$SRC" -I"$SRC/Redesigned/Lyrics" -Wall -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../scene.m" "$HERE/stubs.m" "$HERE/translation-check.m" "$HERE/../sing/button/sing-stubs.m" \
    "$SRC"/Redesigned/Lyrics/AutoTranslatorName.m \
    "$HERE"/auto-source.m $( [ -f "$SRC"/Redesigned/Lyrics/TranslationStatusView.m ] && echo "$SRC"/Redesigned/Lyrics/TranslationStatusView.m ) "$HERE"/karaoke-source.m "$SRC"/Redesigned/Lyrics/LyricsText.m "$SRC"/Redesigned/Lyrics/LyricsLook.m "$SRC"/Redesigned/Lyrics/LyricsStyle.m \
    "$SRC"/Redesigned/Lyrics/SongLanguage.m "$SRC"/Redesigned/Lyrics/MeaningSheet.m "$SRC"/Redesigned/Lyrics/SGRSingButton.m \
    "$SRC"/Shared/Lyrics/KaraokeTiming.m "$SRC"/Shared/Lyrics/Romanise.m "$SRC"/Shared/Lyrics/LyricsLanguage.m \
    "$SRC"/Shared/LyricsMeanings/Meanings.m "$SRC"/Shared/LyricsSources/SongMatch.m "$SRC"/Shared/AdBlock/Protobuf.m "$SRC"/Shared/LyricsSources/SGTTML.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRGlass.m "$HERE"/download-source.m "$SRC"/Redesigned/Kit/SGRRestyle.m "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m "$HERE/../page-style-with-presenter-stubs.m" "$SRC"/Core/SGViewTree.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -framework Symbols -framework NaturalLanguage -o "$APP/Contents/MacOS/Check"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Check</string>
<key>CFBundleIdentifier</key><string>com.vojta.lyricsharness.translationcheck</string>
<key>CFBundleVersion</key><string>1</string>
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
if [ "${SG_LYRICS_CLOCK_ONLY:-0}" = 1 ]; then
    mkdir -p "$APP/Contents/Resources"
    cp "$HERE/fixtures/plain.lrc" "$HERE/fixtures/static.txt" "$HERE/fixtures/duet.ttml" "$APP/Contents/Resources/"
fi
codesign -f -s - "$APP" >/dev/null 2>&1
if [ "${SG_LYRICS_CLOCK_ONLY:-0}" = 1 ]; then
    "$APP/Contents/MacOS/Check" -song plain -frameRateCheck 1
    "$APP/Contents/MacOS/Check" -song static -plainIdle 1
else
    "$APP/Contents/MacOS/Check" -translationCheck 1
fi
