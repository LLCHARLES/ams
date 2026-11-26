#!/bin/sh
# build.sh: builds check.m against this checkout's LocalFiles.m as a Mac Catalyst binary and runs it with
# a home of its own under build/, so its defaults and its covers never reach the Mac's.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=${BUILD_DIR:-"$HERE/build"}
mkdir -p "$OUT/home"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" "$HERE/check.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/check"
CFFIXED_USER_HOME="$OUT/home" "$OUT/check"
# The imported lyrics files, with the lyrics engine's line timing and the TTML reader as the tweak has them.
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" "$HERE/lrc.m" "$SRC/Shared/LocalFiles/LocalLyrics.m" "$SRC/Shared/LocalFiles/EmbeddedLyrics.m" "$SRC/Shared/LocalFiles/LyricRetirement.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/LyricsSources/SGTTML.m" "$SRC/Shared/AdBlock/Protobuf.m" \
    -framework UIKit -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/lrc"
python3 "$HERE/embedded-fixtures.py" "$OUT/tags"
CFFIXED_USER_HOME="$OUT/home" SG_TEST_TAGS="$OUT/tags" "$OUT/lrc"
# Cover fallback, including the malformed image URI that crashed Spotify 9.1.90.
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" "$HERE/cover.m" "$SRC/Shared/LocalFiles/LocalCover.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework MediaPlayer -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/cover"
CFFIXED_USER_HOME="$OUT/home" "$OUT/cover"
# The actual redesigned bridge and field identity gate over the production local-cover resolver.
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Kit/SGRBridges.x" > "$OUT/SGRBridges.m"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" -I"$SRC/Redesigned/Kit" \
    "$HERE/bridge.m" "$OUT/SGRBridges.m" "$SRC/Redesigned/Kit/SGRField.m" \
    "$SRC/Shared/LocalFiles/LocalCover.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework MediaPlayer -framework QuartzCore -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/bridge"
CFFIXED_USER_HOME="$OUT/home" "$OUT/bridge"
# The native cover consumer's Logos watcher over the production resolver and a late system artwork.
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Native/LocalFiles/LocalCover.x" > "$OUT/LocalCover.m"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" -I"$SRC/Native/LocalFiles" \
    "$HERE/watcher.m" "$OUT/LocalCover.m" "$SRC/Shared/LocalFiles/LocalCover.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework MediaPlayer -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/watcher"
CFFIXED_USER_HOME="$OUT/home" "$OUT/watcher"
# The actual Logos observer over a fake player and now-playing extras sink.
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/LocalFiles/LocalFileInfo.x" > "$OUT/LocalFileInfo.m"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" -I"$SRC/Shared/LocalFiles" \
    "$HERE/now-playing.m" "$OUT/LocalFileInfo.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework MediaPlayer -framework CoreGraphics -framework Foundation -framework ImageIO "$SRC/Core/SGDataRoot.m" -o "$OUT/now-playing"
CFFIXED_USER_HOME="$OUT/home" "$OUT/now-playing"
# Audio import: the copy's names, never overwriting, the list of what was imported and the delete. AUDIO_SOURCE
# names the file under test, so a deliberately broken copy can be checked to fail.
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -g -Wall -Werror -I"$SRC" "$HERE/audio.m" "${AUDIO_SOURCE:-$SRC/Shared/LocalFiles/LocalAudioImport.m}" \
    -framework Foundation -o "$OUT/audio"
CFFIXED_USER_HOME="$OUT/home" "$OUT/audio" "$OUT/audio-files"
# Pure local-library grouping and queue submission order.
BUILD_DIR="$OUT" bash "$HERE/pages-build.sh"
