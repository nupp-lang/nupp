---
order: 630
---

# Ahead-of-time compilation

`@aot` lowers a checked top-level local function through verified IR before the
program runs. CPU entries produce C or Wasm, while `target = "gpu"` produces a
typed resident-buffer kernel and either a native SPIR-V or browser WGSL artifact.

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end
```

`nupp check` validates the target and the structural subset, so `@aot` on
something the backend could not compile is an error rather than a surprise
later, and a check never needs a C compiler. [Build
policy](build-and-artifacts.md) selects what a build does with a
CPU result: `off` by default, `emit-c` to write C beside the build, and
`require` to compile it into the project's own shared library and call it. Lua
5.1 applications have corresponding
[`emit-wasm` and `require-wasm`](wasm.md) policies for pointer kernels and
Lua-building entries.

Pure numeric and span bodies keep the small `kernel` ABI, and a body that
constructs fresh Lua values uses the separate `lua-builder` ABI. GPU entries
replace the function with a checked `compile`, `bind`, and `dispatch` surface.
Nothing in the source names an ABI, a lane, a mask, or a vector width.

## Const-specialized families

An `@aot` function may use scalar `const` binders when checked direct calls
close their carrier parameters:

```nupp
@aot(vectorize = false)
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do answer = answer * 2.0 end
    return answer
end

local result = doubled(5.0, 3)
```

The build collects closed applications across the module graph, emits a private
native body per admitted body class, and removes the carrier from that private
ABI. Constant folding and bounded unrolling run before lane selection. Checked
same- and cross-module calls use the private entry; the public function value
dispatches tuples that were included in the deliverable and reports an unmatched
tuple instead of silently falling back from an AOT-required build.

One module may emit eight logical const body classes before target tiers
multiply them into physical entries. Calls with the same semantic key
deduplicate, and
keys with the same proven body and ABI coalesce. Exceeding the cap is a build
error for a required AOT family and names its demanding call sites. With AOT
off, the generic Lua body remains available; at `-O1` and above it may still be
specialized by [`OPT-8`](../index.md#opt-8-const-monomorphization).

## Annotation guarantees

`@aot` promises three properties.

The body compiles once, ahead of time, with an optimizing compiler behind it.
LuaJIT is a tracing JIT: it compiles what it observes, it gives up on shapes it
cannot record, and a hot loop that aborts a trace runs interpreted however hot
it gets.

The body's numeric meaning is pinned. Ordinary binary64 Nupp arithmetic is
neither contracted nor reassociated, so an AOT function's answers are a
property of what was written rather than of the target that compiled it.
Explicit wrapping integer operations may be reassociated because their modular
answer does not depend on grouping. Ask for a relaxation per function with
[`@relax`](../../../reference/annotations.md#relaxing-observable-guarantees).

And a body that is one map loop over spans may be lowered lane-parallel. That is
the largest single win where it applies, and the compiler decides whether it
applies.

::: deepdive
The annotation is a contract over ordinary Nupp rather than a restricted
sublanguage: the body uses the same parser, type system, operators, and
diagnostics, so removing the annotation changes performance and artifacts but
never the source-level result. There is no silent per-function fallback, because
a contract that degrades quietly is a comment.

See [NEP 9](../../../neps/0009-ahead-of-time-compilation.md) for more
information.
:::

## Next pages

Each page owns one part of the AOT pipeline.

- [CPU kernels](cpu-kernels.md) covers inspection, generated C, calls, and
  representative measurement.
- [Lua values](lua-values.md) covers table and string construction through the
  VM-rooted builder ABI.
- [Vectorization](vectorization.md) covers automatic lanes, explicit SIMD, and
  target feature tiers.
- [Numeric semantics](numeric-semantics.md) covers arithmetic guarantees and
  verification.
- [Builds and artifacts](build-and-artifacts.md) covers policies, cross builds,
  caches, and shipping.
- [Wasm applications](wasm.md) covers Lua 5.1 hosts and Wasm side modules.
- [GPU compute](gpu.md) covers native resident buffers, workgroup kernels, and
  browser WebGPU.

## FAQ

### Does `@aot` change what a function answers?

Only through `@relax`. Removing `@aot`, or building the same source under
`aot = "off"`, changes performance and artifacts and never the result, which is
what the differentials in
[Verification](numeric-semantics.md#verification) check. `@relax` is the one
annotation that changes the answer, and it says so per function.

### Why did my loop compile but run one iteration at a time?

Either the shape is outside what lane lowering admits, or the loop does too
little arithmetic per byte it touches to pay for assembling the vectors.
`nupp aot --check` exits 1 for the first case and names the construct; see
[Admitted loop shape](vectorization.md#admitted-loop-shape).

### Does a project need a C compiler?

Only under `aot = "require"`, `emit-wasm`, or `require-wasm`. `off` is the
default and `nupp check` never compiles C, so validating `@aot` source needs no
toolchain at all. See [Accepting a C
compiler](build-and-artifacts.md#accepting-a-c-compiler) and [Wasm AOT
applications](wasm.md).

::: seealso
- [jit-trace-checking.md](../jit-trace-checking.md) for deciding whether LuaJIT
  can compile the loop you were about to annotate
- [performance.md](../index.md) for the rewrites applied to ordinary Nupp
- [](nupp.mem.span) for the span types a kernel takes
- [NEP 9](../../../neps/0009-ahead-of-time-compilation.md) for the AOT design
  record
:::
