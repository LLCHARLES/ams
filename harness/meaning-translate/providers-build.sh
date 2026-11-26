#!/bin/sh
# Real provider entrypoints and URLSession transport, with fixture Keychain and NSURLProtocol only.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
if [ -n "${OUT:-}" ]; then mkdir -p "$OUT"; else OUT=$(mktemp -d /tmp/meaning-providers.XXXXXX); trap 'rm -rf "$OUT"' EXIT; fi
SDK=$(xcrun --sdk macosx --show-sdk-path)
T="$SRC/Shared/LyricsTranslation"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -g -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -I"$T" -Wall -Werror -Wno-unused-parameter -Wno-deprecated-declarations \
    -DSecItemCopyMatching=ProseTestKey -DSecItemAdd=ProseTestKeyAdd \
    -DSecItemUpdate=ProseTestKeyUpdate -DSecItemDelete=ProseTestKeyDelete \
    "$HERE/providers.m" "${TEXT_SOURCE:-$T/TextTranslation.m}" "${SEGMENTS_SOURCE:-$T/ProseSegments.m}" \
    "$T/BingTranslate.m" "$T/GoogleTranslate.m" "$T/DeepL.m" \
    "$SRC/Shared/LyricsSources/SGBoundedRequest.m" \
    "${OPENAI_SOURCE:-$T/OpenAITranslate.m}" "${CLAUDE_SOURCE:-$T/ClaudeTranslate.m}" \
    "${GEMINI_SOURCE:-$T/LyricsTranslation.m}" "$T/AIServices.m" "$T/CredentialSettings.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -Wl,-dead_strip -framework UIKit -framework Foundation -framework Security -o "$OUT/providers"
"$OUT/providers"
