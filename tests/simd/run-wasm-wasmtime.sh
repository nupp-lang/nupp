#!/usr/bin/env bash
# Run compact pure-Wasm conformance and owned algorithms through the ordinary harness.
# The browser guest has its own small packaging/integration pack.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
. ./scripts/luajit.sh
select_luajit "$repo"
output=${NUPP_SIMD_WASM_OUTPUT:-$repo/build/simd-wasm}
if [[ -e "$output/report.json" ]]; then
  echo "Refusing to overwrite Wasmtime harness evidence: $output/report.json" >&2
  exit 2
fi
mkdir -p "$output"
./bin/nupp test simdwasmtimeconformancetest simdwasmalgorithmdifferentialtest --json > "$output/report.json"
luajit tests/simd/validate-wasmtime-harness.lua "$output/report.json"
