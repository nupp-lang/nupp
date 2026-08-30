#!/bin/sh
# Build the existing SIMD Mandelbrot controls and add the matched SDL GPU path.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/sdl-gpu-spike"
BUILD="$BENCH/build/mandelbrot"
FRAMEWORK=${NUPP_SDL_FRAMEWORK_ROOT:?set NUPP_SDL_FRAMEWORK_ROOT to the SDL3 framework directory}

./bin/nupp build
./bin/nupp check "$BENCH/mandelbrot.nupp"
mkdir -p "$BUILD"

LUA_PATH="$ROOT/build/?.lua;$ROOT/build/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_NATIVE_LIBRARY="$ROOT/build/lib/libnupp_native_dev.dylib"
export LUA_PATH LUA_CPATH NUPP_NATIVE_LIBRARY

luajit "$BENCH/generate-msl.lua" "$BENCH/mandelbrot.nupp" "$BUILD/mandelbrot.msl"
${NUPP_NATIVE_CC:-clang} -std=c11 -O3 -Wall -Wextra -Werror -fPIC -dynamiclib \
    -F"$FRAMEWORK" "$BENCH/mandelbrot-gpu.c" -framework SDL3 \
    -Wl,-rpath,"$FRAMEWORK" -o "$BUILD/libmandelbrot_gpu.dylib"

MANDELBROT_GPU_LIBRARY="$ROOT/$BUILD/libmandelbrot_gpu.dylib"
MANDELBROT_GPU_SHADER="$ROOT/$BUILD/mandelbrot.msl"
export MANDELBROT_GPU_LIBRARY MANDELBROT_GPU_SHADER
exec bench/simd-mandelbrot/run.sh
