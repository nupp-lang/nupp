#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
BENCH="bench/wgpu-spike"
LUAJIT=$("$ROOT/scripts/toolchain" luajit)/bin/luajit

./bin/nupp build
(
    cd "$BENCH"
    "$ROOT/bin/nupp" build --target typed
)

TYPED="$ROOT/$BENCH/build/typed"
LUA_PATH="$TYPED/?.lua;$TYPED/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_NATIVE_V2_LIBRARY="$TYPED/lib/nupp_native_v2"
export LUA_PATH LUA_CPATH NUPP_NATIVE_V2_LIBRARY

exec "$LUAJIT" "$BENCH/tiled-gemm-api.lua"
