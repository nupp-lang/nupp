# Declared modules and qualified namespaces

Status: superseded by plans 068, 069, and 070 before anything below was built.
Written 2026-08-18. The problem statement describes the tree as of commit
`bd1856cd`.

## Decision

Add first-class `module` and `export` declarations. A declared module is a real
source file, a separately checked and generated Lua module, and the sole owner
of its public surface. The compiler reads the headers of mutually dependent
modules before checking their bodies, so declaration order and type-level
cycles do not force authors to arrange or duplicate source.

Keep `require`. A top-level literal call through the unshadowed builtin is a
static dependency the checker understands and ordinary Lua still executes.
Add generic destructuring to `local` and `const` bindings, including aliases and
type-only selections from a statically resolved module. Change plucked named
arguments to use the same braces, while function parameter declarations remain
ordinary names.

Register package namespace roots. An unshadowed qualified path below one of
those roots resolves its longest module prefix and generates one cached
`require` binding in the containing module. `nupp.mem.span.fromCarray(...)` and
`tecs.world.query.each(...)` therefore name real modules without constructing
ambient `nupp` or `tecs` tables. This is a generic package facility; the Nupp
standard library is its first in-tree consumer and Tecs can consume the same
mechanism.

The runtime model has an instantiation phase and an evaluation phase. A module
publishes its stable export table and hoistable immutable declarations before
loading dependencies, then evaluates imports, constants, and top-level work.
Mutually recursive types and functions work. A cycle that needs a top-level
value before it is initialized is a diagnostic, never `any` and never a late
nil read.

## Problem

Nupp currently represents a module through a Lua convention:

```nupp
local span = {}

function span.fromCarray(...)
    -- body
end

return span
```

The checker infers the module name from its path, infers the public value from
the returned table, discovers nominal exports through qualified declarations,
and recognizes literal `require` after the fact. This works for an acyclic
graph, but it makes the language infer several facts the author already knows:
that this file is a module, what it is named, which declarations form its
surface, and which table must retain a stable identity.

The standard library then has a second model. Native facilities are declared in
the large prelude and reached through an ambient `nupp` table, while facilities
implemented in Nupp are real files reached through `require`. Moving a facility
between implementations changes its public access discipline. Generalizing the
ambient table would preserve that accidental model and require a second
declaration of every source module's surface.

Cross-module checking has a correctness hole too. `envMod.resolveModule`
returns `T.any` for a module whose record is `inProgress`. A load cycle therefore
silently erases the very information grouped checking should already possess.
The project header index seeds nominal exports, but it does not yet describe
exported function and value signatures well enough to check a complete strongly
connected component before any body supplies them.

Finally, manual `require` bindings are ceremony when a fully qualified path
already identifies a module unambiguously. Nupp needs this for its standard
library, and Tecs needs it for a large, nested public API. Making either package
an ambient runtime tree would solve the spelling by giving up real module
boundaries, ordinary Lua interoperation, and precise feature selection.

## Constraints

- **One public surface.** A checked source module is its implementation and its
  declaration. No generated or handwritten public `.d.nupp` repeats it.
- **Real modules.** Every file retains its own private scope, module identity,
  generated output, runtime initialization, and incremental cache entry.
- **No hot-path loader.** A resolved module becomes a direct local or upvalue.
  Generated calls do not invoke a loader, proxy, or guard on every access.
- **Lua interoperation.** Raw Lua continues to consume the result with ordinary
  `require("name")`. Dynamic require remains available.
- **No silent cycle hole.** A cycle is checked from headers or diagnosed. It
  never resolves to `any` because work happens to be in progress.
- **Closed namespaces.** A misspelled export or qualified module path is a
  diagnostic with spelling fixes, not an open table read.
- **Demand selection.** A module or native provider not reached by generated
  code is not staged. Effects removed by optimization do not retain it.
- **Incremental granularity.** A body-only edit recompiles its module. A public
  signature edit invalidates its dependents, not every member of a checking
  component merely because they were checked as a group.
- **Deterministic output.** Module discovery, component traversal, generated
  imports, bundles, and resources have stable sorted order.
- **Portable names.** Module path segments remain luacase and continue to match
  their portable filesystem paths. Exported identifiers keep ordinary Nupp
  identifier casing.

## Syntax

### Module declarations

The first non-comment declaration in a declared module names it:

```nupp
module nupp.mem.heap
```

The name is a dotted sequence of luacase path segments. It must agree with the
file's name beneath a configured source root:

```text
src/nupp/mem/heap.nupp  ->  module nupp.mem.heap
```

