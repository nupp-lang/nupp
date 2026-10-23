---
order: 0
layout: home
---

<!-- nupp:hero -->

# Nupp

A statically typed Lua dialect with its own VM.

Nupp adds checked types, resource contracts, concurrency, and a complete project
toolchain to Lua's modules and control flow, and runs the result on the Nupp
VM.

[Get started](getting-started/index.md)

![A nuppeppo in a moonlit forest](images/nupp.png)

<!-- /nupp:hero -->

---

<!-- nupp:features -->

## Checked Lua

`.nupp` source is checked, and plain `.lua` files sit beside it under one
module resolver. Records, structs, interfaces, unions, refinements, generics, and
narrowing add contracts where a module needs them.

```nupp
local record Point
    x: number
    y: number
end

local function scale(point: Point, factor: number): Point
    return new Point(x = point.x * factor, y = point.y * factor)
end
```

Compiler diagnostics carry stable codes, source spans, related locations,
repair help, and structured fixes. See the [language
tour](getting-started/tour.md) and [type
system](learn/language/types/index.md).

## Resources and foreign code

Affine ownership records a cleanup obligation in the type. Borrowing, pinning,
and exact scopes make C pointer lifetimes and deterministic cleanup visible to
the checker.

```nupp
local function consume(borrows file: LuaFile): string
    return file:read("*a")
end

do
    local report = assert(io.open("report.txt", "r"))
    print(consume(report))
end
```

C headers import as checked declarations, and a Rust application can embed the
VM and the modules it runs. See [ownership](learn/runtime/ownership/index.md),
[C interop](learn/runtime/c-interop/index.md), and
[native modules](learn/projects/native-modules.md).

## Waiting and parallel work

Suspension-aware functions keep ordinary call syntax and return types. A call
blocks without a scheduler and parks its coroutine under a host handler.
Structured task scopes and worker pools compose concurrent work at different
isolation boundaries.

```nupp
local tasks = nupp.tasks
local time = nupp.time

local function waitFor(results: {number}, index: integer, milliseconds: number): nil
    time.sleep(milliseconds)
    results[index] = milliseconds
end

local results: {number} = {}
with scope = tasks.open() do
    scope:spawn(results, 1, 20, waitFor)
    scope:spawn(results, 2, 10, waitFor)
end

print(results[1], results[2])
```

See [suspension](learn/runtime/concurrency/suspension.md),
[task scopes](learn/runtime/concurrency/task-scopes.md), and
[workers](learn/runtime/concurrency/workers.md).

## Comptime and data

Comptime functions inspect and construct types, and `comptime do` evaluates
ordinary Nupp during compilation. Reflection and derives turn those facts into
checked serializers, layouts, and generated declarations.

```nupp
@comptime
local function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = "ready"
```

The standard library includes files, networking, TLS, HTTP, processes, JSON,
hashes, parsing, and memory spans. See
[comptime](learn/language/comptime.md), [serde](learn/runtime/data/serde.md),
and the [standard library](learn/runtime/data/standard-library.md).

## Kernels and SIMD

`@aot` holds a function to a checked subset with stable numeric meaning, and
`nupp.simd` writes a loop in CPU vector lanes with its species, masks, and tail
stated. `target = "gpu"` checks a function as a typed resident-buffer kernel;
the VM has no GPU provider yet, so no device runs one.

```nupp
local span = require("nupp.mem.span")

@aot
local function double(exclusive values: span.WriteSpan<float>): nil
    for index = 1, #values do
        values[index] = values[index] * 2.0
    end
end
```

See [ahead-of-time compilation](learn/performance/ahead-of-time/index.md),
[SIMD programming](learn/performance/ahead-of-time/simd-programming.md),
and
[GPU compute](learn/performance/ahead-of-time/gpu.md).

## Libraries and binaries

A library is its source, and building it checks its modules. A program builds
to one executable: its image stamped onto the VM runtime for the machine
building it.

```lua [nupp.lua]
return {
   include = {"src"},
}
```

See [project builds](learn/projects/build.md) and
[portable libraries](learn/projects/portability/libraries.md).

## Language-aware tools

The checker, builder, test runner, formatter, language server, documentation
generator, profiler, coverage tool, migration tools, and compiler inspectors
ship in one executable.

```text
nupp check                 # check the configured source graph
nupp fmt --write           # format project source
nupp test                  # build and run project tests
nupp build                 # build the default deliverable
nupp explain NUPP2119      # expand one diagnostic
nupp reference --for CODE  # print the relevant language section
```

See [tooling](learn/tooling/index.md) for the guided map and
[CLI reference](reference/cli.md) for exact command options.

<!-- /nupp:features -->

::: columns

## Start here

- [Getting started](getting-started/index.md)
- [Tour of Nupp](getting-started/tour.md)
- [Feature map](getting-started/features.md)
- [Why use Nupp](getting-started/why.md)
- [Installation](getting-started/installation.md)

## Learn

- [Language syntax](learn/language/syntax.md)
- [Type system](learn/language/types/index.md)
- [Ownership](learn/runtime/ownership/index.md)
- [Concurrency](learn/runtime/concurrency/suspension.md)
- [Performance](learn/performance/index.md)
- [Project builds](learn/projects/build.md)
- [Tooling](learn/tooling/index.md)

## Reference

- [CLI](reference/cli.md)
- [Annotations](reference/annotations.md)
- [Derives](reference/derives.md)
- [Diagnostics](reference/diagnostics.md)
- [Lints](reference/lints.md)
- [Grammar](reference/grammar.md)
- [Distribution](reference/distribution.md)

:::
