#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
scalar_project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-scalar.XXXXXX")
simd_project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-simd.XXXXXX")
gpu_project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-gpu.XXXXXX")
host=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-host.XXXXXX")
trap 'rm -rf "$scalar_project" "$simd_project" "$gpu_project" "$host"' EXIT

if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi

cp -R "$script_dir/project/." "$scalar_project"
(
  cd "$scalar_project"
  NUPP_WASM_CC="$emcc_command" "$repo/bin/nupp" build --target app
)
# Resolve the shared conformance fixture before moving out of the source tree.
cp -RL "$script_dir/simd-project/." "$simd_project"
(
  cd "$simd_project"
  NUPP_WASM_CC="$emcc_command" "$repo/bin/nupp" build --target app
)
lpeg_source=$("$repo/scripts/toolchain" lpeg-source)
EMCC="$emcc_command" "$repo/runtime/wasm/build-app-host.sh" \
  "$host/nupp-app.mjs" "$lua_source" "$lpeg_source"
node "$script_dir/run.mjs" "$scalar_project" "$host" scalar
node "$script_dir/run.mjs" "$simd_project" "$host" simd128

# Exercise the actual memory service's rooting and revocation, including GC.
NUPP_LUA51_SOURCE="$lua_source" NUPP_WASM_CC="$emcc_command" \
  "$repo/tests/wasm-memory/run.sh" wasm

# Build-only GPU packaging is checked after the executable memory suites.
cp -R "$script_dir/gpu-project/." "$gpu_project"
(
  cd "$gpu_project"
  NUPP_WASM_CC="$emcc_command" "$repo/bin/nupp" build --target app
)
if ! grep -Fq 'dispatchWords' "$gpu_project/dist/app.lua" ||
   grep -Eq 'nupp\.runtime\.native|native\.ffi' "$gpu_project/dist/app.lua"; then
  echo "browser GPU binding was not emitted without LuaJIT FFI" >&2
  exit 1
fi
