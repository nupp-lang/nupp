## Try Nupp

```playground
```

<!-- nupp:features -->

## Getting started

Start here and you have run a program by the end of the second page:

- [Installation](start/installation.md): requirements, a checkout, and a first
  project.
- [A tour of Nupp](start/tour.md): the whole language in one pass.
- [Suspension](start/suspension.md) waits with or without a scheduler, composes
  concurrent work, and checks where suspension is forbidden.
- [Workers](start/workers.md) run CPU work in isolated LuaJIT states and
  communicate through bounded copied messages.
- [Nupp syntax](start/syntax.md): the syntax, and what LuaJIT 2.1 carries.

## API docs

For looking something up rather than learning it:

- [Type system](type-system/overview.md): gradual typing, records,
  structs, interfaces, generics, and narrowing.
- [Ownership](start/ownership.md): resources that are hard to leak.
- [Effect contracts](effects.md): what calls may observe, change, or expose.
- [Suspension](start/suspension.md) covers scheduler-neutral waiting, checked
  suspension effects, cancellation, and structured concurrency.
- [Tooling](start/tooling.md): the checker, build system, formatter, language
  server, documentation generator, and profiler.
- [Performance](tooling/performance.md): what Nupp does for speed — switch
  dispatch, indexed views, SoA hot loops, and where each pass is specified.
- [LuaJIT trace checking](tooling/jit-trace-checking.md): deterministic blockers,
  `@jit` contracts, editor inspection, and observed abort reasons.
- [The `nupp` standard library](stdlib.md): JSON, UTF-8, buffers, readers,
  writers, paths, URIs, identifiers, hashes, checksums, math and vectors.
- [Checked spans](spans.md): rooted, bounds-checked shared and writable views
  over contiguous C storage.
- [Reflection](concepts/reflection.md): comptime semantic descriptors, runtime
  type witnesses, lazy descriptors, and JSON's extension-backed codec.
