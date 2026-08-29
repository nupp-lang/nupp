#!/bin/sh
# Compile mandelbrot.nupp through the AOT spike and run it.
#
# Same pipeline as build.sh, on the compute-bound workload rather than the
# memory-bound one. NUPP_NATIVE_MODE=emit-c stops after the C so it can be read.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
SOURCE=${1:-mandelbrot}
OUT="$SPIKE/build/$SOURCE"
MODE=${NUPP_NATIVE_MODE:-require}

./bin/nupp build
./bin/nupp check "$SPIKE/$SOURCE.nupp"

mkdir -p "$OUT"
"$SPIKE/generate.sh" "$SPIKE/$SOURCE.nupp" "$OUT"

if [ "$MODE" = emit-c ]; then
    echo "$OUT/kernel.c"
    exit 0
fi

case $(uname -s) in
    Darwin) LIB="$OUT/lib$SOURCE.dylib"; SHARED_FLAGS="-dynamiclib" ;;
    Linux)  LIB="$OUT/lib$SOURCE.so"; SHARED_FLAGS="-shared"; MATH_LIB="-lm" ;;
    *) echo "mandelbrot: unsupported host $(uname -s)" >&2; exit 2 ;;
esac
MATH_LIB=${MATH_LIB:-}

${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT/kernel.c" $MATH_LIB -o "$LIB"

# Build the exact annotated body through the ordinary Lua path as the semantic
# oracle. The generated C and ordinary module never come from separate source.
./bin/nupp build -O2 -o "$OUT/fallback" "$SPIKE/$SOURCE.nupp"
mkdir -p "$OUT/fallback/nupp/mem"
./bin/nupp build -O2 -o "$OUT/fallback/nupp/mem" src/nupp/mem/span.nupp
echo "$LIB"
