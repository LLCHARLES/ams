#!/bin/sh
# build.sh: the meaning sheet's Translate action (Redesigned/Lyrics/MeaningSheet.m) and the shared plain-text
# translation it uses (Shared/LyricsTranslation/TextTranslation.m) as a Mac Catalyst app, with the translation
# services as doubles. No simulator and no network: the sheet's short sheet, its layout and its text are asserted.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/meaning-translate.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
APP=$OUT/MeaningTranslateCheck.app
if [ "${MEANING_SIMULATOR:-0}" = 1 ]; then
    SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
    TARGET=arm64-apple-ios17.0-simulator
    BUNDLE=$APP
    INSIDE=MeaningTranslateCheck
else
    SDK=$(xcrun --sdk macosx --show-sdk-path)
    TARGET=arm64-apple-ios17.0-macabi
    BUNDLE=$APP/Contents
    INSIDE=Contents/MacOS/MeaningTranslateCheck
    mkdir -p "$BUNDLE/MacOS"
fi
EXECUTABLE=$APP/$INSIDE
mkdir -p "$BUNDLE"
xcrun clang -target "$TARGET" -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$SRC/Redesigned/Lyrics" -Wall -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    "$HERE/check.m" "$HERE/../scene.m" \
    "${SHEET_SOURCE:-$SRC/Redesigned/Lyrics/MeaningSheet.m}" "${TEXT_SOURCE:-$SRC/Shared/LyricsTranslation/TextTranslation.m}" \
    -I"$SRC/Shared/LyricsTranslation" \
    "$SRC/Shared/LyricsTranslation/ProseSegments.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreText -framework Foundation \
    -o "$APP/$INSIDE"
cat > "$BUNDLE/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MeaningTranslateCheck</string>
<key>CFBundleIdentifier</key><string>com.retrine.meaningtranslate.check</string>
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
if [ "${MEANING_SIMULATOR:-0}" != 1 ]; then
    "$EXECUTABLE"
    if [ "${MEANING_UI_ONLY:-0}" != 1 ]; then OUT="$OUT/providers-build" sh "$HERE/providers-build.sh"; fi
fi
