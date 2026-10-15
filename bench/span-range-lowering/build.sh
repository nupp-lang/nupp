#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

OUT=bench/span-range-lowering/build
mkdir -p "$OUT/disabled" "$OUT/enabled" "$OUT/runtime/nupp"
./bin/nupp build -O1 -Zno-opt=OPT-6 -o "$OUT/disabled" \
    bench/span-range-lowering/kernel.nupp bench/span-range-lowering/matrix.nupp
./bin/nupp build -O1 -o "$OUT/enabled" \
    bench/span-range-lowering/kernel.nupp bench/span-range-lowering/matrix.nupp

# Ad-hoc builds now preserve source-relative paths and carry dependencies.
# Stage the runner's existing artifact layout from that complete closure.
for mode in disabled enabled; do
    cp "$OUT/$mode/bench/span-range-lowering/kernel.lua" "$OUT/$mode/kernel.lua"
    cp "$OUT/$mode/bench/span-range-lowering/matrix.lua" "$OUT/$mode/matrix.lua"
done
cp -R "$OUT/enabled/src/nupp/." "$OUT/runtime/nupp/"
