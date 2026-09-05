#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
out=build/portable-storage-io
./bin/nupp build -O1 -o "$out" src/nupp/io/init.nupp src/nupp/compiler/runtime/math.nupp
luajit_prefix=$(./scripts/toolchain luajit)
"$luajit_prefix/bin/luajit" bench/portable-storage-io/native.lua "$out/src"