A disagreement is a diagnostic on the declaration with fixes for either the
source name or the file location. Two source files may not declare the same
module. A declared module has no final module-value `return`; returning from its
top level is an error.

The declaration is semantic rather than a build flag. `check`, `build`, tests,
documentation, and the LSP must assign the same module identity to the file.
The path check prevents a file from meaning something different under another
invocation's include roots.

Legacy return-table modules continue to work during migration. They do not gain
the new cycle guarantees until converted because the compiler cannot assume
their returned value is a stable namespace table.

### Exports

Declarations are private to their module unless marked `export`:

```nupp
module nupp.mem.heap

local function finishArray(...): nil
    -- private
end

export record Array<T>
    readonly count: integer
end

export function allocate<T>(element: ctype<T>, count: integer): Array<T>
    -- body
end

export const DEFAULT_CAPACITY: integer = 16
```

The initial set of exportable declarations is:

- `export function`;
- `export record`, `export interface`, and `export struct`;
- `export type`;
- `export const`; and
- exported annotations and comptime providers wherever their existing
  visibility rules admit them.

An exported nominal binds both its type name and its runtime declaration value
when that declaration has one. An exported type alias is compile-time-only.
Exported functions, nominal declaration values, and constants are immutable
bindings. Mutable named exports and ES-module live binding cells are deferred;
module state initially remains private and is observed or changed through
exported functions.

Member declarations inside an exported nominal keep their current visibility
rules. `export record Array` does not make its private fields public.

### Explicit require bindings

`require` remains the ordinary way to bind a module:

```nupp
const heap = require("nupp.mem.heap")
local replaceable = require("plugin.selected.at.runtime")
```

A literal call through the unshadowed builtin is checked statically. A dynamic
name or a shadowed `require` retains ordinary gradual Lua behavior. `const` is
preferred for a static module because neither the binding nor the resolved
module identity can change; `local` remains available where rebinding is
intentional.

### Binding destructuring

Braces form a shallow named binding pattern on `local` and `const`:

```nupp
const {allocate, Array as HeapArray} = require("nupp.mem.heap")
local {x, y as vertical} = position
```

The right-hand expression is evaluated once. An ordinary pattern then reads
each named field once and binds a snapshot:

```nupp
local temporary = position
local x = temporary.x
local vertical = temporary.y
```

`as` names the local binding. It is deliberately not `:`, which already marks
types and method syntax. A missing field, repeated local, or incompatible
annotation is diagnosed through the same field and assignment rules as the
expanded code.

A static module pattern may select an erased type:

```nupp
const {
    type Span,
    fromCarray as makeSpan,
} = require("nupp.mem.span")
```

`type Span` binds only the exported type. If every selection is type-only, the
statement generates no runtime `require`. A nominal selected without `type`
binds its type and runtime declaration value. A type alias without a runtime
value must be selected with `type`.

Nested patterns, defaults, rest captures, tuple patterns, and destructuring in
function parameter declarations are not part of the first implementation.
They need separate decisions about missing values, evaluation order, and
partial moves of affine fields.

### Braced plucked arguments

Function parameters remain ordinary named declarations:

```nupp
local function draw(x: number, y: number, color: string?): nil
end
```

At a call site, braces pluck fields into named parameter slots:

```nupp
draw({x, y} = position, color = "blue")
```

This means:

```nupp
draw(x = position.x, y = position.y, color = "blue")
```

It preserves the current plucking semantics: the operand is a name or dotted
path, names form an unordered set, shared prefixes are evaluated once where the
current lowering promises it, and the result erases to positional Lua
arguments. A differently named source field uses an ordinary named argument:

```nupp
draw(x = position.horizontal, y = position.vertical, color = "blue")
```

The existing `(x, y) = position` spelling receives a mechanical fix to
`{x, y} = position`, is deprecated for one compatibility release, and is then
removed. Both spellings must not remain permanent alternatives.

## Qualified module namespaces

### Registered roots

A package module index records the declared modules supplied by the project,
its dependencies, and compiler-bundled packages. Each dotted prefix that owns
at least one declared module is a known namespace prefix. The compiler does not
probe the filesystem after an arbitrary failed field read.

Nupp's bundled catalog registers `nupp`. A Tecs package can register `tecs` by
shipping declarations such as:

```nupp
module tecs.world.query
module tecs.storage.archetype
```

Dependency metadata must expose the module header index without loading or
checking every implementation. Registration is therefore explicit package
metadata backed by declared module headers, not an ambient value placed in the
prelude.

### Resolution

