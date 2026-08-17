#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

OUT=bench/span-range-lowering/build
mkdir -p "$OUT/disabled" "$OUT/enabled" "$OUT/runtime/nupp" "$OUT/aot"
./bin/nupp build -O1 --relax=frames -Zno-opt=OPT-6 -o "$OUT/disabled" \
    bench/span-range-lowering/kernel.nupp bench/span-range-lowering/matrix.nupp
./bin/nupp build -O1 --relax=frames -o "$OUT/enabled" \
    bench/span-range-lowering/kernel.nupp bench/span-range-lowering/matrix.nupp
./bin/nupp build -O1 --relax=frames -o "$OUT/runtime/nupp" src/nupp/span.nupp

# AOT is context rather than the acceptance target. Reuse the checked subset
# generator, force its scalar oracle, and call that oracle from the benchmark.
bench/kernel-subset-spike/generate.sh bench/span-range-lowering/aot.nupp "$OUT/aot"
case $(uname -s) in
    Darwin) AOT_LIB="$OUT/aot/libspan_range_aot.dylib"; AOT_FLAGS="-dynamiclib" ;;
    Linux) AOT_LIB="$OUT/aot/libspan_range_aot.so"; AOT_FLAGS="-shared" ;;
    *) echo "span-range-lowering: unsupported host $(uname -s)" >&2; exit 2 ;;
esac
NATIVE_CC=${NUPP_NATIVE_CC:-clang}
$NATIVE_CC -std=c11 -O3 -ffp-contract=off -fno-fast-math -fPIC \
    -Wall -Wextra -Werror -Wno-parentheses-equality $AOT_FLAGS \
    "$OUT/aot/kernel.c" -o "$AOT_LIB"
