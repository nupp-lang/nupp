#!/usr/bin/env bash
# Use the established Lua 5.1 Wasm host; this adds no browser runtime route.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
./bin/nupp build
output=${NUPP_SIMD_WASM_OUTPUT:-$repo/build/simd-wasm}
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
if [[ -e "$output/revision.txt" ]]; then
  echo "Refusing to overwrite Wasm SIMD matrix evidence: $output" >&2
  exit 2
fi
mkdir -p "$output/host"
git rev-parse HEAD > "$output/revision.txt"
printf '%s\n' "${NUPP_SIMD_TYPES:-float,number,int8,uint8,int16,uint16,int32,uint32,int64,uint64}" > "$output/types.txt"
printf '%s\n' "${NUPP_SIMD_FAMILIES:-primitives,reducers}" > "$output/families.txt"
printf '%s\n' "${NUPP_SIMD_LANES:-all}" > "$output/lanes.txt"
"$emcc_command" --version > "$output/compiler.txt"
lpeg_source=$(./scripts/toolchain lpeg-source)
EMCC="$emcc_command" runtime/wasm/build-app-host.sh "$output/host/nupp-app.mjs" "$lua_source" "$lpeg_source"
IFS=, read -r -a families <<< "${NUPP_SIMD_FAMILIES:-primitives,reducers}"
IFS=, read -r -a types <<< "${NUPP_SIMD_TYPES:-float,number,int8,uint8,int16,uint16,int32,uint32,int64,uint64}"
for family in "${families[@]}"; do
  for element in "${types[@]}"; do
    directory="$output/$family/$element"
    if [[ -e "$directory/result.json" ]]; then
      echo "Refusing to overwrite Wasm SIMD execution evidence: $directory" >&2
      exit 2
    fi
    mkdir -p "$directory"
    NUPP_WASM_CC="$emcc_command" NUPP_SIMD_TYPES="$element" \
      luajit tests/simd/run.lua wasm "$family" "$directory" > "$directory/driver.log" 2>&1
    node tests/simd/run-wasm.mjs "$directory" "$output/host" > "$directory/execution.log" 2>&1
    NUPP_WASM_CC="$emcc_command" node tests/simd/prepare-wasm-scalar.mjs "$directory" "$directory/scalar-c" > "$directory/scalar-build.log" 2>&1
    node tests/simd/run-wasm.mjs "$directory/scalar-c" "$output/host" > "$directory/scalar-execution.log" 2>&1
    echo "Wasm SIMD128 and scalar C / $family / $element passed"
  done
done

node tests/simd/summarize-wasm.mjs "$output"
