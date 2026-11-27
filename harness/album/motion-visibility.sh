#!/bin/bash
# CI owns a temporary simulator. A caller passing a booted UDID owns its lifecycle.
set -eu
sim=${1:-}
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
bundle=
own=
prefix=RetrineHeaderMotion-
cleanup() {
    if [ -n "$bundle" ]; then xcrun simctl uninstall "$sim" "$bundle" || true; fi
    if [ -n "$own" ]; then xcrun simctl shutdown "$own" >/dev/null 2>&1 || true; xcrun simctl delete "$own"; fi
    rm -rf "$out"
}
trap cleanup EXIT
trap 'exit 143' TERM INT
if [ -z "$sim" ]; then
    for stale in $(xcrun simctl list devices | sed -nE "s/^ *${prefix}([0-9]+) \(([0-9A-F-]+)\).*/\1:\2/p"); do
        if kill -0 "${stale%:*}" 2>/dev/null; then continue; fi
        xcrun simctl shutdown "${stale#*:}" >/dev/null 2>&1 || true
        xcrun simctl delete "${stale#*:}"
    done
    own=$(xcrun simctl create "$prefix$$" com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro)
    sim=$own
    xcrun simctl bootstatus "$sim" -b
fi
python=${MOTION_PIXELS_PYTHON:-python3}
"$python" "$here/album/motion-pixels.py" fixture "$out"
HARNESS_BUILD_DIR="$out/Album" /usr/bin/lockf -k /tmp/vitrine-build.lock sh "$here/album/build.sh"
HARNESS_BUILD_DIR="$out/Artist" /usr/bin/lockf -k /tmp/vitrine-build.lock sh "$here/artist/build.sh"
status=0
for page in Album Artist; do
    lower=$(printf '%s' "$page" | tr '[:upper:]' '[:lower:]')
    app="$out/$page/${page}Harness.app"
    cp "$out/motion-fixture.mp4" "$out/replacement.mp4" "$app/"
    id="com.vojta.${lower}harness.motion-$$"
    awk -v entry="<key>CFBundleIdentifier</key><string>$id</string>" '{ n += sub(/<key>CFBundleIdentifier<\/key><string>[^<]+<\/string>/, entry); print } END { exit n != 1 }' "$app/Info.plist" > "$out/Info.plist"
    mv "$out/Info.plist" "$app/Info.plist"
    xcrun simctl install "$sim" "$app"
    bundle=$id
    "$python" "$here/album/motion-pixels.py" "$sim" "$bundle" "$out" || status=1
    xcrun simctl uninstall "$sim" "$bundle"
    bundle=
done
exit "$status"
