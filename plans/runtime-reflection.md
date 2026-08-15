# Runtime reflection and schema extensions

## Decision

Nupp will make every record declaration a visible first-class nominal type
object. The declaration value `User` has static type `Type<User>`; it is not a
`User` instance and it is not merely the compiler's `metatable<User>` phantom.
For a record the same runtime table remains the instance metatable, and for a
struct the type object wraps or is its FFI ctype. A runtime intrinsic on the
type object allocates and caches a versioned descriptor on first use.

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

Descriptors hold declaration facts. Format-specific behavior is a runtime
extension allocated against the descriptor. `@derive(nupp.derive.JSON)`
declares that the record admits the JSON extension and supplies its checked
JSON configuration; it does not materialize or embed a complete codec. Its
generated `toJSON` and `fromJSON` members are convenience wrappers that obtain
the extension at runtime.

```text
visible Type<User> object (User)
              |
              +-- runtime TypeInfo<User>, cached on first .reflect()
                       |
                       +-- core semantic descriptor
                       |
                       +-- runtime extension cache
                              |
                              +-- JSON_KEY -> JSONCodec<User>, on first request
```

Core descriptor facts are immutable. Extension instances are ordinary runtime
objects, allocated and cached per descriptor; their cache is private to the
reflection runtime rather than a mutable public field on the descriptor.

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

The current JSON derive is a useful narrow precursor. It validates a schema
from the compiler's semantic type information, registers it under a derive key,
and uses shared runtime code to write directly into a `string.buffer`. What it
lacks is a common type-owned descriptor and a runtime extension cache; it
should be migrated into those, not replaced with a per-record JSON
implementation.

Smithy-like generators precompute protocol bindings from a schema and traits,
then run without their source model at runtime. Nupp gets the same useful
boundary without making every application model a service definition:

```text
Nupp declaration + annotations
        -> compact immutable descriptor blueprint
        -> runtime TypeInfo<T>.reflect()
        -> runtime extension factory
        -> cached JSONCodec<T> or another extension instance
```

## Goals

- Give every record a user-visible declaration value of type `Type<T>`.
- Let `json.decode(User, text)` infer `User` without an explicit descriptor.
- Allocate runtime semantic reflection only for declarations that use it.
- Keep the current immutable, graph-shaped semantic reflection as the one
  source of type meaning; do not invent a second field/type vocabulary.
- Give codecs and later consumers an O(1) type-extension lookup.
- Let runtime extensions precompute validation and dispatch data once per type
  and cache it, without changing their source API.
- Preserve nominal identity across modules and constructed record values.
- Make descriptor blueprints and extension keys deterministic; let runtime
  extension instances carry their own compatibility/version contract.
- Keep the core descriptor format-neutral: JSON, binary protocols, database
  mappings, validation, debugging, and UI schemas remain separate extensions.

## Non-goals

- Reflection over arbitrary Lua tables, values typed `any`, or structural
  shapes. Only a nominal `Type<T>` declaration value has declared meaning.
- A universal `Serializable` interface or automatic serialization of every
  record or struct.
- Treating C layout as a JSON schema. `layoutof(Struct)` remains the
  target-specific memory-layout API and does not install a JSON extension.
- A global mutable registry selected by strings. Extensions use first-class,
  opaque key/factory values and attach only through `TypeInfo<T>`.
- Runtime source generation. An extension may allocate tables, maps, closures,
  and state at runtime, but does not turn a descriptor into source and `load`
  it merely to install itself.
- Streaming JSON parsing in the first release. The initial decoder may retain
  cjson parsing and apply the extension's validation/construct step afterward.

## Core runtime descriptor

### Identity and lookup

For a record, `User.reflect()` calls a compiler intrinsic that obtains the
compact descriptor blueprint for `User`, constructs `TypeInfo<User>` on its
first call, and stores it in a compiler-private slot or weak side table keyed
by the `Type<User>` object's declaration/metatable table. Constructed values
can make the same lookup through `getmetatable(value)`. The cache key is an
opaque runtime sentinel, not a writable string member such as
`__nuppTypeInfo`.

For a struct, the witness is its ctype. A descriptor may refer to the existing
`layoutof` helper when layout information is explicitly requested, but semantic
reflection itself remains target-independent.

Every record emits its visible `Type<T>` declaration object. The compiler emits
only the compact descriptor blueprint and intrinsic path needed by a reachable
`.reflect()`/extension use; it does not allocate `TypeInfo<T>` during module
load. Thus an ordinary record adds no descriptor graph or reflection helper
beyond its existing declaration table and methods; an ordinary struct adds no
descriptor graph beyond its ctype and metatype.

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
fingerprint, kind, ordered fields, annotations, and typed extension requests.
No consumer may rely on a raw Lua table layout. The blueprint's raw encoding is
private; runtime consumers receive only `TypeInfo<T>` and extension values.

### Lifetime and cross-module behavior

