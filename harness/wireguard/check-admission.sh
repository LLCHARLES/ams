#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/sgwg-admission.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
xcrun clang -fobjc-arc -framework Foundation "$ROOT/harness/wireguard/admission.m" -o "$WORK/admission"
"$WORK/admission"
