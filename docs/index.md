---
order: 0
layout: home
---

<!-- nupp:hero -->

# Nupp

LuaJIT with static guarantees.

Nupp adds checked types, resource contracts, concurrency, native compilation,
and a complete project toolchain while keeping ordinary Lua modules and control
flow.

[Get started](getting-started/index.md)
[Playground](/playground/)

![A nuppeppo in a moonlit forest](images/nupp.png)

<!-- /nupp:hero -->

---

```playground
```

---

<!-- nupp:features -->

## Checked Lua

`.lua`, `.g.nupp`, and `.nupp` provide plain, gradual, and strict source
boundaries. Records, structs, interfaces, unions, refinements, generics, and
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

C headers import as checked declarations, and component builds embed checked
modules in a C-owned process. See [ownership](learn/runtime/ownership/index.md),
[C interop](learn/runtime/c-interop/index.md), and
[embedding](learn/projects/embedding.md).

## Waiting and parallel work

Suspension-aware functions keep ordinary call syntax and return types. A call
blocks without a scheduler and parks its coroutine under a host handler.
Structured task scopes and worker pools compose concurrent work at different
isolation boundaries.

```nupp
local suspension = require("nupp.suspension")
local time = require("nupp.time")

local function waitFor(milliseconds: number): number
    time.sleep(milliseconds)
    return milliseconds
end

local results = suspension.all({
    || -> waitFor(20),
    || -> waitFor(10),
})

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
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = "ready"
```

The standard library includes files, networking, TLS, HTTP, processes, JSON,
hashes, parsing, memory spans, GPU storage, SafeTensors, tokenization, and
quantized numeric helpers. See [comptime](learn/language/comptime.md),
[serde](learn/runtime/data/serde.md), and the [standard
library](learn/runtime/data/standard-library.md).

## CPU, SIMD, and GPU compilation

`@aot` lowers admitted CPU functions through verified IR to C or Wasm. Complete
span maps can become lane-parallel, while `target = "gpu"` produces typed
resident-buffer kernels and native or WebGPU artifacts.

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
[vectorization](learn/performance/ahead-of-time/vectorization.md), and
[GPU compute](learn/performance/ahead-of-time/gpu.md).

## Portable targets and packaging

A build target can lower for native LuaJIT or the portable Lua 5.1 surface.
Projects can produce module trees, bundles, standalone binaries, embedded
components, Wasm side modules, and browser packages.

```lua [nupp.lua]
portable = {
   kind = "modules",
   entries = {"main"},
   dialect = "lua51",
   outDir = "build/lua51",
   backends = {"portable.backend"},
}
```

See [project builds](learn/projects/build.md),
[portable libraries](learn/projects/portability/libraries.md), and
[Wasm applications](learn/performance/ahead-of-time/wasm.md).

## Language-aware tools

The checker, builder, test runner, formatter, language server, documentation
generator, profiler, coverage tool, migration tools, and compiler inspectors
ship in one executable.

```text
nupp check                 # check the configured source graph
nupp fmt --write           # format project source
nupp test                  # build and run configured tests
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
- [NEPs](neps/index.md)

:::
