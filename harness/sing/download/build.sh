#!/bin/sh
# Builds the download check (main.m) for the Mac, through Mac Catalyst since Sing.h imports UIKit: SGSingModel.m
# as the tweak compiles it, with shim/Core/SGCore.h standing in for the mod's core.
#   ./build.sh && CFFIXED_USER_HOME="$(mktemp -d)" ../build/download 0.2
set -e
cd "$(dirname "$0")"
SRC=../../../tweak/Sources
OUT=${OUT:-../build}
mkdir -p "$OUT"
xcrun clang -fobjc-arc -O1 -g -Wall -Werror -target $(uname -m)-apple-ios18.0-macabi \
    -isysroot "$(xcrun --sdk macosx --show-sdk-path)" \
    -iframework "$(xcrun --sdk macosx --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    -I shim -I "$SRC" main.m "$SRC/Shared/Sing/SGSingModel.m" "$SRC/Core/SGFileHash.m" "$SRC/Core/SGLocalize.m" \
    -framework Foundation "$SRC/Core/SGDataRoot.m" -o "$OUT/download"
echo "built $OUT/download"
