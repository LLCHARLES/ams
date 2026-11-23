#!/bin/bash
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d /tmp/retrine-album-counts.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
# Compile the production preference function without the unrelated UIKit header renderer.
python3 "$HERE/cover-source.py" "$SRC" "$OUT/covers.m"
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -I"$SRC" -framework Foundation \
    "$HERE/main.m" "$SRC/Redesigned/Album/AlbumSpotifyCounts.m" \
    "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Core/SGPrefs.m" "$OUT/covers.m" \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/album-counts"
ALBUM_COUNTS_FIXTURE_ROOT="$OUT" "$OUT/album-counts"
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -I"$SRC" -framework Foundation \
    "$HERE/protobuf.m" "$SRC/Shared/AdBlock/Protobuf.m" -o "$OUT/protobuf"
"$OUT/protobuf"
xcrun clang -fobjc-arc -O0 -g -Wall -Werror -I"$HERE/shim" -I"$SRC" -framework Foundation \
    "$HERE/transport.m" "$SRC/Shared/SpotifyMetadata/SGSpotifyMetadata.m" -o "$OUT/transport"
"$OUT/transport"
