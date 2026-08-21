---
title: Schema-driven serialization and deserialization
status: Draft
created: 2026-08-21
---

## Summary

Nupp serialization is organized around three independent values: an immutable
`Schema` describes the logical data, a `Binding<T>` describes how a value of
type `T` physically represents that data, and a codec describes one wire
format. A record binding reads cached Lua fields, a struct binding reads fixed
offsets and physical scalar types, and a dynamic binding reads integer-indexed
slots. All three may share one schema and one JSON, XML or CBOR codec.

Schemas and bindings are extension hosts. A codec lazily computes a typed,
profile-specific extension once and caches it on the object whose facts it
derived. A JSON schema extension contains pre-encoded keys, raw-byte member
lookup, required-member masks and format policy. A struct binding extension
contains offsets and physical load operations; a dynamic binding extension
contains slot indices. The hot path combines those immutable layouts and
traverses a complete value inside one codec entry. It does not generate a
serializer for every type, format and protocol, and does not cross the
Lua/native boundary once per token.

`@derive(nupp.derive.Serde)` creates one schema and binding for either a record
or a struct. It replaces format-owning derives as the architectural boundary;
format-specific convenience APIs may remain as compatibility wrappers. A
schema can also be constructed and frozen at run time, and its dynamic binding
uses the same codecs. That is the path for schema-driven clients such as a
Smithy client loaded from a model without generated types.

## Goals

- Generate one format-neutral description of a type rather than one
  implementation per type, format and protocol.
- Make schema-driven serialization competitive with specialized generated
  code by caching immutable data plans and traversing whole values in native
  codecs.
- Support records, fixed-layout structs and run-time dynamic values through
  the same logical schema.
- Let JSON, XML, CBOR and future codecs share one serde data model without
  forcing their wire rules into that model.
- Permit protocol packages such as Smithy to configure codecs and attach typed
  metadata without making the standard library know about services,
  operations, HTTP bindings or AWS protocols.
- Match JSON object keys against input bytes without constructing Lua strings,
  and write constant keys without repeated UTF-8 validation or escaping.
- Validate and bind a dynamic input once, then reuse member indices and
  established value types on subsequent calls.
- Keep the portable callback surface available for custom codecs and custom
  values while giving built-in codecs a fused schema-and-binding path.
- Make every cache lifetime explicit: schema-derived data dies with its schema,
  binding-derived data dies with its binding, and instance-derived data does
  not enter either cache.

## Non-goals

- Making the serde schema a service-description language. Services,
  operations, resources, authentication and HTTP bindings belong to packages
  built above serde.
- Adopting Smithy shapes or traits as Nupp standard-library vocabulary.
- Treating JSON Schema as the in-memory schema representation. Importers and
  exporters may translate it.
- Serializing the memory image of a struct. Padding, pointers, endianness and
  ABI layout are not a wire format.
- Generating executable machine code for each schema. The specialization is
  immutable data consumed by generic codec loops.
- Requiring a schema to be derived. Dynamic clients construct the same graph at
  run time, and custom bindings may name a schema directly.
- Making all decoded strings borrowed views. A borrowing decoder may be added
  under the ordinary ownership rules, but the default result owns its values.
- Deciding the general `Closeable` and `Flushable` protocols. Encoder and
  decoder sessions may use those protocols without changing the schema model.
- Removing `nupp.derive.JSON` before the serde path has equivalent format
  coverage, validation, diagnostics and measured performance.

## Motivation

### A format-owning derive multiplies generated behavior

A JSON derive knows both what a type contains and how JSON represents it. An
XML derive would learn the first fact again, as would CBOR. A protocol with a
different timestamp, union or member-name rule either needs another derive or
adds protocol conditionals to generated JSON code. Code size grows with the
product of types, formats and protocol variants even though the type topology
was constant.

Moving only the generated methods behind a common interface does not remove
that multiplication. It changes the spelling of the call while each type still
owns a format traversal.

### A callback protocol is not the Nupp fast path

A Rust-Serde-shaped callback interface is a useful portable contract: a value
announces a structure and calls a serializer for each member. On a JVM, the JIT
may inline and devirtualize those calls. In Nupp, a native writer call for every
key, scalar and container crosses the Lua/C boundary and may drain a buffer on
every call. The cost belongs to the physical call graph rather than to the
logical abstraction.

