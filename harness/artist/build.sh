#!/bin/sh
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=${HARNESS_BUILD_DIR:-$(dirname "$0")/build}
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/ArtistHarness.app"

for f in Redesigned/Artist/ArtistField.x Redesigned/Artist/ArtistHeader.x Redesigned/Artist/ArtistSections.x Redesigned/Artist/ArtistFollow.x Redesigned/Kit/SGRHeaderAppearance.x; do
    name=$(basename "$f" .x)
    source="$SRC/$f"
    if [ "$name" = ArtistSections ] && [ -n "${HARNESS_ARTIST_SECTIONS_SOURCE:-}" ]; then
        source="$HARNESS_ARTIST_SECTIONS_SOURCE"
    fi
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$source" > "$OUT/gen/$name.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Artist" -I"$OUT/gen" -isysroot "$SDK" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" "$(dirname "$0")/stubs.m" \
    "$OUT"/gen/*.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m "$SRC"/Settings/SGPageStyle.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m "$SRC"/Shared/AnimatedArtwork/SGMotionCatalog.m "$SRC"/Shared/AnimatedArtwork/SGMotionStore.m "$SRC"/Shared/AnimatedArtwork/SGMotionTicket.m \
    "$SRC"/Shared/Lyrics/LyricsLanguage.m -framework NaturalLanguage -Wl,-dead_strip \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m "$SRC"/Redesigned/Kit/SGRStretchHero.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m "$SRC"/Redesigned/Kit/SGRHeaderClip.m -I"$SRC/Redesigned/Kit" \
    "$SRC"/Redesigned/Artist/ArtistArtwork.m "$SRC"/Shared/AnimatedArtwork/SGMotionClip.m "$SRC"/Shared/AdBlock/Protobuf.m \
    "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m "$SRC"/Redesigned/Kit/SGRCoverRead.m \
    -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols -framework CoreText -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Vision \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/ArtistHarness.app/ArtistHarness"

cat > "$OUT/ArtistHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ArtistHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.artistharness</string>
<key>CFBundleName</key><string>ArtistHarness</string>
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
echo "built $OUT/ArtistHarness.app"
