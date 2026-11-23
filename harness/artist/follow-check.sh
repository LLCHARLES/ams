#!/bin/sh
# Compile the production capture hooks without the unrelated UIKit page rendering.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mktemp -d /tmp/retrine-follow.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
python3 - "$ROOT" "$OUT" "${FOLLOW_SOURCE:-$ROOT/tweak/Sources/Redesigned/Artist/ArtistFollow.x}" <<'PY'
import pathlib, sys
root, out, source = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
capture = text[text.index("@protocol SGRCollectionState"):text.index("#pragma mark - one subscription per page")]
ctor = text[text.index("%ctor {"):]
(out / "capture.x").write_text(capture + ctor)
PY
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/capture.x" > "$OUT/capture.m"
xcrun clang -fobjc-arc -fblocks -Wall -Werror -Wno-unused-function -I "$OUT" \
    "$ROOT/harness/artist/follow-check.m" -framework Foundation -o "$OUT/check"
"$OUT/check"
SPOTIFY_920=1 "$OUT/check"
