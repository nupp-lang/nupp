#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target base64 --out-dir build/aot
(cd ../base64simd && ../../bin/nupp build --target base64-simd --out-dir ../base64/build/simd)

LUA_PATH='build/aot/?.lua;build/aot/?/init.lua;build/simd/?.lua;build/simd/?/init.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua "$@"
