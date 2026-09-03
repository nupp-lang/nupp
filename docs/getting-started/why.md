---
order: 4
title: Why use Nupp
redirects: learn/getting-started/why
---

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
`nupp migrate` converts recognized annotations into a `.g.nupp` file when a
project wants an automated first step.

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
typing](../learn/language/gradual-typing.md#renaming-is-the-migration) for the four
extensions and what each floor adds.

What an annotation buys is the ordinary list of misspelled fields, wrong
argument types, missing returns, and unhandled union members, each reported with
a code, a caret, and usually a machine-applicable fix. See
[diagnostics](../reference/diagnostics.md) for the format and the code families.

## Types that survive erasure

Most Nupp types erase. Declarations that define a runtime representation remain
in the lowered program.

A native-target `struct` becomes FFI cdata: fixed layout, real C widths, no
hash part.

```nupp
local struct Vec2
    x: float
    y: float
end
```

That is `ffi.metatype(ffi.typeof("struct { float x; float y; }"), ...)`. A
portable target may select the checked table-backed struct provider instead. A
`record` with the same fields is always a Lua table with a metatable. Declaring
which representation the type needs is the point. See [records and
structs](../learn/language/types/records-and-structs.md#choosing) for which one a given type wants.

The other survivor is a C declaration, which stays a runtime binding because it
loads a native symbol. Everything else is ordinary Lua once it lowers.

## FFI a header can describe

A raw `ffi.C.point_length(p)` call carries no checked signature. A `cdef`
declaration supplies the ABI and the pointer contract:

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
finalizer. [`nupp import-c`](../learn/runtime/c-interop/index.md#import-a-header) writes a
committed module you can edit, and
[`cheader("mini.h")`](../learn/runtime/c-interop/index.md#type-the-header-in-place) types
the header at compile time with no generated file. A manifest C dependency can
also compile deterministic wrappers for header-only `static inline` functions
and explicitly typed function-like macros.

## Resources that are hard to leak

Nupp puts cleanup and transfer obligations in the type:

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

The model has no named lifetimes, typestate, or graph-wide borrow analysis. It
tracks lexical cleanup and the ownership facts declared at FFI boundaries. See
[ownership](../learn/runtime/ownership/index.md) for the annotations a caller writes, and
[ownership and affine types](../learn/runtime/ownership/borrowing.md) for the whole model.

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
[suspension handler](../learn/runtime/concurrency/suspension.md#hosts-supply-scheduling-policy).
See [suspension](../learn/runtime/concurrency/suspension.md) for the model from an application
call down to the subscription contract.

## Tooling ships with the language

One binary provides the project tools:

- `nupp check` type-checks the project.
- `nupp build` compiles to Lua, incrementally.
- `nupp run` compiles and runs, with a profiler behind a flag.
- `nupp fmt` applies fixed rules with width and method-parentheses controls.
- `nupp doc` generates an API site from the parse tree.
- `nupp lsp` serves hover, rename, and code actions.
- `nupp test` ships assertions and a parallel runner, and still accepts another harness.
- `nupp explain` describes a diagnostic code, with worked examples.
- `nupp import-c` turns a C header into typed declarations.

The profiler is the part people are most surprised to find in a compiler. `nupp
run --profile` writes collapsed-stack text that speedscope reads, and `nupp run
--jit-aborts` reports every place LuaJIT declined to compile something. The
second is the question a sampling profiler structurally cannot answer, and on
LuaJIT it is usually the one that matters. See [tooling](../learn/tooling/index.md) for the
guided version of that list.

## Limits

The compiler optimizes costs paid before execution and facts the type checker
proves. Eight passes run at `-O1` and `-O2`, each named by a stable `OPT-n`
code. Ad-hoc builds default to `-O0`; deliverable targets default to `-O2`.

::: deepdive
A tracing JIT is already good at the transformations an ahead-of-time compiler
usually performs, and it performs them with the run-time types in hand rather
than the declared ones. Doing them again in the compiler buys a soundness
burden on every pass for gains that vanish once a trace warms up, and it puts
two optimizers in the path of any miscompile.

What is left is the work a trace cannot reach: anything paid once before the
first trace is recorded, and anything resting on a fact the checker proved and
then erased. See [optimization
passes](../learn/performance/index.md#optimization-passes) for what each one
rewrites, and how to turn one off to bisect a miscompile.
:::

The type system has deliberate holes, and they are written down rather than
implied: arrays are covariant, `as` is unchecked, `table` is gradual in both
directions, and a declared `is` edge is trusted instead of proved. Each buys
compatibility with how Lua is actually written. See [deliberate
unsoundness](../learn/language/types/index.md#deliberate-unsoundness) for what each
hole admits.

::: seealso
- [tour.md](tour.md) for the core language in one pass
- [features.md](features.md) for the broader feature map
- [installation.md](installation.md) for released binaries and package managers
- [contributing.md](../contributing.md) for source-checkout requirements
- [strictness.md](../learn/language/gradual-typing.md) for how an existing `.lua` file
  becomes a checked one
- [overview.md](../learn/language/types/index.md) for the type system as a whole
:::
