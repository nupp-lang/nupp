---
order: 630
---

# Ahead-of-time compilation

`@aot` lowers a checked top-level local function through verified IR before the
program runs. CPU entries produce native code or Wasm through LLVM, while
`target = "gpu"` produces a typed resident-buffer kernel and either a native
SPIR-V or browser WGSL artifact.

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end
```

`nupp check` validates the target and the structural subset, and for a target
whose policy compiles `@aot` code it lowers each function for every feature tier
the build selects, so `@aot` on something the backend could not compile is an
error rather than a surprise later. [Build policy](build-and-artifacts.md) selects what a build does with a
CPU result: `off` by default, and `require` to compile it into the project's
own shared library and call it. Browser
applications have corresponding
[`emit-wasm` and `require-wasm`](wasm.md) policies for pointer kernels and
Lua-building entries.

Pure numeric and span bodies keep the small `kernel` ABI, and a body that
constructs fresh Lua values uses the separate `lua-builder` ABI. GPU entries
replace the function with a checked `compile`, `bind`, and `dispatch` surface.
Nothing in the source names an ABI. A loop that runs in CPU vector lanes states
its species, masks, and tail through `simd`.

## Const-specialized families

An `@aot` function may use scalar `const` binders when checked direct calls
close their carrier parameters:

```nupp
@aot
local function doubled<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do answer = answer * 2.0 end
    return answer
end

local result = doubled(5.0, 3)
```

The build collects closed applications across the module graph, emits a private
native body per admitted body class, and removes the carrier from that private
ABI, which LLVM then folds and unrolls like any other constant. Checked
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

`@aot` promises ahead-of-time compilation and stable numeric meaning.

The body compiles once, ahead of time, with an optimizing compiler behind it.
LuaJIT is a tracing JIT: it compiles what it observes, it gives up on shapes it
cannot record, and a hot loop that aborts a trace runs interpreted however hot
it gets.

The body's numeric meaning is pinned. Ordinary binary64 Nupp arithmetic is
neither contracted nor reassociated, so an AOT function's results are a property
of what was written rather than of the target that compiled it. Explicit
wrapping integer operations may be reassociated because their modular answer
does not depend on grouping. Ask for a relaxation per function with
[`@relax`](../../../api.md#annotation-relax).

## Next pages

See these pages for each part of the AOT pipeline.

- [CPU kernels](cpu-kernels.md) for inspection, generated code, calls, and
  representative measurement.
- [Lua values](lua-values.md) for table and string construction through the
  VM-rooted builder ABI.
- [SIMD programming](simd-programming.md) for lanes, masks, reducers, native
  helpers, and feature tiers, with runnable examples.
- [Numeric semantics](numeric-semantics.md) for arithmetic guarantees and
  verification.
- [Builds and artifacts](build-and-artifacts.md) for policies, cross builds,
  caches, and shipping.
- [Wasm applications](wasm.md) for the browser guest and Wasm side modules.
- [GPU compute](gpu.md) for native resident buffers, workgroup kernels, and
  browser WebGPU.
