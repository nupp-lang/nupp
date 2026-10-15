#!/bin/sh
set -eu
cd "$(dirname "$0")"
../../../bin/nupp build --target paths-scalar --output build/scalar
ROCKS='../../../.rocks/share/lua/5.1/?.lua;../../../.rocks/share/lua/5.1/?/init.lua;;'
LUA_PATH="build/scalar/?.lua;build/scalar/?/init.lua;$ROCKS" LUA_CPATH='../../../.rocks/lib/lua/5.1/?.so;;' luajit tests/run.lua ../evidence/paths-corpus.tsv luajit
LUA_PATH="build/scalar/?.lua;build/scalar/?/init.lua;$ROCKS" LUA_CPATH='../../../.rocks/lib/lua/5.1/?.so;;' luajit -joff tests/run.lua ../evidence/paths-corpus.tsv luajit-interp
