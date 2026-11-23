#!/bin/bash
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$HERE/../../tweak/Sources" \
    "$HERE/check.m" -framework UIKit -framework Foundation -o "$OUT/signing-check"
for launch in tour after-restart already-warned; do
    "$OUT/signing-check" "$launch" "$OUT/defaults.plist"
done
