#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
. ./scripts/luajit.sh
select_luajit "$ROOT"
export NUPP_COMPILER_ROOT="$ROOT"
export LUA_PATH="$ROOT/build/?.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;;"
exec luajit bench/cross-module-facts/run.lua "$@"
