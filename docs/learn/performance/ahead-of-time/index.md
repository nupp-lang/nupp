---
order: 630
---

# Ahead-of-time compilation

`@aot` marks a checked top-level local function as one that must stay inside
the subset ahead-of-time lowering can represent: no closures, dynamic or
optional calls, varargs, `goto`, constructor calls, owned scopes or `@unsafe`
constructs.
`target = "gpu"` makes it a typed resident-buffer kernel.

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end

print(clamp(5, 1, 3))
```

`nupp check` validates the target and the structural subset, so `@aot` on
something outside it is an error where it is written. A target's `aot` policy is
`off` by default; `require` also binds every `@aot(target = "gpu")` kernel. On
the VM a CPU `@aot` function is lowered with the rest of the program, so it runs
on the same runtime as its callers.

GPU entries replace the function with a checked `compile`, `bind`, and
`dispatch` surface; the VM has no GPU provider yet, so no device opens on it. A
loop that runs in CPU vector lanes states its species, masks, and tail through
`simd`.

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

The checker admits such a body as it admits any other `@aot` function. No
per-constant bodies are produced: the lowering that specialized them was
retired, and [NUPP2908](../../../reference/diagnostics.md), which capped them,
is no longer reported.

## Annotation guarantees

`@aot` promises stable numeric meaning.

The body's numeric meaning is pinned. Ordinary binary64 Nupp arithmetic is
neither contracted nor reassociated, so an AOT function's results are a property
of what was written rather than of the target that compiled it. Explicit
wrapping integer operations may be reassociated because their modular answer
does not depend on grouping. Ask for a relaxation per function with
[`@relax`](../../../api.md#annotation-relax).

## Next pages

See these pages for each part of the AOT pipeline.

- [SIMD programming](simd-programming.md) for lanes, masks, reducers, native
  helpers, and feature tiers, with runnable examples.
- [Numeric semantics](numeric-semantics.md) for arithmetic guarantees and
  verification.
- [GPU compute](gpu.md) for resident buffers and workgroup kernels.

::: seealso
- [performance.md](../index.md) for reading the bytecode ordinary Nupp lowers to
- [](binary.span) for the span types a kernel takes
:::
