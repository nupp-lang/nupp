#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"
OUT="$SPIKE/build"

# `kernel_compiler.lua` deliberately consumes Nupp's real parser rather than a
# second grammar, so ensure the development compiler modules are available.
"$ROOT/bin/nupp" build
"$ROOT/bin/nupp" check "$SPIKE/kernels.nupp"

mkdir -p "$OUT"
luajit "$SPIKE/generate.lua" "$SPIKE/kernels.nupp" "$OUT"

case $(uname -s) in
    Darwin)
        LIB="$OUT/libkernel_subset_spike.dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        LIB="$OUT/libkernel_subset_spike.so"
        SHARED_FLAGS="-shared"
        ;;
    *)
        echo "kernel-subset-spike: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

TARGET_FLAGS=
if [ "$(uname -m)" = "x86_64" ]; then
    TARGET_FLAGS="-march=x86-64"
fi

clang -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -fPIC $TARGET_FLAGS $SHARED_FLAGS \
    "$OUT/kernel.c" -o "$LIB"
ln -sf "$(basename "$LIB")" "$OUT/libkernel_subset_spike"

# The binding is generated from the same verified IR as the C signature. Build
# it with the ordinary span module so the benchmark enters through Nupp's
# checked one-call wrapper rather than a handwritten FFI facade.
"$ROOT/bin/nupp" check "$OUT/checked.nupp"
"$ROOT/bin/nupp" build -O2 -o "$OUT/nupp" "$OUT/checked.nupp"
mkdir -p "$OUT/nupp/nupp"
"$ROOT/bin/nupp" build -O2 -o "$OUT/nupp/nupp" "$ROOT/src/nupp/span.nupp"

# Keep the ordinary Lua lowering of the exact annotated source as the semantic
# oracle. The custom annotation erases, so this is also the fallback obtained
# by removing the native-compilation requirement.
"$ROOT/bin/nupp" build -O2 -o "$OUT/fallback" "$SPIKE/kernels.nupp"
mkdir -p "$OUT/fallback/nupp"
"$ROOT/bin/nupp" build -O2 -o "$OUT/fallback/nupp" "$ROOT/src/nupp/span.nupp"

echo "$LIB"
