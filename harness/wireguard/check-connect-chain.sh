#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sgwg-chain.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun clang -dynamiclib "$ROOT/harness/wireguard/chain-shared.c" -o "$WORK/SpotifyShared"
xcrun clang -fobjc-arc -O2 -Wall -Werror -I "$ROOT/tweak/Sources" \
  "$ROOT/harness/wireguard/connect-chain.m" "$ROOT/tweak/Sources/Core/SGRebind.m" \
  "$ROOT/tweak/Sources/Shared/WireGuard/SGWGNative.m" \
  "$ROOT/tweak/Sources/Shared/WireGuard/SGWGAdmission.m" \
  "$ROOT/tweak/Sources/Shared/Connect/SGMDNS.m" "$ROOT/tweak/Sources/Shared/Connect/SGConnectRelay.m" \
  -framework Foundation -framework Network -o "$WORK/Spotify"
"$WORK/Spotify" connect-first "$WORK/SpotifyShared"
"$WORK/Spotify" wireguard-first "$WORK/SpotifyShared"
