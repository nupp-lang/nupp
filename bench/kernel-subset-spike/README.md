# Checked `@kernel` subset spike

This spike tests a whole-function annotation as the public face of the existing
width-polymorphic SIMD mechanism. The source in [`kernels.nupp`](kernels.nupp)
is ordinary, type-checked Nupp:

```nupp
@kernel
local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows left: span.Span<float>,
    borrows right: span.Span<float>,
    scale: float
): nil
    if output.count ~= left.count or output.count ~= right.count then
        error("length mismatch", 2)
    end

    for i = 1, output.count do
        output:set(i, left:get(i) + right:get(i) * scale)
    end
end
```

`@kernel` is a test-only custom annotation here. The production design document
currently reserves the name `@native`; this spike uses the spelling under
discussion without changing the public language.

## Build and run

From the repository root:

```sh
bench/kernel-subset-spike/build.sh
luajit bench/kernel-subset-spike/test.lua
luajit bench/kernel-subset-spike/main.lua
```

The build writes ignored artifacts under `bench/kernel-subset-spike/build`:

- `kernel.ir`, the deterministic verified native IR;
- `kernel.c`, private scalar, NEON, SSE2, and AVX2 implementations;
- `checked.nupp`, a generated `countedBy` declaration;
- `nupp/checked.lua`, Nupp's checked one-call span wrapper; and
- `fallback/kernels.lua`, the ordinary Lua lowering of the exact source.

`KERNEL_SPIKE_ELEMENTS` controls approximately how many elements each timing
row processes. Correctness covers counts zero through 33 and 257 first, along
with the checked wrapper's unequal-length failure. The larger case includes
deterministic random mantissas as well as signed zero, subnormals, infinities,
and NaNs, and compares result bits rather than Lua numeric equality.

## Admitted subset

The spike consumes Nupp's real lossless syntax tree after the ordinary Nupp
checker accepts the source. Its separate kernel validator currently admits:

- one local, non-generic, non-variadic `@kernel` function per compilation unit;
- one `exclusive span.WriteSpan<float>` output;
- one or more borrowed `span.Span<float>` inputs;
- uniform `float` parameters and a `nil` result;
- a complete input/output length guard;
- one one-based numeric loop over `output.count`;
- one `output:set(i, expression)` operation per iteration; and
- `+`, `-`, `*`, `/`, literals, uniforms, and `input:get(i)` in that expression.

It rejects unsupported parameter types, allocation, arbitrary calls, offset
loads, missing guards, other loop forms, captures, varargs, and extra statements
with a source-local diagnostic. [`test.lua`](test.lua) checks representative
rejections and byte-identical IR, C, and binding generation. Rejection is the
contract: an annotated function never silently falls back to ordinary Lua.
Removing the annotation explicitly selects the ordinary implementation.

The resulting IR names every span root, count relationship, load index,
mutability, scalar type, conversion, operation, region, alias relationship, and
source site. It records the output's exclusive borrow as disjoint from every
input and records shared inputs as potentially aliasing each other. A verifier
requires a complete relationship for every region pair before either backend
sees the IR. There is no raw pointer, unchecked address operation, arbitrary
call, Lua value, or embedded C in the admitted source.

The C emitter uses that proof narrowly: only the output pointer is `restrict`.
The readable inputs are not restricted because two shared spans may legally
alias. The generated `cdef` spells every physical counted pointer `borrows`
because those projections live only for the call; the source-level mutable
pointer still becomes a `WriteSpan` and must arrive through an exclusive borrow.
The verified region facts are what transport that source proof into native IR.

## Execution model

The IR is rendered into forced-scalar, compiler-auto-vectorized, explicit NEON,
explicit SSE2, and explicit AVX2 implementations. Host selection is cached
process-wide. Every explicit vector implementation uses the scalar expression
for its tail, and no vector value crosses the Lua/native ABI.

Ordinary Nupp does not evaluate this expression in binary32. A value loaded
from a `float` slot widens to Lua's binary64 `number`, function annotations
erase at runtime, arithmetic rounds as binary64, and `WriteSpan<float>:set`
narrows once at the store. The first spike incorrectly labeled every operation
`f32`; its exact-valued test data hid the difference. This version makes the
conversions load-bearing in IR: `f32 -> f64`, binary64 arithmetic, then
`f64 -> f32`. Consequently NEON and SSE2 evaluate two source elements per
explicit vector and AVX2 evaluates four. Choosing binary32-per-operation
semantics would require a separate ordinary-language contract, not an
`@kernel` optimization rule.

The generated Nupp declaration turns the private pointer/count signature back
into the source-level `WriteSpan<float>` and `Span<float>` parameters. Its Lua
wrapper checks equal lengths, projects the spans, and makes one physical call.
It contains no element loop.

Clang is built with contraction and fast math disabled. On ARM64, decoded code
contains explicit float-to-double conversions, separate `fmul.2d` and
`fadd.2d`, and a final double-to-float conversion. The auto-vectorized row is
generated from the same loop without the disabling pragma, while the
forced-scalar row deliberately disables vectorization and interleaving. This
makes the baseline honest about what explicit intrinsics add beyond optimized
C generated from the same verified facts.

## Representative result

An ARM64 development run selected two-lane explicit NEON. It established the
important comparison: Clang's auto-vectorized C was faster than the simple
compositional intrinsic lowering on medium and large rows. The benchmark prints
all five paths so later results cannot describe a speedup over deliberately
de-vectorized C as a speedup over optimized C. Numbers are intentionally not
frozen here; this is a compiler seam and correctness experiment, not a stable
performance claim.

## What this does not prove

This is not a production annotation or a general native compiler. The subset
recognizes one map-loop form, generated C and Clang remain the backend, and only
the ARM64 implementation executes locally. The x86 implementations are
cross-compiled and decoded, not run. A differently named single function is
representable and receives a derived private symbol, but several functions in
one compilation unit remain an explicit subset rejection.

For this experiment, writing a kernel makes Clang a build dependency. Projects
without a kernel do not probe for or require Clang. A production release must
either ship a pinned toolchain, consume validated prebuilt target artifacts, or
select a direct emitter before it can promise an offline zero-setup build.

The validator is a spike beside the compiler rather than a semantic compiler
pass. A production implementation would consume checked types and effects
directly, reserve diagnostics, model several control-flow blocks and failures,
cache native IR, validate artifacts, and integrate inspection and source maps.

The result does establish the architectural seam: a restricted ordinary Nupp
function can lower into a small safety-verifiable IR, reuse the portable SIMD
backend, retain ordinary fallback semantics, and enter native code through one
checked span call.