The retained [serde architecture spike](../../bench/serde-spike/README.md)
measured this distinction. Static format-neutral callbacks and a generic Lua
schema walk were within seven percent of handwritten writer calls. A
benchmark-only codec consuming the same schema in one native entry encoded a
three-field record about 27 times faster and a twelve-field record about 25
times faster. Integer-indexed dynamic slots increased those figures to about
35 and 36 times. Raw-byte schema decoding into twelve dynamic slots was about
five times faster than the existing derived path.

Those native results cover flat scalar structures and are an upper-bound
mechanism result, not proof of a complete implementation. They do establish
which boundary a complete implementation has to preserve: the whole traversal,
not each serde event, is the native operation.

### A generic document is too late

Decoding into a generic table before applying the expected type constructs
every object key, every selected value and an intermediate container graph.
The typed pass then looks the keys up again, validates values it could have
validated while parsing, and copies them into their final representation.

A schema-guided codec instead maps an input key directly to a member index and
writes its value into the final record field, struct offset or dynamic slot.
Unknown input can be consumed without constructing a value. A generic document
remains the answer when the caller asked for a document; it is not the
intermediate representation of typed decoding.

### Dynamic clients require a run-time schema

A generated client can compile field access into source. A dynamic client
loads a model after the program was built, discovers operations and shapes at
run time, and still needs the same protocol codecs. Reflection alone cannot be
its schema because there is no Nupp declaration to reflect.

The schema therefore has to be a first-class immutable run-time graph. A derive
materializes that graph from reflection; a model adapter builds and freezes the
same graph directly. Format extensions and dynamic slot bindings then apply to
both without a code-generation step.

### Logical shape and physical storage are different facts

A Nupp record, a Nupp struct and a dynamic value may all represent a structure
with the same three logical members. A record reaches them by Lua keys, a struct
by byte offsets, and a dynamic value by integer slots. Putting any one access
strategy in the schema either excludes the other two or duplicates the schema.

Separating `Schema` from `Binding<T>` lets format specialization depend on the
logical graph and access specialization depend on the representation. This is
also what prevents a codec from mistaking a struct's padding or pointer value
for data.

## Overview and specification

### Vocabulary

The design uses four terms with separate ownership:

| Value | Describes | Examples of cached facts |
| --- | --- | --- |
| `Schema` | Logical data | members, kinds, requiredness, defaults, constraints, annotations |
| `Binding<T>` | Representation of that data as `T` | record keys, struct offsets, dynamic slots, construction |
| `Profile` | One format's policy | field naming, timestamps, union representation, unknown members |
| `Codec` | Bytes for one format and profile | JSON, XML or CBOR parser and writer |

An annotation is input declared on a schema node. An extension is derived data
computed from a schema or binding and cached for later use. They are not the
same facility: annotations survive model conversion; extensions may contain
native pointers, interned strings and other process-local acceleration data.

### Schema data model

`Schema` is an immutable, identity-bearing graph. It admits references while
being built so recursive types do not require recursive Lua tables, and
`freeze()` resolves every reference and makes the graph shareable.

The format-neutral kinds are:

- unit and null;
- boolean;
- signed and unsigned integers with semantic width;
- floating point and arbitrary-precision decimal;
- string and bytes;
- timestamp;
- optional;
- list and map;
- structure;
- union;
- string and integer enumeration; and
- document, where the caller explicitly requests an unconstrained value.

A structure member has a stable identity inside its schema, a dense run-time
index, a logical name, a target schema, requiredness, an optional default and
typed annotations. The dense index is an acceleration value and is not a wire
identifier or persistent model identity.

Representation-independent constraints such as length, numeric range and
enumeration membership may be precomputed on the schema. A codec validates
wire syntax and scalar conversion; the schema-guided builder validates model
constraints and required members while constructing the result.

Service and operation nodes are absent. A protocol package holds those values
and refers to serde schemas for inputs, outputs, errors and payload members.

### Static derivation

One annotation derives the schema and representation binding:

```nupp
@derive(nupp.derive.Serde)
record User
    id: uint32
    displayName: string?
    active: boolean
end

const userBinding: serde.Binding<User> = serde.of(User)
```

