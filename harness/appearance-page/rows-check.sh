#!/bin/bash
# Real appearance row builders and history, with settings/picker UI replaced by row data doubles.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-appearance-rows.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -O0 -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" \
    "$HERE/rows-check.m" "$SRC/Native/Appearance/AppearanceSettings.m" "$SRC/Native/Appearance/AccentHistory.m" \
    "$SRC/Redesigned/Kit/SGRAppearanceSettings.m" "$SRC/Redesigned/Kit/SGRAccentHistory.m" \
    "$SRC/Redesigned/Kit/SGRGlass.m" "$SRC/Redesigned/Kit/SGRRefinements.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$OUT/check"
"$OUT/check"
