#!/bin/sh
# Builds the launch check for the Mac as Mac Catalyst, so the tweak's UIKit headers compile and the
# sources go in as the tweak builds them: the flag forcing of Core/, AdBlock.m's forcer, the redesign's
# and the generated flag table (copy tweak/Sources/Shared/Flags/SGFlagList.m in first, `make flags`).
set -e
cd "$(dirname "$0")"
SRC=../../tweak/Sources
OUT=${OUT:-build}
mkdir -p "$OUT"
SDK=$(xcrun --sdk macosx --show-sdk-path)
IOS="$SDK/System/iOSSupport"
xcrun clang -isysroot "$SDK" -iframework "$IOS/System/Library/Frameworks" -isystem "$IOS/usr/include" \
    -F "$IOS/System/Library/Frameworks" -L "$IOS/usr/lib" -fobjc-arc -O2 -g -Wall -Werror -target $(uname -m)-apple-ios17.0-macabi -I "$SRC" -DSG_VERSION='"0.0.0"' \
    main.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGLog.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGCounterStore.m \
    "$SRC"/Shared/AdBlock/AdBlock.m "$SRC"/Shared/Flags/SGFlagList.m "$SRC"/Shared/Flags/AIBadges.m "$SRC"/Redesigned/Kit/SGRedesign.m \
    "$SRC"/Shared/Flags/CacheLimit.m -framework Foundation -framework UIKit -o "$OUT/launch-check"
echo "built $OUT/launch-check"
