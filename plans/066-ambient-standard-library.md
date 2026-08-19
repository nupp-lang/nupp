# Ambient standard library

Status: superseded by plan 067. Nothing below was built. Written 2026-08-18.
The problem statement describes the tree as of commit `32a33a80`; the options
are designs, none of them built or prototyped.

## Problem

Nupp's standard library has two access disciplines, and which one a facility
gets is decided by the language it happens to be implemented in.

Facilities implemented natively are ambient. `nupp` is a table the prelude
declares, present in every generated module, so `nupp.data.sha256(...)` and
`nupp.io.newBuffer(...)` need no `require` and cost nothing when unreached.

Facilities implemented in Nupp are ordinary modules. `nupp.span`, `nupp.heap`,
`nupp.zone`, `nupp.dynamic`, `nupp.suspension`, `nupp.io.process`,
`nupp.io.http` and the rest are listed in `BUNDLED_SOURCE`
(`src/nupp/compiler/env.nupp:1495`) and reached with `require("nupp.span")`.

Nothing a user cares about distinguishes the two groups. The split is an
implementation detail of the compiler that reached the public API.

### Docs already describe the unified world

`docs/stdlib.md` introduces `nupp` as "an ambient global… so standard
facilities do not need `require`", then lists `nupp.span` among its namespaces
beside `nupp.data` and `nupp.io`. Every actual use is
`local span = require("nupp.span")` — `src/nupp/heap.nupp:11`,
`src/nupp/soa.nupp:12`, `src/nupp/compiler/reference.nupp:1473`, and throughout
`tests/`. The documented surface and the real one disagree today.

### Only existing bridge costs a duplicate declaration

One facility already spans both worlds. `nupp.data.bitset` is installed at
runtime as a lazy require of a Nupp module:

```
__nuppLazy(__nuppData,"bitset",function()return require("nupp._bitset")end)
```

(`src/nupp/compiler/stdlib.nupp:1008`), and typed by a hand-written
`record bitset` in the prelude (`src/nupp/compiler/decls/prelude.d.nupp:1477`).

That second copy is precisely what the bundled-module policy forbids.
`src/nupp/compiler/env.nupp:1490` states it for the modules in
`BUNDLED_SOURCE`: they are "typed already, so there is nothing to declare a
second time: the implementation is the surface, and a project outside this tree
reads exactly the source that went into the binary it is running. A hand-written
`.d.nupp` beside it would be a second copy with nothing holding the two
together."

So the one existing instance of the pattern is paid for by violating the policy
that governs everything around it. Generalizing the pattern as it stands means
generalizing the violation.

### Load-time require produces cycles the checker pays for in `any`

`local span = require("nupp.span")` at a module's top level is a load-time
dependency edge. When those edges close a loop, `envMod.resolveModule` returns
`T.any` for the module reached while `inProgress`
(`src/nupp/compiler/env.nupp:1025`). A silent `any` inside a self-hosted
compiler is a type hole that reports nothing.

The compiler's own layering is shaped around avoiding this.
`src/nupp/compiler/comptime.nupp:1496` records typing a value directly rather
than reaching the parser specifically because doing so "would close a module
cycle".

### Naming rules are shaped by the require path

`docs/modules.md:272` requires module names be luacase — all lowercase, run
together — and gives the reason: "A module name is a filesystem path before it
is an identifier". A case-insensitive filesystem resolves
`nupp.io.processBackend` to `processbackend.nupp` and a case-sensitive one does
not, so a mixed-case module name is a `require` that works on one machine and
fails on the next.

That reasoning is sound for a `require` argument and does not apply to a field
read on an ambient table.

### Consequence

Questions of the form "where does this facility belong" cannot be answered on
their merits, because the namespace a facility sits in and the path used to
load it are currently the same decision. The immediate instance is
`nupp.resources` (`src/nupp/resources.nupp`), whose five exports split into an
ownership container (`Set`, `set`) and three io openers (`openFile`,
`openProcess`, `temporaryFile`); asking whether it should become
`nupp.io.resources` is really asking two unrelated questions at once.

## Constraints

Any solution has to preserve these. They are the reasons the current design is
the way it is, not preferences.

