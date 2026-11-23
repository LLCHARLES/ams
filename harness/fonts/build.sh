#!/bin/sh
# build.sh: builds check.m with the real FontLibrary.m, the free fonts page, the Font page and the page framework as the
# tweak compiles them, as a Mac Catalyst binary with a home of its own under build/ (or BUILD_DIR).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=${BUILD_DIR:-"$HERE/build"}
mkdir -p "$OUT/home"
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -Wno-deprecated-declarations -I"$SRC" "$HERE/check.m" "$HERE/../settings-search/search-attach-stub.m" \
    "$HERE/font-import-source.m" "$SRC"/Settings/SGModPage.m "$HERE/font-library-page-source.m" "$SRC"/Shared/Fonts/FontSelection.m "$SRC"/Core/SGFileHash.m "$SRC"/Shared/LyricsPiP/LyricsPiPStyle.m \
    "$SRC"/Shared/LyricsPiP/LyricsPiPSettings.m "$SRC"/Shared/LyricsPiP/LyricsPiPFrame.m \
    "$SRC"/Shared/LyricsBackground/LyricsBackground.m "$SRC"/Shared/LyricsBackground/LyricsBackgroundSettings.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework CoreText -framework ImageIO -framework UniformTypeIdentifiers -framework Accelerate \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/check"
CFFIXED_USER_HOME="$OUT/home" "$OUT/check"
xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -Wno-deprecated-declarations -I"$SRC" \
    "$HERE/selection-main.m" "$HERE/font-selection.m" "$HERE/font-library-source.m" "$HERE/../settings-search/search-attach-stub.m" \
    "$SRC"/Shared/Fonts/FontImport.m "$SRC"/Shared/Fonts/FontLibraryPage.m "$SRC"/Shared/Fonts/FontSelection.m "$SRC"/Core/SGFileHash.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLocalize.m "$SRC"/Core/SGGlass.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework CoreText -framework UniformTypeIdentifiers \
    "$SRC/Core/SGDataRoot.m" -o "$OUT/selection-check"
mkdir -p "$OUT/selection-home"
CFFIXED_USER_HOME="$OUT/selection-home" "$OUT/selection-check"
