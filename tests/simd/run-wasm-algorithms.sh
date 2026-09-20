#!/usr/bin/env bash
# One owned-algorithm job, independent of the type/width primitive shards.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
./bin/nupp build
output=${NUPP_SIMD_WASM_ALGORITHMS_OUTPUT:-$repo/build/simd-wasm-algorithms}
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
if [[ -e "$output/revision.txt" ]]; then
  echo "Refusing to overwrite algorithm execution evidence: $output" >&2
  exit 2
fi
mkdir -p "$output/host"
git rev-parse HEAD > "$output/revision.txt"
"$emcc_command" --version > "$output/compiler.txt"
lpeg_source=$(./scripts/toolchain lpeg-source)
EMCC="$emcc_command" runtime/wasm/build-app-host.sh "$output/host/nupp-app.mjs" "$lua_source" "$lpeg_source" > "$output/host-build.log" 2>&1
for algorithm in utf8simd base64simd simd-json fused-json; do
  directory="$output/$algorithm"
  if NUPP_WASM_CC="$emcc_command" luajit tests/simd/build-algorithm-wasm.lua "$algorithm" "$directory" > "$output/$algorithm-build.log" 2>&1; then
    if ! node tests/simd/run-algorithm-wasm.mjs "$algorithm" "$directory" "$output/host" > "$output/$algorithm-execution.log" 2>&1; then
      echo "$algorithm failed; preserved its execution log" >&2
    fi
  else
    echo "$algorithm failed to build; preserved its build log" >&2
  fi
done
node tests/simd/summarize-wasm-algorithms.mjs "$output" "$(git rev-parse HEAD)"
