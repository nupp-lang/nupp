#!/bin/sh
# Builds this tree's fused JSON decoder ahead of time and measures it against
# Lunajson. An optional argument sets the sample count.
set -eu

cd "$(dirname "$0")"
./prepare.sh
../../bin/nupp build --target fused-json --out-dir build

LUA_PATH='build/?.lua;build/?/init.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit tests/bench.lua "$@"
