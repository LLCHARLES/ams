#!/bin/sh
# Run the keeper and walk on the Mac, omitting only the Logos hooks that need Spotify.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=${LYRICS_SOURCE_ROOT:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d "/tmp/retrine-lyrics-state-build.XXXXXX")
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
sed '/^%hook SPTEsperantoPlayer/,$d' "$SRC/Shared/Lyrics/KaraokeSource.x" > "$OUT/karaoke.inc"
sed -n '/^static NSArray<SGKaraokeLine \*> \*timedLinesForCard(/,/^}/p' "$SRC/Shared/LiveActivity/LiveActivity.x" > "$OUT/activity-lines.inc"
sed -n '/^SPTPlayerTrack \*SGPlayerUpNextIn/,/^}/p' "$SRC/Shared/Player/PlayerState.x" > "$OUT/player-up-next.inc"
sed -n '/^static const NSTimeInterval kLyricsGrace =/p; /^static const NSTimeInterval kRest =/p; /^#pragma mark - the track changing under them/,/^%ctor {/ { /^%ctor {/!p; }' \
    "$SRC/Redesigned/Player/PlayerLyrics.x" > "$OUT/player-lyrics-watcher.inc"
sed '/^#pragma mark - hooks/,$d' "$SRC/Shared/LyricsSources/LyricsHook.x" > "$OUT/lyrics-hook.inc"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -Wno-unused-function -Wno-unused-variable \
    -I"$SRC" -I"$SRC/Shared/Lyrics" -I"$SRC/Shared/LyricsSources" -I"$OUT" -DSG_VERSION=\"0.0.0\" \
    "$SRC/Shared/LyricsSources/SGBoundedRequest.m" "$HERE/pixie-boundaries.m" \
    "$HERE/state-check.m" "$HERE/netease-check.m" "$SRC/Shared/LyricsSources/LyricsRequest.m" "$SRC/Shared/LyricsSources/LyricsHosts.m" "$SRC/Shared/LyricsSources/TTMLResult.m" "$SRC/Shared/LyricsSources/LrcLib.m" "$SRC/Shared/LyricsSources/Lyricsfile.m" "$SRC/Shared/LyricsSources/SongMatch.m" "$SRC/Shared/LyricsSources/LyricsPick.m" "$SRC/Shared/Lyrics/KaraokeTiming.m" \
    "$SRC/Shared/Lyrics/LyricsLanguage.m" "$SRC/Shared/Lyrics/Romanise.m" "$SRC/Shared/Lyrics/LyricsStore.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGFileHash.m" "$SRC/Core/SGOptionalWork.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGGlass.m" "$SRC/Shared/LyricsSources/SGTTML.m" \
    -framework UIKit -framework QuartzCore -framework Foundation -framework NaturalLanguage -framework AVFoundation -framework Security -framework Network "$SRC/Core/SGDataRoot.m" -o "$OUT/state-check"
"$OUT/state-check"
RETRINE_PIXIE_ONLY=1 "$OUT/state-check"
for mode in reset coldRemoval deleteOff enableDuringDelete responsive largeLedger byteBudget; do RETRINE_PIXIE_COLD=$mode "$OUT/state-check"; done
RETRINE_PRESSURE_ONLY=1 "$OUT/state-check"
