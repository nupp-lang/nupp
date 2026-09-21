---
order: 632
---

# CPU kernels

An `@aot` CPU kernel keeps numeric and span data in a pointer-free native entry. Its ordinary loops lower to scalar C, which the selected C compiler may optimize or vectorize.

```nupp
local span = require("nupp.mem.span")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    for i = 1, #input do
        output[i] = input[i] * factor
    end
end
```

Use `aot = "require"` in a build target to compile the C and replace this declaration with a checked native wrapper. With AOT off, the unchanged Nupp body runs.

## Inspecting a kernel

Run `nupp aot --emit ir FILE` for the admitted operations, `--emit c` for the translation unit, and `--emit asm --function NAME FILE` for the instructions the C compiler emitted. `--target` and `--features` select the triple and CPU tier being inspected.

```bash
nupp aot --emit c bench/simd11/kernels.nupp
nupp aot --emit asm --function map --features neon bench/simd11/kernels.nupp
```

The human report describes scalar, explicit SIMD, or GPU work that Nupp owns. A scalar loop in that report may still be vectorized downstream. Judge that by the assembly, not by the Nupp loop outcome.

## Bounds and ownership

A loop from one through a span's count proves its direct accesses are in bounds. If it writes a second span, an equality guard such as `assert(#output == #input)` relates the two counts. A zero-based append cursor must be guarded by `cursor < #output` before writing `output[cursor + 1]`.

Exclusive writable spans become `restrict` pointers in C when ownership proves they cannot alias other live inputs. Shared reads may alias one another. The generated wrapper checks layout and bounds claims before calling the private native entry; the private entry does not carry Lua values.

Physical storage type and arithmetic type are separate. Reading a `float` field widens it to ordinary Nupp binary64 unless the source uses `nupp.math.f32` operations. The generated C preserves Nupp's strict floating-point contract unless the function explicitly asks for a documented `@relax` guarantee.

## Calls and helpers

A compiled entry called by another compiled entry remains a real scalar call, with its own symbol and ABI. A small ordinary local helper may be inlined by the AOT compiler. Neither call form implicitly maps a scalar callee across vector lanes; code that requires SIMD writes vector operations in its own body.

An entry may return several numeric or boolean results through its private aggregate. `lua-builder` entries are a separate ABI for fresh tables and strings; they are not pointer kernels. GPU entries map invocations and have a different binding surface.

## Explicit SIMD

When vector execution matters, use [`nupp.simd`](vectorization.md) inside a block kernel. The vector loop, mask, tail, and scalar continuation are visible in the source, and the same C and assembly inspection commands show their lowering. A forced-scalar twin remains available for explicit-SIMD conformance; it is not a performance baseline.

## Benchmarks

Compare complete exported functions, including guards, setup, tails, and reducer finalization. The `bench/simd11` historical record compares the old required-loop route, ordinary optimized C, its no-vector control, and explicit SIMD with paired samples and archived artifacts. Its `@simd` results describe the revision measured; a current benchmark must use current source.

High-arithmetic divergent kernels can benefit from explicit SIMD, but a wider logical species also waits for its slowest live lane. Streaming updates may be limited by memory traffic and may already vectorize well in C. Measure the actual target and tier before choosing a vector implementation.
