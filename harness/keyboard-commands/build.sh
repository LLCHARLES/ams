#!/bin/sh
# Host check of the parts of Shared/Keyboard that need no app: the volume's 16-step grid (snap, one step a press,
# clamped to 0–100%), the command table with its inputs, modifiers and titles, and the two readings the commands are
# gated on, over described screen trees and window lists (which screen is front, what covers the app window). The
# production sources are compiled as they are; nothing here hooks UIKit or needs a simulator.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=${SRC:-$(cd "$HERE/../../tweak/Sources" && pwd)}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/retrine-keyboard-commands.XXXXXX")
trap 'rm -rf "$OUT"' EXIT HUP INT TERM
SDK=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -O0 -Wall -Wextra -Werror -Wno-unused-parameter -I "$SRC" \
    "$HERE/retrine-keyboard-commands-check.m" \
    "$SRC/Core/SGLocalize.m" \
    -framework UIKit -framework Foundation -framework CoreGraphics -o "$OUT/retrine-keyboard-commands-check"
"$OUT/retrine-keyboard-commands-check"
