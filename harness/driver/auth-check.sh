#!/bin/sh
# Foundation-only migration, header and diagnostic-redaction checks; no simulator, listener or device.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-driver-auth.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
xcrun clang -fobjc-arc -DSG_DRIVER=1 -I"$SRC" \
    "$HERE/auth-check.m" "$SRC/Diagnostics/SGDriverAuth.m" \
    "$SRC/App/About/SGDiagnosticRedaction.m" "$SRC/Core/SGPrefs.m" \
    -framework Foundation -o "$OUT/check"
"$OUT/check"
"$OUT/check" migrated
