#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
manifest="$repo/tests/simd/wasmtime-host/Cargo.toml"
if [[ -n "${NUPP_WASMTIME_HOST_LIBRARY:-}" ]]; then
  test -f "$NUPP_WASMTIME_HOST_LIBRARY"
  printf '%s\n' "$NUPP_WASMTIME_HOST_LIBRARY"
  exit 0
fi
target=${NUPP_WASMTIME_TARGET_DIR:-$repo/build/simd-wasmtime-host}
cargo build --locked --release --manifest-path "$manifest" --target-dir "$target" >&2
case "$(uname -s)" in
  Darwin) library="$target/release/libnupp_simd_wasmtime_host.dylib" ;;
  MINGW*|MSYS*|CYGWIN*) library="$target/release/nupp_simd_wasmtime_host.dll" ;;
  *) library="$target/release/libnupp_simd_wasmtime_host.so" ;;
esac
test -f "$library"
printf '%s\n' "$library"
