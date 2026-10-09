---
order: 632
---

# CPU kernels

An `@aot` CPU kernel keeps numeric and span data in a pointer-free native entry. Its loops lower to LLVM IR, which the code generator in `nupp` optimizes and compiles.

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

Use `aot = "require"` in a build target to compile it and replace this declaration with a checked native wrapper. With AOT off, the unchanged Nupp body runs.

## Inspecting a kernel

Run `nupp aot --emit ir FILE` for the admitted operations, `--emit llvm` for the LLVM IR it is compiled from, and `--emit asm --function NAME FILE` for the instructions the code generator emitted. `--triple` and `--features` select the triple and CPU tier being inspected, and any target can be inspected from any machine.

```bash
nupp aot --emit llvm bench/simd11/kernels.nupp
nupp aot --emit asm --function map --features neon bench/simd11/kernels.nupp
```

The human report says whether each function lowered to scalar code, explicit SIMD, or GPU invocations. The assembly is the record of the instructions that run.

## Bounds and ownership

A loop from one through a span's count proves its direct accesses are in bounds. If it writes a second span, an equality guard such as `assert(#output == #input)` relates the two counts. A zero-based append cursor must be guarded by `cursor < #output` before writing `output[cursor + 1]`, or by a bound on a span the leading guards hold no longer than `output`.

A guard offset by a literal proves the elements within it: `at + 2 < #source`, or equally `at + 3 <= #source`, admits `source[at + 1]` through `source[at + 3]`, so a byte triple is read through one cursor rather than one cursor per byte, and a whole-vector guard such as `at + 3 * s.lanes <= #source` admits the element reads within its width the same way. The guard may be written either way round, may be one conjunct of a loop or branch condition, and holds for the right operand of an `and` (or, negated, of an `or`). The comparison is computed exactly rather than wrapped at thirty-two bits, which is what makes the room believable, and the accesses under it carry no check of their own: an access one element past what the guard proves is refused when the kernel is compiled, naming the guard it would need.

```nupp:fragment
while at + 2 < #source and out + 3 < #output do
    local c0: uint32 = source[at + 1]
    local c1: uint32 = source[at + 2]
    local c2: uint32 = source[at + 3]
    output[out + 1] = c0
    output[out + 4] = c1 + c2
    at = at + 3
    out = out + 4
end
```

Spans become `noalias` pointers when ownership proves no written span aliases them. Shared reads may alias one another. The generated wrapper checks layout and bounds claims before calling the private native entry, and refuses a call whose written span overlaps another span (`native spans overlap`): the checker proves disjointness at typed call sites, and the wrapper holds a plain Lua or gradual caller to the same promise. The private entry does not carry Lua values.

Physical storage type and arithmetic type are separate. Reading a `float` field widens it to ordinary Nupp binary64 unless the source uses `nupp.math.f32` operations. The generated code preserves Nupp's strict floating-point contract unless the function explicitly asks for a documented `@relax` guarantee.

## Calls and helpers

A compiled entry called by another compiled entry of the same file calls that entry's own definition, which the code generator may inline. A small ordinary local helper may be inlined by the AOT compiler. Neither call form implicitly maps a scalar callee across vector lanes; code that requires SIMD writes vector operations in its own body.

An entry may return several numeric or boolean results through its private aggregate. `lua-builder` entries are a separate ABI for fresh tables and strings; they are not pointer kernels. GPU entries map invocations and have a different binding surface.

## Explicit SIMD

When vector execution matters, use [`nupp.simd`](simd.md) inside a block kernel. `simd.species` always answers a species, one lane wide where the tier has no vectors, and `species:over` strip-mines a span so the loop is written once; the lanes, the tail mask and any hand-written continuation are visible in the source, and the same LLVM IR and assembly inspection commands show their lowering. A forced-scalar twin remains available for explicit-SIMD conformance; it is not a performance baseline.

## Benchmarks

Compare complete exported functions, including guards, setup, tails, and reducer finalization. `bench/simd11` compares explicit SIMD kernels against their scalar forms with paired samples and archived artifacts.

High-arithmetic divergent kernels can benefit from explicit SIMD, but a wider logical species also waits for its slowest live lane. Streaming updates may be limited by memory traffic rather than arithmetic. Measure the actual target and tier before choosing a vector implementation.
