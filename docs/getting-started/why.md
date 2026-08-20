# Why use Nupp

Nupp is LuaJIT with a type system, cleanup obligations the checker tracks, and
one binary holding every tool. Every valid LuaJIT program is already a valid
Nupp program, and each addition below is opted into on the declaration that
wants it.

```nupp:playground
local record Point
    x: number
    y: number
end

local function scale(p: Point, k: number): Point
    return new Point(x = p.x * k, y = p.y * k)
end

print(scale(new Point(x = 3, y = 4), 2).x)
```

## Typing one file at a time

Your Lua already builds. A `.lua` file is required, compiled, and run
unchanged, and nothing in it has to be annotated for that to keep working.
There is no configuration step and no migration mode.

What a file is called says which floor it is held to. A `.nupp` file is checked
strictly: unknown variables are errors, and nothing untyped crosses a module
boundary. Rename a `.lua` file to `.g.nupp` and the typed syntax becomes
available with that floor still down, so annotations go in one at a time.

```nupp
-- models.g.nupp: the typed syntax, no floor yet
local function scale(p, k)
    return {x = p.x * k, y = p.y * k}
end
```

The same function, once it is ready to hold the floor:

```nupp
-- models.nupp
local function scale(p: Point, k: number): Point
    return new Point(x = p.x * k, y = p.y * k)
end
```

The marker is not part of the module's name, so `require("models")` finds the
file either way and nothing that depends on it changes when it moves.
`nupp check --strict` holds every file to the floor whatever it is called, which
is how to see what a rename would cost before making it. See [gradual
typing](../concepts/strictness.md#renaming-is-the-migration) for the four
extensions and what each floor adds.

What an annotation buys is the ordinary list of misspelled fields, wrong
argument types, missing returns, and unhandled union members, each reported with
a code, a caret, and usually a machine-applicable fix. See
[diagnostics](../reference/diagnostics.md) for the format and the code families.

## Types that survive erasure

Most typed Lua erases everything. Nupp erases most things and keeps the ones
that have to be real at run time.

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
dynamism, and GC. Declaring which one you meant is the point. See [records and
structs](../type-system/records.md#choosing) for which one a given type wants.

The other survivor is a C declaration, which stays a runtime binding because it
loads a native symbol. Everything else is ordinary Lua once it lowers.

## FFI a header can describe

LuaJIT's FFI is fast and completely untyped. `ffi.C.point_length(p)` accepts
anything and tells you nothing.

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

Now the call is checked, and `borrows` records something the C prototype could
not: the callee only looks at the pointer for the duration of the call.

Nupp imports a whole header two ways, and neither changes the ABI or installs a
finalizer. [`nupp import-c`](../concepts/c-interop.md#import-a-header) writes a
committed module you can edit, and
[`cheader("mini.h")`](../concepts/c-interop.md#type-the-header-in-place) types
the header at compile time with no generated file. A manifest C dependency can
also compile deterministic wrappers for header-only `static inline` functions
and explicitly typed function-like macros.

## Resources that are hard to leak

Plain LuaJIT draws no distinction between a fresh allocation, a shared pointer,
one C is holding, and one already dropped. The convention lives in a comment.

Nupp puts the obligation in the type:

```nupp
local handle = assert(io.open("in.txt", "r"))
print(handle:read("*a"))
-- handle is destroyed automatically here, including when read raises
```

Discharge it earlier with `drop`, transfer it to a `takes` parameter, or return
it from a function whose result is `affine(T, cleanup)` when automatic lexical
destruction is not the desired end:

```nupp
local handle = assert(io.open("in.txt", "r"))
print(handle:read("*a"))
drop handle
```

Cleanup runs on fallthrough, errors, and every structured exit. The checker also
rejects using a value after it moves, letting a borrow outlive its source, and
suspending a coroutine with cleanup still owed.

The model is smaller than Rust's: no named lifetimes, no typestate, no borrow
checker over arbitrary object graphs. It is aimed at the failures that happen at
an FFI boundary, and it costs one annotation on the producer. See
[ownership](../concepts/ownership.md) for the annotations a caller writes, and
[ownership and affine types](../type-system/ownership.md) for the whole model.

## Waiting without a second API

A suspension-aware library exposes one API instead of separate blocking and
async surfaces. Callers keep the same return types when an operation may wait.

Nupp uses one ordinary call. With no scheduler installed, a suspension-aware
operation blocks and drives its readiness sources. Under a scheduler, it parks
the current coroutine and lets other work run. If the answer is already ready,
it returns without either path.

The compiler tracks suspension separately from value types. Most code uses
inference; a `nosuspend` region or function type asks for proof when a callback,
C boundary, cleanup, or critical operation must not park. The runtime protocol
requires every real park to provide cancellation, so abandoning a handled extent
wakes suspended stacks far enough to run deterministic cleanup.

This is not invisible interception of arbitrary blocking calls. Libraries opt in
through `nupp.suspension`, while the host owns scheduling policy through a
[suspension handler](../concepts/suspension.md#hosts-supply-scheduling-policy).
See [suspension](../concepts/suspension.md) for the model from an application
call down to the subscription contract.

## Tooling ships with the language

One binary, built from one parse of your source:

- `nupp check` type-checks the project.
- `nupp build` compiles to Lua, incrementally.
- `nupp run` compiles and runs, with a profiler behind a flag.
- `nupp fmt` formats to a fixed style with nothing to configure.
- `nupp doc` generates an API site from the parse tree.
- `nupp lsp` serves hover, rename, and code actions.
- `nupp test` builds, then runs the configured suite.
- `nupp explain` describes a diagnostic code, with worked examples.
- `nupp import-c` turns a C header into typed declarations.

The profiler is the part people are most surprised to find in a compiler. `nupp
run --profile` writes collapsed-stack text that speedscope reads, and `nupp run
--jit-aborts` reports every place LuaJIT declined to compile something. The
second is the question a sampling profiler structurally cannot answer, and on
LuaJIT it is usually the one that matters. See [tooling](tooling.md) for the
guided version of that list.

## Limits

The compiler does not repeat LuaJIT's optimizer. It optimizes what the JIT
structurally cannot see: costs paid before it runs, and facts only a type
checker holds. Today that is six passes at `-O1`, each named by a stable `OPT-n`
code, and the set grows only when a benchmark says a new one earns its place.
`-O0` is the default and rewrites nothing.

::: deepdive
A tracing JIT is already good at the transformations an ahead-of-time compiler
usually performs, and it performs them with the run-time types in hand rather
than the declared ones. Doing them again in the compiler buys a soundness
burden on every pass for gains that vanish once a trace warms up, and it puts
two optimizers in the path of any miscompile.

What is left is the work a trace cannot reach: anything paid once before the
first trace is recorded, and anything resting on a fact the checker proved and
then erased. See [optimization
passes](../guides/performance.md#optimization-passes) for what each one
rewrites, and how to turn one off to bisect a miscompile.
:::

The type system has deliberate holes, and they are written down rather than
implied: arrays are covariant, `as` is unchecked, `table` is gradual in both
directions, and a declared `is` edge is trusted instead of proved. Each buys
compatibility with how Lua is actually written. See [deliberate
unsoundness](../type-system/overview.md#deliberate-unsoundness) for what each
hole admits.

::: seealso
- [tour.md](tour.md) for every construct in one pass
- [installation.md](installation.md) for requirements and a first project
- [strictness.md](../concepts/strictness.md) for how an existing `.lua` file
  becomes a checked one
- [overview.md](../type-system/overview.md) for the type system as a whole
:::
