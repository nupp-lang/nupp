# GPU counted-loop conformance

Verified on 2026-09-19 with Apple M5 Pro, macOS 26.6 (25G72), Metal,
Rust 1.98.0, WGPU/Naga 30.0.1 and the workspace Cargo.lock. The durable
Cargo example was also run in release mode. These are untimed correctness checks.

`typed/counted.nupp` covers implicit-one-step loops with signed `int32`
bounds or exact signed-32-bit literals: evaluation once in source order,
statementful bounds, bound mutation in the body, assignment to the authored
loop variable, empty/reversed ranges, both signed extremes, nested loops,
`break`, and `continue`. It uses distinct local names because the existing AOT
profile refuses shadowing. Fractional, `uint32`, nested span-length and
out-of-range bounds, and all explicit steps, produce positioned refusals.

Both shader routes passed 15 cases and 3,855 checked output values. The native
binding is checked by `counted-api.lua` against ordinary Lua numeric loops;
the WGSL route uses the independent Rust integer oracle in
`native/crates/gpu/examples/counted_wgsl.rs`. Every one of the four SPIR-V
modules passed `spirv-val`, and every WGSL module passed Naga validation before
execution. `shader-hashes.json` identifies those validated shader bytes;
`validators.log`, `spirv-pass.log` and `wgsl-pass.log` preserve the results.

From the repository root, generate and check the WGSL route with:

```sh
mkdir -p /private/tmp/nupp-counted-wgsl
for kernel in literal boundaries snapshots control; do
    ./bin/nupp aot --emit wgsl --target wasm32-unknown-emscripten \
        --function "$kernel" bench/wgpu-spike/typed/counted.nupp \
        > "/private/tmp/nupp-counted-wgsl/$kernel.wgsl"
done
cargo run --locked -p nupp-native-gpu --example counted_wgsl -- \
    /private/tmp/nupp-counted-wgsl
```

The Linux/Vulkan and Windows/DX12 GPU conformance scripts now run both the
native binding oracle and this WGSL oracle. Their normal typed build supplies
the native binding and provider.

## Continuing-expression translation finding

The first device run returned 70 rather than 71 for input 3: the 64-iteration
loop ran only 63 times, followed by four unrolled increments. Both native
SPIR-V and WGSL routes showed this result. Their validation passed; changing
the expected answer would have hidden a real semantic failure.

`naga30-original.wgsl` preserves the valid failing shader, and
`naga30-original.msl` preserves Naga's translation. The relevant WGSL is:

```wgsl
continuing {
    let done = counter == last;
    if (!done) { counter = counter + 1; }
    break if done;
}
```

The MSL computes the saved comparison for the conditional increment, then
recomputes `counter == last` **after** incrementing for the final break. This
changes the answer. `wgsl-failure.log` and `spirv-failure.log` preserve the
first failures. `workspace-repro.log` confirms that the durable workspace-locked
example reproduces the same result. To reproduce after generating the four shaders above:

```sh
repro=$(mktemp -d)
cp /private/tmp/nupp-counted-wgsl/*.wgsl "$repro/"
cp bench/wgpu-spike/results/counted-loops/naga30-original.wgsl "$repro/literal.wgsl"
cargo run --locked -p nupp-native-gpu --example counted_wgsl -- "$repro"
# Expected on the recorded Metal/Naga version: assertion failure, 70 versus 71.
```

Both emitters now save completion into an explicit boolean variable declared
outside the loop continuation, then update the counter and branch on that
stored flag. This also preserves the last iteration at `INT32_MAX` without
increment overflow. The original WGSL remains here as a downstream compiler
reproducer; the completion flag should not be simplified back to a continuing
`let` without repeating the device differential.
