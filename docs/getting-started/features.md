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

- [File types](../learn/language/file-types.md) divides checked `.nupp` source
  from plain `.lua`, whose type comments are still imported.
- [Modules](../learn/language/modules.md),
  [named arguments](../learn/language/named-arguments.md),
  [switch expressions](../learn/language/switch-expressions.md), and
  [exit suffixes](../learn/language/exit-suffixes.md) cover the main
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

- [Performance](../learn/performance/index.md) explains how checked types reach
  VM instructions and how to read the bytecode a file lowers to.
- [Ahead-of-time compilation](../learn/performance/ahead-of-time/index.md) covers the
  checked `@aot` subset and its numeric guarantees.
- [SIMD programming](../learn/performance/ahead-of-time/simd-programming.md)
  teaches what SIMD is and how a Nupp loop uses lanes, starting from nothing.
- [GPU compute](../learn/performance/ahead-of-time/gpu.md) covers checked
  resident-buffer kernels; the VM has no GPU provider yet, so none runs on a
  device.

## Projects and hosts

- [Project builds](../learn/projects/build.md) covers targets, dependencies, caches,
  and standalone binaries.
- [Portable libraries](../learn/projects/portability/libraries.md) choose
  host-specific implementations at require time.
- [Native modules](../learn/projects/native-modules.md) write a module's functions
  in Rust or C, and embed the VM in a Rust application.
- [Hot reload](../learn/projects/hot-reload.md) replaces compatible function bodies
  at explicit safe points.
- [Integrations](../learn/projects/integrations/index.md) covers LuaCATS
  annotations and pinned API definitions.

## Libraries and tools

[Standard library](../learn/runtime/data/standard-library.md) maps the public modules
for I/O, networking, data, parsing, memory, model assets, and workers.
[Tooling](../learn/tooling/index.md) maps checking, building, testing,
formatting, documentation, editor services, diagnostics, coverage, migration,
ownership audits, and compiler inspection.
