# Runtime reflection and schema extensions

## Decision

Nupp will make every record declaration a visible first-class nominal type
object. The declaration value `User` has static type `Type<User>`; it is not a
`User` instance and it is not merely the compiler's `metatable<User>` phantom.
For a record the same runtime table remains the instance metatable, and for a
struct the type object wraps or is its FFI ctype. A runtime intrinsic on the
type object returns an immutable, versioned descriptor on demand.

```nupp
local info = User.reflect()
local user, problem = json.decode(User, text)
```

`User` is the only value callers supply. They never carry both `User` and a
second `TypeInfo<User>` argument. A generic parameter infers through the
witness:

```nupp
function read<T>(target: Type<T>, text: string): T?
    local value, problem = json.decode(target, text)
    if problem ~= nil then return nil end
    return value
end

local user = read(User, text)
```

The compiler may pass the descriptor or a codec as hidden evidence at a typed
call site. The public spelling remains one `User` argument.

Runtime reflection is distinct from the existing comptime-only
`nupp.reflect(T)`. The surface spelling and namespace are chosen during R1 so
the two cannot be confused in diagnostics or documentation; this plan writes
the runtime operation as `User.reflect()`.

Descriptors hold declaration facts. Format-specific behavior is a sealed
extension on the descriptor. `@derive(nupp.derive.JSON)` therefore produces a
`json` extension recipe, not a general reflection implementation and not a
separate bespoke registry. Its generated `toJSON` and `fromJSON` members are
convenience wrappers over that extension.

```text
visible Type<User> object (User)
              |
              +-- private TypeInfo<User>, only when required
                       |
                       +-- core semantic descriptor
                       |
                       +-- extensions[JSON_KEY] -> JsonShape / JSONCodec<User>
```

The descriptor and every extension are immutable once a module is linked. No
ordinary runtime code can attach, replace, or mutate one.

### `Type<T>` is a user type, not an implementation detail

The distinction is observable and useful in ordinary source:

```nupp
local record UserInfo
    id: integer
end

local type: Type<UserInfo> = UserInfo
local value: UserInfo = new UserInfo(id = 7)
local fields = UserInfo.reflect().fields
```

`Type<UserInfo>` represents the nominal declaration as a value. `UserInfo`
represents an instance. The declaration value is available in bindings,
parameters, returns, arrays, maps, and generic arguments; it is not an
invisible compiler token that only special intrinsics may receive. The compiler
creates the `Type<T>` object for every record whether or not the program ever
asks it to reflect. What remains lazy is the descriptor graph and every
extension payload behind it.

For source compatibility, a record's `Type<T>` object has a compiler-known
record-only coercion to `metatable<T>` when it reaches `setmetatable` or an
existing API that deliberately asks for an instance metatable. A manually
constructed `metatable<T>` never gains the reverse coercion: it is not a
nominal `Type<T>`, cannot call `.reflect()`, and cannot stand in for the
declaration. Struct `Type<T>` objects have no metatable coercion.

## Why this shape

Records already have an unambiguous runtime identity: `new User(...)` stamps
the `User` type object's table as the instance metatable. Tecs components and
events use the same useful shape: a visible nominal container is passed to
registration, construction, dispatch, and storage APIs, while instances retain
their separate nominal type. Nupp should express that relationship directly as
`User: Type<User>`, rather than hiding it behind `metatable<User>`.

The record table therefore needs no second allocation to become a `Type<T>`
object. The checker and prelude give it its real public nominal type, while the
lowering keeps its existing Lua table/metatable behavior. JSON derives also
already register a private derived entry against that same identity. Runtime
reflection should reuse this fact rather than require `User, info` at every
call.

The current JSON derive is a useful narrow precursor. It makes a schema from
the compiler's semantic type information, registers it under a derive key, and
uses shared runtime code to write directly into a `string.buffer`. What it
lacks is a common type-owned descriptor and a general extension slot; it should
be migrated into those, not replaced with a per-record JSON implementation.

Smithy-like generators precompute protocol bindings from a schema and traits,
then run without their source model at runtime. Nupp gets the same useful
boundary without making every application model a service definition:

```text
Nupp declaration + annotations
        -> reflected semantic descriptor
        -> derive/provider extension recipe
        -> linked immutable extension
        -> generic runtime fallback or specialized codec
```

## Goals

- Give every record a user-visible declaration value of type `Type<T>`.
- Let `json.decode(User, text)` infer `User` without an explicit descriptor.
- Materialize runtime semantic reflection only for declarations that use it.
- Keep the current immutable, graph-shaped semantic reflection as the one
  source of type meaning; do not invent a second field/type vocabulary.
