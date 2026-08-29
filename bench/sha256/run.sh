#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target sha256 --out-dir build/aot
../../bin/nupp build --target sha256-scalar --out-dir build/scalar

LUA_PATH='build/aot/?.lua;build/aot/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua "$@"