- **No second copy of a module's surface.** The policy at `env.nupp:1490`.
- **Closed shapes stay closed.** `nupp` is a closed record, so a misspelled
  member is `NUPP2004` rather than a silent `any`. A typo must still be an
  error after the change.
- **Laziness in the checker.** `env.bundled` carries a metatable
  (`env.nupp:1577`) that loads a bundled module only when a name asks for it,
  added because eager loading "doubled the wall time of a small [project] for
  modules it never required". Misses memoize as `false`.
- **Laziness at runtime, and feature selection.** An unused facility must
  contribute no generated adapter and no native artifact, and at `-O1` and
  above a facility used only in code DCE removes must not retain either
  (`docs/stdlib.md`).
- **Incremental granularity.** `timing.compiledModules` has to keep meaning
  what it means. A change that makes the invalidation unit larger regresses the
  edit/check loop.
- **Deterministic bundling.** Modules and resources are emitted in sorted order
  (`docs/distribution.md:133`).

## Non-goals

- Deciding where `nupp.resources` lands. That is downstream of this and easier
  once the namespace question is separable from the require path.
- Changing what `nupp.io` currently contains.
- Extending ambient access to a user's own project modules.
- Removing `require` from the language.

## Option A — declare the namespaces in a prelude file

Add every Nupp-implemented namespace to `prelude.d.nupp`, or to a companion
`.d.nupp`, the way `record bitset` is declared today.

Cheapest to build; nothing in the resolver changes. Rejected on the constraint
it breaks: it is the second copy, once per module, maintained by hand, and it
drifts silently the moment an implementation changes without the declaration
following. It also breaks the property that a project outside this tree reads
exactly the source that went into its binary.

## Option B — resolve namespace members through the module loader

Recommended. The checker keeps no declaration for these namespaces; it resolves
`nupp.zone` to the checked type of `src/nupp/zone.nupp` through the same
`env.resolveModule` path that `require` uses.

The mechanism to copy already exists for required modules.
`require("nupp.zone")` tags the call node (`check/callexpr.nupp:904`),
`check/bindings.nupp:274` propagates that onto the bound local's entry as
`requiredModule`, and field access consults it (`check/index.nupp:174`).
`exportedValue()` (`check/index.nupp:217`) resolves an exported nominal through
`c.env.exportedNominal` as a fallback immediately before the `NUPP2004` miss
fires at `check/index.nupp:378`. Types come from `check.check` on the real file
(`env.nupp:1003`).

Three changes:

1. **Tag the ambient root.** The prelude publishes its globals at
   `check/init.nupp:2343`. Give `nupp`'s entry a `namespaceModule = "nupp"`
   marker, the sibling of `requiredModule`.
2. **Propagate on each hop.** A field resolved on a base whose holder carries
   `namespaceModule` yields a result carrying
   `namespaceModule = holder.namespaceModule .. "." .. memberName`.
3. **Resolve at the miss.** Beside the existing `exportedValue()` fallback at
   `check/index.nupp:366`, try
   `env.resolveModule(env, namespaceModule .. "." .. memberName)`. A hit
   returns that module's checked type; a miss falls through to `NUPP2004`
   unchanged.

Precedence is prelude member, then bundled module, then diagnostic. The closed
shape is never opened, so `nupp.zne` still errors with a spelling fix, and a
facility can move between native and Nupp implementations without a call site
changing.

Codegen has a category for this already. The feature registry at
`native.nupp:43` carries `stdlib.bitset` with the comment "Checked Nupp
reached through the ambient namespace. The installer loads the module, so there
is no native host feature and no shared module name." Each namespace key needs
an entry of that shape and one installer line of the `__nuppLazy` form above.
Generate both from `BUNDLED_SOURCE` rather than listing them by hand, so adding
a file is the whole change and the lists cannot drift.

Nesting falls out. `nupp.io.resources` is two hops: the first hits the prelude's
`io` record, the second misses it and resolves the module. One namespace level
can therefore mix native members and Nupp modules — `nupp.io.files` beside
`nupp.io.process` — with neither declared in terms of the other.

**Cost and risk.**

- Cross-module reference becomes a table read rather than an upvalue read.
  After first access `__nuppLazy` drops the loader and `rawset`s the value, so
  it is a plain lookup on a monomorphic table, and a `local zone = nupp.zone`
  at the top of a body recovers the upvalue while keeping demand loading.
  `nupp bc --check` settles this without a quiet machine.
