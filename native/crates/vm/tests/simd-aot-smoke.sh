#!/bin/sh
set -eu

# Compile the public-source image, then run it without a code generator or
# executable mappings. Keep evidence in the supplied output directory.
seed=$1
image=$2
output=$3
runner=native/crates/vm/tests/simd-smoke.py
if [ "${4:-}" = typed ]; then
    runner=native/crates/vm/tests/native-simd-smoke.py
fi
mkdir -p "$output"
output=$(cd "$output" && pwd)
binary=build/rust/target/release/nupp-vm
cargo build -q --release -p nupp-vm --features aot --offline
cp "$binary" "$output/nupp-vm-jit"
"$binary" aot "$image" "$output/simd.o" --frames >"$output/emission.log" 2>&1
NUPP_AOT_OBJECT="$output/simd.o" cargo build -q --release -p nupp-vm --no-default-features --features aot-linked --offline
cp "$binary" "$output/nupp-vm-aot"
cargo tree -p nupp-vm --no-default-features --features aot-linked --offline >"$output/dependencies.txt"
nm "$output/nupp-vm-aot" >"$output/symbols.txt"
if rg -q cranelift "$output/dependencies.txt" "$output/symbols.txt"; then
    echo 'SIMD AOT runtime contains Cranelift' >&2
    exit 1
fi
if [ "$(uname -s)" != Darwin ]; then
    echo 'Executable-memory denial currently requires macOS' >&2
    exit 1
fi
otool -tvV "$output/simd.o" >"$output/assembly.txt"
cc -dynamiclib native/crates/vm/tests/deny-exec.c -o "$output/deny-exec.dylib"
cc -x c -o "$output/probe" - <<'C'
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
        DYLD_INSERT_LIBRARIES="$output/deny-exec.dylib" "$output/probe" >"$output/probe-$mode.log" 2>&1 || status=$?
    else
        DYLD_INSERT_LIBRARIES="$output/deny-exec.dylib" "$output/probe" protect >"$output/probe-$mode.log" 2>&1 || status=$?
    fi
    test "$status" = 86
    rg -q 'no-JIT gate: executable memory requested' "$output/probe-$mode.log"
done
DYLD_INSERT_LIBRARIES="$output/deny-exec.dylib" python3 "$runner" "$seed" --binary "$output/nupp-vm-aot" --image "$image" --aot --output "$output"
