# Lints

A lint is advice the compiler is confident enough to give but not entitled to
force. It is separate from a type error, and the difference is the whole design:

- A **type error** says the program does not mean what it says it means. It is
  not configurable, not suppressible, and always stops the build. `NUPP2001`
  and its neighbours are these.
- A **lint** says the program means something you probably did not intend. It
  has a name, a default level, and both project-wide and per-statement
  overrides. Being wrong about one costs you a suppression, not a fork.

Clippy's split between `rustc` errors and `clippy::` lints is the same line.

One annotation turns any of them off for one statement:

```nupp
@allow("unused-binding")
local pending = 1
```

## Severity levels

| level | reported | build | @allow | editor |
| --- | --- | --- | --- | --- |
| `off` | no | - | - | - |
| `note` | yes | continue | yes | Information (3) |
| `warning` | yes | continue | yes | Warning (2) |
| `error` | yes | FAILS | yes | Error (1) |

Three things vary independently, which is why they are three columns rather
than one switch:

- **Whether the build stops.** Only `error`.
- **Whether it can be waved away.** Every lint can, at any level. A lint is a
  judgement call by definition; a project that disagrees says so. This is what
  separates a lint at `error` from a type error, which nothing silences.
- **How loudly an editor says it.** A file being typed into is half-written, so
  a lint may be shown more quietly than it is enforced. `missing-require` is an
  error in a build and a warning in an editor.

## Lint names and codes

Every lint has a name and a stable code:

| name | code | category | default |
| --- | --- | --- | --- |
| missing-require | `NUPP2120` | correctness | error |
| `exhaustiveness` | `NUPP2107` | correctness | warning |
| string-pointer | `NUPP2501` | suspicious | warning |
| jit-callback | `NUPP2502` | suspicious | warning |
| customary-operator | `NUPP2504` | style | warning |
| loop-invariant-closure | `NUPP2505` | suspicious | warning |
| undocumented-raise | `NUPP2506` | suspicious | warning |
| unused-binding | `NUPP2507` | suspicious | warning |
| discarded-result | `NUPP2508` | suspicious | warning |
| reifiable-record | `NUPP2509` | performance | off |
| gradual-projection | `NUPP2511` | suspicious | warning |
| else-if | `NUPP2510` | style | warning |
| positional-record-construction | `NUPP2512` | style | warning |
| deprecated | `NUPP2513` | suspicious | warning |
| jit-boundary | `NUPP2514` | suspicious | warning |
| jit-loop-closure | `NUPP2515` | performance | off |

The name is what you write in configuration and suppressions; the code is what
survives renaming and what tooling keys on. Either is accepted everywhere.

`nupp lints` prints each lint's name, category, effective level and summary,
marking any the project has moved. The text table has no code column;
`nupp lints --json` carries `code`, `default` and `moved` as well.

## Built-in lints

These outputs were captured from `nupp check --no-color`.

### `missing-require`

A project module must be required before its name is in scope. This project
also contains `src/mathutil.nupp`.

::: code-group
```nupp [src/missing-require.nupp]
local doubled: number = mathutil.double(21)
```

```text [nupp check output]
src/missing-require.nupp:1:25: error: NUPP2120 missing-require: "mathutil" names a project module; require("mathutil") to use it
 1 | local doubled: number = mathutil.double(21)
   |                         ^~~~~~~~
```
:::

### `exhaustiveness`

A returning dispatch over a closed set must handle every remaining member.

::: code-group
```nupp [src/exhaustiveness.nupp]
local type Color = "red" | "green" | "blue"

local function name(color: Color): string
    if color == "red" then
        return "red"
    end
    return "other"
end

return name
```

```text [nupp check output]
src/exhaustiveness.nupp:4:5: warning: NUPP2107 exhaustiveness: every branch returns, so this handles "blue" | "green" | "red" and leaves "blue", "green" unhandled
 4 |     if color == "red" then return "red" end
   |     ^~
help: add branches for "blue", "green" or add an else clause
```
:::

### `string-pointer`

A pointer into a temporary Lua string cannot be kept after the cast.

::: code-group
```nupp [src/string-pointer.nupp]
local pointer = ffi.cast<cstring>("hello")
```

```text [nupp check output]
src/string-pointer.nupp:1:17: warning: NUPP2501 string-pointer: a pointer taken from a Lua string is only valid for the call it is passed to
 1 | local pointer = ffi.cast<cstring>("hello")
   |                 ^~~
```
:::

