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
row processes. Correctness always covers counts zero through 33 first, along
with the checked wrapper's unequal-length failure.

## Admitted subset

The spike consumes Nupp's real lossless syntax tree after the ordinary Nupp
checker accepts the source. Its separate kernel validator currently admits:

- one local, non-generic, non-variadic `@kernel` function;
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
rejections and byte-identical IR, C, and binding generation.

The resulting IR names every span root, count relationship, load index,
mutability, scalar type, operation, and source site. A verifier checks those
facts before either backend sees it. There is no raw pointer, unchecked address
operation, arbitrary call, Lua value, or embedded C in the admitted source.

## Execution model

The IR is rendered into scalar, four-lane NEON, four-lane SSE2, and eight-lane
AVX2 implementations. Host selection is cached process-wide. Every vector
implementation uses the scalar expression for its tail, and no vector value
crosses the Lua/native ABI.

The generated Nupp declaration turns the private pointer/count signature back
into the source-level `WriteSpan<float>` and `Span<float>` parameters. Its Lua
wrapper checks equal lengths, projects the spans, and makes one physical call.
It contains no element loop.

Clang is built with contraction and fast math disabled. On ARM64, decoded code
contains separate `fmul.4s` and `fadd.4s` operations; the x86 cross-build
contains separate SSE2 and AVX2 multiply/add operations and no FMA. That keeps
the scalar source's two-rounding expression rather than silently changing its
numeric meaning.

## Representative result

One longer ARM64 run with `KERNEL_SPIKE_ELEMENTS=64000000` selected four-lane
NEON and measured:

| Elements | Ordinary Nupp | Raw LuaJIT loop | Scalar C | Checked kernel SIMD |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 21.7 ns | 1.0 ns | 1.0 ns | 1.7 ns |
| 8 | 34.8 ns | 19.1 ns | 4.8 ns | 2.1 ns |
| 64 | 107.0 ns | 73.9 ns | 24.2 ns | 8.0 ns |
| 262,144 | 299.2 us | 219.5 us | 96.4 us | 30.9 us |

At one element, dispatch and the checked boundary lose to a direct scalar C
call. By eight elements the checked kernel is about 2.3 times faster than the
generated scalar function. On the large row it is about 3.1 times faster than
scalar C, 7.1 times faster than the raw LuaJIT loop, and 9.7 times faster than
ordinary Nupp span method calls.

## What this does not prove

This is not a production annotation or a general native compiler. The subset
recognizes one map-loop form, the IR has only `f32` expressions, generated C and
Clang remain the backend, and only the ARM64 implementation executes locally.
The x86 implementations are cross-compiled and decoded, not run.

The validator is a spike beside the compiler rather than a semantic compiler
pass. A production implementation would consume checked types and effects
directly, reserve diagnostics, model several control-flow blocks and failures,
cache native IR, validate artifacts, and integrate inspection and source maps.

The result does establish the architectural seam: a restricted ordinary Nupp
function can lower into a small safety-verifiable IR, reuse the portable SIMD
backend, retain ordinary fallback semantics, and enter native code through one
checked span call.
