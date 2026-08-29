#!/bin/sh
# Build and run the checksum-only SIMD Mandelbrot at equal and preferred widths.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/simd-mandelbrot"
SOURCE="mandelbrot"
OUT="$BENCH/build/preferred"
OUT_X4="$BENCH/build/equal-width"

./bin/nupp build
./bin/nupp check "$BENCH/$SOURCE.nupp"
mkdir -p "$OUT" "$OUT_X4"

case $(uname -s) in
    Darwin)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.dylib"
        SUFFIX="dylib"
        SHARED_FLAGS="-dynamiclib"
        MATH_LIB=""
        ;;
    Linux)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.so"
        SUFFIX="so"
        SHARED_FLAGS="-shared"
        MATH_LIB="-lm"
        ;;
    *)
        echo "simd-mandelbrot: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

LUA_PATH="$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_NATIVE_LIBRARY="$NATIVE"
export LUA_PATH LUA_CPATH NUPP_NATIVE_LIBRARY

luajit "$BENCH/compile.lua" "$BENCH/$SOURCE.nupp" "$OUT"
NUPP_AOT_BENCH_GANG_BYTES=16 \
    luajit "$BENCH/compile.lua" "$BENCH/$SOURCE.nupp" "$OUT_X4"

${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT/kernel.c" $MATH_LIB -o "$OUT/lib${SOURCE}.$SUFFIX"
${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-parentheses-equality -fPIC $SHARED_FLAGS \
    "$OUT_X4/kernel.c" $MATH_LIB -o "$OUT_X4/lib${SOURCE}_x4.$SUFFIX"

exec luajit "$BENCH/main.lua"
