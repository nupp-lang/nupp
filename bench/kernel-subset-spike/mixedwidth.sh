#!/bin/sh
# What the all-or-nothing gang-width rule costs.
#
# Builds the same arithmetic twice -- once with a binary64 running total and step
# counter, which takes the binary64 gang, and once with both narrowed, which
# takes the 32-bit gang and twice the lanes -- and reports each against its own
# forced-scalar body from the same source.
#
# The ratio between the two speedups is the ceiling on mixed-width gang sizing,
# not what it would deliver: a gang that carried the wide value at its own width
# would still spend twice the registers on it.
set -eu

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
OUT="$SPIKE/build/mixedwidth-timing"

CC=${NUPP_NATIVE_CC:-}
if [ -z "$CC" ]; then
    if command -v clang >/dev/null 2>&1; then CC=clang; else CC=cc; fi
fi
DIALECT=""
case $($CC --version 2>&1 | head -1) in
    *clang*) DIALECT="-Wno-parentheses-equality" ;;
esac

ARCH=$(uname -m)
case $ARCH in
    x86_64|amd64) DEFAULT_CFLAGS="-mavx2" ;;
    *) DEFAULT_CFLAGS="" ;;
esac

./bin/nupp build
mkdir -p "$OUT"

for kernel in mixedwidth mixedwidth_f64 mixedwidth_f32; do
    ./bin/nupp aot --emit c "$SPIKE/$kernel.nupp" > "$OUT/$kernel.c"
    $CC -std=c11 -O3 -ffp-contract=off -fno-fast-math \
        -Wall -Wextra -Werror $DIALECT ${NUPP_CHECK_CFLAGS:-$DEFAULT_CFLAGS} \
        -DKERNEL_C="\"$ROOT/$OUT/$kernel.c\"" -DKERNEL_NAME="\"$kernel\"" \
        "$SPIKE/checks/mixedwidth_time.c" -lm -o "$OUT/$kernel"
done

# The gang each one actually took, so the numbers below are read beside the
# thing that produced them rather than beside an assumption about it.
#
#   mixedwidth      f64x4, rounding every explicit binary32 operation
#   mixedwidth_f64  f64x4, the same four lanes and nothing to round
#   mixedwidth_f32  f32x8, twice the lanes and nothing to round
#
# The first two differ only in the rounding; the last two only in the width.
for kernel in mixedwidth mixedwidth_f64 mixedwidth_f32; do
    ./bin/nupp aot "$SPIKE/$kernel.nupp"
done

for kernel in mixedwidth mixedwidth_f64 mixedwidth_f32; do
    "$OUT/$kernel"
done
