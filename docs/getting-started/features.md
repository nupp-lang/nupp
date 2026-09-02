---
order: 3
redirects: learn/getting-started/features
---

# Feature map

Nupp keeps its advanced facilities in ordinary functions, modules, and build
targets. This map points from a goal to the page that owns its rules.

```nupp
local record Job
    name: string
    attempts: integer
end

local pending = new Job(name = "index", attempts = 0)
print(pending.name)
```

## Language

- [Gradual typing](../learn/language/gradual-typing.md) moves annotated `.lua` into
  `.g.nupp`, then raises the strict floor with `.nupp`.
- [Modules](../learn/language/modules.md),
  [named arguments](../learn/language/named-arguments.md), and
  [switch expressions](../learn/language/switch-expressions.md) cover the main
  source-level additions.
- [Comptime](../learn/language/comptime.md),
  [comptime types](../learn/language/types/comptime-types.md), and
  [reflection](../learn/language/reflection.md) compute values and types during
  compilation.
- [Types](../learn/language/types/index.md) links records, structs, interfaces,
  unions, refinements, generics, packs, and narrowing.

## Resources and foreign code

- [Ownership](../learn/runtime/ownership/index.md) introduces borrowing, transfer,
  pinning, and deterministic cleanup.
- [C interop](../learn/runtime/c-interop/index.md) covers declarations, header import,
  lifetime contracts, memory, and exported struct layouts.
- [Schema-driven serde](../learn/runtime/data/serde.md) derives typed encoders and
  decoders, while
  [structure-of-arrays storage](../learn/runtime/data/structure-of-arrays.md) keeps
  hot fields in compact columns.

## Waiting and parallel work

- [Suspension](../learn/runtime/concurrency/suspension.md) lets one blocking-shaped
  API run directly or park under a host scheduler.
- [Task scopes](../learn/runtime/concurrency/task-scopes.md) structure application
  concurrency within one runtime.
- [Workers](../learn/runtime/concurrency/workers.md) run exported functions in
  persistent isolated states on a bounded pool.

## Performance and compute

- [Performance](../learn/performance/index.md) explains optimization levels, remarks,
  observable guarantees, and the eight named optimization passes.
- [JIT trace checking](../learn/performance/jit-trace-checking.md) and
  [profiling](../learn/performance/profiling.md) distinguish code that did not record
  from code that recorded and ran slowly.
- [Ahead-of-time compilation](../learn/performance/ahead-of-time/index.md) covers CPU kernels,
  SIMD, Lua-value construction, native artifacts, and Wasm side modules.
- [GPU compute](../learn/performance/ahead-of-time/gpu.md) covers generated resident-buffer
  kernels, structured workgroups, tensor layouts, and the browser WebGPU
  profiles.

## Projects and hosts

- [Project builds](../learn/projects/build.md) covers targets, dependencies, caches,
  standalone binaries, and static components.
- [Portable libraries](../learn/projects/portability/libraries.md) lower one checked
  source tree for LuaJIT or the portable Lua 5.1 surface.
- [Embedding](../learn/projects/embedding.md) loads checked components into a C or C++
  application through the Rust-owned SDK.
- [Hot reload](../learn/projects/hot-reload.md) replaces compatible function bodies
  at explicit safe points.
- [Integrations](../learn/projects/integrations/index.md) covers LuaRocks, LuaCATS,
  and LÖVE projects.

## Libraries and tools

[Standard library](../learn/runtime/data/standard-library.md) maps the public modules
for I/O, networking, data, parsing, memory, GPU compute, model assets, and
workers. [Tooling](../learn/tooling/index.md) maps checking, building, testing,
formatting, documentation, editor services, diagnostics, coverage, migration,
ownership audits, and compiler inspection.
