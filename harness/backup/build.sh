#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
BUILD=$(mktemp -d "${TMPDIR:-/tmp}/retrine-backup.XXXXXX")
trap 'rm -rf "$BUILD"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -Os -Wl,-dead_strip -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -DSG_VERSION=\"test\" \
    "$HERE/check.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework Foundation -framework OSLog -framework UniformTypeIdentifiers -o "$BUILD/check"
"$BUILD/check"
