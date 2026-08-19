
---

```playground
```

---

<!-- nupp:features -->

## Learning Nupp

- [Installation](getting-started/installation.md): requirements, a checkout, and
  a first project.
- [A tour of Nupp](getting-started/tour.md): the whole language in one pass.
- [Suspension](concepts/suspension.md) waits with or without a scheduler,
  composes concurrent work, and checks where suspension is forbidden.
- [Workers](concepts/workers.md) run CPU work in isolated LuaJIT states and
  communicate through bounded copied messages.
- [Nupp syntax](concepts/syntax.md): the syntax, and what LuaJIT 2.1 carries.

**API docs**

- [Type system](type-system/overview.md): gradual typing, records, structs,
  interfaces, generics, and narrowing.
- [Ownership](concepts/ownership.md): resources that are hard to leak.
- [Effect contracts](concepts/effects.md): what calls may observe, change, or
  expose.
- [Suspension](concepts/suspension.md) covers scheduler-neutral waiting, checked
  suspension effects, cancellation, and structured concurrency.
- [Tooling](getting-started/tooling.md): the checker, build system, formatter,
  language server, documentation generator, and profiler.
- [Performance](guides/performance.md): switch dispatch, indexed views, SoA hot
  loops, and where each pass is specified.
- [LuaJIT trace checking](guides/jit-trace-checking.md): deterministic blockers,
  `@jit` contracts, editor inspection, and observed abort reasons.
- [The `nupp` standard library](concepts/standard-library.md): JSON, UTF-8,
  buffers, readers, writers, paths, URIs, identifiers, hashes, checksums, math
  and vectors.
- [Checked spans](modules/nupp/mem/span.md): rooted, bounds-checked shared and
  writable views over contiguous C storage.
- [Reflection](concepts/reflection.md): comptime semantic descriptors, runtime
  type witnesses, lazy descriptors, and JSON's extension-backed codec.
