---
order: 5
---

# Learn Nupp

Nupp adds checked types, explicit resource contracts, concurrency, and native
compilation to Lua source. Start with a project, then follow the subject that
matches the code you are building.

```bash
nupp init app hello
cd hello
nupp check
nupp task start
```

## Starting a project

[Getting started](getting-started/index.md) creates and runs a maintained
project template. The [tour](getting-started/tour.md) introduces the core
language, and the [feature map](getting-started/features.md) links every larger
area without turning the tour into a reference manual.

## Language and runtime

[Language syntax](language/syntax.md) covers the source forms.
[Types](language/types/index.md) explains the checking model, while
[ownership](runtime/ownership/index.md),
[concurrency](runtime/concurrency/suspension.md), and
[C interop](runtime/c-interop/index.md) cover runtime boundaries.

## Building and measuring

[Project builds](projects/build.md) owns targets, dependencies, and artifacts.
[Performance](performance/index.md) covers optimization and measurement, and
[ahead-of-time compilation](performance/ahead-of-time/index.md) covers CPU, Wasm, SIMD,
and GPU code generation.

## Tools and deployment

[Tooling](tooling/index.md) introduces the checker, formatter, language server,
documentation generator, and inspection commands. The project pages cover
[portable libraries](projects/portability/libraries.md),
[embedding](projects/embedding.md), and
[integrations](projects/integrations/index.md).
