#!/bin/sh
set -eu

# Run from the repository root after generating jit.image. Build-time code
# generation is allowed; the linked runtime must have no Cranelift dependency.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
image=native/crates/vm/jit.image
binary=build/rust/target/debug/nupp-vm

cargo build -q -p nupp-vm --features aot --offline
"$binary" aot "$image" "$tmp/jit.o"
NUPP_AOT_OBJECT="$tmp/jit.o" cargo build -q -p nupp-vm --no-default-features --features aot-linked --offline
cargo tree -p nupp-vm --no-default-features --features aot-linked --offline >"$tmp/deps"
if grep -q cranelift "$tmp/deps"; then
    echo 'no-JIT build still depends on Cranelift' >&2
    exit 1
fi
nm "$binary" >"$tmp/symbols"
if grep -q cranelift "$tmp/symbols"; then
    echo 'no-JIT binary still contains Cranelift symbols' >&2
    exit 1
fi

if [ "$(uname -s)" = Darwin ]; then
    cc -dynamiclib native/crates/vm/tests/deny-exec.c -o "$tmp/deny-exec.dylib"
    # Prove the harness rejects both executable mappings and W -> X changes.
    cc -x c -o "$tmp/probe" - <<'C'
#include <sys/mman.h>
#include <unistd.h>
int main(int argc, char **argv) {
    size_t size = (size_t)sysconf(_SC_PAGESIZE);
    void *p = mmap(0, size, argc == 1 ? PROT_READ | PROT_EXEC : PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANON, -1, 0);
    if (p == MAP_FAILED) return 1;
    if (argc > 1) mprotect(p, size, PROT_READ | PROT_EXEC);
    return 0;
}
C
    for mode in mapping protection; do
        status=0
        if [ "$mode" = mapping ]; then
            DYLD_INSERT_LIBRARIES="$tmp/deny-exec.dylib" "$tmp/probe" >"$tmp/probe.out" 2>&1 || status=$?
        else
            DYLD_INSERT_LIBRARIES="$tmp/deny-exec.dylib" "$tmp/probe" protect >"$tmp/probe.out" 2>&1 || status=$?
        fi
        test "$status" = 86
        grep -q 'no-JIT gate: executable memory requested' "$tmp/probe.out"
    done
    export DYLD_INSERT_LIBRARIES="$tmp/deny-exec.dylib"
else
    echo 'Executable-memory denial harness skipped: currently macOS only' >&2
fi

"$binary" run "$image" nupp.bench.jitbench run >"$tmp/aot.out"
NO_AOT=1 "$binary" run "$image" nupp.bench.jitbench run >"$tmp/interp.out"
test "$(head -1 "$tmp/aot.out")" = "$(head -1 "$tmp/interp.out")"
GC_STRESS=1 GC_ORACLE=1 "$binary" run "$image" nupp.bench.jitbench run >/dev/null
cp "$image" "$tmp/mismatch.image"
printf '\n' >> "$tmp/mismatch.image"
if "$binary" run "$tmp/mismatch.image" nupp.bench.jitbench run >"$tmp/mismatch.out" 2>&1; then
    echo 'AOT accepted a different image' >&2
    exit 1
fi
grep -q 'aot: linked object was built for another image' "$tmp/mismatch.out"
echo 'No-JIT smoke passed'
