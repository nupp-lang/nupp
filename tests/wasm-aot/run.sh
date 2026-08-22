#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
scalar_project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-scalar.XXXXXX")
simd_project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-simd.XXXXXX")
host=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-aot-host.XXXXXX")
trap 'rm -rf "$scalar_project" "$simd_project" "$host"' EXIT

if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi

cp -R "$script_dir/project/." "$scalar_project"
(
  cd "$scalar_project"
  NUPP_WASM_CC="$emcc_command" "$repo/bin/nupp" build --target app
)
cp -R "$script_dir/simd-project/." "$simd_project"
(
  cd "$simd_project"
  NUPP_WASM_CC="$emcc_command" "$repo/bin/nupp" build --target app
)
EMCC="$emcc_command" "$repo/runtime/wasm/build-app-host.sh" \
  "$host/nupp-app.mjs" "$lua_source"
node "$script_dir/run.mjs" "$scalar_project" "$host" scalar
node "$script_dir/run.mjs" "$simd_project" "$host" simd128
