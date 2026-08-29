#!/bin/sh
# Builds the four implementations and runs the differential tests.
#
#     ./run.sh              tests only
#     ./run.sh --bench      tests, then the measurements
#     ./run.sh --bench 25   the same, over twenty-five paired samples
#
# Everything is built into `build/`, which is ignored. The two Nupp targets go
# to separate directories because they declare the same module name and only one
# of them can own it in a process.
set -eu

cd "$(dirname "$0")"

TERRA=$(./fetch.sh)

../../bin/nupp build --target terra-bench --out-dir build/aot
../../bin/nupp build --target terra-bench-scalar --out-dir build/scalar

mkdir -p build/terra
case "$(uname -s)" in
    Darwin) SUFFIX=dylib ;;
    *) SUFFIX=so ;;
esac
"$TERRA/bin/terra" terra/kernels.t "build/terra/libterrakernels.$SUFFIX" 2>&1 |
    grep -v 'single_module is obsolete' || true

LUAJIT=$(../../scripts/toolchain luajit)/bin/luajit
export LUA_PATH='build/aot/?.lua;build/aot/?/init.lua;;'

"$LUAJIT" tests/run.lua

if [ "${1:-}" = "--bench" ]; then
    shift
    "$LUAJIT" benchmark.lua "$@"
fi
