#!/bin/bash
# Production accent owner and drawing hooks, existing artwork/top-controller boundaries as test doubles.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=$(mktemp -d /tmp/retrine-appearance-accent.XXXXXX)
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk macosx --show-sdk-path)
# Every check runs from a bundle of its own, so each has a preference domain no other harness shares
# (scripts/harness-plan.py's lock audit reads these literal identifiers).
CHECK="$OUT/Check.app"
PLAYER="$OUT/Player.app"
NAV="$OUT/Navigation.app"
mkdir -p "$CHECK/Contents/MacOS" "$PLAYER/Contents/MacOS" "$NAV/Contents/MacOS"
cat > "$CHECK/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>check</string>
<key>CFBundleIdentifier</key><string>com.retrine.appearance.check</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
cat > "$PLAYER/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>player-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.appearance.player-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>PlayerScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
cat > "$NAV/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>navigation-check</string>
<key>CFBundleIdentifier</key><string>com.retrine.appearance.navigation-check</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>NavigationScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${ACCENT_HOOK:-$SRC/Redesigned/Kit/SGRAccent.x}" > "$OUT/SGRAccent.m"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Redesigned/Kit" \
    "$HERE/check.m" "${CONTEXT:-$SRC/Redesigned/Kit/SGRAccentContext.m}" "$OUT/SGRAccent.m" "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$OUT/Check.app/Contents/MacOS/check"
codesign -f -s - "$CHECK"
case "${1:-all}" in
    stock|animations|reenable) "$CHECK/Contents/MacOS/check" "$1"; exit ;;
    provenance) ;;
    *) "$CHECK/Contents/MacOS/check"; "$CHECK/Contents/MacOS/check" stock ;;
esac
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "${PLAYER_ACCENT:-$SRC/Redesigned/Player/PlayerCoverAccent.x}" > "$OUT/PlayerCoverAccent.m"
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Redesigned/Kit" -I"$SRC/Redesigned/Player" \
    "$HERE/player-check.m" "$SRC/Redesigned/Kit/SGRAccentContext.m" "$OUT/SGRAccent.m" "$OUT/PlayerCoverAccent.m" \
    "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGLog.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$OUT/Player.app/Contents/MacOS/player-check"
codesign -f -s - "$PLAYER"
"$PLAYER/Contents/MacOS/player-check" stock
[ "${1:-all}" = provenance ] && exit 0
for automatic in 0 1; do
    for follow in 0 1; do
        "$PLAYER/Contents/MacOS/player-check" -spotifyglass.redesign.accent.auto "$automatic" -spotifyglass.redesign.player.followsCover "$follow"
    done
done
xcrun clang -target $(uname -m)-apple-ios17.0-macabi -fobjc-arc -O0 -g -isysroot "$SDK" \
    -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -I"$SRC" -I"$SRC/Redesigned/Kit" \
    "$HERE/navigation-check.m" "$SRC/Redesigned/Kit/SGRAccentContext.m" "$OUT/SGRAccent.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGTopController.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -o "$OUT/Navigation.app/Contents/MacOS/navigation-check"
codesign -f -s - "$NAV"
"$NAV/Contents/MacOS/navigation-check"
