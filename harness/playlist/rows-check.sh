#!/bin/sh
# The playlist track row hairline's check (rows-check.m), run as a plain executable in a simulator of its own, made for
# the run and deleted after it. Exits nonzero on a failed check.
#     THEOS=$HOME/theos ./rows-check.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${HARNESS_BUILD_DIR:-$HERE/build-rows}
rm -rf "$OUT"; mkdir -p "$OUT/gen"
for f in PlaylistField PlaylistHeader PlaylistRows PlaylistMenu; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Playlist/$f.x" > "$OUT/gen/$f.m"
done

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target $(uname -m)-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Redesigned/Playlist" -I"$SRC/Redesigned/Kit" -I"$OUT" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$HERE/rows-check.m" "$HERE/stubs.m" \
    "$OUT/gen/PlaylistField.m" "$OUT/gen/PlaylistHeader.m" "$OUT/gen/PlaylistMenu.m" \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m \
    "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGLocalize.m "$HERE/../page-style-with-presenter-stubs.m" \
    "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$SRC"/Redesigned/Kit/SGRField.m "$SRC"/Redesigned/Kit/SGRFlow.m "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m \
    "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
    "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m \
    "$SRC"/Redesigned/Kit/SGRedesign.m "$SRC"/Redesigned/Kit/SGRPress.m "$SRC"/Redesigned/Kit/SGRCoverViewer.m \
    -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework CoreImage -framework Foundation -framework Symbols -framework CoreText \
    -o "$OUT/rows-check"

TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "PlaylistRows-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl spawn "$UDID" "$OUT/rows-check" > "$OUT/run.log" 2>&1 || true
cat "$OUT/run.log"
grep -q "PASS rows" "$OUT/run.log" || { echo "FAILED: playlist rows"; exit 1; }
