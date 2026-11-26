#!/bin/sh
# Compile the actual PlayerLyrics.x measurement section against UIKit view geometry.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/lyrics-layout-check.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
python3 - "$SRC/Redesigned/Player/PlayerLyrics.x" "$OUT/lyrics-layout-production.inc" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text()
constants = source[source.index("static const CGFloat kThumbSide"):source.index("static BOOL sg_open;")]
measurements = source[source.index("typedef struct {", source.index("#pragma mark - the measurements")):
                      source.index("#pragma mark - the title row")]
fade = source[source.index("static void fadeControls("):source.index("// Where the lines go on their own")]
header = pathlib.Path(sys.argv[1]).with_name("Player.h").read_text()
safe = header[header.index("static inline CGRect SGRPlayerVisibleSafeArea"):header.index("#pragma mark - the lyrics")]
pathlib.Path(sys.argv[2]).write_text(constants + "\n" + safe + "\n" + measurements + "\n" + fade)
PY
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$OUT" -I"$SRC" \
    "$HERE/lyrics-layout-check.m" -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
    -o "$OUT/lyrics-layout-check"
"$OUT/lyrics-layout-check"
python3 "$HERE/ipad-check.py" --screenshots "${PLAYER_SCREENSHOTS:-$OUT/frames}"
