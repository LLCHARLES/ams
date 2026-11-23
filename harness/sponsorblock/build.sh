#!/bin/sh
# Foundation-only production model/session; no GUI, account or live network.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/retrine-sponsorblock.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
xcrun --sdk macosx clang -fobjc-arc -fblocks -Wall -I"$SRC" \
    "$HERE/main.m" "$SRC/Shared/SponsorBlock/SponsorBlockModel.m" \
    "$SRC/Shared/SponsorBlock/SponsorBlockPrefs.m" \
    "$SRC/App/About/SGDiagnosticRedaction.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Shared/SponsorBlock/SponsorBlockAPI.m" \
    -framework Foundation -o "$BUILD/sponsorblock"
"$BUILD/sponsorblock" "$HERE/segments.json"
