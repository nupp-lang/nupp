#!/usr/bin/env bash
# Execute the compact native harness packs and owned algorithms at every
# available requested compiler/tier pair. Missing hardware remains explicit.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"

# Keep the provisioned host runtime fixed while NUPP_NATIVE_CC selects the
# compiler for emitted C. The legacy NUPP_CC alias also selects dependency
# prefixes, so changing it per row can hide the provisioned LPeg tree.
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
  export NUPP_TEST_BASH
  NUPP_TEST_BASH=$(cygpath -w "$(command -v bash)")
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

IFS=, read -r -a compilers <<< "${NUPP_SIMD_COMPILERS:-clang,gcc}"
IFS=, read -r -a algorithms <<< "${NUPP_SIMD_ALGORITHMS:-utf8simd,base64simd,simd-json,fused-json}"
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

join_csv() { local IFS=,; printf '%s' "$*"; }
luajit tests/simd/select-native-packs.lua "$output" "$(join_csv "${compilers[@]}")" \
  "$(join_csv "${tiers[@]}")" "$(join_csv "${algorithms[@]}")"
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

    directory="$compiler_dir/$tier/packs"
    mkdir -p "$directory"
    echo "$compiler / $tier / compact native packs"
    if NUPP_NATIVE_CC="$compiler" NUPP_SIMD_TIER="$tier" \
        ./bin/nupp test simdprimitivedifferentialtest --jobs=1 --timings=0 --json \
        > "$directory/report.json" 2> "$directory/driver.log"; then
      printf '%s\t%s\tpacks\tcompact\texecuted\t%s\n' "$index" "$tier" \
        "$directory/report.json" >> "$output/matrix.tsv"
    else
      printf '%s\t%s\tpacks\tcompact\tfailed\t%s\n' "$index" "$tier" \
        "$directory/driver.log" >> "$output/matrix.tsv"
      cat "$directory/driver.log" >&2
      status=1
    fi

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
luajit tests/simd/summarize-native-packs.lua "$output"
exit "$status"
