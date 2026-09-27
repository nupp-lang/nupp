#!/bin/sh
# Build and run scalar and authored SIMD point-batch Mandelbrot entries.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/simd-mandelbrot"
SOURCE="mandelbrot"
OUT="$BENCH/build/current"

# A normal launcher command rebuilds the compiler only after its sources
# changed. Do not unconditionally build the compiler target here: a warm root
# build still validates every compiler module and this runner is also called by
# the WGPU benchmark after its shared preflight.
if [ "${NUPP_MANDELBROT_PRECHECKED:-}" != 1 ]; then
    ./bin/nupp check "$BENCH/$SOURCE.nupp"
fi
mkdir -p "$OUT"

case $(uname -s) in
    Darwin|Linux) ;;
    *)
        echo "simd-mandelbrot: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

LUA_PATH="$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
export LUA_PATH LUA_CPATH

# LLVM compiles in process, through the development native library that
# carries the code generator.
NUPP_NATIVE_LIBRARY="${NUPP_NATIVE_LIBRARY:-$(ls "$ROOT"/build/lib/libnupp_native_dev.* | head -n 1)}"
export NUPP_NATIVE_LIBRARY
luajit "$BENCH/compile.lua" "$BENCH/$SOURCE.nupp" "$OUT"
exec luajit "$BENCH/main.lua"