### `jit-callback`

A Lua function reaching a C-derived callback parameter or an explicit unsafe
cast creates a C callback. The callback remains registered and prevents
compilation through that call path. Use `jit.off(callback)` when intentional.

::: code-group
```nupp [src/jit-callback.nupp]
unsafe do
    local callback = function()
    end
    local pointer = ffi.cast<voidptr>(callback)
    local handle = nupp.pin(pointer, callback)
end
```

```text [nupp check output]
src/jit-callback.nupp:3:21: warning: NUPP2502 jit-callback: a Lua function cast to a C callback stays registered and cannot be compiled through
 3 |     local pointer = ffi.cast<voidptr>(callback)
   |                     ^~~
help: keep the callback off hot paths, or call C with a plain pointer instead
```
:::

### `jit-boundary`

A variadic C call cannot safely execute on a compiled LuaJIT trace. Move it to
a cold helper and call `jit.off(helper)`. Inside an `@jit` function the same
boundary is the non-suppressible `NUPP2707` contract error.

::: code-group
```nupp [src/jit-boundary.nupp]
cdef function printf(format: cstring, ...): int32

local function report(value: int32): nil
    printf("%d", value)
end
```

```text [nupp check output]
src/jit-boundary.nupp:4:5: warning: NUPP2514 jit-boundary: a variadic FFI call cannot safely execute on a compiled trace
 4 |     printf("%d", value)
   |     ^~~~~~
help: move the call into a function disabled with jit.off, or remove @jit from this function
```
:::

### `customary-operator`

C-style operators work, but the lint prefers Lua's word spellings.

::: code-group
```nupp [src/customary-operator.nupp]
local ready = true
local pending = !ready
```

```text [nupp check output]
src/customary-operator.nupp:2:17: warning: NUPP2504 customary-operator: ! is the customary spelling of not
 2 | local pending = !ready
   |                 ^
help: write not
```
:::

### `else-if`

An `else` whose only statement is `if` is the long form of `elseif`. The lint
also recognizes adjacent `if` statements that compare the same local name to
different literals, where the first body does not assign that name.

::: code-group
```nupp [src/else-if.nupp]
if primary then
    usePrimary()
else
    if fallback then
        useFallback()
    end
end
```

```text [nupp check output]
src/else-if.nupp:3:1: warning: NUPP2510 else-if: this else contains only an if; write elseif instead
 3 | else
   | ^~~~
help: replace else followed by if with elseif
```
:::

### `positional-record-construction`

A record without a declared constructor may be built either way, and both build
the same table. Naming the fields says at the call site which value lands where;
leaving it to the order says it in the declaration, so a reader has to go there,
and adding a field silently changes what an existing call means.

A struct is exempt. It is its C layout, the ctype takes its values in that
layout's order, and naming them is an error rather than a preference.

::: code-group
```nupp [src/positional-record-construction.nupp]
local record Point
    x: integer
    y: integer
end

local p = new Point(1, 2)

return p
```

```text [nupp check output]
src/positional-record-construction.nupp:6:15: warning: NUPP2512 positional-record-construction: record Point is constructed by field order
 6 | local p = new Point(1, 2)
   |               ^~~~~
help: write new Point(field = value, ...) to name the fields
```
:::

### `loop-invariant-closure`

A loop should not build the same non-capturing function on every iteration.

::: code-group
```nupp [src/loop-invariant-closure.nupp]
for _, item in ipairs(items) do
    register(item, function(event)
        return event.kind == "click"
    end)
end
```

```text [nupp check output]
src/loop-invariant-closure.nupp:2:28: warning: NUPP2505 loop-invariant-closure: this function is built once per iteration but does not use the iteration, so every one of them is the same function, and building one is what keeps the loop from compiling
 2 |     register(item, function(event) return event.kind == "click" end)
   |                            ^
help: declare it once above the loop and pass the name
```
:::

The wasted allocation is the smaller half. LuaJIT has no recording for the
bytecode that builds a function, so a loop containing one aborts recording every
time it is tried, and after enough attempts the loop is blacklisted and never
compiled again. The cost is not a closure per iteration; it is the whole
enclosing loop running interpreted, however hot it gets and whatever else is in
it.

