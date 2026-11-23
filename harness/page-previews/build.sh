#!/bin/sh
# Builds and runs the page previews harness in an iOS simulator of its own, made for the run and deleted after it
# (Mac Catalyst keeps one text size, and the cards follow the reader's): the redesign's Playlists, Home, Search,
# Albums and Artists pages as their builders make them, with the preview card (Redesigned/Kit/SGRPagePreview.m), the
# Settings/ framework and the Kit's tokens and accent. Runs left to right, then right to left (`rtl`). Writes each
# card in each state to build/png/ and exits nonzero on a failed check. Needs THEOS for logos.pl (the accent's Logos
# file).
#     THEOS=$HOME/theos ./build.sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT=${HARNESS_BUILD_DIR:-"$HERE/build"}
APP="$OUT/PagePreviewsHarness.app"
mkdir -p "$APP" "$OUT/gen" "$OUT/png"
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Kit/SGRAccent.x" > "$OUT/gen/SGRAccent.m"
python3 "$HERE/../album-counts/cover-source.py" "$SRC" "$OUT/gen/cover-prefs.m"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 -isysroot "$SDK" \
    -I"$SRC" -iquote "$SRC/Redesigned/Kit" -Wall -Werror -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/stubs.m" "$OUT/gen/SGRAccent.m" "$OUT/gen/cover-prefs.m" \
    "$SRC/Redesigned/Kit/SGRPagePreview.m" "$SRC/Redesigned/Kit/SGRTokens.m" "$SRC/Redesigned/Kit/SGRPalette.m" \
    "$SRC/Redesigned/Kit/SGRAccentContext.m" "$SRC/Core/SGTopController.m" \
    "$SRC/Redesigned/Playlist/PlaylistSettings.m" "$SRC/Redesigned/Search/SearchSettings.m" \
    "$SRC/Redesigned/Home/HomeSettings.m" "$SRC/Redesigned/Home/HomeShelves.m" \
    "$SRC/Redesigned/Album/AlbumSettings.m" "$SRC/Redesigned/Album/AlbumNotes.m" "$SRC/Redesigned/Album/AlbumPlays.m" \
    "$SRC/Redesigned/Album/AlbumPlaysText.m" \
    "$SRC/Redesigned/Album/AlbumPlaysPlace.m" "$SRC/Redesigned/Artist/ArtistSettings.m" \
    "$SRC/Shared/Player/SGLastTrack.m" "$SRC/Shared/AnimatedArtwork/MotionSources.m" \
    "$SRC/Shared/AnimatedArtwork/SGMotionTicket.m" \
    "$SRC/Settings/SGPage.m" "$SRC/Settings/SGPageStyle.m" "$SRC/Settings/SGModPage.m" "$SRC/Settings/SGSettingsSearch.m" "$SRC/Settings/SGSettingsIndex.m" "$SRC/Settings/SGGlowSwitch.m" \
    "$SRC/Settings/SGSourcesPage.m" \
    "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLocalize.m" "$SRC/Core/SGGlass.m" "$SRC/Core/SGViewTree.m" "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGUIMode.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework CoreImage -framework Foundation \
    -o "$APP/PagePreviewsHarness"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PagePreviewsHarness</string>
<key>CFBundleIdentifier</key><string>com.retrine.page-previews-harness</string>
<key>CFBundleName</key><string>PagePreviewsHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict>
<key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Default</string>
<key>UISceneDelegateClassName</key><string>HarnessScene</string>
</dict></array></dict></dict>
</dict></plist>
PLIST
codesign -f -s - "$APP" >/dev/null 2>&1

# A simulator of the run's own, so no other run's state or settings meet this one; shut down and deleted however the
# run ends.
TYPE=$(xcrun simctl list devicetypes | sed -n 's/.*(\(com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro\))$/\1/p' | head -1)
RUNTIME=$(xcrun simctl list runtimes available | sed -n 's/.* - \(com.apple.CoreSimulator.SimRuntime.iOS-[0-9-]*\)$/\1/p' | tail -1)
UDID=$(xcrun simctl create "PagePreviewsHarness-$$" "$TYPE" "$RUNTIME")
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1; xcrun simctl delete "$UDID" >/dev/null 2>&1' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" >/dev/null
xcrun simctl install "$UDID" "$APP"
SIMCTL_CHILD_PAGE_PREVIEWS_PNG="$OUT/png" xcrun simctl launch --console-pty "$UDID" com.retrine.page-previews-harness \
    -AppleLanguages '(en)' -AppleLocale en_US | tee "$OUT/run.log"
grep -q "page previews: all checks passed" "$OUT/run.log"
# Again right to left: the same checks, the PNGs named <...>-rtl.png, and the cards mirrored (main.m, the mirror check).
SIMCTL_CHILD_PAGE_PREVIEWS_PNG="$OUT/png" xcrun simctl launch --console-pty "$UDID" com.retrine.page-previews-harness \
    rtl -AppleLanguages '(en)' -AppleLocale en_US -AppleTextDirection YES -NSForceRightToLeftWritingDirection YES | tee "$OUT/run-rtl.log"
grep -q "page previews: all checks passed" "$OUT/run-rtl.log"
