#!/bin/sh
# Compiles the oracle handlers with clang -O2 for arm64 and prints each one's
# code, for comparison with what s0 selects for the same handler.
set -eu
HERE=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
OUT=${1:-"$HERE/../../build/codegen/oracle"}
mkdir -p "$OUT"
clang -O2 -c -arch arm64 "$HERE/handlers.c" -o "$OUT/handlers.o"
objdump -d --no-show-raw-insn "$OUT/handlers.o" > "$OUT/handlers.dis"
echo "$OUT/handlers.dis"
