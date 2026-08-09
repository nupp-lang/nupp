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

## Severity levels

```
 level     reported   build     @allow    editor
 ────────  ─────────  ────────  ────────  ──────────────
 off       no         —         —         —
 note      yes        continues yes       Information (3)
 warning   yes        continues yes       Warning (2)
 error     yes        FAILS     yes       Error (1)
```

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

```
 name                     code       category      default
 ───────────────────────  ─────────  ────────────  ───────
 missing-require          NUPP2120   correctness   error
 exhaustiveness           NUPP2107   correctness   warning
 string-pointer           NUPP2501   suspicious    warning
 jit-callback             NUPP2502   suspicious    warning
 lossy-narrowing          NUPP2503   suspicious    warning
 customary-operator       NUPP2504   style         warning
 loop-invariant-closure   NUPP2505   suspicious    warning
 undocumented-raise       NUPP2506   suspicious    warning
 unused-binding           NUPP2507   suspicious    warning
 discarded-result         NUPP2508   suspicious    warning
 reifiable-record         NUPP2509   performance   off
 else-if                  NUPP2510   style         warning
```

The name is what you write in configuration and suppressions; the code is what
survives renaming and what tooling keys on. Either is accepted everywhere.

`nupp lints` prints each lint's name, category, effective level and summary,
marking any the project has moved. The text table has no code column;
`nupp lints --json` carries `code`, `default` and `moved` as well.

`lossy-narrowing` is checked only in a strict file — a `.nupp` one, or any file
under `--strict`. Moving its level does not raise a file's floor by itself.

## Built-in lints

These outputs were captured from `nupp check --no-color`; the
`lossy-narrowing` example also uses `--strict`.

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
    if color == "red" then return "red" end
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

An `unsafe` cast may create a C callback, but the callback remains registered
and prevents compilation through that call path.

::: code-group
```nupp [src/jit-callback.nupp]
unsafe do
    local callback = function() end
    local pointer = ffi.cast<voidptr>(callback)
    local handle = pin(pointer, callback)
end
```

```text [nupp check output]
src/jit-callback.nupp:3:21: warning: NUPP2502 jit-callback: a Lua function cast to a C callback stays registered and cannot be compiled through
 3 |     local pointer = ffi.cast<voidptr>(callback)
   |                     ^~~
help: keep the callback off hot paths, or call C with a plain pointer instead
```
:::

### `lossy-narrowing`

Strict checking asks for an explicit cast when a value may not fit the narrower
integer type.

::: code-group
```nupp [src/lossy-narrowing.nupp]
local value: number = 5
local narrow: int32 = value
```

```text [nupp check --strict output]
src/lossy-narrowing.nupp:2:23: warning: NUPP2503 lossy-narrowing: number does not fit every int32; cast if the narrowing is intended
 2 | local narrow: int32 = value
   |                       ^~~~~
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

### `loop-invariant-closure`

A loop should not allocate the same non-capturing function on every iteration.

::: code-group
```nupp [src/loop-invariant-closure.nupp]
for _, item in ipairs(items) do
    register(item, function(event) return event.kind == "click" end)
end
```

```text [nupp check output]
src/loop-invariant-closure.nupp:2:28: warning: NUPP2505 loop-invariant-closure: this function is built once per iteration but does not use the iteration, so every one of them is the same function
 2 |     register(item, function(event) return event.kind == "click" end)
   |                            ^
