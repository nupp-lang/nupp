#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-spike"
OUT="$SPIKE/build"
DYNASM_ROOT=${DYNASM_ROOT:-}

if [ -z "$DYNASM_ROOT" ] || [ ! -f "$DYNASM_ROOT/dynasm.lua" ]; then
    echo "kernel-spike: set DYNASM_ROOT to LuaJIT's dynasm directory" >&2
    echo "kernel-spike: for example, DYNASM_ROOT=/path/to/LuaJIT/dynasm" >&2
    exit 2
fi

mkdir -p "$OUT"
luajit "$DYNASM_ROOT/dynasm.lua" \
    -o "$OUT/kernel_spike.c" \
    "$SPIKE/kernel_spike.dasc"

case $(uname -s) in
    Darwin)
        LIB="$OUT/libkernel_spike.dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        LIB="$OUT/libkernel_spike.so"
        SHARED_FLAGS="-shared"
        ;;
    *)
        echo "kernel-spike: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

clang -std=c11 -O3 -Wall -Wextra -Werror -Wno-unused-function -fPIC \
    $SHARED_FLAGS \
    -I"$DYNASM_ROOT" \
    "$OUT/kernel_spike.c" \
    -o "$LIB"

# Nupp's `from` clause passes the library spelling to ffi.load unchanged.
ln -sf "$(basename "$LIB")" "$OUT/libkernel_spike"

echo "$LIB"
