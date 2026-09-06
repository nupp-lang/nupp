#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

OUT=build/bench/events
./bin/nupp build -O2 -q -o "$OUT" bench/events/candidate.nupp
LUAJIT_PREFIX=$(./scripts/toolchain luajit)
"$LUAJIT_PREFIX/bin/luajit" bench/events/run.lua "$OUT" "$@"
