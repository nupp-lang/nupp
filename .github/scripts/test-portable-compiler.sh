#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/nupp-browser-compiler
rm -rf "$work"
mkdir -p "$work"

cd "$root"
./scripts/prelude-image luajit
luajit_dir=$(./scripts/toolchain luajit)
"$luajit_dir/bin/luajit" tests/luajit-browser/prepare-compiler.lua \
  build/browser-luajit/nupp-compiler.lua "$work"

test -s "$work/compiler.ljbc"
test -s "$work/compiler-expected.json"
./bin/nupp build --strict -O1 \
  -o "$work/examples" editors/playground/src/examples/*.nupp

echo "LuaJIT browser compiler and homepage examples passed"