- Give codecs and later consumers an O(1) type-extension lookup.
- Let extensions precompute validation and dispatch data, and later choose a
  generated fast path, without changing their source API.
- Preserve nominal identity across modules and constructed record values.
- Make extension keys, payloads, provider ABI, and fingerprints deterministic,
  checked, cacheable, and visible to incremental invalidation.
- Keep the core descriptor format-neutral: JSON, binary protocols, database
  mappings, validation, debugging, and UI schemas remain separate extensions.

## Non-goals

- Reflection over arbitrary Lua tables, values typed `any`, or structural
  shapes. Only a nominal `Type<T>` declaration value has declared meaning.
- A universal `Serializable` interface or automatic serialization of every
  record or struct.
- Treating C layout as a JSON schema. `layoutof(Struct)` remains the
  target-specific memory-layout API and does not install a JSON extension.
- A mutable plugin registry or runtime code generation. Extensions are linked
  artifacts, not callbacks selected by strings at runtime.
- A public third-party extension ABI in the first release. Built-in JSON is
  the proof; package extension publication follows only once its type, cache,
  visibility, and conflict contracts are proven.
- Streaming JSON parsing in the first release. The initial decoder may retain
  cjson parsing and apply the extension's validation/construct step afterward.

## Core runtime descriptor

### Identity and lookup

For a record, `User.reflect()` looks up a compiler-private slot or weak side
table keyed by the `Type<User>` object's declaration/metatable table.
Constructed values can make the same lookup through `getmetatable(value)`. The
key is an opaque runtime sentinel, not a writable string member such as
`__nuppTypeInfo`.

For a struct, the witness is its ctype. A descriptor may refer to the existing
`layoutof` helper when layout information is explicitly requested, but semantic
reflection itself remains target-independent.

Every record emits its visible `Type<T>` declaration object. The compiler
installs only descriptor portions requested by reachable runtime reflection or
extension uses. Thus an ordinary record adds no descriptor graph or reflection
helper beyond its existing declaration table and methods; an ordinary struct
adds no descriptor graph beyond its ctype and metatype.

### Descriptor content

The descriptor is a frozen indexed graph, based on schema 3 of comptime
reflection. It preserves recursion through node indices rather than nested Lua
tables. Its stable payload includes:

- owner nominal identity, kind, qualified name, and semantic fingerprint;
- ordered visible stored fields, field names, read/write type edges, defaults,
  and checked annotations;
- type graph nodes for primitives, literals, arrays, maps, tuples, shapes,
  unions, references, generic arguments, and other already-supported semantic
  terms;
- an extension set keyed by opaque extension identities.

Private fields follow the same visibility rule as comptime reflection. A
runtime descriptor never exposes checker objects, source locations, mutable
annotation tables, or process-local type identities.

The public descriptor surface starts deliberately small: identity,
fingerprint, kind, ordered fields, annotations, and opaque extension queries.
The compiler may retain a richer private representation for codec lowering.
No consumer may rely on a raw Lua table layout.

### Lifetime and cross-module behavior

The descriptor owns no value instances. A module's `Type<T>` object is the
identity and remains the registry key; descriptors may be weakly retained where
module unloading makes that relevant. A derived entry cannot depend on module
evaluation order for nested types: nested extension references are registered
by stable nominal key and resolved once, or use a one-time lazy thunk with a
deterministic "dependency is not loaded" failure.

A complete project build knows every reachable use. It may arrange descriptor
installation at the owner declaration, or install an equivalent immutable
entry from a caller module; the observable contract is one descriptor per
nominal witness. Separate compilation records the descriptor and extension
fingerprints in the exported module interface.

## Extension model

### Extension identity

An extension is identified by a compiler-controlled opaque key and has a fixed
owner kind, payload schema, runtime value contract, helper ABI, and provider
ABI. JSON's initial key is conceptual rather than a public string:

```text
JSON_KEY: ExtensionKey<JsonShape -> JSONCodec<T>>
```

The extension table's O(1) lookup is an implementation property, typically a
Lua table indexed by an unforgeable sentinel. It happens once per root codec
selection, not once per field. Specialized nested codecs may retain direct
references; generic nested codecs resolve a cached extension reference.

Two providers cannot install the same key on an owner unless the extension
explicitly defines a checked composition rule. JSON has no composition rule:
two JSON derives or a hand-written JSON extension are a diagnostic, never
last-writer-wins behavior.

### Production and linking

At comptime, an extension provider reads the immutable descriptor and returns
a sealed, versioned recipe. The compiler validates that recipe against the
extension key, fingerprints it, merges it with the declaration, and lowers it
to an immutable runtime value. The provider cannot return source, arbitrary
Lua, mutable descriptor data, or a raw registry key.

