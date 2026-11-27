#!/bin/sh
# Host migration, header and diagnostic-redaction checks; no simulator, listener or device.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-driver-auth.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
xcrun clang -fobjc-arc -DSG_DRIVER=1 -I"$SRC" \
    -DSecItemCopyMatching=DriverTestCopy -DSecItemUpdate=DriverTestUpdate -DSecItemAdd=DriverTestAdd \
    "$HERE/auth-check.m" "$SRC/Diagnostics/SGDriverAuth.m" \
    "$SRC/App/About/SGDiagnosticRedaction.m" "$SRC/Core/SGPrefs.m" \
    -framework Security -framework Foundation -o "$OUT/check"
for mode in migrated fresh existing rotate; do "$OUT/check" "$mode"; done
xcrun clang -fobjc-arc -DSG_DRIVER=0 -I"$SRC" -c "$SRC/Diagnostics/SGDriverAuth.m" -o "$OUT/release.o"
nm "$OUT/release.o" > "$OUT/symbols"
if grep -Eq 'SGDriver|SecItem' "$OUT/symbols"; then
    echo "release contains driver authentication" >&2
    exit 1
fi
