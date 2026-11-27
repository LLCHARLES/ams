#!/bin/bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
sed -n '/^static NSString \*const kShader =/,/^"}\\n";/p' \
    "${FLUID_SOURCE:-$here/../../tweak/Sources/Redesigned/Kit/SGRFluidGPU.m}" > "$work/shader.inc"
xcrun clang -fobjc-arc -framework Metal -framework Foundation -I"$work" "$here/fluid-fragment-check.m" -o "$work/check"
"$work/check"
