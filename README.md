<img src="docs/public/images/og.png" alt="Nupp" width="460" align="center"/>

# Nupp

Nupp is LuaJIT with checked types, resource contracts, concurrency, and native
compilation. It keeps ordinary Lua modules and control flow while adding the
information needed to check, optimize, and package a program.

```nupp
local record Point
    x: number
    y: number
end

local function scale(point: Point, factor: number): Point
    return new Point(x = point.x * factor, y = point.y * factor)
end

print(scale(new Point(x = 3, y = 4), 2).x)
```

## Start a project

The built-in application template includes a manifest, a checked module, a
test, and the tasks that run them:

```bash
nupp init app hello
cd hello
nupp check
nupp test
nupp task start
```

See [Getting started](docs/learn/getting-started/index.md) for the daily loop
and the browser, library, SIMD, and LÖVE templates. Building Nupp itself from a
source checkout is documented separately in
[Installation](docs/learn/getting-started/installation.md).

## Language and runtime

- `.lua`, `.g.nupp`, and `.nupp` provide plain, gradual, and strict source
  boundaries under one module resolver.
- Records, structs, interfaces, unions, refinements, generics, and narrowing
  add checked structure. Native LuaJIT targets represent structs as FFI cdata;
  portable targets select a checked table representation.
- Affine ownership, borrowing, pinning, and exact scopes track cleanup and C
  pointer lifetimes.
- Suspension, task scopes, and worker pools express waiting and parallel work
  without changing a function's return type.
- Comptime evaluation, type computation, reflection, and derives produce
  checked data and declarations during compilation.
- The standard library covers files, networking, TLS, HTTP, processes, data
  formats, hashes, parsing, memory views, GPU storage, and model assets.

The [Feature map](docs/learn/getting-started/features.md) links each area to the
page that owns its rules. The complete checking model is under
[Types](docs/learn/language/types/index.md).

## Compilation and deployment

Configured targets can lower for native LuaJIT or the portable Lua 5.1 surface,
which runs on Lua 5.1 through 5.4 and LuaJIT. Builds can produce module trees,
bundles, standalone binaries, embedded components, and browser packages.

`@aot` lowers admitted CPU functions to C or Wasm, including automatic or
explicit SIMD. `@aot(target = "gpu")` produces checked resident-buffer kernels,
structured workgroups, and native or WebGPU artifacts. See
[Ahead-of-time compilation](docs/learn/performance/ahead-of-time/index.md) and
[GPU compute](docs/learn/performance/ahead-of-time/gpu.md).

## Tooling

One executable provides checking, building, testing, formatting, editor
services, documentation, profiling, coverage, migration, C import and export,
ownership audits, and compiler inspection. Diagnostics carry stable codes,
source spans, related locations, repair help, and structured fixes.

See [Tooling](docs/learn/tooling/index.md) for the guided command map,
[CLI reference](docs/reference/cli.md) for exact options, and the
[playground](https://nupp.dev/playground/) for browser-compatible examples.
