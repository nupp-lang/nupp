#!/bin/sh
# Build the existing SIMD Mandelbrot controls and add the matched WGPU path.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/wgpu-spike"
BUILD="$BENCH/build/mandelbrot"
LUAJIT=$("$ROOT/scripts/toolchain" luajit)/bin/luajit

# `build --target typed` below does not rebuild this checkout's compiler first:
# as a build command, it must be able to build another project's target without
# mutating the compiler it runs. Check once here instead. The launcher rebuilds
# the compiler when its sources changed, and otherwise this validates only the
# benchmark source.
./bin/nupp check bench/simd-mandelbrot/mandelbrot.nupp
mkdir -p "$BUILD"

(
    cd "$BENCH"
    "$ROOT/bin/nupp" build --target typed
)

TYPED="$ROOT/$BENCH/build/typed"
LUA_PATH="$TYPED/?.lua;$TYPED/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
export LUA_PATH LUA_CPATH

# The control compiler is launched directly rather than through bin/nupp, so it
# needs the broad development provider that bin/nupp otherwise exports only to
# its own process. Keep it feature-complete through the CPU comparison, then
# restore the typed GPU provider for the generated binding below.
NUPP_NATIVE_V2_LIBRARY=$("$ROOT/scripts/toolchain" native-rust base,files,http,net,process,tls,uri,uuid)
export NUPP_NATIVE_V2_LIBRARY
NUPP_MANDELBROT_PRECHECKED=1 \
    MANDELBROT_RESULTS="$ROOT/$BUILD/expected.bin" bench/simd-mandelbrot/run.sh
NUPP_NATIVE_V2_LIBRARY="$TYPED/lib/nupp_native_v2"
export NUPP_NATIVE_V2_LIBRARY
exec "$LUAJIT" "$BENCH/mandelbrot-api.lua" "$ROOT/$BUILD/expected.bin"
