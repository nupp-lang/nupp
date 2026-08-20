
---

```playground
```

---

<!-- nupp:features -->

## Learning Nupp

- [Installation](getting-started/installation.md): requirements, a checkout, and
  a first project.
- [Tour of Nupp](getting-started/tour.md): every construct in one pass, each
  linked to the page that owns it.
- [Why use Nupp](getting-started/why.md): what Lua gives you, what Nupp adds,
  and what each addition costs.
- [Gradual typing](concepts/strictness.md): how an existing `.lua` file becomes
  a checked one, a declaration at a time.
- [Nupp syntax](concepts/syntax.md): the typed layer, and what LuaJIT 2.1
  carries underneath it.
- [Tooling](getting-started/tooling.md): the checker, build system, formatter,
  language server, documentation generator, and profiler.

## Language reference

- [Type system](type-system/overview.md): inference, records, structs,
  interfaces, generics, and narrowing.
- [Ownership](concepts/ownership.md): resources that are hard to leak.
- [Suspension](concepts/suspension.md): scheduler-neutral waiting, checked
  suspension effects, cancellation, and structured concurrency.
- [Workers](concepts/workers.md): CPU work in isolated LuaJIT states, exchanged
  as bounded copied messages.
- [Effect contracts](concepts/effects.md): what a call may observe, change, or
  expose.
- [Reflection](concepts/reflection.md): comptime semantic descriptors, runtime
  type witnesses, lazy descriptors, and JSON's extension-backed codec.
- [Standard library](concepts/standard-library.md): JSON, UTF-8, buffers,
  readers, writers, paths, URIs, identifiers, hashes, checksums, math, and
  vectors.
- [Checked spans](modules/nupp/mem/span.md): rooted, bounds-checked shared and
  writable views over contiguous C storage.

## Performance and profiling

- [Performance](guides/performance.md): switch dispatch, indexed views, SoA hot
  loops, and where each pass is specified.
- [LuaJIT trace checking](guides/jit-trace-checking.md): deterministic blockers,
  `@jit` contracts, editor inspection, and observed abort reasons.
- [Profiling](guides/profiling.md): sampling, zones, and the places LuaJIT
  declined to compile.
