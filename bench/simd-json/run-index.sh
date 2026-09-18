#!/bin/sh
# Builds the structural indexer alone and holds it to its byte-at-a-time
# reference. `--time` adds a timing run.
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target simd-json-index --out-dir build/index

LUA_PATH='build/index/?.lua;build/index/?/init.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/index.lua "$@"