When the first name of a dotted expression is unbound and names a registered
root, the checker finds the longest module prefix in the module index:

```nupp
nupp.io.process.new(...)
|-----------------||-|
       module      member

tecs.world.query.each(...)
|--------------||----|
     module      member
```

An exact module path in value position denotes that module's namespace table.
The remaining segments are ordinary checked export reads. In type position,
the remaining segment may name an exported type and generates no runtime work.

A lexical binding always wins:

```nupp
local nupp = makeTestDouble()
nupp.io.process -- ordinary field reads, never module resolution
```

The same canonical module record answers a qualified path and
`require("nupp.io.process")`. Nominal identity, exported definitions, compiler
intrinsics, native feature effects, documentation, references, and completion
therefore do not acquire a second spelling internally.

Unknown paths are closed. `nupp.io.proces` consults known child module names and
exports for a spelling fix, then reports a diagnostic. It never becomes `any`
and never asks the runtime table whether the name happens to exist.

### Generation and laziness

Each distinct qualified module used by one generated module receives one hidden
binding:

```nupp
return nupp.mem.span.fromCarray(pointer, count)
```

generates the equivalent of:

```lua
local __nupp_mem_span = require("nupp.mem.span")
return __nupp_mem_span.fromCarray(pointer, count)
```

Every use shares that local. There is no runtime `nupp` table, loader function,
namespace proxy, or metatable lookup. The generated call has the same hot path
as a handwritten local `require` binding.

Laziness is at module selection and module initialization boundaries:

- a qualified module absent from checked live code is not generated or staged;
- a construct removed before generation does not leave its hidden import or
  feature effect behind; and
- a selected dependency loads once when its containing Lua module initializes,
  following ordinary `require` caching.

Deferring a dependency until the first execution of an arbitrary function body
would require a guard or proxy on that path. This design deliberately does not
do that. A facility needing finer selection gets a narrower module boundary.

## Grouped checking

### Groups are derived, not declared

There is no `group` keyword and no command-line "single file" mode. The compiler
builds the static module dependency graph from declared modules, literal
requires, qualified module paths, exported signatures, and comptime
dependencies. Its strongly connected components are the checking groups.

This is generic across standard-library, project, and dependency modules. It
does not give files a shared lexical scope. A module may see only its own
private declarations and the exports of dependencies it names. Two files in a
component remain two real modules.

### Header phase

The existing project header index expands from nominal declarations to the
complete source-written module interface:

- exported nominal and alias signatures;
- exported function parameter and result signatures;
- exported constant annotations;
- annotations, effects, ownership modes, generics, and comptime facts that are
  part of those signatures; and
- source definitions and documentation needed by diagnostics and the LSP.

Every header is parsed and cached independently. Header construction does not
infer a public signature from a body. An exported function already names its
parameters and results; an exported constant that participates in a cycle must
carry an annotation. An acyclic unannotated constant may be inferred after its
dependencies, but its inferred public fingerprint is then part of invalidation.

The header phase allocates stable nominal identities and export entries for the
whole component before checking any body. A reference can therefore resolve to
the real declaration rather than a placeholder `any`.

### Body phase

Bodies are checked module by module against the component's registered
interfaces. Results fill the same export entries allocated by the header phase.
Private inference remains local to one file.

The scheduler may check independent modules in parallel. Within a component it
chooses a deterministic order for diagnostics, but no answer may depend on that
order. A body-only edit reuses every unchanged header and dependent interface.

`envMod.resolveModule` must return structured states that distinguish absent,
declared, checking, checked, and failed modules. Asking for a module in the same
checking component returns its registered interface. Asking for a runtime value
that has no registered signature reports the cycle at the requesting node. The
current `inProgress and T.any` fallback is removed.

## Runtime instantiation and cycles

### Stable namespace tables

A declared module always owns one compiler-created namespace table. Generated
Lua publishes it before loading dependencies:

```lua
local __exports = {}
package.loaded["nupp.mem.heap"] = __exports
```

The generator does not copy a returned user table into this namespace. Source
exports populate the stable table, and the generated chunk returns that same
identity. Raw Lua `require("nupp.mem.heap")` receives it normally.

Initialization failure must retain Lua's "previous error loading module"
behavior rather than leave a usable partial table. The generated loader or a
small shared runtime wrapper records loading, loaded, and failed states and
rethrows the original failure. Its cost is paid once during module loading.

### Instantiation phase

Before executing dependency loads, generation:

1. creates and publishes the export table;
2. declares locals that imported and exported functions will capture;
3. creates exported function bodies;
4. creates exported nominal declaration values that do not require evaluated
   top-level values; and
