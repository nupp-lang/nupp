#!/bin/sh
set -eu

# Run from the repository root. This checks object emission, static linking,
# image binding, the collector's compiled roots, and the interpreter oracle.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
image=native/crates/vm/jit.image
binary=build/rust/target/debug/nupp-vm

cargo build -q -p nupp-vm --features aot --offline
"$binary" aot "$image" "$tmp/jit.o"
NUPP_AOT_OBJECT="$tmp/jit.o" cargo build -q -p nupp-vm --features aot --offline

aot=$("$binary" run "$image" nupp.bench.jitbench run | head -1)
interp=$(NO_AOT=1 NO_JIT=1 "$binary" run "$image" nupp.bench.jitbench run | head -1)
test "$aot" = "$interp"
GC_STRESS=1 GC_ORACLE=1 "$binary" run "$image" nupp.bench.jitbench run >/dev/null

cp "$image" "$tmp/mismatch.image"
printf '\n' >> "$tmp/mismatch.image"
if "$binary" run "$tmp/mismatch.image" nupp.bench.jitbench run >"$tmp/mismatch.out" 2>&1; then
    echo 'AOT accepted a different image' >&2
    exit 1
fi
grep -q 'aot: linked object was built for another image' "$tmp/mismatch.out"
echo 'AOT smoke passed'