```text
immutable Info<T>
      |
      v
extension provider
      |
      v
validated ExtensionRecipe<JSON_KEY>
      |
      v
materialized JSON extension + optional forwarding members
```

This reuses derive recipe evaluation, opaque materialization envelopes,
provenance, runtime effects, output limits, and fingerprints. It does not make
the existing general materializer registry user-extensible.

Each linked extension fingerprint includes:

- the canonical core descriptor fingerprint;
- extension-key and payload-schema versions;
- provider and helper ABI versions;
- relevant typed annotations and derive configuration;
- runtime emitter/helper ABI and selected backend.

Changing a JSON field name, default, type, or omission rule invalidates the
JSON extension and consumers. A body-only change outside its provider inputs
does not.

### Fast paths

Every extension has one specified semantic contract and may have several
lowering backends:

1. **Generic backend:** shared runtime code walks `JsonShape`.
2. **Prepared backend:** link time precomputes name maps, required masks,
   default factories, union dispatch, and nested codec handles.
3. **Specialized backend:** compiler emits an `encodeInto` writer and, where
   available, a direct decoder/visitor for a concrete record shape.

All backends produce the same JSON bytes, validation behavior, error paths,
unknown-field policy, depth/cycle handling, and fingerprint. Unsupported
options fall back to the generic/prepared backend. Backend selection is not
visible through source APIs and is recorded in the extension fingerprint.

## JSON proof

### Surface

The initial source surface remains familiar:

```nupp
@derive(nupp.derive.JSON)
@json(unknown = "reject")
local record User
    @json(name = "user_id")
    id: integer
    name: string = "anonymous"
end

local text = json.encode(new User(id = 7))
local user, problem = json.decode(User, text)
```

`user:toJSON()` and `User.fromJSON(text)` remain source-compatible wrappers.
`User.fieldCodec()` keeps its existing shallow keyed-projection meaning until a
separate API migration says otherwise; it is not silently widened into a JSON
codec.

The derive builds a `JsonShape` payload: JSON field names, field order, omit
and omit-empty policy, defaults, unknown-field policy, recursively supported
type terms, and tagged-union choices. Linking that payload creates the JSON
extension and any selected fast path. JSON is therefore an extension on the
reflected record, not a method table pretending to be all reflection.

`json.encode(value)` resolves a compile-time `JSONCodec<T>` evidence value when
`value` has a concrete static nominal type. `json.encodeAs(User, value)` is the
escape hatch for a value erased to `any`. `json.decode(User, text)` always has
its `Type<User>` witness directly. A value from an untyped Lua boundary is not
accepted merely because it looks structurally similar to `User`.

### Decoder evolution

R1 preserves the current cjson parse followed by typed validation and record
construction. The prepared extension makes field dispatch and defaults cheap
without changing parsing. A later pull/SAX parser can call the same extension's
field and union dispatch entries; this avoids creating a second JSON semantic
planner merely to obtain streaming decode.

## Delivery plan

### R0: Specify and pin current behavior

- Add this plan's invariants to the semantic-reflection and derive
  documentation.
- Capture current derived JSON byte output, failure paths, decoder options,
  unknown-field behavior, defaults, cycles, maps, nested records, and tagged
  unions as compatibility fixtures.
- Add generated-output fixtures showing that every record declaration is a
  `Type<T>` value, remains the runtime instance metatable, and coerces to
  `metatable<T>` only where an existing metatable API requires it.

Exit: current JSON behavior is a testable contract rather than an accidental
property of `__nuppDeriveTypes`.

### R1: Runtime type witnesses and core descriptor materialization

- Add the public `Type<T>` type and make every record declaration expression
  have that type; retain its runtime table as the record instance metatable.
- Add the `Type<T>.reflect()` intrinsic and decide the corresponding struct
  type-object surface.
- Define the frozen runtime descriptor graph, public projection, visibility
  rule, schema version, and canonical fingerprint.
- Add a compiler-owned materializer from semantic reflection to a runtime
  descriptor, reusing graph encoding rather than serializing checker objects.
- Lower a direct `User.reflect()` only where written; verify every record has
  its cheap `Type<T>` object but a program without runtime reflection emits no
  descriptor helper or descriptor payload.
- Diagnose non-nominal witnesses, runtime values, and attempts to mutate a
  descriptor.

Exit: `User.reflect()` has stable identity and field metadata; repeated calls
return the same descriptor; no record gains an unrequested descriptor graph or
runtime reflection helper.

### R2: Extension registry and link contract

