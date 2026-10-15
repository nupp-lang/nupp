---
order: 630
---

# Ahead-of-time compilation

`@aot` lowers a checked top-level local function through verified IR before the
program runs. `target = "gpu"` produces a typed resident-buffer kernel and a
native SPIR-V artifact. A CPU `@aot` function is lowered by the VM, which runs
the same verified IR on its native tier.

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
the build selects, so `@aot` on something the backend could not lower is an
error rather than a surprise later. A target's `aot` policy selects what a
build does with it: `off` by default, and `require` to compile every
`@aot(target = "gpu")` kernel. Under `require` a CPU `@aot` function is refused:
its LuaJIT-era native code generator was removed.

GPU entries replace the function with a checked `compile`, `bind`, and
`dispatch` surface. A loop that runs in CPU vector lanes states its species,
masks, and tail through `nupp.simd`.

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

Lowering collects closed applications across the module graph and specializes a
private body per admitted body class. One module may lower eight logical const
body classes before target tiers multiply them. Calls with the same semantic
key deduplicate, and keys with the same proven body and ABI coalesce. Exceeding
the cap is an error that names its demanding call sites. With AOT off, the
generic Lua body remains available; at `-O1` and above it may still be
specialized by [`OPT-8`](../index.md#opt-8-const-monomorphization).

## Annotation guarantees

`@aot` promises ahead-of-time compilation and stable numeric meaning.

The body's numeric meaning is pinned. Ordinary binary64 Nupp arithmetic is
neither contracted nor reassociated, so an AOT function's results are a property
of what was written rather than of the target that compiled it. Explicit
wrapping integer operations may be reassociated because their modular answer
does not depend on grouping. Ask for a relaxation per function with
[`@relax`](../../../reference/annotations.md#relaxing-observable-guarantees).

::: deepdive Required compilation
The annotation is a contract over ordinary Nupp rather than a restricted
sublanguage: the body uses the same parser, type system, operators, and
diagnostics, so removing the annotation changes performance and artifacts but
never the source-level result. There is no silent per-function fallback, because
a contract that degrades quietly is a comment.

:::

## Next pages

See these pages for each part of the AOT pipeline.

- [SIMD programming](simd-programming.md) for lanes, masks, reducers, native
  helpers, and feature tiers, with runnable examples.
- [Numeric semantics](numeric-semantics.md) for arithmetic guarantees and
  verification.
- [GPU compute](gpu.md) for native resident buffers and workgroup kernels.

## FAQ

<a id="does-aot-change-what-a-function-answers"></a>

### Does `@aot` change what a function returns?

Only through `@relax`. Removing `@aot`, or building the same source under
`aot = "off"`, changes performance and artifacts and never the result.
`@relax` is the one annotation that changes the answer, and it says so per
function.

### How does a loop run in vector lanes?

By saying so with `nupp.simd`: a species, its vector loads and stores, masks,
and a tail. A loop without those operations is scalar. See
[simd-programming.md](simd-programming.md) for the model and vector operations.

::: seealso
- [performance.md](../index.md) for the rewrites applied to ordinary Nupp
- [](nupp.mem.span) for the span types a kernel takes
:::
