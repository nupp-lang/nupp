#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SPIKE="$ROOT/bench/kernel-subset-spike"
OUT="$SPIKE/build"
MODE=${NUPP_NATIVE_MODE:-require}

build_fallback() {
    "$ROOT/bin/nupp" build -O2 -o "$OUT/fallback" "$SPIKE/kernels.nupp"
    mkdir -p "$OUT/fallback/nupp"
    "$ROOT/bin/nupp" build -O2 -o "$OUT/fallback/nupp" "$ROOT/src/nupp/span.nupp"
}

# `kernel_compiler.lua` deliberately consumes Nupp's real parser rather than a
# second grammar, so ensure the development compiler modules are available.
"$ROOT/bin/nupp" build
"$ROOT/bin/nupp" check "$SPIKE/kernels.nupp"

mkdir -p "$OUT"
if [ "$MODE" = off ]; then
    build_fallback
    echo "kernel-subset-spike: AOT compilation disabled; ordinary Nupp built"
    exit 0
fi

case "$MODE" in
    require|emit-c|object) ;;
    *)
        echo "kernel-subset-spike: NUPP_NATIVE_MODE must be off, require, emit-c, or object" >&2
        exit 2
        ;;
esac

luajit "$SPIKE/generate.lua" "$SPIKE/kernels.nupp" "$OUT"

if [ "$MODE" = emit-c ]; then
    echo "$OUT/kernel.c"
    exit 0
fi

NATIVE_CC=${NUPP_NATIVE_CC:-clang}
NATIVE_CFLAGS=${NUPP_NATIVE_CFLAGS:-}
if [ "$MODE" = object ]; then
    # The caller selects a target compiler/sysroot. Nothing target-built is run.
    $NATIVE_CC -std=c11 -O3 -ffp-contract=off -fno-fast-math \
        -Wall -Wextra -Werror $NATIVE_CFLAGS -c "$OUT/kernel.c" -o "$OUT/kernel.o"
    echo "$OUT/kernel.o"
    exit 0
fi

case $(uname -s) in
    Darwin)
        LIB="$OUT/libkernel_subset_spike.dylib"
        SHARED_FLAGS="-dynamiclib"
        ;;
    Linux)
        LIB="$OUT/libkernel_subset_spike.so"
        SHARED_FLAGS="-shared"
        MATH_LIB="-lm"
        ;;
    *)
        echo "kernel-subset-spike: unsupported host $(uname -s)" >&2
        exit 2
        ;;
esac

MATH_LIB=${MATH_LIB:-}

TARGET_FLAGS=
if [ "$(uname -m)" = "x86_64" ]; then
    TARGET_FLAGS="-march=x86-64"
fi

$NATIVE_CC -std=c11 -O3 -ffp-contract=off -fno-fast-math \
    -Wall -Wextra -Werror -fPIC $NATIVE_CFLAGS $TARGET_FLAGS $SHARED_FLAGS \
    "$OUT/kernel.c" $MATH_LIB -o "$LIB"
ln -sf "$(basename "$LIB")" "$OUT/libkernel_subset_spike"

# The binding is generated from the same verified IR as the C signature. Build
# it with the ordinary span module so the benchmark enters through Nupp's
# checked one-call wrapper rather than a handwritten FFI facade.
"$ROOT/bin/nupp" check "$OUT/checked.nupp"
"$ROOT/bin/nupp" build -O2 -o "$OUT/nupp" "$OUT/checked.nupp"
mkdir -p "$OUT/nupp/nupp"
"$ROOT/bin/nupp" build -O2 -o "$OUT/nupp/nupp" "$ROOT/src/nupp/span.nupp"

# Keep the ordinary lowering of the exact annotated source as the semantic
# oracle and as the artifact selected by NUPP_NATIVE_MODE=off.
build_fallback

echo "$LIB"
