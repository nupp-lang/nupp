# Declared modules and grouped checking

Status: implemented. Recursive interfaces are published through the incremental
query graph rather than a separate Tarjan cache, and closed constants remain in
the evaluation tier. Written 2026-08-18. This replaces the declared-module and
cycle portions of superseded plan 067 and depends on plan 068.

## Decision

Add first-class `module` and `export` declarations. Each declared module is one
real source file with its own private scope, generated Lua chunk, stable export
table, runtime initialization, and incremental cache entry. A module is its
own public declaration; no ambient table or companion `.d.nupp` repeats it.

Keep literal `require` as the explicit Lua-shaped import. Before checking
bodies, build complete interfaces for a strongly connected component of the
static dependency graph. Type and hoisted-function cycles then resolve to real
declarations instead of the current `inProgress` fallback to `any`.

At runtime, instantiate stable export tables and hoist eligible immutable
exports before evaluating dependencies. Reject a cycle that reads an export
before its initialization tier makes it available.

Qualified paths such as `nupp.mem.span.fromCarray` are deliberately not part of
this plan. Plan 070 adds that generic convenience after declared module
identity, interfaces, and initialization are real.

## Module declarations

The first non-comment declaration names the module:

```nupp
module nupp.mem.heap
```

The name is a dotted sequence of luacase path segments. It must equal the
canonical module name computed by the existing source-root rules:

- `.nupp` and `.g.nupp` are source modules; the `.g` strictness marker is not
  part of the name;
- project `.d.nupp` files cannot declare source modules;
- a final `/init` is erased, so `src/nupp/io/init.nupp` declares
  `module nupp.io`;
- every configured source root is considered; and
- when a path lies under multiple roots, the shortest resulting dotted name is
  canonical, matching `envMod.moduleNameInRoots`.

The declaration must match that canonical shortest name, not merely one
possible root-relative alias. A diagnostic shows the canonical name and offers
either a declaration edit or a file move. Static `require` also accepts only
the canonical name. This prevents one file from loading under two keys.

Installed dependency `.d.nupp` surfaces remain a legacy external-interface
format. They can describe a Lua module beneath a dependency type root, but
they are not source declared modules and do not acquire the cycle guarantees
until their package publishes declared headers.

Two files may not declare the same canonical module. A package root may also
be a module: `src/nupp/init.nupp` may declare `module nupp` while
`nupp.mem.span` exists. The root's own exports are read from the exact module;
children remain separate modules. Plan 070 adds the registration collision
rules needed for qualified traversal.

A declared module has no final module-value `return`. A top-level return is a
diagnostic. Legacy return-table modules remain valid during migration but do
not gain declared-module cycle behavior.

## Export declarations

Declarations are private unless marked `export`:

```nupp
module nupp.mem.heap

local function finishArray(...): nil
end

export record Array<T>
    readonly count: integer
end

export function allocate<T>(element: ctype<T>, count: integer): Array<T>
end

export const DEFAULT_CAPACITY: integer = 16
```

The initial exportable declarations are functions, records, interfaces,
structs, type aliases, constants, annotations, and comptime providers wherever
their existing phase rules admit them. An exported nominal binds its type and,
when it has one, its runtime declaration value. An exported alias is erased.

Mutable named export cells are deferred. State stays private and is accessed
through exported functions. Exported functions, nominal declaration values,
and constants are immutable module bindings.

`global` is illegal inside a declared module. It remains available to legacy
project files and declarations that intentionally contribute a project-wide
name, but it cannot silently escape a module whose surface is otherwise
explicit. The diagnostic replaces `global` with `export` when the declaration
can be exported, or asks the author to move the legacy global outside the
declared module.

Member visibility inside an exported nominal is unchanged. Exporting a record
does not export its private fields.

## Explicit require and named selection

`require` remains ordinary Lua-shaped source:

```nupp
const heap = require("nupp.mem.heap")
local plugin = require(selectedAtRuntime)
```

A literal call through the unshadowed builtin is a static dependency and
resolves a declared interface. A dynamic name or shadowed `require` preserves
the current gradual Lua behavior. `const` is preferred for a static module;
`local` remains legal.

If plan 068 is implemented, its brace pattern selects runtime exports without
special syntax:

```nupp
const {allocate, Array as HeapArrayValue} = require("nupp.mem.heap")
```

Declared modules extend that pattern with module-only erased selections:

```nupp
const {
    type Array as HeapArray,
    allocate as makeArray,
} = require("nupp.mem.heap")
```

`type` selects only an exported type and generates no field read. A statement
containing only type selections generates no `require`. Selecting a nominal
without `type` binds both its type and runtime declaration value; an erased
alias requires `type`.

An exported comptime function or provider is not a type selection. It is
selected as an ordinary named export whose phase metadata comes from the
module interface. The binding may be called only in a comptime context and is
erased when it has no runtime representation. The static dependency is still
recorded for checking, cache invalidation, and provider materialization.

## Two interface cache tiers

The word "header" must not widen the existing parser-only cache boundary. The
implementation has two named tiers.

### Syntactic source header

