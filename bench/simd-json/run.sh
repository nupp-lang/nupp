#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target simd-json

LUA_PATH='build/?.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/run.lua
