#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/volume-layout-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
python3 -B - "$SRC/Redesigned/Player" "$OUT" <<'PY'
from pathlib import Path
import sys
source = (Path(sys.argv[1]) / "PlayerFooter.x").read_text()
constants = source[source.index("static const CGFloat kRowAboveSafeArea"):source.index('// "airplayaudio"')]
layout = source[source.index("#pragma mark - lower down"):source.index("static void placeQueueGlyph(")]
header = (Path(sys.argv[1]) / "Player.h").read_text()
safe = header[header.index("static inline CGRect SGRPlayerVisibleSafeArea"):header.index("#pragma mark - the lyrics")]
margins = header[header.index("#pragma mark - the player's margins and rhythm"):header.index("#pragma mark - the cover")]
(Path(sys.argv[2]) / "volume-margins-production.inc").write_text(margins)
(Path(sys.argv[2]) / "volume-layout-production.inc").write_text(constants + "\n" + safe + "\n" + layout)
source = (Path(sys.argv[1]) / "PlayerVolume.m").read_text()
constants = source[source.index("static const CGFloat kRowHeight"):source.index("// The slider is drawn as the progress bar")]
placement = source[source.index("static char kVolumeKey"):]
(Path(sys.argv[2]) / "volume-placement-production.inc").write_text(constants + "\n" + placement)
source = (Path(sys.argv[1]) / "PlayerArtwork.x").read_text()
top = source.index("static const CGFloat kCoverTopUnderSafeArea")
lift = source[source.index("// The header rows taking touches in a player"):source.index("static void layOutCoversIn(")]
(Path(sys.argv[2]) / "volume-cover-production.inc").write_text(source[top:source.index("\n", top)] + "\n" + lift)
PY
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$OUT" \
    "$HERE/volume-layout-check.m" -framework UIKit -framework Foundation -framework CoreGraphics -o "$OUT/volume-layout-check"
"$OUT/volume-layout-check"
# Issue #71: the Volume switch is read once per launch, so the cover is measured with it on, then with it off.
on=$("$OUT/volume-layout-check" cover)
HARNESS_VOLUME=0 "$OUT/volume-layout-check" cover $on