5. installs those hoistable immutable exports on the table.

An exported function may close over an import local assigned later. Lua
closures capture the local cell, so this introduces no call-site indirection.

### Evaluation phase

Generation then:

1. executes static dependency `require` calls;
2. binds namespace and named imports;
3. evaluates exported constants and private top-level initializers;
4. executes remaining top-level statements; and
5. marks the module loaded and returns its namespace.

The import itself is one direct local assignment. A function that calls an
imported function calls that local directly.

### Valid cycles

Types are available from headers and generate no runtime edge. Mutually
recursive exported functions are installed during instantiation before either
side evaluates its dependency loads:

```nupp
module example.a
const {callA} = require("example.b")
export function callB(): nil
    callA()
end
```

```nupp
module example.b
const {callB} = require("example.a")
export function callA(): nil
    callB()
end
```

Each named import reads an already installed immutable function and becomes a
direct local. No live binding cell or loader remains on the hot path.

### Invalid cycles

An exported constant is not available until evaluation reaches its initializer:

```nupp
module example.a
const b = require("example.b")
export const value: integer = b.value + 1
```

```nupp
module example.b
const a = require("example.a")
export const value: integer = a.value + 1
```

The checker reports an initialization cycle with the complete path and the
specific reads that require unavailable values. The same applies to a
top-level call through a namespace table or destructuring a non-hoistable value
from a module still being instantiated.

This is the TypeScript/ES-module distinction worth preserving: the graph is
linked before evaluation, but linking cannot invent the result of cyclic
top-level computation. Nupp diagnoses the temporal failure statically rather
than exposing a nil or temporal-dead-zone exception at runtime.

## Standard-library migration

1. Add declared-module syntax and generation while legacy modules still work.
2. Convert one leaf bundled source module, preserving explicit `require`
   consumers and validating raw Lua loading.
3. Move each public source-backed standard-library module to `module` and
   `export` declarations. Remove its returned table boilerplate.
4. Move public native-backed surfaces out of `prelude.d.nupp` into checked Nupp
   facade modules. Private `.d.nupp` files describe only external native ABIs;
   they do not repeat the public surface.
5. Split facades at feature-selection boundaries where loading one broad module
   would retain unrelated native providers.
6. Atomically delete the compiler-owned ambient `nupp` binding and its runtime
   installers, register the `nupp` package root, and enable qualified access.
   Ordinary lexical bindings named `nupp` continue to shadow the registered
   root; the migration never gives the legacy ambient value precedence over a
   qualified module path.
7. Update standard-library documentation and examples to choose explicit
   `require`, destructured require, or qualified namespace access according to
   readability rather than implementation language.

The compiler-bundled module catalog is generated from declared module headers
and embedded source metadata. The environment, feature registry, bootstrap,
documentation, and completion consume that catalog instead of maintaining
parallel module lists.

## Tecs adoption

Tecs is a required external validation of the generic design, not a special
case in Nupp. Its package publishes declared module headers and registers the
`tecs` root. A consumer may then choose any of:

```nupp
const query = require("tecs.world.query")
const {each as eachEntity} = require("tecs.world.query")
tecs.world.query.each(...)
```

All three resolve the same module and exported definitions. Qualified access
generates a hidden direct `require` binding exactly as it does for `nupp`.

Acceptance requires a representative Tecs graph with nested module paths,
mutually referring exported types and functions, explicit require consumers,
qualified namespace consumers, and a raw Lua consumer. Moving that graph from
explicit require to qualified access must not change nominal identity,
generated call shape, initialization order, or packaged module names.

## Tooling

- **Formatter.** Format `module` first, `export` as a declaration modifier,
  multiline binding patterns with trailing commas, and `{x, y} = value`
  plucks. Never rewrite explicit require into qualified access or the reverse.
- **LSP completion.** Complete child module segments from the package index,
  then exported members from the resolved longest module prefix. Respect
  lexical shadowing.
- **Navigation.** Go-to-definition on a module segment opens its declared file;
  an export opens its source declaration. References unify explicit and
  qualified access through canonical module identity.
- **Rename.** Export rename edits imports, aliases where appropriate, qualified
  accesses, and the declaration. Module rename previews the file move and all
  static paths but never rewrites dynamic strings it cannot prove.
- **Diagnostics.** Add fixes for missing `export`, module/path disagreement,
  unknown child modules, unsafe initialization cycles, and old parenthesized
  plucks.
- **Documentation.** Declared modules generate their own pages. Package trees
  come from the module index, not the prelude shape.
