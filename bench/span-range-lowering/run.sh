#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

bench/span-range-lowering/build.sh
LUAJIT_PREFIX=$(./scripts/toolchain luajit)
"$LUAJIT_PREFIX/bin/luajit" bench/span-range-lowering/main.lua
"$LUAJIT_PREFIX/bin/luajit" bench/span-range-lowering/matrix.lua
"$LUAJIT_PREFIX/bin/luajit" bench/span-range-lowering/sinking.lua
"$LUAJIT_PREFIX/bin/luajit" bench/span-range-lowering/roots.lua
