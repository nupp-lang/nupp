#!/bin/sh
# The builder-mode workloads built by LLVM, each measured by its own benchmark
# for several rounds so drift shows.
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
    (cd bench/sha256 && ../../bin/nupp build --target sha256 --out-dir "build/aot-$backend" >/dev/null)
    (cd bench/fused-json && ./prepare.sh >/dev/null && ../../bin/nupp build --target fused-json --out-dir "build/$backend" >/dev/null)
}

build llvm
(cd bench/sha256 && ../../bin/nupp build --target sha256-scalar --out-dir build/scalar >/dev/null)

# The benchmark reads `build/aot`, so that names the build measured.
sha256() {
    backend=$1
    (cd bench/sha256 && rm -rf build/aot && ln -s "aot-$backend" build/aot && \
        LUA_PATH="build/aot/?.lua;build/aot/?/init.lua;$ROOT/.rocks/share/lua/5.1/?.lua;;" \
        LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;;" luajit benchmark.lua 9)
}

fused() {
    backend=$1
    (cd bench/fused-json && LUA_PATH="build/$backend/?.lua;build/$backend/?/init.lua;$ROOT/build/?.lua;$ROOT/.rocks/share/lua/5.1/?.lua;$ROOT/.rocks/share/lua/5.1/?/init.lua;;" \
        LUA_CPATH="$ROOT/.rocks/lib/lua/5.1/?.so;;" luajit tests/bench.lua 9)
}

round=1
while [ "$round" -le "$ROUNDS" ]; do
    echo "== round $round sha256"
    sha256 llvm
    echo "== round $round fused-json"
    fused llvm
    round=$((round + 1))
done
