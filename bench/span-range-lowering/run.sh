#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

bench/span-range-lowering/build.sh
luajit bench/span-range-lowering/main.lua
luajit bench/span-range-lowering/matrix.lua
