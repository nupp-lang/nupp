# Qualified module namespaces

Status: proposed — nothing below exists. Written 2026-08-18. This replaces the
qualified-namespace and package-migration portions of superseded plan 067 and
depends on declared modules from plan 069.

## Decision

Let packages register roots whose descendants are real declared modules. An
unshadowed qualified path resolves its longest canonical module prefix and
generates one hidden direct `require` binding per containing module:

```nupp
nupp.mem.span.fromCarray(pointer, count)
tecs.world.query.each(...)
```

There is no runtime `nupp` or `tecs` namespace tree. Laziness means a qualified
module is selected, generated, staged, and initialized only when live checked
code reaches it. Once selected, its hidden `require` runs when the containing
Lua module initializes. Arbitrary first-call laziness would need a guard on the
hot path and is not part of the design.

This is a generic package facility. Nupp is the first in-tree migration and
Tecs is the required external validation.

## Registered roots and canonical modules

Projects, dependencies, and compiler-bundled packages publish declared module
headers plus package metadata. Every dotted prefix with at least one module is
a closed namespace prefix. The compiler never probes the filesystem after an
arbitrary failed field read.

A root may also be an exact module. `module nupp` can own the root's direct
exports while `module nupp.mem.span` is a child. The expression `nupp` denotes
the exact module when a value is required; `nupp.mem.span` selects the child
module. A pure namespace prefix has no standalone runtime value.

Only plan 069's canonical module names enter the index. Alternate names from
overlapping roots, `/init` paths, bundle aliases, or differently registered
`package.preload` keys are rejected. Qualified access and explicit require
therefore cannot instantiate two export tables for one file.

Registration rejects an export/child collision. If `module nupp.io` exports
`process`, then `module nupp.io.process` cannot also exist. The diagnostic is
reported while building the index and points to both the export and child
module declaration; longest-prefix lookup must never silently shadow an
export. The rule covers runtime values, types, comptime exports, and annotations
because each would be ambiguous in at least one language phase.

## Resolution

For an ordinary dotted expression whose first name is lexically unbound and is
a registered root, resolve the longest module prefix. Remaining segments are
closed exported member reads:

```text
nupp.io.process.new(...)
|-------------||-|
    module     export
```

An exact module path in value position denotes its stable export table. In type
position, a remaining segment may name an exported type and generates no
runtime import. Unknown children and exports receive spelling diagnostics
using the module index; they never fall back to `any` or an ambient table.

A lexical binding wins for ordinary access:

```nupp
local nupp = makeTestDouble()
nupp.io.process -- ordinary field reads
```

Explicit require, binding-pattern selection, and qualified access reuse the
same canonical module and export records. Definition, references, effects,
nominal identity, documentation, and completion therefore have one internal
identity regardless of source spelling.

## Compiler-owned `nupp` surface and precedence

The current `nupp` spelling contains language operations that are not real Lua
exports. Removing the ambient table must not feed them into ordinary
longest-prefix lookup.

Resolution order is explicit:

1. The checker recognizes an unshadowed, exact language-intrinsic spelling in
   the syntactic position where that intrinsic is legal.
2. It resolves compiler-owned comptime namespace entries with their phase and
   capability rules.
3. It resolves declared modules and their exports under the registered root.
4. If the root is lexically bound, ordinary lexical field access replaces all
   three steps. Bare ownership-intrinsic spellings retain their existing,
   independent shadowing rules.

The ownership intrinsics `nupp.pin`, `nupp.borrow`, `nupp.borrowFrom`,
`nupp.region`, `nupp.partition`, and `nupp.attemptAll` remain compiler syntax.
They resolve before module paths and are not fake exports. Existing bare forms
and shadowing behavior remain exactly as defined by
`cst.ownershipIntrinsicSpelling`; namespace registration does not broaden or
narrow them. Their names are reserved against child modules or root exports.

`nupp.sizeof`, `nupp.alignof`, `nupp.offsetof`, `nupp.types`, and other
compiler-materialized type/layout operations are compiler-owned comptime
namespace entries. Their signatures include a `comptime-only` phase, they
generate no runtime `require`, and their names are also reserved against
declared modules or exports. This is a closed compiler namespace overlay, not
an ambient runtime record.

Source-backed comptime APIs should become real modules where their behavior can
be expressed by declared interfaces. In particular, migrate `nupp.derive` from
`src/nupp/derive.nupp` to a declared module and keep its sealed materializer
hooks attached to canonical exports. `nupp.reflect` is different: today it is a
callable compiler operation and a compiler-materialized namespace, not a
source module. It remains a reserved compiler entry, including
`nupp.reflect(T)`, its descriptor types, and `fieldCodec`, until a separate
design can express that callable-namespace shape as a real module without
weakening its comptime checks.

