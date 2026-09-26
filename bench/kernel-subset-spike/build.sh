#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
OUT="$SPIKE/build"
MODE=${NUPP_NATIVE_MODE:-require}

build_fallback() {
    ./bin/nupp build -O2 -o "$OUT/fallback" "$SPIKE/kernels.nupp"
    mkdir -p "$OUT/fallback/nupp/mem"
    ./bin/nupp build -O2 -o "$OUT/fallback/nupp/mem" src/nupp/mem/span.nupp
}

# `kernel_compiler.lua` deliberately consumes Nupp's real parser rather than a
# second grammar, so ensure the development compiler modules are available.
./bin/nupp build
./bin/nupp check "$SPIKE/kernels.nupp"

mkdir -p "$OUT"
if [ "$MODE" = off ]; then
    build_fallback
    echo "kernel-subset-spike: AOT compilation disabled; ordinary Nupp built"
    exit 0
fi

case "$MODE" in
    require|emit-llvm|object) ;;
    *)
        echo "kernel-subset-spike: NUPP_NATIVE_MODE must be off, require, emit-llvm, or object" >&2
        exit 2
        ;;
esac

if [ "$MODE" != require ]; then
    "$SPIKE/generate.sh" "$SPIKE/kernels.nupp" "$OUT"
    if [ "$MODE" = emit-llvm ]; then
        echo "$OUT/kernel.ll"
    else
        echo "$OUT/kernel.o"
    fi
    exit 0
fi

case $(uname -s) in
    Darwin) LIB="$OUT/libkernel_subset_spike.dylib" ;;
    Linux) LIB="$OUT/libkernel_subset_spike.so" ;;
    *)
        echo "kernel-subset-spike: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

"$SPIKE/generate.sh" "$SPIKE/kernels.nupp" "$OUT" "$LIB"
ln -sf "$(basename "$LIB")" "$OUT/libkernel_subset_spike"

# The binding is generated from the same verified IR as the library. Build
# it with the ordinary span module so the benchmark enters through Nupp's
# checked one-call wrapper rather than a handwritten FFI facade.
./bin/nupp check "$OUT/checked.nupp"
./bin/nupp build -O2 -o "$OUT/nupp" "$OUT/checked.nupp"
mkdir -p "$OUT/nupp/nupp/mem"
./bin/nupp build -O2 -o "$OUT/nupp/nupp/mem" src/nupp/mem/span.nupp

# Keep the ordinary lowering of the exact annotated source as the semantic
# oracle and as the artifact selected by NUPP_NATIVE_MODE=off.
build_fallback

echo "$LIB"