- Add compiler-private descriptor installation/lookup keyed by record
  metatable and struct ctype.
- Define opaque extension keys, sealed extension recipes, duplicate/conflict
  diagnostics, extension fingerprinting, and module-interface transport.
- Add generic hidden-evidence lowering for a function requiring an extension,
  while preserving the one-`Type<T>`-witness source call.
- Test direct calls, generic helpers, aliases, first-class storage of
  `Type<T>` values, cross-module imports, recursive record graphs, repeated
  module loads, and absent extension failures.

Exit: an extension lookup is O(1), immutable, deterministic, and never relies
on a user-writable string key or registration order.

### R3: Migrate JSON derive to `JSON_KEY`

- Define and validate `JsonShape` as the first extension payload.
- Move JSON derive data from the private derive-entry schema into that payload;
  retain forwarding members as compatibility wrappers.
- Implement `json.decode(User, text)`, `json.encode(value)`, and
  `json.encodeAs(User, value)` with the stated type-evidence behavior.
- Keep `fieldCodec` separate and add tests proving it remains shallow keyed
  projection rather than JSON serialization.
- Compare all R0 JSON fixtures byte-for-byte and error-for-error.

Exit: JSON is selected through the descriptor extension; no public JSON API
requires callers to pass both a type and an info object.

### R4: Prepared JSON backend

- Materialize precomputed field-name lookup, required masks, default cloning
  strategy, union lookup, and nested extension references.
- Ensure deep nesting, cycles, omitted fields, maps, arrays, unknown fields,
  invalid UTF-8, non-finite numbers, and missing dependencies retain the R0
  contract.
- Benchmark cold startup, repeated encode/decode, and large-record decode
  against the current schema walker; retain the generic backend as reference.

Exit: prepared codecs improve a named workload without changing behavior or
loading reflection for types that do not use JSON.

### R5: Specialized writer and optional streaming decoder

- Add a direct `encodeInto` lowering backend only where measurements justify
  its code size and compile cost.
- Select/fall back deterministically based on documented feature support.
- If a pull/SAX parser lands, target the same `JsonShape`/extension contract;
  do not create generated JSON semantics beside it.

Exit: a specialized codec and the generic codec agree on the complete R0
fixture suite and the generated writer is demonstrably worthwhile.

### R6: Evaluate public extension providers

- Use at least two non-JSON internal consumers, such as validation and a
  protocol/database mapping, to prove whether a public provider ABI is needed.
- If opened, require each exported extension key to specify its owner kinds,
  typed payload envelope, conflict rule, runtime contract, fingerprints,
  visibility policy, diagnostics, helper ABI, and acceptance tests.
- Keep materializer registration compiler-owned; a package may provide a
  recipe for a declared extension key but may not emit arbitrary runtime code
  or mutate a descriptor.

Exit: either the ABI has concrete multi-package evidence, or it remains
compiler-owned without blocking useful built-in extensions.

## Verification

- Unit tests for descriptor graph encoding, identity, immutability, field
  visibility, recursive references, fingerprints, and absence from unused
  output.
- Checker tests for the distinction between `Type<T>`, `T`, and
  `metatable<T>`; first-class `Type<T>` bindings; invalid witnesses; erased
  values; record-only metatable coercion; and extension conflicts.
- Generated-code tests proving lazy descriptor/extension installation and no
  user-visible registry keys.
- Cross-module and hot-reload tests for stable nominal identity, cache
  invalidation, helper/provider ABI changes, and repeated loading.
- Full JSON compatibility fixtures from R0 under generic, prepared, and
  specialized backends.
- Benchmarks that report emitted bytes, cold load time, allocation, encode
  throughput, and decode throughput. A fast path that increases code size but
  fails to improve a named workload does not ship.
- `./bin/nupp test` after each milestone; `./bin/nupp fixpoint` when compiler
  sources or generated standard-library output change.

## Open questions

- Whether `Type<T>.reflect()` is the only runtime reflection spelling or a
  namespaced free-function alias is useful without duplicating diagnostics.
- Whether a runtime descriptor exposes the full semantic graph immediately or
  lazily exposes typed projections behind opaque handles.
- How an imported type's descriptor is installed in independently compiled
  modules while preserving one identity and dead-code elimination.
- Whether structs initially participate only as witnesses for layout-aware
  extensions, or receive the full core descriptor before a concrete consumer
  needs it.
- Whether JSON's preferred public streaming target is `string.buffer`, the
  existing `nupp.io.Writer`, or a narrower byte-sink interface.
- Which non-JSON consumers justify making extension keys/provider recipes
  public rather than retaining a closed compiler-owned set.