The same derive applies to a struct:

```nupp
@derive(nupp.derive.Serde)
struct Vec3
    x: float
    y: float
    z: float
end

const vec3Binding: serde.Binding<Vec3> = serde.of(Vec3)
```

This extends derive application to structs for providers whose result contract
explicitly admits a struct. It does not let an arbitrary record-only provider
run on one. `nupp.derive.Debug` and compatibility `nupp.derive.JSON` retain
their existing target rules until separately changed.

`serde.of(T)` is type directed and returns the binding registered for that
declaration. The call is normally held in a module-level `const`, an operation
descriptor or a prepared codec. A hot member traversal does not repeatedly
look the binding up.

For code that does not want declaration augmentation, the materializer is
available directly:

```nupp
const vec3Serde: serde.Binding<Vec3> = comptime do
    return serde.binding(nupp.reflect(Vec3))
end
```

Both spellings produce the same schema and binding blueprint. The derive is
convenience and discoverability, not a second implementation.

### Binding representations

`Binding<T>` joins one logical schema to one physical representation. Its
public contract exposes the schema and the ability to prepare it for a codec;
the access plan itself is sealed so checked code cannot manufacture offsets or
claim that an arbitrary table is a bound value.

Conceptually:

```nupp
interface serde.Binding<T>
    schema: function(self): serde.Schema
end
```

A record binding contains:

- the nominal record identity and construction metatable;
- interned logical field keys;
- the member index corresponding to each key;
- presence and default rules; and
- custom field adapters, where declared.

A struct binding contains:

- its layout fingerprint and size;
- each member's checked byte offset;
- its physical scalar load and store kind;
- nested struct and fixed-array bindings; and
- construction storage for decoding.

A dynamic structure contains its schema identity, a presence bit set and a
dense value array. Member names are resolved while binding input or when an
application explicitly asks for a member by name; codecs operate on indices.

The logical schema contains none of these facts. Two physical types may bind
the same schema, and one dynamic binding may represent a schema that has no
Nupp declaration.

### Struct rules

Serde reads declared struct fields; it never copies or hashes the raw memory
image. A physical load is converted to the schema's semantic scalar and handed
to the codec. Decoding performs the inverse checked conversion before storing
at the derived offset.

Automatic struct derivation admits fixed-width scalar fields, booleans and
bitfields, nested serde structs, and fixed arrays of admitted values. It
rejects a pointer, variable-length C array, unbound union or other field whose
extent and ownership are not described by its type.

A programmer may omit such a field or provide a typed adapter. For example, a
pointer and count can be exposed as bytes only by an adapter that names the
count, establishes the root and returns a checked span. The derive never
guesses that relationship and never serializes an address.

Padding, target endianness, C enum storage and bitfield packing remain binding
implementation details. Wire encodings follow the logical schema.

### Dynamic schemas and values

A run-time schema is built and frozen before use:

```nupp
local schemaBuilder = new serde.SchemaBuilder()
schemaBuilder:structure("example.User")
schemaBuilder:required("id", serde.uint32)
schemaBuilder:optional("displayName", serde.string)
schemaBuilder:required("active", serde.boolean)
local schema = schemaBuilder:freeze()

local binding = serde.dynamic(schema)
```

An ergonomic table is accepted at a deliberate binding boundary:

```nupp
local input = binding:bind {
    id = 41,
    displayName = "Ada",
    active = true,
}
```

`bind` resolves names, validates the structure and produces indexed dynamic
storage. Reusing that value does not repeat name lookup or structural
validation. Callers constructing many values may retain member handles:

```nupp
local idMember = schema:expectMember("id")
local activeMember = schema:expectMember("active")

local input = binding:newValue()
input:set(idMember, 41)
input:set(activeMember, true)
```

Decoded dynamic structures use the same slots. `value:get("id")` is the
ergonomic, name-resolving operation; `value:get(idMember)` is the resolved
operation. Neither choice changes how the codec decodes input.

### Typed extensions

The extension mechanism used by reflection descriptors is generalized into a
sealed standard-library facility shared by reflection, schemas and bindings.
An extension key has identity, a result type and a provider. Hosts store results
in dense key slots and compute an absent value once. The provider runs only on
the cold preparation path.

The conceptual operation is:

