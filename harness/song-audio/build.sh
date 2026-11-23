#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=$(mktemp -d /tmp/retrine-song-audio.XXXXXX)
SUITE="dev.retrine.song-audio.$(basename "$OUT")"
trap 'rm -rf "$OUT"; defaults delete "$SUITE"' EXIT
SRC="$HERE/../../tweak/Sources"
xcrun clang -fobjc-arc -I"$HERE/stub" -I"$SRC" -I"$SRC/Shared/Player" -framework Foundation -framework AudioToolbox \
    "$HERE/main.m" "${SONG_AUDIO_SOURCE:-$SRC/Shared/Player/SpeedPitchSongs.m}" \
    -o "$OUT/retrine-song-audio-retention"
"$OUT/retrine-song-audio-retention" "$SUITE" write
"$OUT/retrine-song-audio-retention" "$SUITE" read