The descriptor owns no value instances. A module's `Type<T>` object is the
identity and remains the registry key; `TypeInfo<T>` and its extension cache
may be weakly retained where module unloading makes that relevant. A derived
entry cannot depend on module evaluation order for nested types: extension
factories resolve nested `Type<U>` values through stable nominal identity, or
use a one-time lazy thunk with a deterministic "dependency is not loaded"
failure.

A complete project build knows every reachable use. It may emit the descriptor
blueprint beside the owner declaration or in a caller module; the observable
contract is one lazily allocated `TypeInfo<T>` per nominal witness per Lua
state. Separate compilation records blueprint identity, derive declarations,
and extension-key compatibility requirements in the exported module interface.

## Extension model

### Extension identity

An extension is a first-class runtime factory identified by an opaque key. It
has a fixed owner-kind contract and produces one runtime value for one
`TypeInfo<T>`. JSON's initial key is conceptual rather than a public string:

```text
JSON: Extension<JSONCodec<T>>
```

The source-level shape is intentionally receiver-owned:

```nupp
local info = User.reflect()
local codec: JSONCodec<User> = info:extension(json)
```

`extension` uses the extension's opaque identity to look in a private runtime
cache. On a miss it calls the extension factory with `TypeInfo<T>`, stores the
returned value, and returns it. The lookup and allocation happen once per type
per Lua state, not once per field or value. The exact generic spelling for an
extension whose result depends on `T` is part of R2; the important rule is that
the type checker preserves `JSONCodec<User>`, never `any`.

The cache state is `empty`, `initializing`, `ready`, or `failed`. An extension
can publish an initializing placeholder before resolving a nested type, which
makes mutually recursive codecs possible. Reentry that needs an unfinished
operation produces a deterministic cycle error. A failure is memoized for the
descriptor's lifetime rather than repeatedly allocating and failing.

Extension keys are values, not strings and not global names. A package may
export one; ordinary runtime code may pass it, store it, and ask a descriptor
for it. The descriptor owns the one cached instance for a key, so a second
request cannot replace or race the first. A differently configured codec is a
separate extension value, not a mutable overwrite of `json`.

### Runtime allocation

```text
Type<User>.reflect()
      |
      v
allocate TypeInfo<User> from immutable blueprint, once
      |
      v
info:extension(json)
      |
      v
JSON factory reads info and allocates prepared JSONCodec<User>, once
```

The compiler may emit a compact literal blueprint, field accessor closures, or
unrolled helpers to make allocation cheap. Those are inputs to the runtime
factory, not a linked extension object. The factory allocates its maps, masks,
default-cloning state, nested extension handles, and any codec instance at
runtime. No source is generated and loaded at runtime.

The core descriptor carries its canonical semantic fingerprint. An extension
that needs compatibility reporting computes its own runtime fingerprint from:

- the canonical core descriptor fingerprint;
- the extension key/factory version;
- extension-specific configuration and relevant annotations;
- the chosen runtime representation version.

Changing a JSON field name, default, type, or omission rule changes the core
blueprint or JSON declaration and therefore causes the next runtime extension
allocation to produce a different codec. There is no stale linked codec object
to invalidate. A body-only change outside its provider inputs changes neither.

### Prepared extensions and fast paths

Every extension has one specified semantic contract and may prepare itself at
runtime in stages:

1. **Generic backend:** shared runtime code walks `JsonShape`.
2. **Prepared backend:** the extension factory precomputes name maps, required masks,
   default factories, union dispatch, and nested codec handles.
3. **Specialized helper backend:** a compiler-emitted helper may be selected by
   the runtime factory for a concrete record shape, but its stateful extension
   object is still allocated and cached at runtime.

All backends produce the same JSON bytes, validation behavior, error paths,
unknown-field policy, depth/cycle handling, and fingerprint. Unsupported
options fall back to the generic/prepared backend. Backend selection is not
visible through source APIs and is included in the extension's own compatibility
fingerprint when one is exposed.

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

The derive validates and declares the JSON policy: JSON field names, field
order, omit and omit-empty policy, defaults, unknown-field policy, recursively
supported type terms, and tagged-union choices. `User.reflect():extension(json)`
reads those declaration facts and allocates the `JsonShape`/`JSONCodec<User>`
at runtime. JSON is therefore an extension on the reflected record, not a
method table pretending to be all reflection and not a codec object embedded by
the derive.

`json.encode(value)` uses the concrete static nominal type to lower a
receiver-based runtime extension lookup (or a local cached result). It does
not construct a codec at compile time. `json.encodeAs(User, value)` is the
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

### R1: Runtime type witnesses and core descriptor allocation

- Add the public `Type<T>` type and make every record declaration expression
  have that type; retain its runtime table as the record instance metatable.
- Add the `Type<T>.reflect()` intrinsic and decide the corresponding struct
  type-object surface.
- Define the frozen runtime descriptor graph, public projection, visibility
  rule, schema version, and canonical fingerprint.
- Emit an immutable compact descriptor blueprint and lazy allocator intrinsic
  from semantic reflection, reusing graph encoding rather than serializing
  checker objects.
