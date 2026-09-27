#!/bin/sh
# Run the spike generator with the same compiler modules and providers as Nupp.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"

LUA_PATH="$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
export LUA_PATH LUA_CPATH
# LLVM compiles in process, through the development native library that
# carries the code generator.
NUPP_NATIVE_LIBRARY="${NUPP_NATIVE_LIBRARY:-$(ls "$ROOT"/build/lib/libnupp_native_dev.* | head -n 1)}"
export NUPP_NATIVE_LIBRARY

exec luajit "$SPIKE/generate.lua" "$@"
