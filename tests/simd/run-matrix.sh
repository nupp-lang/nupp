#!/usr/bin/env bash
# Execute every available native tier with both real compiler dialects.
# Missing hardware is recorded as not-executed, never as compile-only success.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
# Keep the compiler's provisioned host runtime fixed while NUPP_NATIVE_CC
# selects each emitted-C compiler. That legacy variable is also a toolchain
# alias: without a primary NUPP_CC, even an absolute path to the same compiler
# changes the dependency prefix and hides the already provisioned LPeg.
if [[ -z ${NUPP_CC:-} ]]; then
  NUPP_CC=${NUPP_NATIVE_CC:-}
  if [[ -z "$NUPP_CC" ]]; then
    case $(uname -s) in
      MINGW*|MSYS*|CYGWIN*) host_compilers=(gcc cc clang) ;;
      *) host_compilers=(clang cc gcc) ;;
    esac
    for candidate in "${host_compilers[@]}"; do
      if command -v "$candidate" >/dev/null 2>&1; then
        NUPP_CC=$candidate
        break
      fi
    done
  fi
fi
export NUPP_CC
: "${NUPP_CC:?No compiler is available for the provisioned host toolchain}"
. ./scripts/luajit.sh
select_luajit "$repo"
if command -v cygpath >/dev/null 2>&1; then
  export NUPP_TEST_BASH=$(cygpath -w "$(command -v bash)")
fi
./bin/nupp build
output=${NUPP_SIMD_OUTPUT:-$repo/build/simd-matrix}
mkdir -p "$output"
if [[ -f "$output/matrix.tsv" || -f "$output/selection.json" ]]; then
  echo "Refusing to overwrite SIMD matrix evidence: $output/matrix.tsv" >&2
  exit 2
fi
git rev-parse HEAD > "$output/revision.txt"
uname -a > "$output/host.txt"
luajit -v > "$output/vm.txt" 2>&1
case $(uname -s) in
  Darwin)
    if ! sysctl -n machdep.cpu.brand_string > "$output/cpu.txt" 2> "$output/cpu-probe.log"; then
      printf '%s\n' 'CPU model unavailable; see cpu-probe.log (capability execution is still required)' > "$output/cpu.txt"
    fi
    ;;
  Linux) cat /proc/cpuinfo > "$output/cpu.txt" ;;
  *) printf '%s\n' "${PROCESSOR_IDENTIFIER:-unknown}" > "$output/cpu.txt" ;;
esac
printf '%s\n' "${NUPP_SIMD_LANES:-all}" > "$output/lanes.txt"
IFS=, read -r -a compilers <<< "${NUPP_SIMD_COMPILERS:-clang,gcc}"
IFS=, read -r -a families <<< "${NUPP_SIMD_FAMILIES:-primitives,reducers}"
IFS=, read -r -a algorithms <<< "${NUPP_SIMD_ALGORITHMS:-utf8simd,base64simd,simd-json,fused-json}"
IFS=, read -r -a types <<< "${NUPP_SIMD_TYPES:-float,number,int8,uint8,int16,uint16,int32,uint32,int64,uint64}"
case $(uname -m) in
  arm64|aarch64) tiers=(neon) ;;
  x86_64|amd64) tiers=(baseline avx2 avx512f) ;;
  *) echo "Unmodeled SIMD execution host" >&2; exit 2 ;;
esac
if [[ -n ${NUPP_SIMD_TIERS:-} ]]; then
  IFS=, read -r -a tiers <<< "$NUPP_SIMD_TIERS"
  for tier in "${tiers[@]}"; do
    case "$tier" in baseline|avx2|avx512f|neon) ;; *) echo "Unknown tier: $tier" >&2; exit 2 ;; esac
  done
fi
# Freeze the request before capability probing or any corpus can fail.
join_csv() { local IFS=,; printf '%s' "$*"; }
luajit tests/simd/select-native.lua "$output" "$(join_csv "${compilers[@]}")" \
  "$(join_csv "${tiers[@]}")" "$(join_csv "${families[@]}")" \
  "$(join_csv "${types[@]}")" "$(join_csv "${algorithms[@]}")" "${NUPP_SIMD_LANES:-all}"
: > "$output/matrix.tsv"
status=0
index=0
for compiler in "${compilers[@]}"; do
  index=$((index+1))
  compiler_dir="$output/compiler-$index"
  mkdir -p "$compiler_dir"
  printf '%s\n' "$compiler" > "$compiler_dir/command.txt"
  if ! {
    "$compiler" --version > "$compiler_dir/version.txt" &&
    "$compiler" -dumpmachine > "$compiler_dir/target.txt" &&
    "$compiler" -std=c11 -O2 -Wall -Wextra -Werror tests/simd/capabilities.c -o "$compiler_dir/capabilities.exe" &&
    "$compiler_dir/capabilities.exe" | tr -d '\r' > "$compiler_dir/tiers.txt"
  } > "$compiler_dir/setup.log" 2>&1; then
    for tier in "${tiers[@]}"; do
      printf '%s\t%s\t-\t-\tfailed\t%s\n' "$index" "$tier" "$compiler_dir/setup.log" >> "$output/matrix.tsv"
    done
    status=1
    continue
  fi
  for tier in "${tiers[@]}"; do
    if ! grep -Fxq "$tier" "$compiler_dir/tiers.txt"; then
      printf '%s\t%s\t-\t-\tnot-executed\t%s\n' "$index" "$tier" "$compiler_dir/tiers.txt" >> "$output/matrix.tsv"
      echo "$compiler / $tier: NOT EXECUTED (host capability unavailable)"
      continue
    fi
    for family in "${families[@]}"; do
      for element in "${types[@]}"; do
        directory="$compiler_dir/$tier/$family/$element"
        mkdir -p "$directory"
        echo "$compiler / $tier / $family / $element"
        if NUPP_NATIVE_CC="$compiler" NUPP_SIMD_TIER="$tier" NUPP_SIMD_TYPES="$element" NUPP_SIMD_REPORT="$directory/report.json" \
            luajit tests/simd/run.lua native "$family" "$directory" > "$directory/driver.log" 2>&1; then
          printf '%s\t%s\t%s\t%s\texecuted\t%s\n' "$index" "$tier" "$family" "$element" \
            "$directory/matrix-result.json" >> "$output/matrix.tsv"
        else
          printf '%s\t%s\t%s\t%s\tfailed\t%s\n' "$index" "$tier" "$family" "$element" \
            "$directory/driver.log" >> "$output/matrix.tsv"
          cat "$directory/driver.log" >&2
          status=1
        fi
      done
    done
    for algorithm in "${algorithms[@]}"; do
      [[ "$algorithm" == none ]] && continue
      directory="$compiler_dir/$tier/algorithms/$algorithm"
      mkdir -p "$directory"
      echo "$compiler / $tier / algorithm / $algorithm"
      if NUPP_NATIVE_CC="$compiler" NUPP_SIMD_TIER="$tier" \
          luajit tests/simd/run-algorithm.lua "$algorithm" "$directory" > "$directory/driver.log" 2>&1; then
        printf '%s\t%s\talgorithms\t%s\texecuted\t%s\n' "$index" "$tier" "$algorithm" \
          "$directory/matrix-result.json" >> "$output/matrix.tsv"
      else
        printf '%s\t%s\talgorithms\t%s\tfailed\t%s\n' "$index" "$tier" "$algorithm" \
          "$directory/driver.log" >> "$output/matrix.tsv"
        cat "$directory/driver.log" >&2
        status=1
      fi
    done
  done
done
luajit tests/simd/summarize.lua "$output"
exit "$status"
