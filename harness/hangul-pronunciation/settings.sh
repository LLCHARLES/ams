#!/bin/bash
# Catalyst command-line test, no simulator or GUI application launch.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-hangul-settings.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun --sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -Wall -I"$SRC" \
    "$HERE/settings.m" "$SRC/Shared/Lyrics/LyricsSettings.m" "$SRC/Shared/Lyrics/Romanise.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -Wl,-dead_strip -framework UIKit -framework Foundation -framework QuartzCore -o "$OUT/hangul-pronunciation-settings"
"$OUT/hangul-pronunciation-settings"
