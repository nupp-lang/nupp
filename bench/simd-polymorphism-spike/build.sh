#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/simd-polymorphism-spike"
OUT="$SPIKE/build"

mkdir -p "$OUT"
luajit "$SPIKE/generate.lua" "$OUT/simd_spike.c"

case $(uname -s) in
    Darwin)
        LIB="$OUT/libsimd_spike.dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        LIB="$OUT/libsimd_spike.so"
        SHARED_FLAGS="-shared"
        ;;
    *)
        echo "simd-polymorphism-spike: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

TARGET_FLAGS=
if [ "$(uname -m)" = "x86_64" ]; then
    # Keep the translation-unit baseline at SSE2. The AVX2 functions opt in
    # independently, so host compiler defaults cannot leak newer instructions
    # into the fallback implementation.
    TARGET_FLAGS="-march=x86-64"
fi

clang -std=c11 -O3 -Wall -Wextra -Werror -fPIC $TARGET_FLAGS $SHARED_FLAGS \
    "$OUT/simd_spike.c" -o "$LIB"

# Nupp's `from` clause passes the library spelling to ffi.load unchanged.
ln -sf "$(basename "$LIB")" "$OUT/libsimd_spike"

echo "$LIB"
