#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/sdl-gpu-spike"
FRAMEWORK=${NUPP_SDL_FRAMEWORK_ROOT:?set NUPP_SDL_FRAMEWORK_ROOT to the SDL3 framework directory}

./bin/nupp build
(
    cd "$BENCH"
    NUPP_SDL_FRAMEWORK_ROOT="$FRAMEWORK" "$ROOT/bin/nupp" build --target typed
)

TYPED="$ROOT/$BENCH/build/typed"
LUA_PATH="$TYPED/?.lua;$TYPED/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_GPU_LIBRARY="$TYPED/lib/nupp_native"
export LUA_PATH LUA_CPATH NUPP_GPU_LIBRARY

exec luajit "$BENCH/quantized-gemv.lua"
