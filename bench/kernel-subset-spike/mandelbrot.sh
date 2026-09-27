#!/bin/sh
# Compile mandelbrot.nupp through the AOT spike and run it.
#
# Same pipeline as build.sh, on the compute-bound workload rather than the
# memory-bound one. NUPP_NATIVE_MODE=emit-llvm stops after the LLVM IR so it
# can be read.
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
if [ "$MODE" = emit-llvm ]; then
    "$SPIKE/generate.sh" "$SPIKE/$SOURCE.nupp" "$OUT"
    echo "$OUT/kernel.ll"
    exit 0
fi

case $(uname -s) in
    Darwin) LIB="$OUT/lib$SOURCE.dylib" ;;
    Linux)  LIB="$OUT/lib$SOURCE.so" ;;
    *) echo "mandelbrot: unsupported host $(uname -s)" >&2; exit 2 ;;
esac
"$SPIKE/generate.sh" "$SPIKE/$SOURCE.nupp" "$OUT" "$LIB"

# Build the exact annotated body through the ordinary Lua path as the semantic
# oracle. The compiled library and ordinary module never come from separate
# source.
./bin/nupp build -O2 -o "$OUT/fallback" "$SPIKE/$SOURCE.nupp"
mkdir -p "$OUT/fallback/nupp/mem"
./bin/nupp build -O2 -o "$OUT/fallback/nupp/mem" src/nupp/mem/span.nupp
mkdir -p "$OUT/fallback/nupp/compiler/runtime"
./bin/nupp build -O2 -o "$OUT/fallback/nupp/compiler/runtime" src/nupp/compiler/runtime/math.nupp
echo "$LIB"
