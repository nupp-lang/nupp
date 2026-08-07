# Why use Nupp?

Nupp is LuaJIT with types, safer resource handling, and a toolchain in the box.
It is a superset: your Lua already compiles, and each thing below is something
you opt into on the declaration where you want it.

## Types you add one at a time

Anything unannotated is `any` and checks silently. That is the whole adoption
story — there is no configuration step, no migration mode, and no point at
which a half-typed project stops building.

```nupp
-- checks nothing, and that is allowed
local function scale(p, k)
    return {x = p.x * k, y = p.y * k}
end

-- checks the boundary
local function scale(p: Point, k: number): Point
    return Point{x = p.x * k, y = p.y * k}
end
```

`--strict` raises the floor when a project is ready: unknown variables become
errors, and nothing untyped is allowed to cross a module boundary.

What you get for an annotation is the ordinary list — misspelled fields, wrong
argument types, missing returns, unhandled enum members — reported with a code,
a caret, and usually a machine-applicable fix.

## Types that survive to runtime

Most typed Lua erases everything. Nupp erases most things, and keeps the ones
worth keeping.

A `struct` becomes FFI cdata: fixed layout, real C widths, no hash part.

```nupp
local struct Vec2
    x: float
    y: float
end
```

That is `ffi.metatype(ffi.typeof("struct { float x; float y; }"), ...)`. Two
floats of memory, indexed by offset. A `record` with the same fields is a Lua
table with a metatable, which is the right answer when you want identity,
dynamism, and GC. Declaring which one you meant is the point.

## FFI that a header can describe

LuaJIT's FFI is fast and completely untyped. `ffi.C.point_length(p)` accepts
anything and tells you nothing.

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from "mini"
```

Now the call is checked, and `borrows` records something the C prototype could
not: the callee only looks at the pointer for the duration of the call. Nupp
imports whole headers two ways — `nupp import-c` for a committed module you can
edit, `cheader("mini.h")` for compile-time typing with no generated file — and
neither changes the ABI or installs a finalizer.

## Resources that are hard to leak

Plain LuaJIT draws no distinction between a fresh allocation, a shared pointer,
one C is holding, and one already freed. The convention lives in a comment.

Nupp puts the obligation in the type:

```nupp
local file = resources.open_file("in.txt", "r")
-- error: NUPP2603: owned value "file" leaves scope without being
-- consumed, disposed, returned, or converted with intoRaw
```

Discharge it by disposing, transferring it to a `takes` parameter, returning it
from an `@owned` function — or by scoping it:

```nupp
with file = resources.open_file("in.txt", "r") do
    print(file:read("*a"))
end
```

Cleanup runs on fallthrough, errors, and every structured exit. The checker
also rejects using a value after it moves, letting a borrow outlive its source,
and suspending a coroutine with cleanup still owed.

This is a smaller model than Rust's: no named lifetimes, no typestate, no
borrow checker over arbitrary object graphs. It is aimed at the failures that
actually happen at an FFI boundary, and it costs one annotation on the producer.

## A toolchain that ships with the language

One binary, built from one parse of your source:

```
 Command       What it does
 ────────────  ───────────────────────────────────────────────
 nupp check    Type-check the project
 nupp build    Compile to Lua, incrementally
 nupp run      Compile and run, with a profiler behind a flag
 nupp fmt      Format; fixed style, nothing to configure
 nupp doc      Generate an API site from the parse tree
 nupp lsp      Language server: hover, rename, code actions
 nupp test     Build, then run the configured suite
 nupp explain  Describe a diagnostic code, with worked examples
 nupp import-c Turn a C header into typed declarations
```

The profiler is the part people are most surprised to find in a compiler.
`nupp run --profile` writes collapsed-stack text that speedscope reads, and
`nupp run --jit-aborts` reports every place LuaJIT declined to compile
something — the question a sampling profiler structurally cannot answer, and on
LuaJIT usually the one that matters.

## What it does not try to be

The compiler does not repeat LuaJIT's optimizer. A tracing JIT is very good at
the transformations a compiler usually performs, and doing them again buys a
soundness burden for gains that vanish once a trace warms up. Nupp optimizes
what the JIT structurally cannot see — costs paid before it runs, and facts
only a type checker holds. Today that is one pass, and it grows only when a
benchmark says a new one earns its place.

The type system has deliberate holes, and they are written down rather than
implied: arrays are covariant, `as` is unchecked, `table` is gradual in both
directions, and a declared `is` edge is trusted instead of proved. Each buys
compatibility with how Lua is actually written.

## Where to start

- [Installation](installation.md), then [a tour of Nupp](tour.md).
- [Nupp syntax](syntax.md) if you already know Lua and want the delta.
- [The type system](../type-system/overview.md) for what the checker proves.
