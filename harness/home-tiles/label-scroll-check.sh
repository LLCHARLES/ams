#!/bin/bash
# Exercise the Home and navbar hooks on unrelated player labels and scroll views.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../../tweak/Sources" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for file in "${HOME_CARDS:-$src/Redesigned/Home/HomeCards.x}" "${TAB_MINIMIZE:-$src/Redesigned/Navbar/TabBarMinimize.x}"; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$file" > "$out/$(basename "$file").m"
done
sdk=$(xcrun --sdk macosx --show-sdk-path)
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$sdk" -iframework "$sdk/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -I"$src" -I"$src/Redesigned/Home" -I"$src/Redesigned/Navbar" "$out"/*.m "$here/label-scroll-check.m" \
    "$src/Core/SGViewTree.m" -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$out/check"
"$out/check" labels
"$out/check" scrolls