That is why this reads a function *built* in a loop rather than one that
outlives it, and why it is worth heeding where the allocation alone would look
too small to bother with.

It reports only what it can prove pointless: a function reading nothing from the
iteration, which therefore lifts out with no change in meaning. One that does
read the iteration costs the same trace and cannot be lifted, so it is
`jit-loop-closure` below rather than this.

### `jit-loop-closure`

The other half of the pair, for a function that reads the iteration. There is
nothing to lift and no mechanical edit to suggest, so this is off until a
project asks for it. The loop does not compile either way, which is worth being
able to ask about.

::: code-group
```nupp [src/jit-loop-closure.nupp]
for _, item in ipairs(items) do
    register(item, function(event)
        return event.kind == item.kind
    end)
end
```

```text [nupp check output]
src/jit-loop-closure.nupp:2:28: note: NUPP2515 jit-loop-closure: this function is built once per iteration and reads the iteration, so it cannot be declared above the loop, and LuaJIT does not record building a function, so this loop never compiles
 2 |     register(item, function(event)
   |                            ^
help: hand what varies to a function declared outside the loop, so the loop calls one rather than builds one
```
:::

The way out, where there is one, is to change what varies rather than where the
function sits: declare one function above the loop that takes the varying part
as an argument, so the loop calls it instead of building one. Where the closure
really has to be built per iteration, the honest answer is that the loop runs
interpreted, and the choice belongs to whoever wrote it.

Two things report it without being asked. Inside an `@jit` function it is the
non-suppressible `NUPP2707`, because that annotation promised the absence of
catalogued recorder blockers; `jit.off` on the enclosing function silences it,
since a function taken off the JIT has no trace to lose. And `nupp bc --check`
reads the bytecode of any file and reports the same loops, together with the
ones the compiler's own lowerings could introduce.

### `undocumented-raise`

A documented function that calls `error` must say when it raises.

::: code-group
```nupp [src/undocumented-raise.nupp]
--- Reads a file.
--- @param path where to read from
local function load(path: string): string
    if path == "" then
        error("no path")
    end
    return path
end

return load
```

```text [nupp check output]
src/undocumented-raise.nupp:3:16: warning: NUPP2506 undocumented-raise: load raises, but its documentation does not say when
 3 | local function load(path: string): string
   |                ^~~~
src/undocumented-raise.nupp:4:24: note: raises here
 4 |     if path == "" then error("no path") end
   |                        ^~~~~
help: add an @raises line saying what makes it raise
```
:::

Only functions with a `---` documentation run are judged. `error` counts but
`assert` does not, nested functions own their raises, and the lint does not
propagate through calls. `nupp lsp inspect` shows a callee's documented
`@raises` at its use site.

### `unused-binding`

A `local` nothing reads is a leftover, and a `require` nothing reads is the
other half of `missing-require`. This project also contains `src/strutil.nupp`.

::: code-group
```nupp [src/unused-binding.nupp]
local strutil = require("strutil")

local function shout(text: string): string
    local prefix = "> "
    return text .. "!"
end

return shout
```

```text [nupp check output]
src/unused-binding.nupp:1:7: warning: NUPP2507 unused-binding: nothing uses strutil, so requiring "strutil" does nothing here
 1 | local strutil = require("strutil")
   |       ^~~~~~~
help: delete the require
src/unused-binding.nupp:4:11: warning: NUPP2507 unused-binding: nothing uses prefix
 4 |     local prefix = "> "
   |           ^~~~~~
help: delete the binding, or name it _ if it is deliberately unused
```
:::

Three kinds of binding are left alone. A parameter's presence is dictated by the
signature it implements and a loop variable's by the iterator, so neither is a
mistake its author is free to correct; a name beginning with `_` says the
binding is deliberate and the value is not wanted. An owned value nothing reads
is `NUPP2603` instead, which is the rule with something to say about it.

Writing counts as reading, because both resolve the name the same way. A binding
only ever assigned to is a separate question, asked flow-sensitively, and this
lint does not answer it. Nor does it unpick a function that only calls itself.
Both are silences rather than false reports, which is the direction to be wrong
in.

### `discarded-result`

A call written as a statement is made for what it does. A callee that does
nothing but return, called for a value that is then dropped, does nothing at
all.

::: code-group
```nupp [src/discarded-result.nupp]
local function double(value: number): number
    return value * 2
end

double(21)

return double
```

