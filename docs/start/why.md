# Reasons to use Nupp

Nupp is LuaJIT with types, safer resource handling, and a toolchain in the box.
It is a superset: your Lua already compiles, and each thing below is something
you opt into on the declaration where you want it.

## Types you add one file at a time

Your Lua already builds: a `.lua` file is required, compiled and run
unchanged, and nothing in it has to be annotated for that to keep working.
There is no configuration step and no migration mode.

What a file is called says which floor it is held to. A `.nupp` file is checked
strictly: unknown variables are errors, and nothing untyped crosses a module
boundary. Rename a `.lua` file to `.g.nupp` and the typed syntax becomes
available with that floor still down, so annotations can go in one at a time:

```nupp:static
-- models.g.nupp: the typed syntax, no floor yet
local function scale(p, k)
    return {x = p.x * k, y = p.y * k}
end

-- models.nupp: the same file, once it is ready to hold the floor
local function scale(p: Point, k: number): Point
    return new Point(x = p.x * k, y = p.y * k)
end
```

The marker is not part of the module's name, so `require("models")` finds it
either way and nothing that depends on the file has to change when it moves.
`nupp check --strict` holds every file to the floor whatever it is called,
which is how you find out what a rename would cost before doing it.

What you get for an annotation is the ordinary list of misspelled fields, wrong
argument types, missing returns and unhandled union members, reported with a
code, a caret, and usually a machine-applicable fix.

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

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

Now the call is checked, and `borrows` records something the C prototype could
not: the callee only looks at the pointer for the duration of the call. Nupp
imports whole headers two ways, `nupp import-c` for a committed module you can
edit and `cheader("mini.h")` for compile-time typing with no generated file, and
neither changes the ABI or installs a finalizer.

## Resources that are hard to leak

Plain LuaJIT draws no distinction between a fresh allocation, a shared pointer,
one C is holding, and one already freed. The convention lives in a comment.

Nupp puts the obligation in the type:

```nupp:static
local file = resources.openFile("in.txt", "r")
print(file:read("*a"))
-- file is destroyed automatically here, including when read raises
```

Drop early, transfer it to a `takes` parameter, or return it from an
`@owned` function when automatic lexical destruction is not the desired end:

```nupp:static
local file = resources.openFile("in.txt", "r")
submit(file) -- takes file; automatic destruction is deactivated
```

Cleanup runs on fallthrough, errors, and every structured exit. The checker
also rejects using a value after it moves, letting a borrow outlive its source,
and suspending a coroutine with cleanup still owed.

This is a smaller model than Rust's: no named lifetimes, no typestate, no
borrow checker over arbitrary object graphs. It is aimed at the failures that
actually happen at an FFI boundary, and it costs one annotation on the producer.

## Waiting without an async half of the program

A suspension-aware library exposes one API instead of separate blocking and
async surfaces. Callers keep the same return types when an operation may wait.

Nupp uses one ordinary call. With no scheduler installed, a
suspension-aware operation blocks and drives its readiness sources. Under a
scheduler, it parks the current coroutine and lets other work run. If the
answer is already ready, it returns without either path.

The compiler tracks suspension separately from value types. Most code simply
uses inference; a `nosuspend` region or function type asks for proof when a
callback, C boundary, cleanup, or critical operation must not park. The runtime
protocol requires every real park to provide cancellation, so abandoning a
handled extent wakes suspended stacks far enough to run deterministic cleanup.

This is not invisible interception of arbitrary blocking calls. Libraries opt
in through `nupp.suspension`, while the host owns scheduling policy through a
[suspension handler](suspension-handlers.md). [Suspension](suspension.md)
follows the model from an application call down to the subscription contract.

## Toolchain ships with the language

One binary, built from one parse of your source:

| Command | What it does |
| --- | --- |
| nupp check | Type-check the project |
| nupp build | Compile to Lua, incrementally |
| nupp run | Compile and run, with a profiler behind a flag |
| nupp fmt | Format; fixed style, nothing to configure |
| nupp doc | Generate an API site from the parse tree |
| nupp lsp | Language server: hover, rename, code actions |
| nupp test | Build, then run the configured suite |
| nupp explain | Describe a diagnostic code, with worked examples |
| nupp import- | Turn a C header into typed declarations |

The profiler is the part people are most surprised to find in a compiler. `nupp
run --profile` writes collapsed-stack text that speedscope reads, and `nupp run
--jit-aborts` reports every place LuaJIT declined to compile something, which is
the question a sampling profiler structurally cannot answer, and on LuaJIT
usually the one that matters.

## Limits

The compiler does not repeat LuaJIT's optimizer. A tracing JIT is very good at
the transformations a compiler usually performs, and doing them again buys a
soundness burden for gains that vanish once a trace warms up. Nupp optimizes
what the JIT structurally cannot see: costs paid before it runs, and facts only
a type checker holds. Today that is one pass, and it grows only when a benchmark
says a new one earns its place.

The type system has deliberate holes, and they are written down rather than
implied: arrays are covariant, `as` is unchecked, `table` is gradual in both
directions, and a declared `is` edge is trusted instead of proved. Each buys
compatibility with how Lua is actually written.

## Where to start

In this order:

- [Installation](installation.md), then [a tour of Nupp](tour.md).
- [Nupp syntax](syntax.md) if you already know Lua and want the delta.
- [Suspension](suspension.md) for waiting with or without a scheduler.
- [Type system](../type-system/overview.md) covers what the checker proves.
