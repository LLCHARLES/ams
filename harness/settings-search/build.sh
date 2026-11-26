#!/bin/sh
# The settings search index offline: Settings/SGSettingsIndex.m against pages of plain SGModRow rows, on Mac
# Catalyst's UIKit. Nothing is drawn and no window is made, so it runs as a command-line check, not in a simulator.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=${HARNESS_BUILD_DIR:-"$HERE/build"}
mkdir -p "$OUT" "$OUT/tmp"
# The index writes the recents under the app's own defaults domain; a throwaway home keeps the real one untouched.
export CFFIXED_USER_HOME="$OUT/tmp"
export TMPDIR="$OUT/tmp"
mkdir -p "$CFFIXED_USER_HOME/Library/Preferences"
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter \
    -Wno-deprecated-declarations -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -I "$SRC" \
    "$HERE/check.m" "$SRC/Settings/SGSettingsIndex.m" "$SRC/Settings/SGModPage.m" "$SRC/Settings/SGPage.m" \
    "$SRC/Settings/SGPageStyle.m" "$SRC/Settings/SGGlowSwitch.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGGlass.m" \
    "$HERE/search-attach-stub.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/settings-search"
"$OUT/settings-search" -AppleLanguages '(en)'