An exported comptime function is selected like any other export, retains its
phase metadata, and erases at runtime when it has no runtime representation.
Plan 069's named module selection and qualified access both support it; `type`
is not used for functions.

The registry has one duplicate-name check spanning compiler entries, exact
modules, child module segments, and parent exports. A collision is diagnosed
at registration, never selected by an undocumented precedence accident.

## Generation and performance

Each distinct qualified module used by one generated module gets one hidden
binding. This source:

```nupp
return nupp.mem.span.fromCarray(pointer, count)
```

generates the equivalent of:

```lua
local __nupp_mem_span = require("nupp.mem.span")
return __nupp_mem_span.fromCarray(pointer, count)
```

Every access reuses the local. The import is generated from the same live IR
and feature-effect path as an explicit static require. Dead code leaves no
hidden binding, staged module, native provider, or resource.

This is a positive hot-path improvement over today's ambient native access.
The representative LuaJIT call shape changes from:

```text
GGET nupp; TGETS data; TGETS sha256; MOV; CALLT
```

to the hidden-import shape:

```text
UGET module; TGETS sha256; MOV; CALLT
```

Acceptance must assert the direct local/upvalue read and fewer dynamic lookup
instructions, not merely the absence of a loader. No generated call may invoke
a require helper, lazy proxy, metatable guard, or feature loader per access.

## Laziness and initialization

Qualified access is lazy at compilation and module initialization boundaries:

- an unreachable module is absent from generated imports and packaging;
- optimization that removes the last access removes its module and feature
  effects;
- a selected module loads once when its containing Lua module evaluates its
  hidden require; and
- Lua's canonical require cache owns all later reuse.

It is not lazy on every nested field access. A function containing a live
qualified reference normally causes its containing module's hidden require at
module initialization, just as a handwritten top-level `const m = require(...)`
does. Finer runtime selection is achieved by a narrower module boundary or an
explicit dynamic require.

Cycles use plan 069's instantiation/evaluation rules. A qualified dependency
adds the same static edge and reads the same initialization tier as an explicit
require. The convenience spelling cannot legalize a cycle that explicit
require would reject.

## Standard-library nominal identity migration

Declared exported nominals use the fully qualified canonical module spelling.
After conversion, `Span` in `module nupp.mem.span` is identified as
`nupp.mem.span.Span`, not the legacy `span.Span` and not bare `Span`. This is
the public spelling used by reflection, LSP symbols, documentation anchors,
and diagnostics.

That conversion is an intentional identity migration. It must not be hidden
behind display-only renaming:

1. Inventory every legacy standard-library nominal identity and generate a
   reviewed map such as `span.Span -> nupp.mem.span.Span`.
2. Bump the reflection descriptor schema and any derived-codec or persisted
   artifact schema whose fingerprint incorporates the identity.
3. Emit only canonical new identities and fingerprints for new artifacts.
4. For one explicit compatibility schema version, decoders may accept a
   declared `legacyQualifiedNames` entry from the migration map. They must
   normalize it to the new identity and never encode the legacy spelling.
5. A persisted artifact whose format has no versioned alias mechanism is
   rejected with a migration diagnostic rather than silently treated as a
   different nominal.
6. Update doc anchors, golden diagnostics, symbol fixtures, materializer keys,
   codec fixtures, and reflection examples in the same module conversion.

The alias map is data for persisted-boundary migration, not an alternate
source-level type name and not a second runtime module key. Once the documented
compatibility window ends, the decoder support and map may be removed in a
schema bump.

For an already-declared external package such as Tecs, switching a consumer
from explicit require to qualified access does not change nominal identity.
Only converting a legacy declaration to plan 069's canonical module identity
causes the one-time migration above.

## Nupp migration

1. Complete plan 069, including the syntax-capable bootstrap and canonical
   loader, while the ambient `nupp` surface still works.
2. Build the namespace registry with compiler-intrinsic reservations and all
   duplicate checks before enabling qualified paths.
3. Convert one source-backed leaf module and verify explicit require,
   destructured require, qualified access, and raw Lua receive one module and
   one set of export identities.
4. Inventory nominal identities and land the reflection/codec schema migration
   before converting any module that exports nominals.
5. Convert source-backed modules and compiler components one SCC at a time,
   rolling bootstrap before converted compiler syntax is required.
6. Move native-backed public APIs out of `prelude.d.nupp` into checked facade
   modules. Private declarations describe only external ABIs and do not repeat
   public surfaces.
7. Split facade modules at feature-selection boundaries so a narrow qualified
   access does not retain unrelated native providers.
8. Convert `src/nupp/init.nupp` to the exact root `module nupp`; reserve or
   export every direct child name without collisions.