The syntactic header is extracted independently per file and depends only on
source text, lexer/parser/CST format, and the narrow header schema. It records:

- the raw module declaration and source location;
- raw exported declaration shapes and written signatures;
- import strings and dependency-bearing syntax visible without checking;
- documentation and definition locations; and
- enough stable syntax to elaborate the interface later.

It does not resolve types, compute effects, allocate final nominal identities,
or run comptime. The current parser-only cache stamp remains narrow so an
unrelated checker edit does not discard every source header.

### Elaborated module interface

The checker elaborates syntactic headers into typed interfaces. This tier
contains exported parameter and result types, constant types, nominal
identities, generics, effects, ownership modes, phase/comptime facts,
annotations, and dependency edges.

For an acyclic module, its key includes the syntactic-header digest, dependency
interface fingerprints, target/configuration facts, and the checker/interface
schema. An SCC instead has one elaboration key containing the sorted member
header digests and only its external dependency fingerprints; internal edges
cannot form recursive cache keys. The component may reach a deterministic
fixpoint, then emits a separate interface and fingerprint for each module.

A body-only edit reuses the interfaces. A public header edit re-elaborates its
component, but only module fingerprints that actually change invalidate
transitive dependents or their bodies. Group membership may widen interface
elaboration work; it does not by itself widen body recompilation.

Public interfaces come from source-written declarations, not body inference.
Exported functions must write their public parameter and result types. An
exported constant involved in a component cycle must have an annotation.
Acyclic unannotated constants may retain current inference only if the inferred
type is stored in the elaborated fingerprint and invalidates dependents.

Body checking is a third, module-local cache tier. It consumes elaborated
interfaces, infers private declarations, and fills generation data without
changing the identities allocated for exports.

## Grouped checking

There is no `group` keyword and no "pretend these files are one file" mode.
The compiler derives the static graph from module interfaces, literal requires,
type references, annotations, and comptime provider dependencies. Its strongly
connected components are checking groups.

Files in a group do not share lexical scope. A body sees only its private
declarations and exports of dependencies it names. Every module remains
separately checked, generated, cached, documented, and loadable by Lua.

For a component, interface elaboration allocates all stable nominal and export
entries before any body is checked. Bodies then check in deterministic order
against those entries. Independent components or modules may run in parallel.

`envMod.resolveModule` replaces the current `inProgress -> any` escape with
explicit absent, declared, elaborating, checking, checked, and failed states.
A request within the active component returns the registered interface. A
request for a value with no written interface or unavailable initialization
tier reports a diagnostic at the read.

## Instantiation and evaluation

Every declared module owns one compiler-created export table. Generated Lua
publishes it under the canonical module key before loading dependencies:

```lua
local __exports = {}
__nupp_begin_module("nupp.mem.heap", __exports)
```

The wrapper is required because overwriting `package.loaded[name]` early would
bypass Lua's own loop sentinel and "previous error loading module" behavior.
It records loading, loaded, and failed states, removes or poisons partial state
on failure, and rethrows the original error. The cost occurs once per module
load, never per exported call.

Only the canonical module identity may be published, registered in
`package.preload`, or used by a static require. Alternate root-relative names
and bundle aliases are rejected during resolution or packaging. A dynamic Lua
require remains Lua's responsibility, but the compiler never emits a second
key that could create a second export table.

### Instantiation tier

Before dependency loads, generation:

1. creates and publishes the stable export table;
2. declares locals captured by exports and imports;
3. creates exported function closures;
4. creates eligible nominal declaration values; and
5. installs those immutable exports.

An `export const` also belongs to instantiation when its initializer is a
closed constant expression accepted by the existing constant evaluator and
the generator can reify its result without a runtime module read. A referenced
export qualifies only when its canonical constant value is present in the
elaborated interface and can be embedded directly; instantiation never calls
`require` merely to fold a constant. Eligibility and the canonical value are
part of the interface fingerprint. The initializer is emitted once; this is
not a general cross-module optimizer. `export const VERSION = "1.0"` is
therefore available to a benign cycle, while a constant containing a call or
evaluated module read is not.

### Evaluation tier

Generation then:

1. executes static dependency requires;
2. binds namespace, named, and comptime imports;
3. evaluates non-hoistable exported constants and private initializers;
4. executes remaining top-level statements; and
5. marks the module loaded and returns its stable table.

Functions may capture import locals assigned during evaluation. Lua closes
over their cells, so calls use direct locals after initialization and need no
loader or live-binding proxy.

## Cycle rules

Type references generate no runtime read. Exported functions and eligible
nominal or constant values are available once their module is instantiated.
Thus mutually recursive exported types and functions work even when each side
uses a named require binding.

A cycle is invalid when top-level evaluation reads an export not installed in
the dependency's instantiation tier. Examples include computed constants that
depend on one another and a top-level call through a dependency whose imports
are not initialized. The checker reports:

- the complete module cycle;
- the exact export reads that require evaluation;
- each export's initialization tier; and
- a fix when moving work behind an exported function or making a genuinely
  closed constant is sufficient.

