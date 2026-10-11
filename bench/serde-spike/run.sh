#!/bin/sh
set -eu

cd "$(dirname "$0")"

../../bin/nupp build --target serde-spike

LUA_PATH='build/?.lua;build/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='build/lib/lib?.dylib;build/lib/lib?.so;../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua

# The capacity limits every nupp command and host applies
# (src/nupp/tools/jitlimits.nupp). Under LuaJIT's defaults this benchmark
# flushes its traces, which made decode read 20% slower than it runs.
LUA_PATH='build/?.lua;build/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='build/lib/lib?.dylib;build/lib/lib?.so;../../.rocks/lib/lua/5.1/?.so;;' \
luajit -Omaxtrace=20000 -Omaxside=1000 -Osizemcode=16384 -Omaxmcode=16384 \
    benchmark.lua "$@"
