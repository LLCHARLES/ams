#!/bin/sh
set -eu
cd "$(dirname "$0")"
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
xcrun clang -fobjc-arc -I"${SRC:-../../tweak/Sources}" -framework Foundation check.m -o "$out/check"
"$out/check" "$out/fixture"