- Lower a direct `User.reflect()` only where written; verify every record has
  its cheap `Type<T>` object but a program without runtime reflection emits no
  descriptor helper or descriptor payload.
- Diagnose non-nominal witnesses, runtime values, and attempts to mutate a
  descriptor.

Exit: `User.reflect()` allocates one stable descriptor with field metadata;
repeated calls return it; no record allocates an unrequested descriptor graph
or runtime reflection helper.

### R2: Runtime extension factory and cache contract

- Define an `Extension` factory value with an opaque key, owner kinds, typed
  result relation, configuration/version identity, and a private cache on each
  `TypeInfo<T>`.
- Specify cache states for empty, initializing, ready, and failed entries so
  recursion is safe, failures are deterministic, and an extension cannot be
  replaced after it is ready.
- Expose the generic source form for `info:extension(json)` while preserving
  its dependent result type; no caller supplies a separate info object.
- Test direct calls, generic helpers, aliases, first-class storage and passing
  of `Type<T>` and extension values, cross-module imports, recursive record
  graphs, repeated module loads, cache failure, and absent-extension failures.

Exit: a lookup is O(1) after allocation, each extension instance is allocated
once per descriptor and Lua state, and neither the cache nor its keys rely on
user-writable strings or registration order.

### R3: Make JSON derive declare the `json` extension

- Define and validate `JsonShape` as JSON declaration data consumed by the
  runtime JSON extension factory.
- Move JSON derive data from the private derive-entry schema into that
  declaration; retain forwarding members as compatibility wrappers, but never
  materialize a codec during derive or module initialization.
- Implement `json.decode(User, text)`, `json.encode(value)`, and
  `json.encodeAs(User, value)` with the stated type-evidence behavior.
- Keep `fieldCodec` separate and add tests proving it remains shallow keyed
  projection rather than JSON serialization.
- Compare all R0 JSON fixtures byte-for-byte and error-for-error.

Exit: the first JSON request allocates one codec through the descriptor
extension; no public JSON API requires callers to pass both a type and an info
object.

### R4: Prepared JSON backend

- Have the runtime JSON factory precompute field-name lookup, required masks,
  default cloning strategy, union lookup, and nested extension references.
- Ensure deep nesting, cycles, omitted fields, maps, arrays, unknown fields,
  invalid UTF-8, non-finite numbers, and missing dependencies retain the R0
  contract.
- Benchmark cold startup, repeated encode/decode, and large-record decode
  against the current schema walker; retain the generic backend as reference.

Exit: prepared codecs improve a named workload without changing behavior or
loading reflection for types that do not use JSON.

### R5: Specialized writer and optional streaming decoder

- Add a direct `encodeInto` helper backend only where measurements justify its
  code size and compile cost; the runtime factory selects and wraps it rather
  than receiving a compiler-materialized codec.
- Select/fall back deterministically based on documented feature support.
- If a pull/SAX parser lands, target the same `JsonShape`/extension contract;
  do not create generated JSON semantics beside it.

Exit: a specialized codec and the generic codec agree on the complete R0
fixture suite and the generated writer is demonstrably worthwhile.

### R6: Validate an extension ecosystem

- Implement or prototype at least two non-JSON consumers, such as validation
  and a protocol/database mapping, as ordinary runtime extension factories.
- Require each exported extension value to specify owner kinds, typed result,
  configuration/version identity, runtime contract, recursion behavior,
  fingerprints, visibility policy, diagnostics, and acceptance tests.
- Verify packages can pass and store extension values without mutating a
  descriptor's private cache or relying on compiler materializer registration.

Exit: public factory values work across real packages, or the limitations that
prevent them are concrete and documented.

## Verification

- Unit tests for descriptor graph encoding, identity, immutability, field
  visibility, recursive references, fingerprints, and absence from unused
  output.
- Checker tests for the distinction between `Type<T>`, `T`, and
  `metatable<T>`; first-class `Type<T>` bindings; invalid witnesses; erased
  values; record-only metatable coercion; and extension conflicts.
- Generated-code tests proving descriptor blueprints are lazy, no runtime
  allocation occurs without a reflective request, and no user-visible registry
  keys are emitted.
- Runtime tests for descriptor and extension identity, one-time allocation,
  initialization cycles, cached failures, and Lua-state isolation.
- Cross-module and hot-reload tests for stable nominal identity, cache
  invalidation, blueprint/factory ABI changes, and repeated loading.
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
- How the type relation between an `Extension` factory and its result is
  represented in user-visible generics without an `any` escape hatch.
- Whether a failed extension allocation remains memoized forever or exposes an
  explicit retry policy for reload and development workflows.
- Whether structs initially participate only as witnesses for layout-aware
  extensions, or receive the full core descriptor before a concrete consumer
  needs it.
- Whether JSON's preferred public streaming target is `string.buffer`, the
  existing `nupp.io.Writer`, or a narrower byte-sink interface.
- Which non-JSON consumers establish the right public package ergonomics for
  exporting extension factory values and their configuration.