```nupp
local layout: json.Layout = schema:extension(json.layoutKey)
```

Profiles do not allocate a new global extension key. The one JSON extension is
a holder for layouts keyed by immutable, interned profile identity:

```nupp
local layout = schema:extension(json.layoutsKey):forProfile(profile)
```

This prevents a process creating profiles from growing the extension-key
registry. A codec normally hides both calls behind `prepare`:

```nupp
local prepared: json.Prepared<User> = codec:prepare(userBinding)
```

An extension provider prepares a recursive schema as a graph. It records an
empty layout node in its own identity map before visiting that node's children,
then fixes the child references after their layouts are available. It does not
recursively ask the same host for the same extension. Accidental re-entry keeps
the reflection extension rule and reports recursive initialization.

Schemas and bindings are immutable after preparation begins. Consequently no
cache invalidation exists. A dynamic model owns its schemas, schemas retain
their extension values, prepared layouts retain what they address, and
releasing the model releases the complete graph. Separate worker states build
their own native extensions rather than sharing process-local pointers.

### JSON schema extensions

The JSON extension for a structure may contain:

- the quoted and colon-terminated bytes for every wire key;
- comma-prefixed key fragments for non-first members;
- packed bytes for short-key comparison;
- lengths and hashes for longer keys;
- collision buckets and expected-next-member order;
- the member index returned by each match;
- required-member bit positions;
- scalar and container decoding kinds;
- timestamp and number policies; and
- literal or default values whose encoded bytes are constant.

Those byte fragments are trusted values constructed from frozen schema input.
The encoder appends them without repeating UTF-8 validation or escaping. They
are schema constants, not instance caches. A caller's reusable pre-encoded
instance value remains a separate trusted-value API. The portable writer path
uses the existing opaque `json.EncodedString` and `json.EncodedValue` forms;
the fused codec may retain equivalent native byte spans inside its layout.

The decoder receives a key as bytes from the parser. It first compares the next
member expected from schema order, then uses the cached packed or hashed lookup.
The result is a member index, not a Lua key string. Escaped keys are unescaped
into parser scratch before the same lookup. An unknown value is consumed and
validated without materialization when policy permits it.

### Other format extensions

The same schema produces different cached data for other codecs.

An XML extension may cache qualified names, namespace bindings, encoded start
and end tags, attribute versus element placement, text members and flattened
container rules. A CBOR extension may cache encoded map keys and tags,
canonical key order and numeric-width decisions.

These facts are not added to the base schema. Format-specific annotations are
available to their owning codec, and a protocol profile may project external
model metadata into the same decisions.

### Profiles and protocol variation

A codec profile is immutable and interned. It supplies policy rather than
model topology:

```nupp
local codec = json.newCodec {
    fieldNames = protocol.fieldNames,
    timestamps = protocol.timestamps,
    unions = protocol.unions,
    unknownMembers = protocol.unknownMembers,
}
```

Two profiles may derive different JSON layouts from the same schema. Profile
identity therefore participates in the layout cache. The profile object, not
the schema, knows whether to prefer a format-specific annotation, an external
model trait or the logical member name.

HTTP envelopes, headers, labels, query strings and errors remain outside the
JSON codec. A protocol implementation binds those parts of an operation and
hands only its payload schema and value to the configured format codec.

### Codec surface and fused traversal

The convenient operation accepts a binding and performs lazy preparation:

```nupp
local output = string.buffer.new()
codec:encode(userBinding, user, output)

local decoded: User = codec:decode(userBinding, input)
```

A long-lived client prepares once and retains the result:

```nupp
local prepared = codec:prepare(userBinding)

prepared:encode(user, output)
local decoded = prepared:decode(input)
```

`Prepared<T>` combines a format-and-profile schema layout with the binding's
access layout. Its native implementation enters once for a complete root value
and keeps recursive traversal, raw-key lookup, scalar conversion, unknown-value
skipping and buffered output on that side of the boundary. A buffer grows or
flushes in chunks, not at every serde event.

The prepared plan is immutable and shareable. The mutable encoder or decoder
session owns its output buffer, parser scratch, path stack, required-member bits
and other per-operation state. A completed session can be reset and reused with
the same prepared plan, so a client may pool sessions without pooling schemas or
bindings. A session is never cached as an extension and is never used
concurrently. Its `close()` and `flush()` behavior, where applicable, follows
the separate I/O protocols rather than becoming a codec or schema rule.

