#!/bin/sh
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$(mktemp -d /tmp/retrine-ad-settings.XXXXXX)
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
python3 - "$ROOT/tweak/Sources/Shared/AdBlock/AdBlockSettings.m" "$OUT/page.inc" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(source[source.index("static UIViewController *adFlagsPage(void)"):source.index("// The switches first")])
PY
xcrun clang -fobjc-arc -fblocks -Wall -Werror -I "$OUT" -I "$ROOT/harness/adblock/shim" \
    -I "$ROOT/tweak/Sources" "$ROOT/harness/adblock/settings-check.m" -framework Foundation -o "$OUT/check"
"$OUT/check"
SPOTIFY_920=1 "$OUT/check"
