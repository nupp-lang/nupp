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
 enum-exhaustiveness      NUPP2107   correctness   warning
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

Two of these need a footnote. `lossy-narrowing` is only reachable under
`--strict`, which is what enables the check that raises it, so its level does
nothing on its own. `jit-callback` is registered but is not currently raised
anywhere in the checker; it holds its name and code for the trace work.

## undocumented-raise

Raising is part of how a function is called. A caller who does not know has no
reason to be ready, and in Lua there is no signature to find it out from, so the
`---` run is where it has to be said:

```nupp
--- Reads a configuration file.
---
--- @param path where to read from
--- @return the parsed table
--- @raises when the file cannot be read
function config.load(path: string): table
    local f = io.open(path)
    if not f then error("no such file: " .. path) end
    ...
end
```

Three rules are worth stating, because none of them follows from the summary:

- **Only a documented function is judged.** One with no `---` run has promised
  nothing, and a lint that asked every function in a gradually typed language
  for a docblock would be a different lint with a different name.
- **`error` counts and `assert` does not.** There is no reason to write `error`
  except to raise. Lua writes `assert` both for a caller who passed the wrong
  thing and for an invariant its author believes cannot fail, and the call does
  not say which; reading the second as a documented raise would ask for a
  promise about something that never happens.
- **A nested function's raises are its own.** The walk stops where a new body
  begins, which is also what keeps a function that hands a raising body to
  `pcall` from being asked to document a raise it catches.

The lint judges a function's own body and does not propagate through calls.
Documenting what a callee raises is a claim the checker cannot verify, and
enforcing it at every intermediate frame is the trade that made `throws
Exception` ubiquitous in Java. What a caller needs instead is one hop of
retrieval: `nupp lsp inspect` on the call shows the callee's `@raises` at the
point the decision is being made.

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
      ["enum-exhaustiveness"] = "off",

      -- by category, applied before names, so a name still wins
      pedantic = "warning",
      style = "off",
   },
}
```

Resolution runs registry default → category setting → name setting → the
`@allow` on the statement. The most specific wins.

## Suppressing one place

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
lints.Lint{
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

### Why they are raised inline

Lints are raised during checking rather than by a separate pass, because the
type information they need is already in hand there. That is a deliberate
divergence from Clippy, which runs its lints over HIR afterwards: re-walking a
checked tree would mean re-deriving what the checker already knows, and the
incremental engine would have to invalidate both.

The cost is that a lint cannot be added without touching the checker, so this
is not an extension point for users.
