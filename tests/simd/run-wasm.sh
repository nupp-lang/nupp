#!/usr/bin/env bash
# Exercise independently compiled Wasm kernels through the LuaJIT browser guest.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
./bin/nupp build
output=${NUPP_SIMD_WASM_OUTPUT:-$repo/build/simd-wasm}
guest=${NUPP_BROWSER_GUEST_DIR:?NUPP_BROWSER_GUEST_DIR must name the unpacked browser guest}
if [[ -e "$output/revision.txt" ]]; then
  echo "Refusing to overwrite Wasm SIMD matrix evidence: $output" >&2
  exit 2
fi
mkdir -p "$output"
git rev-parse HEAD > "$output/revision.txt"
printf '%s\n' "${NUPP_SIMD_TYPES:-float,number,int8,uint8,int16,uint16,int32,uint32,int64,uint64}" > "$output/types.txt"
printf '%s\n' "${NUPP_SIMD_FAMILIES:-primitives,reducers}" > "$output/families.txt"
printf '%s\n' "${NUPP_SIMD_LANES:-all}" > "$output/lanes.txt"
luajit -e 'print(assert(require("tests.simd.runner").codegen()))' > "$output/compiler.txt"
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
    NUPP_SIMD_TYPES="$element" \
      luajit tests/simd/run.lua wasm "$family" "$directory" > "$directory/driver.log" 2>&1
    node tests/simd/run-browser-guest.mjs "$directory" "$guest" "$directory/browser" simd > "$directory/execution.log" 2>&1
    luajit tests/simd/prepare-wasm-reference.lua "$directory" "$directory/scalar-c" > "$directory/scalar-build.log" 2>&1
    node tests/simd/run-browser-guest.mjs "$directory/scalar-c" "$guest" "$directory/scalar-c/browser" scalar-c > "$directory/scalar-execution.log" 2>&1
    echo "Wasm SIMD128 and scalar twins / $family / $element passed"
  done
done

# Numeric-for setup is a runtime contract, separate from the species matrix.
# Require both independent Wasm routes to agree on numeric-for semantics.
counted="$output/counted"
NUPP_SIMD_COUNTED_OUTPUT="$counted" \
  luajit -e 'require("tests.simd.runner").wasm(require("tests.simd.counted").generate(), {directory=os.getenv("NUPP_SIMD_COUNTED_OUTPUT")})' \
  > "$output/counted-build.log" 2>&1
node tests/simd/run-browser-guest.mjs "$counted" "$guest" "$counted/browser" simd > "$counted/execution.log" 2>&1
luajit tests/simd/prepare-wasm-reference.lua "$counted" "$counted/scalar-c" > "$counted/scalar-build.log" 2>&1
node tests/simd/run-browser-guest.mjs "$counted/scalar-c" "$guest" "$counted/scalar-c/browser" scalar-c > "$counted/scalar-execution.log" 2>&1
echo "Wasm counted-loop runtime semantics and scalar twins passed"

node tests/simd/summarize-wasm.mjs "$output"
