#!/bin/sh
set -e
# SRC may point at another checkout of tweak/Sources (an older commit, to see a bug before its fix).
SRC=${SRC:-$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)}
OUT=${OUT:-$(dirname "$0")/build}
if [ "${PLAYER_INCREMENTAL:-0}" != 1 ]; then rm -rf "$OUT"; fi
mkdir -p "$OUT/gen" "$OUT/PlayerHarness.app"

for f in Redesigned/Player/PlayerLyrics.x Redesigned/Player/PlayerLyricLine.x Redesigned/Player/PlayerArtwork.x Redesigned/Player/PlayerFooter.x \
         Redesigned/Player/PlayerScroll.x Redesigned/Player/PlayerField.x Redesigned/Player/PlayerMotion.x Redesigned/Player/PlayerLandscape.x Redesigned/Player/PlayerControls.x Redesigned/Player/PlayerHeader.x Redesigned/Player/PlayerCoverAccent.x Redesigned/Player/DJPlayer.x Redesigned/Player/PlayerMix.x Redesigned/Kit/SGRBridges.x \
         Shared/Player/AudioQuality.x Shared/Player/VideoSwitch.x; do
    name=$(basename "$f" .x)
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$f" > "$OUT/gen/$name.m.new"
    if ! cmp -s "$OUT/gen/$name.m.new" "$OUT/gen/$name.m"; then
        mv "$OUT/gen/$name.m.new" "$OUT/gen/$name.m"
    else
        rm "$OUT/gen/$name.m.new"
    fi
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
# Only the mutation runner opts in, with one private output directory for its lifetime.
# Clang's dependency files invalidate objects for included headers as well as source edits.
compile() {
    if [ "${PLAYER_INCREMENTAL:-0}" != 1 ]; then
        xcrun -sdk iphonesimulator clang "$@"
        return
    fi
    python3 - "$OUT" "$@" <<'PY'
import json, shlex, subprocess, sys
from pathlib import Path

out = Path(sys.argv[1])
args = sys.argv[2:]
sources, flags, libraries = [], [], []
i = 0
while i < len(args):
    arg = args[i]
    if arg == "-framework":
        libraries.extend(args[i:i + 2])
        i += 2
    elif arg == "-o":
        binary = args[i + 1]
        i += 2
    elif arg in ("-target", "-isysroot", "-include"):
        flags.extend(args[i:i + 2])
        i += 2
    elif arg.endswith(".m"):
        sources.append(arg)
        i += 1
    else:
        flags.append(arg)
        i += 1
objects = out / "objects"
objects.mkdir(exist_ok=True)
compiler = ["xcrun", "-sdk", "iphonesimulator", "clang"]
linked = []
for index, source in enumerate(sources):
    obj = objects / ("%d.o" % index)
    dep = obj.with_suffix(".d")
    record = obj.with_suffix(".json")
    command = compiler + flags + ["-MD", "-MF", str(dep), "-c", source, "-o", str(obj)]
    previous = json.loads(record.read_text()) if record.exists() else None
    valid = previous and obj.exists() and previous["command"] == command
    if valid:
        for name, stamp in previous["dependencies"]:
            path = Path(name)
            if not path.exists() or [path.stat().st_mtime_ns, path.stat().st_size] != stamp:
                valid = False
                break
    if not valid:
        subprocess.run(command, check=True)
        names = shlex.split(dep.read_text().replace("\\\n", "").split(": ", 1)[1])
        dependencies = [[name, [Path(name).stat().st_mtime_ns, Path(name).stat().st_size]] for name in names]
        record.write_text(json.dumps({"command": command, "dependencies": dependencies}))
    linked.append(str(obj))
subprocess.run(compiler + flags + linked + libraries + ["-o", binary], check=True)
PY
}
# The chip-record and owner scenarios inspect the driver's floating-unit snapshots.
compile -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 -DSG_DRIVER="${SG_DRIVER:-1}" -DSGR_FLUID_FRAME_PROBE \
    -I"$SRC" -I"$SRC/Redesigned/Player" -I"$SRC/Redesigned/Kit" -I"$SRC/Shared/Player" -I"$OUT/gen" -I"$(dirname "$0")" -isysroot "$SDK" \
    -include "$SRC/Core/SGLocalize.h" \
    -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/preview-tap-check.m" "$(dirname "$0")/../scene.m" "$(dirname "$0")/stubs.m" "$(dirname "$0")/../tabbar/touch.m" \
    "$(dirname "$0")/stubs-automix.m" "$(dirname "$0")/automix-scenario.m" "$(dirname "$0")/share-check.m" "$(dirname "$0")/background-check.m" \
    "$(dirname "$0")/../sponsorblock/markers-check.m" "$SRC"/Shared/SponsorBlock/SponsorBlockMarkers.m \
    "$SRC"/Shared/SponsorBlock/SponsorBlockModel.m "$SRC"/Shared/SponsorBlock/SponsorBlockPrefs.m \
    "$SRC"/Redesigned/Player/ShareCards.m "$SRC"/Core/SGImageContext.m "$SRC"/Redesigned/Lyrics/LyricCardPicker.m \
    "$SRC"/Redesigned/Player/PlayerQueue.m "$SRC"/Shared/AutoMix/AutoMixSettings.m "$SRC"/Shared/AutoMix/AutoMixPreview.m \
    "$OUT"/gen/*.m "$SRC"/Redesigned/Player/PlayerLyricFit.m "$SRC"/Redesigned/Player/PlayerProgress.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGLocalize.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGFileHash.m "$SRC"/Core/SGOptionalWork.m \
    "$SRC"/Shared/Gestures/GestureHold.m \
    "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m "$SRC"/Shared/AnimatedArtwork/SGMotionCatalog.m "$SRC"/Shared/AnimatedArtwork/SGMotionStore.m \
    "$SRC"/Shared/AnimatedArtwork/SGMotionFollower.m "$SRC"/Shared/AnimatedArtwork/SGMotionClip.m "$SRC"/Shared/Player/SGLastTrack.m \
    "$SRC"/Shared/Player/AudioQualityRules.m "$SRC"/Redesigned/ContextMenu/FireControl.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Settings/SGMarquee.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m \
    "$SRC"/Shared/LyricsSources/SGBoundedRequest.m \
    "$SRC"/Redesigned/Player/PlayerSettings.m "$SRC"/Redesigned/Player/PlayerVisualiser.m "$SRC"/Redesigned/Player/PlayerLyricStages.m "$SRC"/Redesigned/Player/SGRSpectrum.m "$SRC"/Redesigned/Player/PlayerVolume.m "$SRC"/Redesigned/Player/PlayerSpeedLabel.m "$SRC"/Redesigned/NowPlayingBar/NowPlayingBarSettings.m \
    $( [ -f "$SRC"/Redesigned/Player/PlayerBackdrop.m ] && echo "$SRC"/Redesigned/Player/PlayerBackdrop.m ) \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m \
    $( [ -f "$SRC"/Settings/SGSettingsSearch.m ] && echo "$SRC"/Settings/SGSettingsSearch.m ) \
    $( [ -f "$SRC"/Settings/SGSettingsIndex.m ] && echo "$SRC"/Settings/SGSettingsIndex.m ) \
    $( [ -f "$SRC"/Shared/AnimatedArtwork/SGMotionTicket.m ] && echo "$SRC"/Shared/AnimatedArtwork/SGMotionTicket.m "$(dirname "$0")"/stubs-tickets.m ) \
    $( [ -f "$SRC"/Redesigned/Lyrics/AutoTranslation.m ] && echo "$SRC"/Redesigned/Lyrics/AutoTranslation.m ) $( [ -f "$SRC"/Redesigned/Lyrics/TranslationStatusView.m ] && echo "$SRC"/Redesigned/Lyrics/TranslationStatusView.m ) "$SRC"/Redesigned/Lyrics/SGRKaraokeView.m "$SRC"/Redesigned/Lyrics/LyricsLook.m "$SRC"/Redesigned/Lyrics/LyricsStyle.m "$SRC"/Redesigned/Kit/SGRPress.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m "$SRC"/Redesigned/Lyrics/SGRSingButton.m "$SRC"/Redesigned/Lyrics/MeaningSheet.m "$SRC"/Redesigned/Lyrics/LyricsText.m "$SRC"/Shared/Lyrics/KaraokeTiming.m "$SRC"/Shared/Lyrics/Romanise.m "$SRC"/Shared/AdBlock/Protobuf.m \
    "$SRC"/Shared/Lyrics/LyricsLanguage.m "$SRC"/Shared/Lyrics/LyricsSettings.m "$SRC"/Redesigned/Lyrics/SongLanguage.m "$SRC"/Redesigned/Lyrics/LyricsTools.m \
    "$SRC"/Shared/LyricsTranslation/LyricsTranslation.m "$SRC"/Shared/LyricsTranslation/SavedTranslations.m "$SRC"/Shared/LyricsTranslation/TranslatedTitles.m "$SRC"/Shared/LyricsTranslation/AIServices.m "$SRC"/Shared/LyricsTranslation/TranslationPrompt.m "$SRC"/Shared/LyricsTranslation/OpenAITranslate.m "$SRC"/Shared/LyricsTranslation/BingTranslate.m "$SRC"/Shared/LyricsTranslation/ClaudeTranslate.m "$SRC"/Shared/LyricsTranslation/DeepL.m "$SRC"/Shared/LyricsTranslation/GoogleTranslate.m \
    "$SRC"/Core/TranslationStore/SGTranslationFiles.m "$SRC"/Core/TranslationStore/SGTranslationTransfer.m \
    "$SRC"/Redesigned/Lyrics/AutoTranslatorName.m "$SRC"/Shared/LyricsTranslation/CredentialSettings.m "$SRC"/Shared/LyricsSources/SGTTML.m \
    -framework OSLog -framework UIKit -framework IOKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreImage -framework Foundation -framework NaturalLanguage -framework Symbols -framework AVFoundation -framework CoreMedia -framework CoreVideo -framework Accelerate -framework PhotosUI -framework Security -framework MediaPlayer -framework Network -framework CoreText \
    -lz "$SRC/Core/SGDataRoot.m" -o "$OUT/PlayerHarness.app/PlayerHarness"

cat > "$OUT/PlayerHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlayerHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.playerharness</string>
<key>CFBundleName</key><string>PlayerHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
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
echo "built $OUT/PlayerHarness.app"
