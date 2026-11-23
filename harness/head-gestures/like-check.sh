#!/bin/sh
# Exercise the actual collection captures and add-only command on the host runtime.
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mktemp -d /tmp/retrine-like.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
python3 - "$OUT" "${LIKE_SOURCE:-$ROOT/tweak/Sources/Shared/HeadGestures/HeadGestures.x}" <<'PY'
import pathlib, sys
out, source = map(pathlib.Path, sys.argv[1:])
text = source.read_text()
protocol = text[text.index("@protocol SGCollectionPlatform"):text.index("// Tink,")]
capture = text[text.index("static __weak id sg_platform;"):text.index("#pragma mark - the cue")]
command = text[text.index("BOOL SGLikePlayingTrack(void)"):text.index("// Whether it was sent:")]
ctor = text[text.index("%ctor {"):text.index("    static SGHeadGesturesObserver *observer;")] + "}\n"
(out / "capture.x").write_text(protocol + capture + command + ctor)
PY
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$OUT/capture.x" > "$OUT/capture.m"
xcrun clang -fobjc-arc -fblocks -Wall -Werror -I "$OUT" \
    "$ROOT/harness/head-gestures/like-check.m" -framework Foundation -o "$OUT/check"
"$OUT/check"
SPOTIFY_920=1 "$OUT/check"
