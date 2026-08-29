#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
first=$(mktemp -d "${TMPDIR:-/tmp}/nupp-counted-a.XXXXXX")
second=$(mktemp -d "${TMPDIR:-/tmp}/nupp-counted-b.XXXXXX")
trap 'rm -rf "$first" "$second"' EXIT HUP INT TERM

cd "$root"
for output in "$first" "$second"; do
    ./bin/nupp build -O2 -o "$output" bench/kernel-spike/checked.nupp
    mkdir -p "$output/nupp/mem"
    ./bin/nupp build -O2 -o "$output/nupp/mem" src/nupp/mem/span.nupp
    NUPP_GATE_BUILD="$output" luajit bench/kernel-spike/performance-gate.lua
done
