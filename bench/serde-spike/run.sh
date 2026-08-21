#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target serde-spike

LUA_PATH='build/?.lua;build/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='build/lib/lib?.dylib;build/lib/lib?.so;../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua

LUA_PATH='build/?.lua;build/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='build/lib/lib?.dylib;build/lib/lib?.so;../../.rocks/lib/lua/5.1/?.so;;' \
luajit benchmark.lua "$@"
