#!/bin/sh
# Cached release selection only: no simulator, app UI or network request.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-update-check.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target arm64-apple-ios17.0-macabi -fobjc-arc -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I"$SRC" -DSG_VERSION='"1.0.0"' \
    "$SRC/App/About/Update.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" \
    "$HERE/offline-check.m" \
    -framework UIKit -framework Foundation -o "$OUT/check"
"$OUT/check"
APP="$OUT/Language.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R "$SRC/../layout/Library/Application Support/Retrine.bundle" "$APP/Contents/Resources/"
xcrun clang -fobjc-arc -fblocks -I"$SRC" \
    "$SRC/Core/SGLocalize.m" "$HERE/language-check.m" \
    -framework Foundation -o "$APP/Contents/MacOS/Language"
for choice in absent 0 2 9; do
    "$APP/Contents/MacOS/Language" "$choice" "취소" ko
done
"$APP/Contents/MacOS/Language" 1 "Cancel" ko
"$APP/Contents/MacOS/Language" 2 "취소" en
"$APP/Contents/MacOS/Language" absent "Cancel" en
