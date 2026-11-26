#!/bin/sh
# build.sh: builds check.m against this checkout's Musixmatch.m, the translators and KaraokeTiming.m
# (and LocalFiles.m, which Musixmatch.m reads a local file's names from) as a Mac Catalyst binary and runs
# it, so no simulator is needed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=${OUT:-$HERE/build}
mkdir -p "$OUT"
compile() {
    xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" -DSecItemCopyMatching=SGLyricsTestKey -DSecItemAdd=SGLyricsTestKeyAdd -DSecItemUpdate=SGLyricsTestKeyUpdate -DSecItemDelete=SGLyricsTestKeyDelete -fobjc-arc -g -Wall -I"$SRC" "$@"
}
compile -DSGLyricsTranslationSendRequest=SGLyricsTranslationRealSendRequest -DSGLyricsTranslationSendOnce=SGLyricsTranslationRealSendOnce -DSGLyricsTranslationSendOnceUpTo=SGLyricsTranslationRealSendOnceUpTo -c "$SRC/Shared/LyricsTranslation/DeepL.m" -o "$OUT/DeepL.o"
compile -DSG_LYRICS_TEST_STORE \
    "$SRC/Shared/LyricsSources/SGBoundedRequest.m" \
    "$HERE/check.m" "$SRC/Shared/LyricsSources/Musixmatch.m" "$SRC/Shared/LyricsSources/LyricsRequest.m" "$SRC/Shared/LyricsSources/LyricsHosts.m" "$SRC/Shared/LyricsTranslation/LyricsTranslation.m" \
    "$OUT/DeepL.o" "$SRC/Shared/LyricsTranslation/BingTranslate.m" "$SRC/Shared/LyricsTranslation/GoogleTranslate.m" "$SRC/Shared/LyricsTranslation/OpenAITranslate.m" \
    "$SRC/Shared/LyricsTranslation/ProseSegments.m" "$SRC/Shared/LyricsTranslation/TranslationPrompt.m" "$SRC/Core/SGGlass.m" \
    "$SRC/Core/TranslationStore/SGTranslationFiles.m" "$SRC/Core/TranslationStore/SGTranslationTransfer.m" \
    "$SRC/Redesigned/Lyrics/AutoTranslation.m" "$SRC/Shared/LyricsTranslation/ConnectionTest.m" "$SRC/Shared/LyricsTranslation/ClaudeTranslate.m" "${AI_SERVICES_SOURCE:-$SRC/Shared/LyricsTranslation/AIServices.m}" \
    "$SRC/Shared/LyricsTranslation/SavedTranslations.m" "$SRC/Shared/LyricsTranslation/TranslatedTitles.m" "$SRC/Shared/LyricsTranslation/CredentialSettings.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/Lyrics/LyricsLanguage.m" "$SRC/Shared/Lyrics/Romanise.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGFileHash.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework NaturalLanguage -framework UIKit -framework QuartzCore -framework CoreGraphics -framework ImageIO -framework Security -framework Foundation -lz "$SRC/Core/SGDataRoot.m" -o "$OUT/check"
"$OUT/check" "$@"
# A fresh process: startup maintenance must fail before anything else has opened the store.
if [ $# -eq 0 ]; then "$OUT/check" --startup-reclaim-only; fi
if [ $# -eq 0 ]; then "$OUT/check" --first-read-only; fi
if [ $# -eq 0 ]; then "$OUT/check" --first-read-failure-only; fi
if [ $# -eq 0 ]; then
    SG_TEST_PRELAUNCH=1 "$OUT/check" --startup-unlock-only
    SG_TEST_PRELAUNCH=1 SG_TEST_LOCKED_LAUNCH=1 "$OUT/check" --startup-unlock-only
fi
