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

## Levels

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

## Naming

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
```

The name is what you write in configuration and suppressions; the code is what
survives renaming and what tooling keys on. Either is accepted everywhere.

`nupp lints` prints each lint's name, category, effective level and summary,
marking any the project has moved. The text table has no code column;
`nupp lints --json` carries `code`, `default` and `moved` as well.

`lossy-narrowing` is checked only under `--strict`; moving its level does not
enable strict checking by itself.

## Every lint

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

## Categories

- **correctness** — the program is very likely wrong. A project rarely turns
  these off.
- **suspicious** — legal, and probably not meant.
- **style** — it works and reads badly.
- **pedantic** — opinions a project may not share. No lint is in this category
  yet, so setting it currently moves nothing.

A category is a grouping, not a level: the default comes from each lint's own
registry entry, and a category setting in `nupp.lua` moves every member at
once. That is how a project opts into a whole category without listing it.

## Configuring a project

In `nupp.lua`:

```lua
return {
   include = { "src" },
   strict = true, -- also used by the language server

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

**1. Declare it** in the `lints.all` registry in `src/nupp/lints.nupp`:

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

### Optionally, quieter in an editor

A lint that a build should refuse but an editor should not shout about — one
whose fix is usually the next thing the author types — gets a row in
`EDITOR_ADVICE` in `src/nupp/lsp/diagnostics.nupp`:

```nupp
local EDITOR_ADVICE = {
    ["NUPP2120"] = "warning", -- a project module used without requiring it
}
```

The build still enforces the registry level. Only the protocol severity
changes.

### Testing one

`tests/allowtest.lua` has the harness for level resolution — `checkOf(src,
{lints = ...})` returns the diagnostics with a project configuration applied,
which is how the level, the category override and `@allow` are covered. A lint
that spans files wants `tests/projectlinktest.lua`'s `withProject`, and one
whose editor severity differs wants an LSP session in `tests/lsptest.lua`.

Assert the `severity` as well as the code. A lint that reports at the wrong
level is a lint that fails the wrong builds.
