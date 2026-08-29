#!/bin/sh
# Generate and measure one const-generic AOT specialization without installing
# it into the ordinary build or binding pipeline.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"
OUT="$SPIKE/build/const-monomorph-prototype"

cd "$ROOT"
./bin/nupp build
./bin/nupp check "$SPIKE/const-monomorph-prototype.nupp"
mkdir -p "$OUT"

case $(uname -s) in
    Darwin)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.dylib"
        LIB="$OUT/libconst-monomorph-prototype.dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.so"
        LIB="$OUT/libconst-monomorph-prototype.so"
        SHARED_FLAGS="-shared"
        MATH_LIB="-lm"
        ;;
    *) echo "const monomorph prototype: unsupported host $(uname -s)" >&2; exit 2 ;;
esac
MATH_LIB=${MATH_LIB:-}

LUA_PATH="$ROOT/build/?.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_NATIVE_LIBRARY="$NATIVE"
export LUA_PATH LUA_CPATH NUPP_NATIVE_LIBRARY

luajit "$SPIKE/generate_const_monomorph.lua" \
    "$SPIKE/const-monomorph-prototype.nupp" "$OUT"

${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -Wno-unused-parameter -Wno-parentheses-equality \
    -fPIC $SHARED_FLAGS "$OUT/kernel.c" $MATH_LIB -o "$LIB"

"$SPIKE/mandelbrot.sh" const-monomorph-ceiling >/dev/null
luajit "$SPIKE/const-monomorph-prototype_main.lua"
