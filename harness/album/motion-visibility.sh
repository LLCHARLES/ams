#!/bin/bash
# Pass the UUID of a booted simulator with Reduce Motion off and Auto-Play Video Previews on.
set -eu
sim=${1:?pass a booted simulator UUID}
here=$(cd "$(dirname "$0")/.." && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
ffmpeg -loglevel error -f lavfi -i color=blue:s=64x64:d=4 -c:v libx264 -pix_fmt yuv420p "$out/motion-fixture.mp4"
for page in Album Artist; do
    lower=$(printf '%s' "$page" | tr '[:upper:]' '[:lower:]')
    HARNESS_BUILD_DIR="$out/$page" /usr/bin/lockf -k /tmp/vitrine-build.lock sh "$here/$lower/build.sh"
    app="$out/$page/${page}Harness.app"
    cp "$out/motion-fixture.mp4" "$app/"
    xcrun simctl install "$sim" "$app"
    xcrun simctl launch --console "$sim" "com.vojta.${lower}harness" motion-visibility >"$out/result" 2>&1
    cat "$out/result"
    grep -q 'PASS .* header playback:' "$out/result"
done
