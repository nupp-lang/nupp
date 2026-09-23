#!/usr/bin/env bash
# Keep the browser boundary honest without using Chrome as the SIMD corpus VM.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
output=${NUPP_SIMD_BROWSER_SMOKE_OUTPUT:-$repo/build/simd-browser-smoke}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
emcc_path=$(command -v "$emcc_command")
PATH="$(dirname "$emcc_path"):$PATH"
export PATH
EM_CACHE=${EM_CACHE:-$repo/build/simd-emscripten-cache/browser-smoke}
export EM_CACHE
guest=${NUPP_BROWSER_GUEST_DIR:?NUPP_BROWSER_GUEST_DIR must name the unpacked browser guest}
if [[ -e "$output" ]]; then
  echo "Refusing to overwrite browser SIMD smoke evidence: $output" >&2
  exit 2
fi
mkdir -p "$output"
NUPP_WASM_CC="$emcc_command" luajit tests/simd/build-wasm-browser-smoke.lua "$output" \
  > "$output/build.log" 2>&1
node tests/simd/run-browser-guest.mjs "$output" "$guest" "$output/browser" simd \
  > "$output/execution.log" 2>&1
NUPP_WASM_CC="$emcc_command" node tests/simd/prepare-wasm-scalar.mjs "$output" "$output/scalar-c" \
  > "$output/scalar-build.log" 2>&1
node tests/simd/run-browser-guest.mjs "$output/scalar-c" "$guest" "$output/scalar-c/browser" scalar-c \
  > "$output/scalar-execution.log" 2>&1
luajit tests/simd/validate-wasm-browser-smoke.lua "$output" "$output/browser-smoke-report.json"
echo "Browser guest / SIMD128 / int32x4 and counted-runtime routes passed"
