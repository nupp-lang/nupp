#!/bin/sh
# Run the spike generator with the same compiler modules and providers as Nupp.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"

case $(uname -s) in
    Darwin)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.dylib"
        ;;
    Linux)
        NATIVE="$ROOT/build/lib/libnupp_native_dev.so"
        ;;
    *) echo "AOT generator: unsupported host $(uname -s)" >&2; exit 2 ;;
esac

LUA_PATH="$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;${LUA_PATH:-;}"
LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;${LUA_CPATH:-;}"
NUPP_NATIVE_LIBRARY="$NATIVE"
export LUA_PATH LUA_CPATH NUPP_NATIVE_LIBRARY

exec luajit "$SPIKE/generate.lua" "$@"