- **Inspection.** `lsp inspect`, symbols, definitions, references, and hover
  report both the written spelling and canonical module identity.

## Implementation sequence

### Phase 1 — syntax and headers

- Parse, format, and preserve `module` and `export`.
- Add module declarations and exported value signatures to cached headers.
- Validate module names against source roots and diagnose duplicates.
- Keep legacy returned-table modules unchanged.

### Phase 2 — declared-module checking

- Give a declared module its compiler-owned export scope and namespace table
  type.
- Bind exported declarations into headers and module bodies from one identity.
- Enforce private-by-default visibility and remove the need for `@export` as a
  documentation proxy for module surface.
- Replace in-progress `any` with component-aware resolution and diagnostics.

### Phase 3 — generation and initialization

- Generate stable early-published export tables.
- Split instantiation from evaluation and forward-declare captured imports.
- Hoist exported functions and eligible nominal declarations.
- Detect and report reads of uninitialized exports across components.
- Verify initialization failures cannot expose partial tables.

### Phase 4 — patterns and plucking

- Add shallow `local` and `const` binding patterns with `as` aliases.
- Add `type` selections for statically resolved modules and erase type-only
  imports.
- Change plucked arguments to braces, ship the mechanical fix, and update the
  reference, docs, fixtures, and formatter.
- Do not add destructured parameter declarations.

### Phase 5 — qualified namespaces

- Build registered package namespace indexes from declared headers and
  dependency metadata.
- Resolve the longest known module prefix under an unshadowed root.
- Reuse the literal-require module identity and effect path.
- Generate one hidden direct import per qualified module and only from live
  generated nodes.
- Extend completion, navigation, rename, and spelling fixes.

### Phase 6 — Nupp and Tecs migration

- Convert leaf Nupp modules, then cyclic components, then native facade modules.
- Remove the ambient prelude surface and runtime namespace installers.
- Validate Tecs as an external package using the same declared-header format.
- Update plan statuses and current documentation as each user-visible piece
  lands.

## Verification

- Parser and formatter round trips for every new declaration and pattern.
- Diagnostics for duplicate modules, path mismatches, private exports, unknown
  children, shadowed roots, repeated pattern names, and invalid type selections.
- Checker fixtures for acyclic dependencies, type SCCs, function SCCs,
  annotated constant dependencies, and rejected initialization cycles.
- Runtime fixtures required from generated Nupp and raw Lua, both as modules on
  disk and through `package.preload` bundles.
- Identity tests proving explicit require, destructured require, and qualified
  access reach the same nominal declarations and intrinsic effects.
- Optimization tests proving dead qualified accesses retain no hidden import or
  native feature.
- `nupp bc --check` and generated-source assertions proving a qualified call
  uses a direct module local and contains no per-call loader, proxy, or
  metatable lookup.
- Incremental tests proving body edits recompile one module, interface edits
  invalidate only transitive dependents, and SCC membership alone does not
  widen invalidation.
- Completion, definition, references, rename, hover, and documentation fixtures
  for Nupp and Tecs namespace roots.
- Deterministic bundle and packaging fixpoints.
- Compiler `fixpoint` after compiler sources migrate to declared modules.

## Non-goals

- Removing `require` or changing dynamic Lua require semantics.
- Treating arbitrary dotted table access as a filesystem or package lookup.
- Creating ambient runtime `nupp`, `tecs`, or third-party namespace tables.
- Giving files in one checking component a shared private lexical scope.
- Physically concatenating a component into one Lua chunk.
- Supporting multiple files that contribute private declarations to one logical
  module.
- Live mutable ES-module bindings in the first implementation.
- Making cyclic top-level computation valid.
- General nested, defaulted, rest, tuple, or parameter destructuring.
- Extending qualified namespace access to packages that do not publish declared
  module headers.

## Completion criteria

- Public Nupp facilities are declared in real modules rather than the ambient
  prelude, with no duplicated public declaration files.
- `module` and `export` are the source of module identity and visibility.
- Static `require`, destructured static require, and registered qualified paths
  share one canonical resolver and runtime module.
- Nupp and Tecs qualified paths generate direct cached imports and no ambient
  namespace table.
- Type and function cycles check without source ordering and without `any`.
- Impossible initialization cycles report their complete dependency path.
- Braced call plucking replaces the parenthesized form, and function parameter
  declarations remain ordinary names.
- Declared modules remain separately cached, generated, required, documented,
  and consumable from raw Lua.
- Focused suites, bytecode inspection, incremental checks, deterministic
  packaging, and compiler fixpoint all pass.