- `native.decorateGlobals` (`native.nupp:192`) stamps feature effects by
  walking paths through the prelude's `byname`/`nestedTypes`, which is what
  keeps `local d = nupp.data` as precise as the full path. A namespace key is
  not in `byname`, so the effect has to be attached to the module type at
  resolution time instead.
- Several sites match module names literally: `check/declare.nupp:1274`
  (`"nupp.resources"`), `check/callexpr.nupp:502` (`"nupp.span"`),
  `check/callexpr.nupp:1484` (`"nupp.dynamic"`). Normalize a namespace path to
  the canonical module name at resolution so these keep matching untouched,
  rather than teaching each one a second spelling.
- A `nupp.` access in a module's top-level initializer can still re-enter a
  module that is `inProgress`. Member-access-time resolution dodges most of the
  cycle problem but not this case, and it should become a diagnostic rather
  than inheriting the silent `T.any` at `env.nupp:1025`.
- `doc/stdlib.nupp` and `lsp/complete.nupp` read the prelude shape and need the
  module list as a second source, or documentation and completion each cover
  half the namespace.

## Option C — single-file semantics

Introduce a transformation that makes a set of files behave as one translation
unit: one shared scope, declaration order irrelevant, mutual reference free.
This is the Go package model, where files within a package share a scope and
only inter-package cycles are forbidden.

What it genuinely buys: the checker sees every declaration in the unit before
checking any body, so mutually recursive types across files resolve rather than
degrading to `any`. That is worth having, and it is worth having as a
checker-side property independent of the rest of this option.

What it does not buy is the elimination of cycles. Top-level initialization
order survives the merge. If one file's top level calls into another's and back,
no statement order in the merged file satisfies both; the merge converts a
diagnosable require cycle into a nil upvalue read, which fails later and more
quietly. Demand-ordered initialization — which `__nuppLazy` already provides —
is what actually resolves that class.

Two constraints it violates as a codegen strategy:

- LuaJIT caps locals and upvalues per function. The bootstrap already fights
  this budget: the `HOT_BASE` comment at `stdlib.nupp:21` exists to recover one
  top-level local. `nupp.compiler` is 187 files.
- If the merged unit is the compilation unit, an edit anywhere in it
  invalidates all of it, and `timing.compiledModules` stops distinguishing a
  one-module edit from a whole-namespace one.

Reasonable as a checker-side declaration-hoisting rule scoped to a namespace —
cycles free within a namespace, still an error across namespaces. Not
reasonable as a physical merge.

## Option D — generate the declarations

A build step reads `BUNDLED_SOURCE` and emits a `.d.nupp` describing each
module's surface, checked in and verified by `nupp fixpoint`.

Bounded drift, and no resolver change. Still a second copy, so a project
outside this tree no longer reads exactly the source that went into its binary;
and it adds a generated artifact to review in every surface-changing diff. Worth
keeping only as a fallback if Option B's resolution hook proves unworkable.

## Option E — status quo, better names

Leave the two disciplines in place and settle namespace questions by moving
files. Costs nothing and fixes nothing; `docs/stdlib.md` stays wrong about
`nupp.span`, and each future facility repeats the decision.

## Open questions

- **Does `require("nupp.zone")` keep working?** Keeping it is cheap and makes
  the change non-breaking, at the cost of two spellings for one thing.
- **Unit of laziness.** Per namespace (`nupp.zone` loads all of zone) or per
  member (`nupp.zone.begin` loads only what it needs)? Native surfaces are
  already per member — selecting UUID does not declare the path, files, process
  or SHA-256 ABI (`docs/stdlib.md`). Per namespace is simpler for Nupp modules
  and is a knowing inconsistency.
- **Naming.** Under Option B a namespace key is an identifier rather than a
  path, so the luacase justification at `docs/modules.md:272` no longer
  applies to it. Whether to relax the rule, and whether the key may differ from
  the filename, should be settled before more names are written under the old
  constraint.
- **Third-party libraries.** Whether a package outside this tree can publish
  into a namespace, or whether ambient access is reserved for the bundled
  standard library.
