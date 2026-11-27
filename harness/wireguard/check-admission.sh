#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sgwg-admission.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun clang -fobjc-arc -framework Foundation "$ROOT/harness/wireguard/admission.m" -o "$WORK/admission"
"$WORK/admission"
# Run each SDK's compiled key policy on the host without booting a simulator.
for platform in iphoneos iphonesimulator; do
  target=arm64-apple-ios16.0
  if [[ $platform == iphonesimulator ]]; then target="$(uname -m)-apple-ios16.0-simulator"; fi
  xcrun --sdk "$platform" clang -target "$target" -E -P -x c -imacros TargetConditionals.h \
    "$ROOT/tweak/Sources/Shared/WireGuard/SGWGLoaderKeys.inc" > "$WORK/keys.inc"
  xcrun clang -I"$WORK" '-DSGWG_LOADER_KEYS="keys.inc"' "$ROOT/harness/wireguard/loader-policy.c" -o "$WORK/policy"
  env -i "$WORK/policy" "$platform"
done
echo "PASS host load commands and device/simulator loader policy"
