#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-ondevice-kept.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun swiftc -target arm64-apple-ios26.0-macabi -sdk "$SDK" \
    -F "$SDK/System/iOSSupport/System/Library/Frameworks" \
    "$SRC/Shared/LyricsTranslation/OnDeviceTranslation.swift" "$HERE/ondevice-kept-check.swift" \
    -o "$OUT/check"
"$OUT/check"
