#!/bin/sh
# Build and run the scalar-source SIMD differential test.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
OUT="$SPIKE/build/lanedemo"

./bin/nupp build
./bin/nupp check "$SPIKE/lanedemo.nupp"
mkdir -p "$OUT"
"$SPIKE/generate.sh" "$SPIKE/lanedemo.nupp" "$OUT"

case $(uname -s) in
    Darwin) LIB="$OUT/liblanedemo.dylib"; SHARED_FLAGS="-dynamiclib" ;;
    Linux)  LIB="$OUT/liblanedemo.so"; SHARED_FLAGS="-shared" ;;
    *) echo "simd spike: unsupported host $(uname -s)" >&2; exit 2 ;;
esac

${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT/kernel.c" -o "$LIB"

./bin/nupp build -O2 -o "$OUT/fallback" "$SPIKE/lanedemo.nupp"
mkdir -p "$OUT/fallback/nupp/mem"
./bin/nupp build -O2 -o "$OUT/fallback/nupp/mem" src/nupp/mem/span.nupp

luajit "$SPIKE/simd_test.lua"
