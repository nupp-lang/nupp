#!/bin/sh
# The kernels in bench/llvm-gate/kernels built twice by LLVM, one tier at a
# time -- with every proved fact and with the base selection -- checked bit for
# bit and timed interleaved in one process by compare.lua.
#
#   bench/llvm-gate/kernels.sh "TIER..." [ROUNDS]
#
# e.g. `kernels.sh "baseline avx2"` on x86-64, or `kernels.sh neon` on Apple
# arm64. GATE_BASE_FACTS is the base build's NUPP_AOT_FACTS (default `none`).
set -eu

cd "$(dirname "$0")/kernels"
ROOT=$(cd ../../.. && pwd)
TIERS=${1:-neon}
ROUNDS=${2:-15}
BASE=${GATE_BASE_FACTS:-none}
case "$(uname -s)" in
    Darwin) EXT=dylib ;;
    *) EXT=so ;;
esac

for tier in $TIERS; do
    "$ROOT/bin/nupp" build --target "$tier" --out-dir "build/llvm-$tier" >/dev/null
    NUPP_AOT_FACTS=$BASE "$ROOT/bin/nupp" build --target "$tier" --out-dir "build/base-$tier" >/dev/null
    printf '\n## %s: every fact against facts=%s\n\n' "$tier" "$BASE"
    luajit ../compare.lua "build/base-$tier/lib/lib${tier}_aot.$EXT" "build/llvm-$tier/lib/lib${tier}_aot.$EXT" \
        "build/llvm-$tier/aot/src/kernels.$tier.ll" "$ROUNDS"
done
