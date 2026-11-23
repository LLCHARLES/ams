#!/bin/sh
# build.sh: builds check.m against this checkout's lyrics sources and word splitting as a Mac Catalyst
# binary and runs it, so no simulator is needed. Arguments go to the check (saved replies to read).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${LYRICS_SOURCE_ROOT:-$(cd "$HERE/../../tweak/Sources" && pwd)}
LS="$SRC/Shared/LyricsSources"
BUILD=$(mktemp -d "/tmp/retrine-lyrics-sources.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT HUP INT TERM
if [ "${1:-}" != "--transport-only" ]; then
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -I"$SRC" -DSG_VERSION=\"0.0.0\" \
    "$LS/SongMatch.m" "$LS/LyricsRequest.m" "$LS/LyricsHosts.m" "$LS/PetitLyrics.m" "$SRC/Core/SGPrefs.m" \
    "$HERE/check.m" "$LS/KuGou.m" "$LS/QQMusic.m" "$LS/NetEase.m" "$LS/Musixmatch.m" "$LS/LrcLib.m" "$LS/Lyricsfile.m" "$LS/Bugs.m" "$LS/Genie.m" "$LS/LyricsPlus.m" "$SRC/Shared/Lyrics/Romanise.m" "$SRC/Shared/Lyrics/LyricsLanguage.m" "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework Foundation -framework NaturalLanguage -framework Security -lz -o "$BUILD/check"
"$BUILD/check" "$@"
fi
# Compile the real shared JSON transport without the unrelated keeper/UI implementation.
python3 - "$LS/LyricsSources.m" "$BUILD/transport.inc" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.index("#pragma mark - the requests the sources share")
end = text.index("void SGLyricsPageLines", start)
pathlib.Path(sys.argv[2]).write_text(text[start:end])
PY
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -I"$SRC" -I"$BUILD" -DSG_VERSION=\"0.0.0\" \
    "$HERE/transport-check.m" "$LS/LyricsRequest.m" "$LS/LyricsHosts.m" "$LS/QQMusic.m" "$LS/SongMatch.m" "$LS/LrcLib.m" "$LS/Lyricsfile.m" "$LS/LyricsPlus.m" "$LS/Genie.m" "$LS/Genius.m" "$LS/Unison.m" "$LS/BiniLyrics.m" "$LS/SGTTML.m" "$LS/TTMLResult.m" "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework Foundation -framework NaturalLanguage -lz -o "$BUILD/transport-check"
"$BUILD/transport-check"
