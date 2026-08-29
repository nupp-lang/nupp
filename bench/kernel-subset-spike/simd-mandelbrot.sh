#!/bin/sh
# Build and run the checksum-only SIMD Mandelbrot at equal and preferred widths.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
SOURCE="simd_mandelbrot"
OUT="$SPIKE/build/$SOURCE"
OUT_X4="$SPIKE/build/${SOURCE}_x4"

./bin/nupp build
./bin/nupp check "$SPIKE/$SOURCE.nupp"
mkdir -p "$OUT" "$OUT_X4"
"$SPIKE/generate.sh" "$SPIKE/$SOURCE.nupp" "$OUT"
NUPP_AOT_BENCH_GANG_BYTES=16 \
    "$SPIKE/generate.sh" "$SPIKE/$SOURCE.nupp" "$OUT_X4"

case $(uname -s) in
    Darwin)
        SUFFIX="dylib"
        SHARED_FLAGS="-dynamiclib"
        MATH_LIB=""
        ;;
    Linux)
        SUFFIX="so"
        SHARED_FLAGS="-shared"
        MATH_LIB="-lm"
        ;;
    *)
        echo "simd-mandelbrot: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT/kernel.c" $MATH_LIB -o "$OUT/lib${SOURCE}.$SUFFIX"
${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT_X4/kernel.c" $MATH_LIB -o "$OUT_X4/lib${SOURCE}_x4.$SUFFIX"

exec luajit "$SPIKE/${SOURCE}_main.lua"