help: declare it once above the loop and pass the name
```
:::

### `undocumented-raise`

A documented function that calls `error` must say when it raises.

::: code-group
```nupp [src/undocumented-raise.nupp]
--- Reads a file.
--- @param path where to read from
local function load(path: string): string
    if path == "" then error("no path") end
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
cannot see is answered by its effect summary, which is file-local — a callee
that reaches another module, or makes an unresolved call, widens to `top` and is
left alone. Whether it writes is answered separately and syntactically, because
a summary treats a write through a non-parameter local as staying local, and a
local read out of a parameter is not scratch. See
[effects](effects.md#calls-and-fixed-point-propagation).

Reads and allocation are not reasons to call: reading state and dropping the
answer is the mistake being described. Writes, shape and metatable changes,
escapes, declared callees, yielding and raising all are. A function returning
nothing — including one returning only `nil` — discards nothing and is not
judged.

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

```
 what                          on a record        on a struct
 ────────────────────────────  ─────────────────  ──────────────────────────
 type(v)                       "table"            "cdata"
 pairs(v)                      iterates fields    needs a __pairs metamethod
 string.buffer.encode(v)       encodes            raises, and takes no hook
 a table-walking serializer    works              sees no keys
```

`__pairs` is dispatched on a `ffi.metatype`, so iteration can be restored by
declaring one. Serialization cannot be patched the same way — LuaJIT's
serializer refuses cdata outright with no extension point — so a struct that
has to cross a serialization boundary needs a conversion written for it.

[`NUPP2201`](diagnostics.md) is the other half of the pair — it fires once
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

## Categories

- **correctness** — the program is very likely wrong. A project rarely turns
  these off.
- **suspicious** — legal, and probably not meant.
- **style** — it works and reads badly.
- **performance** — a declaration is paying for something it does not use. The
  only opt-in category: its members default to `off`, and a project asks for
  them as a class. Whether a faster declaration is worth having depends on how
  many values are built and where, which no declaration states, so reported
  unprompted these would fire on code that is not hot and teach their reader to
  silence the category before meeting the case they were written for. `nupp
  lints` lists them whatever their level, which is where they are discovered.
- **pedantic** — opinions a project may not share. No lint is in this category
  yet, so setting it currently moves nothing.

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
      pedantic = "warning",
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

**1. Declare it** in the `lints.all` registry in `src/compiler/lints.nupp`:

```nupp
new lints.Lint {
    name = "missing-require", code = "NUPP2120",
    category = "correctness", level = "error",
    summary = "a project module is used without being required",
},
```

- `name` — kebab-case, what a person writes in `@allow` and in `nupp.lua`.
- `code` — the next free `NUPPxxxx`. It survives the name being reconsidered,
  and is what tooling keys on. Add it to the code list in the file's header
  comment too.
- `category` — one of the four declared in `CATEGORIES` beside the registry. A
  category that is not declared there is rejected at load.
- `level` — the default: `note`, `warning` or `error`. Not `off`; a lint
  nobody sees by default is one nobody knows to turn on.
- `summary` — one line, lowercase, no full stop. It is what `nupp lints`
  prints.

`everyLintIsWellFormed` in `tests/allowtest.lua` checks the shape of every
entry — name, code, category, level, uniqueness, and that both spellings
resolve — so a misspelled category is a failing test rather than a lint nothing
can configure. It is a test rather than a load-time assertion on purpose: an
assertion in the compiler would brick a build tree over a typo until it was
deleted.

**2. Raise it** wherever the checker already knows enough to say so:

```nupp
diag("missing-require", node, advice)
```

`diag` takes the name or the code — both reach the same lint, and the reported
diagnostic carries the canonical code either way. Prefer the name at the call
site: it reads as what is being said rather than as a number.

That is the whole of it. The level resolves through the registry, the project's
`lints` table and any surrounding `@allow`; `nupp lints` picks the new row up;
`@allow("your-lint")` works; and `nupp.lua` can move it.

### Editor severity

A lint that a build should refuse but an editor should not shout about — one
whose fix is usually the next thing the author types — gets a row in
`EDITOR_ADVICE` in `src/compiler/lsp/diagnostics.nupp`:

```nupp
local EDITOR_ADVICE = {
    ["NUPP2120"] = "warning", -- a project module used without requiring it
}
```

The build still enforces the registry level. Only the protocol severity
changes.

### Lint tests

`tests/allowtest.lua` has the harness for level resolution — `checkOf(src,
{lints = ...})` returns the diagnostics with a project configuration applied,
which is how the level, the category override and `@allow` are covered. A lint
that spans files wants `tests/projectlinktest.lua`'s `withProject`, and one
whose editor severity differs wants an LSP session in `tests/lsptest.lua`.

Assert the `severity` as well as the code. A lint that reports at the wrong
level is a lint that fails the wrong builds.
