#!/usr/bin/env bash
# One owned-algorithm job, independent of the type/width primitive shards.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
./bin/nupp build
output=${NUPP_SIMD_WASM_ALGORITHMS_OUTPUT:-$repo/build/simd-wasm-algorithms}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
guest=${NUPP_BROWSER_GUEST_DIR:?NUPP_BROWSER_GUEST_DIR must name the unpacked browser guest}
if [[ -e "$output/revision.txt" ]]; then
  echo "Refusing to overwrite algorithm execution evidence: $output" >&2
  exit 2
fi
mkdir -p "$output"
git rev-parse HEAD > "$output/revision.txt"
"$emcc_command" --version > "$output/compiler.txt"
for algorithm in utf8simd base64simd simd-json; do
  directory="$output/$algorithm"
  if NUPP_WASM_CC="$emcc_command" luajit tests/simd/build-algorithm-wasm.lua "$algorithm" "$directory" > "$output/$algorithm-build.log" 2>&1; then
    if ! node tests/simd/run-algorithm-wasm.mjs "$algorithm" "$directory" "$guest" > "$output/$algorithm-execution.log" 2>&1; then
      echo "$algorithm failed; preserved its execution log" >&2
    fi
  else
    echo "$algorithm failed to build; preserved its build log" >&2
  fi
done
node tests/simd/summarize-wasm-algorithms.mjs "$output" "$(git rev-parse HEAD)"
