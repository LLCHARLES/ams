#!/usr/bin/env bash
# Builds the app-local WireGuard engine (wireguard-go + gVisor netstack) as a
# separately loadable iOS arm64 library: WireGuard/build/libsgwg.dylib
#
# macOS: uses Xcode's iPhoneOS SDK via xcrun.
# Linux: set IOS_SDK=/path/to/iPhoneOS.sdk (clang must support -target arm64-apple-ios).
# Requires exactly the Go release in go.mod; never downloads another toolchain.
set -euo pipefail
cd "$(dirname "$0")"
export GOTOOLCHAIN=local
EXPECTED_GO="go$(awk '$1 == "go" {print $2}' go.mod)"
ACTUAL_GO="$(go env GOVERSION)"
if [[ "$ACTUAL_GO" != "$EXPECTED_GO" ]]; then
  echo "WireGuard requires exactly $EXPECTED_GO; got $ACTUAL_GO" >&2
  exit 1
fi

MIN_IOS="${MIN_IOS:-16.0}"  # same deployment target as the tweak (Makefile TARGET)
if [[ -z "${IOS_SDK:-}" ]]; then
  IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
  CLANG="$(xcrun --sdk iphoneos --find clang)"
else
  CLANG="${CLANG:-clang}"
fi
FLAGS="-target arm64-apple-ios${MIN_IOS} -isysroot ${IOS_SDK} -miphoneos-version-min=${MIN_IOS}"

mkdir -p build
GOOS=ios GOARCH=arm64 CGO_ENABLED=1 \
  CC="${CLANG} ${FLAGS}" CGO_CFLAGS="${FLAGS} -O2" CGO_LDFLAGS="${FLAGS}" \
  go build -trimpath -buildvcs=false -ldflags="-s -w -buildid=" -buildmode=c-archive \
  -o build/libsgwg.a .

# GNU ar (Linux) cannot index Mach-O members; Apple's ld64 and lld need an index.
if [[ "$(uname)" == "Darwin" ]]; then
  xcrun ranlib build/libsgwg.a
elif command -v llvm-ranlib >/dev/null; then
  llvm-ranlib build/libsgwg.a
fi

# Go doesn't support c-shared on iOS. Link its indexed archive into an ordinary
# Mach-O dylib, rooting the entire bridge in one typed, versioned export.
"$CLANG" -target "arm64-apple-ios${MIN_IOS}" -isysroot "$IOS_SDK" -dynamiclib \
  -install_name @rpath/libsgwg.dylib -Wl,-adhoc_codesign,-u,_SGWGEngineV2,-exported_symbol,_SGWGEngineV2 \
  build/libsgwg.a -framework CoreFoundation -framework Security -lresolv -o build/libsgwg.dylib