This does not make callbacks unavailable. A custom value may implement a
portable visitor binding, and a pure-Nupp or third-party codec may consume the
format-neutral serializer and deserializer protocol. Built-in native codecs
select the prepared traversal when the binding exposes one. The callback path
is a semantic fallback, not the implementation built-in codecs must use.

### Performance and migration gates

The mechanism spike is not sufficient to retire a format derive. A complete
prototype has to add recursive records, structs, optionals, lists, maps, unions,
defaults, escaped keys, unknown values, failing inputs and useful error paths to
the retained benchmark. Each case measures record, struct and dynamic bindings
where the representation applies.

The comparison records steady-state time, cold `prepare` time, allocations,
peak scratch space and emitted Lua size. It keeps the existing JSON derive,
format-neutral callbacks, a generic Lua schema walk and the prepared native path
as separate implementations. Encoding and decoding are measured independently,
and decoding covers schema order, reverse order, escaped keys and unknown nested
values.

`nupp.derive.JSON` is not redirected to serde until the complete record path is
at least as fast as the derive on its covered cases, without weakening its
validation or diagnostics. The prepared path must also retain a material
advantage over per-event callbacks; otherwise its native binding complexity is
not justified. Struct and dynamic results establish their own baselines rather
than borrowing the record result. Cold preparation is reported, not hidden by
warm-up, because short-lived programs may rationally keep the compatibility
derive until preparation becomes cheap enough.

### Smithy use

A Smithy package converts value shapes in a loaded model to serde schemas and
keeps services, operations and traits in its own model:

```nupp
local model = smithy.load(modelBytes)
local service = model:expectService("example#CoffeeShop")
local operation = service:expectOperation("CreateOrder")

local inputBinding = serde.dynamic(operation.inputSchema)
local input = inputBinding:bind {
    coffeeType = "coldBrew",
}

local output = client:call(operation, input)
```

The protocol selected for the service supplies the JSON, XML or CBOR profile
and prepares each operation's payload schemas. A generated client instead
places derived record bindings in the operation descriptor. Generated and
dynamic clients then share the protocol implementation and codecs; they differ
only in their bindings.

Smithy traits remain typed Smithy metadata. A Smithy profile interprets them
when producing a format extension. Neither `serde.Schema` nor a JSON codec
acquires service, operation or AWS-specific fields.

### Lowering

The exact private representation belongs to the serde materializer. A record
derive lowers conceptually to one schema graph, one record access blueprint and
one registration:

```lua
local userSchema = serdeRuntime.schema({
    kind = "structure",
    members = {
        {index = 1, name = "id", kind = "uint32", required = true},
        {index = 2, name = "displayName", kind = "string", required = false},
        {index = 3, name = "active", kind = "boolean", required = true},
    },
})

local userBinding = serdeRuntime.recordBinding(
    userSchema,
    User,
    {"id", "displayName", "active"}
)

serdeRuntime.register(User, userBinding)
```

A struct derive uses the checked layout the compiler already knows:

```lua
local vec3Binding = serdeRuntime.structBinding(vec3Schema, Vec3, {
    {index = 1, offset = 0, storage = "float"},
    {index = 2, offset = 4, storage = "float"},
    {index = 3, offset = 8, storage = "float"},
})
```

The offsets above are illustrative; the materializer obtains target-specific
values and carries the matching layout fingerprint. It does not paste source,
expose an unchecked offset constructor or make target-specific data part of the
logical schema.

No `writeJSON` or `fromJSON` traversal is generated for each type. Temporary
compatibility members call the default JSON codec with the type's serde binding
and can be removed after migration.

## Risks and assumptions

- **The flat-structure speedup may shrink with complete semantics.** Recursive
  containers, defaults, constraints, detailed paths and custom adapters add
  work. The design depends on retaining a material advantage after those cases
  join the benchmark.
- **A generic native traversal is more code to trust.** It handles several
  formats and representations at a boundary where an incorrect kind or offset
  could corrupt a struct. Binding construction must remain sealed and validate
  layout fingerprints.