This is eager module evaluation, not eager function execution. The graph is
linked and hoistable declarations exist before dependencies evaluate, but the
compiler cannot invent the result of cyclic top-level computation. Nupp
diagnoses that temporal failure instead of allowing a nil read.

## Nominal identity rule

For a newly declared module, the canonical identity of an exported nominal is
`<canonical module>.<export name>`, for example
`example.geometry.Point`. Explicit require, named selection, reflection,
documentation, and later qualified access all share that identity.

Converting legacy qualified declarations such as `span.Span` may therefore be
a migration with compatibility consequences. Plan 070 owns the standard
library identity map, reflection-schema transition, and documentation changes;
this plan must not bulk-convert those modules without that migration.

## Bootstrap sequence

`bootstrap/nupp.lua` is a checked-in stage-0 compiler, so compiler source must
not adopt syntax it cannot parse. Implementation is staged explicitly:

1. Add parser, CST, formatter, syntactic-header, and legacy-compatible checker
   support without converting compiler source.
2. Rebuild and commit `bootstrap/nupp.lua` with a compiler that understands the
   new syntax while still accepting all legacy return-table modules.
3. Verify both the previous bootstrap path and the new current compiler build
   the unchanged legacy source and produce the same accepted behavior.
4. Land interface elaboration, grouped checking, and generation while source
   remains predominantly legacy.
5. Convert one leaf module and verify the stage-0 fallback, current compiler,
   package loader, and raw Lua consumer.
6. Only after that bootstrap is on the branch may compiler components migrate,
   one SCC at a time.

During the skew window the new bootstrap accepts both models; no source file is
converted before every supported entry point parses it. Each compiler-source
migration ends with `fixpoint`.

## Tooling

- Formatter keeps `module` first and treats `export` as a declaration modifier.
- Completion and hover expose only exported members across a module boundary.
- Definition and references unify declaration, explicit require field reads,
  and named selections through canonical export identity.
- Rename of a module previews its file move and static strings; dynamic strings
  it cannot prove are reported but not rewritten.
- Documentation pages and package indexes come from elaborated interfaces.
- Diagnostics cover path disagreement, duplicate modules, illegal `global`,
  private reads, invalid `type` selection, and initialization cycles.
- Incremental timing reports distinguish syntactic-header reuse, interface
  elaboration, and body compilation.

## Implementation sequence

1. Parse and format `module` and `export`; add parser-only syntactic headers.
2. Enforce canonical path rules, duplicate names, private-by-default exports,
   and the declared-module ban on `global`.
3. Roll the syntax-capable compiler into bootstrap before source conversion.
4. Add separately stamped elaborated interfaces and SCC scheduling.
5. Remove `inProgress -> any` and check bodies against registered interfaces.
6. Generate canonical stable tables, load-state wrapping, and the two runtime
   initialization tiers, including eligible constant exports.
7. Add module-only `type` selection to plan 068's binding pattern and preserve
   phase metadata for comptime exports.
8. Convert a leaf module and then representative type/function SCCs. Defer the
   standard-library-wide conversion to plan 070.

## Verification

- Parser and formatter round trips for module/export declarations in `.nupp`,
  `.g.nupp`, and `/init.nupp` files.
- Path fixtures for overlapping roots, shortest canonical names, forbidden
  project `.d.nupp`, duplicate declarations, and rejected static aliases.
- Diagnostics for `global` in a declared module and private export reads.
- Cache tests proving parser-only headers survive checker changes, interfaces
  have their own stamps, body edits compile one module, and interface edits
  invalidate only transitive dependents.
- Checker fixtures for acyclic graphs, type SCCs, function SCCs, comptime
  dependencies, hoisted constant cycles, and rejected evaluation cycles.
- Runtime fixtures through disk `require`, `package.preload`, and raw Lua,
  including failure and retry behavior without exposed partial tables.
- Identity tests proving explicit namespace require and named selection share
  the same exported nominal and definition.
- Bootstrap tests at every migration gate and compiler `fixpoint` after any
  compiler-source conversion.
- Deterministic interface, bundle, and generated-output fixpoints.

## Non-goals

- Qualified package namespaces or ambient `nupp` removal; see plan 070.
- Sharing private lexical scope between files in one SCC.
- Concatenating a checking group into one Lua chunk.
- Multiple source files contributing to one logical module.
- Mutable live export bindings.
- Making cyclic top-level computation valid.
- Inferring exported function signatures from bodies.
- Treating arbitrary dynamic require strings as declared dependencies.

## Completion criteria

- A source file can declare its canonical module and explicit exports without a
  return-table namespace or companion public declaration.
- Literal require and named selection resolve the same typed interface and real
  Lua module.
- Type, function, and eligible constant cycles check without order dependence
  or `any`; invalid evaluation cycles explain the whole path.
- Syntactic headers, elaborated interfaces, and bodies retain separate cache
  boundaries and invalidation granularity.
- Generated modules publish exactly one canonical stable table and preserve
  Lua failure semantics through the load wrapper.
- The bootstrap understands the syntax before compiler source uses it.
- Every module remains independently generated, cached, required, documented,
  and consumable from raw Lua.
