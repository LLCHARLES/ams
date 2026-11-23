#!/bin/sh
# Offline command/log-cursor regression checks; no UIKit, simulator or phone.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-driver-command.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
xcrun clang -fobjc-arc -DSG_DRIVER=1 -I"$SRC" \
    "$HERE/command-check.m" "$SRC/Core/SGLog.m" \
    -framework Foundation -o "$OUT/check"
"$OUT/check"
