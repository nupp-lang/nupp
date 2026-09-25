#!/bin/sh
# Gates A1 and B: the kernels in bench/llvm-gate/kernels built by the C
# lowering with each C compiler named and by LLVM, one tier at a time, checked
# bit for bit and timed interleaved in one process by compare.lua.
#
#   bench/llvm-gate/kernels.sh "TIER..." "CC..." [ROUNDS]
#
# e.g. `kernels.sh "baseline avx2" "gcc clang"` on x86-64, or
# `kernels.sh neon clang` on Apple arm64.
set -eu

cd "$(dirname "$0")/kernels"
ROOT=$(cd ../../.. && pwd)
TIERS=${1:-neon}
COMPILERS=${2:-clang}
ROUNDS=${3:-15}
case "$(uname -s)" in
    Darwin) EXT=dylib ;;
    *) EXT=so ;;
esac

for tier in $TIERS; do
    NUPP_AOT_BACKEND=llvm "$ROOT/bin/nupp" build --target "$tier" --out-dir "build/llvm-$tier" >/dev/null
    for cc in $COMPILERS; do
        NUPP_AOT_BACKEND=c NUPP_AOT_CC=$cc "$ROOT/bin/nupp" build --target "$tier" --out-dir "build/$cc-$tier" >/dev/null
        printf '\n## %s: LLVM against the C lowering through %s\n\n' "$tier" "$cc"
        luajit ../compare.lua "build/$cc-$tier/lib/lib${tier}_aot.$EXT" "build/llvm-$tier/lib/lib${tier}_aot.$EXT" \
            "build/llvm-$tier/aot/src/kernels.$tier.ll" "$ROUNDS"
    done
done