- **Profiles can multiply cached layouts.** Interning makes equality cheap but
  does not bound a program deliberately constructing many distinct policies.
  Layouts follow schema lifetime, so dynamic clients must release models they
  no longer use.
- **First use performs real work.** Hash tables, encoded tags and recursive
  layouts are not free. `prepare` gives clients an eager warm-up point and
  keeps latency out of a first request where that matters.
- **The serde data model can become a lowest-common-denominator model.** Format
  extensions and typed annotations are the escape hatch, but a kind needed by
  one broadly used format may still force a difficult addition to the common
  graph.
- **Custom callback bindings may be much slower.** They preserve expressivity,
  not the performance promise of a prepared built-in binding. Documentation
  and profiling must make the selected path visible.
- **Struct pointers cannot be inferred safely.** Rejecting them makes some C
  layouts require adapters. Guessing their extent or ownership would be a
  correctness bug, so this friction is intentional.
- **Portable dialects may lack a native codec.** The schema and callback
  protocol remain portable, while the fused speedup depends on the selected
  runtime provider. This fits capability-backed standard-library selection but
  does not make all providers equally fast.
- **Extension providers must be deterministic.** Two computations for one
  immutable host and profile must produce equivalent layouts. A provider may
  retain process-local acceleration data but may not observe mutable instance
  state.

## Alternatives considered

**Keep one derive per format.** This makes a small feature easy to explain and
lets generated code specialize freely. It repeats type topology, multiplies
code by protocol variants, provides no natural dynamic-client path and measured
poorly when each generated operation crossed the native writer boundary.

**Generate one format-neutral callback implementation per type.** This is the
portable fallback retained by the proposal. Making it the only path leaves the
dominant per-event crossings intact and does not exploit raw-key parsing or
fixed struct offsets inside one native traversal.

**Use reflection descriptors directly as schemas.** Reflection describes the
whole Nupp type system, much of which no codec can serialize, and exists only
for declarations known to the compiler. Dynamic clients have no reflected
declaration. Derivation should project reflection into the smaller serde graph
rather than make codecs understand compiler semantics.

**Decode through a generic document.** This is maximally flexible and remains
the explicit document kind. Using it for typed decoding allocates keys and
containers that the final representation does not need, then repeats lookup and
validation.

**Generate native code for every prepared schema.** It could remove branches
from the generic codec loop, but introduces executable-memory policy,
architecture-specific generation, compilation latency and a native code cache.
The measured data-driven traversal is already fast enough to require proof
before adding those costs.

**Put field access into the schema.** This makes the first record implementation
smaller. It prevents a record, struct and dynamic value from sharing a schema
and makes format caches accidentally depend on physical representation.

**Serialize struct bytes directly.** This is fast only by changing the answer.
Padding, endian order, pointer addresses, host widths and ABI details become
wire data. Field-wise access through a checked binding retains struct speed
without inventing that format.

**Use a global cache keyed by schema fingerprints.** It can share work between
equivalent graphs, but needs collision handling, invalidation and explicit
ownership for native data. Extensions attached to immutable schema identity
have a natural lifetime and need no global coordination. Cross-schema
deduplication may be added inside an extension provider when measurement earns
it.

**Store format caches as string-keyed schema fields.** This is open to naming
collisions, exposes mutable implementation detail and pays a general table
lookup. Typed extension keys keep ownership and result types explicit and can
use dense internal slots.

## FAQ

### Does this make serde part of the type system?

No new serializable supertype is implied. `Binding<T>` is an ordinary generic
standard-library value produced from checked reflection or built explicitly.
The compiler participates where it already has exclusive knowledge: derive
augmentation, struct layout and opaque materialization.

### Does every encoded value carry a schema?

No. A binding, operation descriptor or prepared codec retains the schema once.
Instances remain ordinary records, structs or dynamic values. Dynamic values
carry schema identity because their slots otherwise have no interpretation.

### Are schema extensions generated code?

No. They are immutable data such as encoded byte fragments, lookup tables,
member indices and physical access descriptors. A generic codec consumes them.

### Can a codec stream?

Yes. A prepared codec may target an encoder session whose internal buffer is
flushed in chunks, and a schema may contain streaming bytes or event values
through an explicit adapter. Streaming changes value lifetime and transport,
not the schema/binding/extension separation.
