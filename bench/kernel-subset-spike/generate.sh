#!/bin/sh
# Run the spike generator with the same compiler modules and providers as Nupp.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"

LUA_PATH="$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
export LUA_PATH LUA_CPATH

exec luajit "$SPIKE/generate.lua" "$@"