```text [nupp check output]
src/discarded-result.nupp:5:1: warning: NUPP2508 discarded-result: double has no effects, so dropping its result leaves this statement doing nothing
 5 | double(21)
   | ^~~~~~
src/discarded-result.nupp:1:16: note: declared here, and does nothing but return
 1 | local function double(value: number): number
   |                ^~~~~~
help: use the result, or delete the call
```
:::

Rust needs `#[must_use]` on each function to say this. Nupp does not: effects
are inferred for every visible function already, so being nothing but a result
is proved rather than declared. Nothing has to be annotated.

The proof is two questions. Whether the callee reaches anything the compiler
cannot see is answered by its effect summary, which is file-local. A callee that
reaches another module, or makes an unresolved call, widens to `top` and is left
alone. Whether it writes is answered separately and syntactically, because a
summary treats a write through a non-parameter local as staying local, and a
local read out of a parameter is not scratch. See
[effects](effects.md#calls-and-fixed-point-propagation).

Reads and allocation are not reasons to call: reading state and dropping the
answer is the mistake being described. Writes, shape and metatable changes,
escapes, declared callees, yielding and raising all are. A function returning
nothing, including one returning only `nil`, discards nothing and is not judged.

### `reifiable-record`

A record whose fields would all fit in C memory is one keyword away from being a
struct, which is the largest speedup the compiler has.

::: code-group
```nupp [src/reifiable-record.nupp]
local record Vec2
    x: float
    y: float
end

return Vec2
```

```text [nupp check output]
src/reifiable-record.nupp:1:14: note: NUPP2509 reifiable-record: record Vec2 declares only fields that reify
 1 | local record Vec2
   |              ^~~~
help: declaring it `struct` puts its instances in C memory, off the collector's graph, at the cost of a fixed layout: no fields added after construction
note: an instance is cdata, not a table: `pairs` needs a `__pairs` metamethod, and a serializer that walks tables will refuse it unless it is converted first
```
:::

The judgement is one-directional and stays a suggestion, because the two are not
interchangeable at runtime. A struct has a fixed layout and gives up the
prototype a record stamps on what it builds. More to the point, an instance
stops being a table: `type` answers `"cdata"`, `is` tests for cdata, and any
code that walks the value by its keys has to be told how.

That last cost is the one worth checking before taking the suggestion, because
it reaches further than the declaration:

| what | on a record | on a struct |
| --- | --- | --- |
| `type(v)` | "table" | "cdata" |
| `pairs(v)` | iterates fields | needs a __pairs metamethod |
| `string.buffer.encode(v)` | encodes | raises, and takes no hook |
| a table-walking serializer | works | sees no keys |

`__pairs` is dispatched on a `ffi.metatype`, so iteration can be restored by
declaring one. Serialization cannot be patched the same way, because LuaJIT's
serializer refuses cdata outright with no extension point, so a struct that has
to cross a serialization boundary needs a conversion written for it.

[`NUPP2201`](diagnostics.md) is the other half of the pair. It fires once
`struct` is written and a field cannot live in C memory, so between them a
declaration is told both what it could gain and what it may not do.

A record is a candidate only when every entry is one a struct also accepts: a
field whose type reifies, a constructor, or a method. An indexer, a Lua array
part, a declaration-only metamethod, a nested declaration, a property
capability, generics, and a declared supertype each end the question. The test
asks what a struct accepts rather than listing what it refuses, so a suggestion
cannot name a change that fails to compile.

The lint is off until a project asks for it:

```lua
lints = { performance = "note" }
```

### `deprecated`

An API marked `@deprecated` remains valid, but every use points callers toward
the migration. The annotation may carry an optional reason and replacement;
the replacement becomes diagnostic help and both appear on hover.

::: code-group
```nupp [src/deprecated.nupp]
local function current(): integer return 1 end

@deprecated(reason = "kept for compatibility", replacement = "current")
local function legacy(): integer return current() end

return legacy()
```

```text [nupp check output]
src/deprecated.nupp:6:8: warning: NUPP2513 deprecated: legacy is deprecated: kept for compatibility
 6 | return legacy()
   |        ^~~~~~
help: use current instead
```
:::

## Categories

Every lint declares one of four, which is what a project
configures when it wants to move a group of them at once:

- **correctness**: the program is very likely wrong. A project rarely turns
  these off.
- **suspicious**: legal, and probably not meant.
- **style**: it works and reads badly.
- **performance**: the code pays for something it did not have to. The only
  opt-in category: its members default to `off`, and a project asks for them as
  a class. What is being paid for is real; whether it is worth changing depends
  on how hot the code is, which the source does not state, so reported
  unprompted these would fire on code that is not hot and teach their reader to
  silence the category before meeting the case they were written for.
  `nupp lints` lists them whatever their level, which is where they are
  discovered.

A category is a grouping, not a level: the default comes from each lint's own
registry entry, and a category setting in `nupp.lua` moves every member at
once. That is how a project opts into a whole category without listing it.

## Project configuration

In `nupp.lua`:

```lua
return {
   include = { "src" },

   lints = {
      -- by name
      ["missing-require"] = "warning",
      ["exhaustiveness"] = "off",

      -- by category, applied before names, so a name still wins
      style = "off",
   },
}
```

Resolution runs registry default → category setting → name setting → the
`@allow` on the statement. The most specific wins.

## Local suppressions

```nupp
@allow("missing-require")
local doubled = mathutil.double(21)
```

`@allow` takes lint names or codes, applies to the statement it decorates and
nothing beyond it, and reaches any lint at any level. Bare `@allow` silences
every lint on that statement.

It does not reach a type error. Naming one is `NUPP2108`, and the error stands.

## Adding a lint

Two edits. Nothing about the level lives where the lint is raised, so a default
is changed in one place and `nupp lints` cannot drift from what the checker
does.

**1. Declare it** in the `lints.all` registry in `src/nupp/compiler/lints.nupp`:

```nupp
new lints.Lint(
    name = "missing-require", code = "NUPP2120",
    category = "correctness", level = "error",
    summary = "a project module is used without being required"
),
```

- `name`: kebab-case, what a person writes in `@allow` and in `nupp.lua`.
- `code`: the next free `NUPPxxxx`. It survives the name being reconsidered,
  and is what tooling keys on. Add it to the code list in the file's header
  comment too.
- `category`: one of the four declared in `CATEGORIES` beside the registry. A
  category that is not declared there is rejected at load.
- `level`: the default: `note`, `warning` or `error`. Not `off`; a lint
  nobody sees by default is one nobody knows to turn on.
- `summary`: one line, lowercase, no full stop. It is what `nupp lints`
  prints.

`everyLintIsWellFormed` in `tests/allowtest.lua` checks the shape of every
entry, covering name, code, category, level, uniqueness, and that both spellings
resolve, so a misspelled category is a failing test rather than a lint nothing
can configure. It is a test rather than a load-time assertion on purpose: an
assertion in the compiler would brick a build tree over a typo until it was
deleted.

**2. Raise it** wherever the checker already knows enough to say so:

```nupp
diag("missing-require", node, advice)
```

`diag` takes the name or the code. Both reach the same lint, and the reported
diagnostic carries the canonical code either way. Prefer the name at the call
site: it reads as what is being said rather than as a number.

That is the whole of it. The level resolves through the registry, the project's
`lints` table and any surrounding `@allow`; `nupp lints` picks the new row up;
`@allow("your-lint")` works; and `nupp.lua` can move it.

### Editor severity

A lint that a build should refuse but an editor should not shout about, one
whose fix is usually the next thing the author types, gets a row in
`EDITOR_ADVICE` in `src/nupp/compiler/lsp/diagnostics.nupp`:

```nupp
local EDITOR_ADVICE = {["NUPP2120"] = "warning", -- a project module used without requiring it
}
```

The build still enforces the registry level. Only the protocol severity
changes.

### Lint tests

`tests/allowtest.lua` has the harness for level resolution.
`checkOf(src, {lints = ...})` returns the diagnostics with a project
configuration applied, which is how the level, the category override and
`@allow` are covered. A lint that spans files wants
`tests/projectlinktest.lua`'s `withProject`, and one whose editor severity
differs wants an LSP session in `tests/lsptest.lua`.

Assert the `severity` as well as the code. A lint that reports at the wrong
level is a lint that fails the wrong builds.

## Next

- [diagnostics.md](diagnostics.md): what a diagnostic carries, and its families.
- [tooling/lsp.md](tooling/lsp.md): the same lints reported as you type.