9. Atomically remove the compiler-owned ambient runtime `nupp` value and its
   installers. Keep the explicit compiler namespace overlay for language and
   comptime operations.
10. Update docs and examples to choose explicit require, named selection, or
    qualified access for readability rather than implementation language.

The compiler-bundled catalog is generated from declared headers and embedded
source metadata. Environment setup, feature registration, bootstrap,
documentation, packaging, and completion consume it rather than maintaining
parallel module lists.

## Tecs validation

Tecs publishes declared headers and registers `tecs` through ordinary package
metadata. A representative consumer must use all three spellings:

```nupp
const query = require("tecs.world.query")
const {each as eachEntity} = require("tecs.world.query")
tecs.world.query.each(...)
```

Validation includes nested module paths, a root that may also be a module,
mutually referring exported types and functions, source-backed comptime
exports, explicit and qualified consumers, and a raw Lua consumer. The three
spellings must preserve canonical nominal identity, call shape, initialization
order, package names, effects, and feature selection.

## Tooling

- Completion lists child modules and exports from the closed registry and
  includes compiler-only entries only in their valid phase.
- Definition on a module segment opens its declared file; definition on an
  export opens the declaration. Intrinsics open their language reference.
- References and rename unify explicit and qualified source spellings through
  canonical identity. Rename reports reserved-name and child/export collisions.
- Hover shows written spelling, canonical module/export identity,
  initialization tier, and comptime-only status where relevant.
- Documentation trees come from the registry and distinguish exact root
  modules, namespace-only prefixes, declared modules, and language intrinsics.
- Packaging reports rejected alias keys and duplicate preload registrations.

## Implementation sequence

1. Build a generic closed registry from declared headers and package metadata.
2. Add exact-root modules, child/export collision diagnostics, canonical-key
   enforcement, and compiler-namespace reservations.
3. Resolve qualified expressions through the shared explicit-require module
   records, including type and comptime phases.
4. Generate one live hidden import per module and reuse plan 069's cycle and
   feature-effect edges.
5. Extend formatter-independent LSP, docs, diagnostics, rename, and packaging.
6. Add bytecode and dead-selection performance gates before migrating hot
   native calls.
7. Land the nominal/reflection migration and convert Nupp in the staged order.
8. Validate the same metadata, resolution, generation, and identity behavior
   against Tecs.

## Verification

- Registry tests for pure prefixes, exact root modules, `.g.nupp` and `/init`
  canonical names, rejected aliases, compiler-reserved names, duplicate
  modules, and parent-export/child-module collisions.
- Resolution tests for longest module prefixes, lexical shadowing, type-only
  access, comptime exports, intrinsic precedence, unknown children, and
  spelling fixes.
- Generated-source tests proving every selected module has one hidden direct
  require and every dead module has none.
- `nupp bc --check` fixtures asserting `UGET module; TGETS export` (or the
  platform-equivalent local form), no `GGET nupp`, fewer dynamic table lookups
  than the legacy ambient call, and no per-call loader/proxy/metatable work.
- Runtime fixtures through modules on disk, `package.preload` bundles, and raw
  Lua, including qualified and explicit edges in the same cycle.
- Feature-selection tests proving unused modules, native providers, and
  resources are not staged.
- Reflection and codec fixtures for the schema bump, canonical identities,
  accepted versioned legacy aliases, and rejected unversioned stale artifacts.
- LSP and documentation fixtures for unified identities and root/module trees.
- Tecs acceptance proving source-spelling changes preserve identity, generated
  calls, initialization order, and package keys.
- Deterministic catalog, bundle, documentation, and compiler fixpoints.

## Non-goals

- A runtime ambient package table.
- Filesystem lookup after arbitrary field access.
- Per-call lazy loaders, namespace proxies, or metatable dispatch.
- Qualified access for packages that publish no declared headers.
- Alternate canonical module keys or source-level legacy nominal aliases.
- Making a qualified spelling change module cycle semantics.
- Moving ownership intrinsics into expressible ordinary functions merely to
  make the registry uniform.

## Completion criteria

- Nupp and Tecs qualified paths select real declared files through a generic
  closed registry and generate one direct cached import.
- Compiler intrinsics and comptime-only entries retain their exact phase,
  checking, ownership, and erasure behavior without an ambient runtime table.
- Roots may also be modules, while every child/export/reserved-name collision
  is diagnosed during registration.
- Qualified access improves the representative ambient hot-call bytecode and
  adds no loader work on the call path.
- Nupp's legacy nominal identities have an explicit versioned migration to
  fully qualified module identities.
- Explicit require, named selection, and qualified access share one module,
  export identity, initialization graph, and feature-effect path.
- Unused qualified modules remain absent from generation and packaging.
- The public standard library is expressed by checked source modules and
  private ABI declarations rather than one ambient declaration record.
