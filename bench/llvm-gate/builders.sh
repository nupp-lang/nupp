#!/bin/sh
# Gate A2's comparison: the builder-mode workloads built by the C lowering and
# by LLVM, each measured by its own benchmark, alternating backends round by
# round so drift reaches both.
#
#   bench/llvm-gate/builders.sh [ROUNDS]
#
# sha256 and fused JSON report against a colocated control (C and Lunajson),
# so the figure compared is that ratio, which a busy machine moves less than a
# raw time.
set -eu

cd "$(dirname "$0")/../.."
ROOT=$(pwd)
ROUNDS=${1:-3}

build() {
    backend=$1
    (cd bench/sha256 && NUPP_AOT_BACKEND=$backend ../../bin/nupp build --target sha256 --out-dir "build/$backend" >/dev/null)
    (cd bench/fused-json && ./prepare.sh >/dev/null && NUPP_AOT_BACKEND=$backend ../../bin/nupp build --target fused-json --out-dir "build/$backend" >/dev/null)
}

build c
build llvm

sha256() {
    backend=$1
    (cd bench/sha256 && LUA_PATH="build/$backend/?.lua;build/$backend/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;;" \
        LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;;" luajit benchmark.lua 9)
}

fused() {
    backend=$1
    (cd bench/fused-json && LUA_PATH="build/$backend/?.lua;build/$backend/?/init.lua;$ROOT/build/?.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;;" \
        LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;;" luajit tests/bench.lua 9)
}

round=1
while [ "$round" -le "$ROUNDS" ]; do
    for backend in c llvm; do
        echo "== round $round sha256 $backend"
        sha256 "$backend"
        echo "== round $round fused-json $backend"
        fused "$backend"
    done
    round=$((round + 1))
done
