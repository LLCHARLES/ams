#!/bin/bash
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d /tmp/retrine-album-notes.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal ../../tweak/Sources/Redesigned/Album/AlbumSections.x > "$OUT/AlbumSections.m"
xcrun -sdk macosx clang -target $(uname -m)-apple-ios17.0-macabi -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
    -fobjc-arc -DSG_MOTION_TEST_STORE -DSG_ALBUM_NOTES_TEST_PROBE -I ../../tweak/Sources -I ../../tweak/Sources/Redesigned/Album \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework AVFoundation -framework CoreMedia -framework CoreVideo \
    main.m catalog-boundary.m "$OUT/AlbumSections.m" ../../tweak/Sources/Core/SGLog.m ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionCatalog.m \
    ../../tweak/Sources/Shared/Lyrics/LyricsLanguage.m -framework NaturalLanguage -Wl,-dead_strip \
    ../../tweak/Sources/Shared/AnimatedArtwork/SGMotionTicket.m ../../tweak/Sources/Redesigned/Album/AlbumNotes.m ../../tweak/Sources/Core/SGDataRoot.m -o "$OUT/retrine-album-notes-check"
RETRINE_TEST_ROOT="$OUT/catalog" "$OUT/retrine-album-notes-check" fixtures/catalog.json
