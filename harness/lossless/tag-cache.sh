#!/bin/sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
for pair in 'one First' 'two Second'; do
    set -- $pair
    ffmpeg -v error -f lavfi -i anullsrc -t 0.1 -c:a alac -metadata title="$2" "$out/$1.m4a"
done
xcrun clang -fobjc-arc -framework Foundation -framework AudioToolbox "$here/tag-cache.m" -o "$out/check"
"$out/check" "$out"
