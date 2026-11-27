#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/retrine-progress-check.XXXXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Redesigned/Player" \
    "$HERE/progress-check.m" -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore -o "$OUT/progress"
"$OUT/progress"

# Exercise the actual geometry publisher and morph hooks without starting Spotify.
python3 - "$SRC/Redesigned/Player/PlayerField.x" "$HERE/settled-field-check.x" "$OUT/field.x" <<'PY'
from pathlib import Path
import sys
field, fixture, out = map(Path, sys.argv[1:])
source = field.read_text()
cache = source[source.index("static __weak SGRArtworkField *sg_field;"):source.index("SGRPlayerBackgroundKind SGRPlayerBackground(void)")]
init = "\n".join(line for line in source.splitlines() if "%init(SGRFieldMorphCoverage)" in line)
out.write_text(fixture.read_text().replace("FIELD_GEOMETRY", cache).replace("FIELD_INIT", init))
PY
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/field.x" > "$OUT/field.m"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$HERE" -I"$HERE/.." \
    "$OUT/field.m" -framework UIKit -framework Foundation -framework CoreGraphics -o "$OUT/field"
"$OUT/field"
