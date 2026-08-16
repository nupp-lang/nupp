#!/bin/sh
# Compare the two generated C bodies of every kernel, on this target.
#
# The Lua differentials answer the semantic question -- does the generated code
# agree with ordinary Nupp -- and they need LuaJIT, a built compiler, and a
# shared library the host can load. This answers the architectural one, which is
# separate and had never been asked: the lane body is written in compiler vector
# extensions, and a select, a mask lane and a horizontal test are different
# instructions on NEON, SSE2 and AVX2.
#
# It needs nothing but a C compiler, so it runs on a second architecture without
# a LuaJIT for it -- cross-compiled and emulated locally, or natively in CI.
#
# NUPP_CHECK_TARGET cross-compiles, and NUPP_CHECK_RUNNER runs the result:
#
#   NUPP_CHECK_TARGET=x86_64-apple-macos11 NUPP_CHECK_RUNNER='arch -x86_64' \
#       bench/kernel-subset-spike/crosscheck.sh
#
# NUPP_CHECK_CFLAGS adds flags, which is how a feature tier is selected. A
# 32-byte vector is two SSE registers and one AVX2 register, so the two lower to
# different instruction sequences and both are worth running.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
OUT="$SPIKE/build/crosscheck"
KERNELS=${NUPP_CHECK_KERNELS:-"mandelbrot mandelbrot_f32 tecsbits mixedwidth uniform"}

# Clang for consistency with the sibling scripts, but nothing here needs it, and
# a machine that has a C compiler under another name can still answer the
# question. `-Wno-parentheses-equality` is Clang's, so it goes only to Clang.
CC=${NUPP_NATIVE_CC:-}
DIALECT=""
if [ -z "$CC" ]; then
    if command -v clang >/dev/null 2>&1; then CC=clang; else CC=cc; fi
fi
case $($CC --version 2>&1 | head -1) in
    *clang*) DIALECT="-Wno-parentheses-equality" ;;
esac

TARGET_FLAGS=""
ARCH=$(uname -m)
if [ -n "${NUPP_CHECK_TARGET:-}" ]; then
    TARGET_FLAGS="-target $NUPP_CHECK_TARGET"
    ARCH=${NUPP_CHECK_TARGET%%-*}
fi

# A gang is 32 bytes. That is one AVX register on x86-64 and two NEON registers
# on arm64, so arm64 has nothing to select and x86-64 has to ask for AVX.
#
# Below AVX a 32-byte vector has no register class on x86-64: it still compiles,
# because the compiler splits it, but it has no stable ABI at a function
# boundary and says so. Rather than silence that, this targets the tier the gang
# shapes were designed for -- and a build that forces a lower one gets the
# warning, which is the honest answer, because no 16-byte gang exists yet.
case $ARCH in
    x86_64|amd64) DEFAULT_CFLAGS="-mavx2" ;;
    *) DEFAULT_CFLAGS="" ;;
esac

./bin/nupp build
mkdir -p "$OUT"

status=0
for kernel in $KERNELS; do
    ./bin/nupp aot --emit c "$SPIKE/$kernel.nupp" > "$OUT/$kernel.c"
    # -Werror because the generated C is meant to be warning-clean on every
    # target it claims, not only the one it was written on.
    $CC -std=c11 -O2 -ffp-contract=off -fno-fast-math \
        -Wall -Wextra -Werror $DIALECT \
        $TARGET_FLAGS ${NUPP_CHECK_CFLAGS:-$DEFAULT_CFLAGS} -DKERNEL_C="\"$ROOT/$OUT/$kernel.c\"" \
        "$SPIKE/checks/$kernel.c" -lm -o "$OUT/$kernel"
    if ${NUPP_CHECK_RUNNER:-} "$OUT/$kernel"; then
        :
    else
        status=1
    fi
done

exit $status
