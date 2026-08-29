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
#
# NUPP_CHECK_COMPILE_ONLY=1 stops after producing the executable. That covers a
# tier CI can compile but its runners cannot execute, which is the case for the
# 64-byte AVX-512 gang.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"
SPIKE="bench/kernel-subset-spike"
OUT="$SPIKE/build/crosscheck"
KERNELS=${NUPP_CHECK_KERNELS:-"mandelbrot mandelbrot_f32 tecsbits mixedwidth mixedwidth_f32 mixedwidth_f64 uniform uniformcall twokernels"}

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

# The default exercises AVX2's 32-byte gangs on x86-64 and NEON's shapes on
# arm64. Baseline and AVX-512 runs select their gang and compiler flags
# explicitly below; keeping those two choices separate is what lets this script
# expose a mismatch as `-Wpsabi` under `-Werror`.
case $ARCH in
    x86_64|amd64) DEFAULT_CFLAGS="-mavx2" ;;
    *) DEFAULT_CFLAGS="" ;;
esac

# Which gang the backend picks, as opposed to which instructions the C is
# compiled for. The two are separate on purpose: the generated C names vector
# widths and nothing else target-specific, so a 16-byte gang chosen for x86-64
# without AVX compiles and runs anywhere with a 16-byte register class -- which
# is every machine this runs on. That is what lets one host check both widths.
#
# The default keeps the two in step: where the C is compiled with -mavx2, the
# gang is chosen for a tier that has 32-byte registers, because a run whose gang
# and whose flags disagreed would be checking neither combination.
GANG_TARGET=${NUPP_CHECK_GANG_TARGET:-}
case $ARCH in
    x86_64|amd64) DEFAULT_GANG_FEATURES="avx2" ;;
    *) DEFAULT_GANG_FEATURES="" ;;
esac
GANG_FEATURES=${NUPP_CHECK_GANG_FEATURES-$DEFAULT_GANG_FEATURES}
GANG_FLAGS=""
if [ -n "$GANG_TARGET" ]; then
    GANG_FLAGS="--target $GANG_TARGET"
fi
if [ -n "$GANG_FEATURES" ]; then
    GANG_FLAGS="$GANG_FLAGS --features $GANG_FEATURES"
fi

# Windows will not execute a file without the extension, and its C runtime keeps
# the math functions in the CRT rather than in a separate library to link.
EXE=""
MATH="-lm"
case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*)
        EXE=".exe"
        MATH=""
        ;;
esac

./bin/nupp build
mkdir -p "$OUT"

status=0
for kernel in $KERNELS; do
    ./bin/nupp aot --emit c $GANG_FLAGS "$SPIKE/$kernel.nupp" > "$OUT/$kernel.c"
    # -Werror because the generated C is meant to be warning-clean on every
    # target it claims, not only the one it was written on.
    $CC -std=c11 -O2 -ffp-contract=off -fno-fast-math \
        -Wall -Wextra -Werror $DIALECT \
        $TARGET_FLAGS ${NUPP_CHECK_CFLAGS:-$DEFAULT_CFLAGS} -DKERNEL_C="\"$ROOT/$OUT/$kernel.c\"" \
        -DKERNEL_NAME="\"$kernel\"" \
        "$SPIKE/checks/$kernel.c" $MATH -o "$OUT/$kernel$EXE"
    if [ "${NUPP_CHECK_COMPILE_ONLY:-}" = "1" ]; then
        :
    elif ${NUPP_CHECK_RUNNER:-} "$OUT/$kernel$EXE"; then
        :
    else
        status=1
    fi
done

exit $status
