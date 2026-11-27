#!/bin/sh
# The picture-aware album cover (Redesigned/Kit/SGRCoverRead.h, Redesigned/Album/AlbumHeader.x) as Mac Catalyst
# programs; no simulator. cover-read-check reads the fixtures (cover-fixtures.h); cover-hero-check draws them in the
# album's hero with the setting on, swaps a cover mid read, and with the setting off draws the hero and keeps the PNG.
# With BASELINE set to a Git revision, the off hero of that revision's sources is drawn too and the two PNGs must be
# the same bytes. Needs Theos ($THEOS, else ~/theos). Builds into a temporary folder (or OUT, kept).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
LOGOS=${THEOS:-$HOME/theos}/bin/logos.pl
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/retrine-cover-check.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
SDK=$(xcrun --sdk macosx --show-sdk-path)
CC="xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot $SDK -iframework $SDK/System/iOSSupport/System/Library/Frameworks -Wno-deprecated-declarations"
FRAMEWORKS="-framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation -framework Vision"

$CC -DSGR_COVER_READ_TEST -I"$SRC" "$HERE/cover-read-check.m" "$SRC/Redesigned/Kit/SGRCoverRead.m" "$SRC/Redesigned/Kit/SGRTokens.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" $FRAMEWORKS -o "$OUT/cover-read-check"
"$OUT/cover-read-check"

# hero <out dir>: the album harness's sources under $SRC (build.sh's) with cover-hero-check.m for main.
hero() {
    dir=$1
    mkdir -p "$dir/gen"
    # The redesign's AMOLED rule (SGRAmoled.x) paints the page as the phone does: a low grey field shows black.
    for f in Shared/Fonts/Fonts.x Redesigned/Album/AlbumField.x Redesigned/Album/AlbumHeader.x Redesigned/Album/AlbumRows.x Redesigned/Album/AlbumSections.x \
             Redesigned/Kit/SGRAmoled.x; do
        "$LOGOS" -c generator=internal "$SRC/$f" > "$dir/gen/$(basename "$f" .x).m"
    done
    field="$SRC/Redesigned/Kit/SGRField.m"
    # An earlier revision may have no cover read.
    cover=""
    clip=""
    baseline=0
    if [ "$dir" = "$OUT/baseline/hero" ]; then baseline=1; fi
    if [ -f "$SRC/Redesigned/Kit/SGRHeaderClip.m" ]; then clip="$SRC/Redesigned/Kit/SGRHeaderClip.m"; fi
    if [ -f "$SRC/Redesigned/Kit/SGRCoverRead.m" ]; then
        cover="$SRC/Redesigned/Kit/SGRCoverRead.m"
        # Provider timing, player readiness and a recycled cache address are simulated at external boundaries.
        python3 "$HERE/cover-mutation.py" "$dir/gen/AlbumHeader.m" seams "$baseline"
    fi
    $CC -DSGR_COVER_BASELINE="$baseline" -I"$SRC" -I"$SRC/Redesigned/Album" -I"$SRC/Redesigned/Kit" -I"$dir/gen" \
        "$HERE/cover-hero-check.m" "$HERE/stubs.m" "$dir"/gen/*.m $cover $clip \
        "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGFileHash.m \
        "$SRC"/Core/SGBackdrop.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m "$HERE/../page-style-with-presenter-stubs.m" \
        "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRPalette.m "$field" "$SRC"/Redesigned/Kit/SGRFlow.m \
        "$SRC"/Redesigned/Kit/SGRFluid.m "$SRC"/Redesigned/Kit/SGRFluidGPU.m "$SRC"/Shared/AnimatedArtwork/SGMotionCatalog.m "$SRC"/Shared/Lyrics/LyricsLanguage.m -framework NaturalLanguage -Wl,-dead_strip \
        "$SRC"/Shared/AnimatedArtwork/SGMotionStore.m "$SRC"/Shared/AnimatedArtwork/SGMotionTicket.m \
        "$SRC"/Redesigned/Kit/SGRGlass.m "$SRC"/Redesigned/Kit/SGRGlyph.m "$SRC"/Redesigned/Kit/SGRRestyle.m \
        "$SRC"/Redesigned/Kit/SGRActionRow.m "$SRC"/Redesigned/Kit/SGRDownload.m "$SRC"/Redesigned/Kit/SGRHeaderInfo.m "$SRC"/Redesigned/Kit/SGRHeroVeil.m "$SRC"/Redesigned/Kit/SGRStretchHero.m \
        "$SRC"/Redesigned/Kit/SGRedesign.m "$SRC"/Redesigned/Album/AlbumCredits.m "$SRC"/Shared/Fonts/FontLibrary.m "$SRC"/Core/SGLocalize.m \
        "$SRC"/Redesigned/Album/AlbumPlays.m "$SRC"/Redesigned/Album/AlbumPlaysText.m "$SRC"/Redesigned/Album/AlbumSpotifyCounts.m \
        "$SRC"/Redesigned/Kit/SGRCoverViewer.m "$SRC"/Shared/ListeningStats/SGPlayLog.m \
        "$SRC"/Redesigned/Album/AlbumNotes.m "$SRC"/Shared/AnimatedArtwork/SGMotionClip.m "$SRC"/Shared/AdBlock/Protobuf.m \
        "$SRC"/Redesigned/Album/AlbumPlaysPlace.m "$SRC"/Redesigned/Kit/SGRRollingDigits.m "$SRC"/Redesigned/Kit/SGRRefinements.m \
        $FRAMEWORKS -framework Metal -framework Symbols -framework CoreText -framework AVFoundation -framework CoreMedia -framework CoreVideo \
        -o "$dir/cover-hero-check"
}

hero "$OUT/hero"
export SGR_COVER_ROOT="$OUT/data"
"$OUT/hero/cover-hero-check" rebuilt
"$OUT/hero/cover-hero-check" motion-row
"$OUT/hero/cover-hero-check" motion-identifiers -spotifyglass.redesign.album.adaptiveCover YES
SGR_COVER_ROOT="$OUT/verified" "$OUT/hero/cover-hero-check" motion-verified
"$OUT/hero/cover-hero-check" on -spotifyglass.redesign.album.adaptiveCover YES
"$OUT/hero/cover-hero-check" swap -spotifyglass.redesign.album.adaptiveCover YES
"$OUT/hero/cover-hero-check" still-swap -spotifyglass.redesign.album.adaptiveCover YES
"$OUT/hero/cover-hero-check" cache-reuse -spotifyglass.redesign.album.adaptiveCover YES
"$OUT/hero/cover-hero-check" off "$OUT/off.png"
if [ -n "${BASELINE:-}" ]; then
    git -C "$HERE/../.." archive --prefix=baseline/ "$BASELINE" tweak/Sources | tar -x -C "$OUT"
    SRC=$OUT/baseline/tweak/Sources
    hero "$OUT/baseline/hero"
    "$OUT/baseline/hero/cover-hero-check" off "$OUT/baseline-off.png"
    if ! cmp -s "$OUT/off.png" "$OUT/baseline-off.png"; then
        echo "[harness] FAIL the album hero with the setting off is not drawn as at $BASELINE"
        exit 1
    fi
    echo "[harness] PASS setting off: the album hero is drawn byte for byte as at $BASELINE"
fi
