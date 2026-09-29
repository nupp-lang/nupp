#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target utf8 --output build/aot
../../bin/nupp build --target utf8-scalar --output build/scalar
(cd ../utf8simd && ../../bin/nupp build --output build)

LUA_PATH='../utf8simd/build/?.lua;../utf8simd/build/?/init.lua;build/aot/?.lua;build/aot/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua "$@"
