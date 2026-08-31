---
order: 135
title: Schema-driven serde
---

# Schema-driven serde

Serde separates a value's logical shape, its physical representation, and its
wire format:

- `Schema` describes members, scalar kinds, requiredness, and defaults.
- `Binding<T>` joins that schema to a record, struct, or dense dynamic value.
- a codec profile decides format policy such as JSON field names and unknown
  member handling.

The separation lets a generated record and a run-time client use the same codec
without making the standard library understand a service model such as Smithy.
Format-specific work is prepared and cached rather than generated once per
type, protocol, and format.

## Derived bindings

`@derive(nupp.derive.Serde)` records format-neutral materialization data. It
does not add serialization methods to an instance.

```nupp:playground
@derive(nupp.derive.Serde)
local record User
    id: uint32
    name: string?
end

local binding = nupp.data.serde.of(User)
local prepared = nupp.data.serde.json():prepare(binding)
local text = prepared:encode(new User(id = 41, name = "Ada"))
local restored, problem = prepared:decode(text)
local output = string.buffer.new()
prepared:write(new User(id = 42), output)

assert(text == [[{"id":41,"name":"Ada"}]])
assert(problem == nil)
assert(restored and restored.name == "Ada")
```

The declaration name is the `Type<T>` witness accepted by `serde.of`. This is
also true for a fixed-layout struct:

```nupp
@derive(nupp.derive.Serde)
local struct Vec3
    x: float
    y: float
    z: float
end

local binding: nupp.data.serde.Binding<Vec3> = nupp.data.serde.of(Vec3)
```

Struct derivation reads fields individually. It does not serialize padding,
endianness, or the memory image. Pointer fields are rejected because the field
type alone establishes neither their extent nor their ownership.

## Dynamic schemas

A dynamic client builds and freezes the same logical schema, then binds names
once into dense indexed storage:

```nupp
const serde = nupp.data.serde
local builder = new serde.SchemaBuilder()
builder:structure("example.User")
builder:required("id", serde.uint32)
builder:defaulted("active", serde.boolean, true)
builder:optional("name", serde.string)

local schema = builder:freeze()
local binding = serde.dynamic(schema)
local value = binding:bind{id = 41, name = "Ada"}
local text = serde.json():prepare(binding):encode(value)
```

`bind` rejects unknown members, missing required members, wrong scalar kinds,
and out-of-range fixed-width integers. Code constructing many values can retain
a `Member` and avoid name resolution:

```nupp
local id = schema:expectMember("id")
local value = binding:newValue()
value:set(id, 41)
assert(value:get(id) == 41)
```

A schema may have several bindings at once. A nominal record and a dynamic
value can therefore share logical member identity while retaining different
physical access plans.

## Typed metadata

`MetadataKey<T>` is a typed identity for data supplied with a schema. A dynamic
client can attach root or member metadata while constructing its model:

```nupp
const serde = nupp.data.serde
local serviceName: nupp.data.serde.MetadataKey<string> = serde.metadataKey()
local builder = new serde.SchemaBuilder()
builder:structure("example.Credentials")
builder:required("user", serde.string)
builder:required("password", serde.string)
builder:metadata(serviceName, "example")
builder:memberMetadata("password", serde.debugRedact, true)

local schema = builder:freeze()
assert(schema:metadata(serviceName) == "example")
assert(schema:expectMember("password"):metadata(serde.debugRedact) == true)
```

Every key receives a dense process-local index. The index is never serialized
or treated as stable across runs; it makes both derived and dynamic metadata a
direct indexed lookup after the schema is frozen.

## Debug preparation

`Debug` is a schema consumer rather than a separate generated traversal. Its
prepared plan combines member metadata such as `debugRedact` and `debugSkip`
with the binding's record, struct, or dynamic-slot access once, then caches the
result on the binding:

```nupp
local prepared = serde.prepareDebug(binding)
local text = prepared:format(value)

local output = string.buffer.new()
prepared:write(value, output)
```

`format` returns the conventional Debug string. `write` appends directly to a
caller-owned LuaJIT string buffer, which avoids allocating that complete result
and is the appropriate path for logging and larger composed diagnostics. A
derived `value:debug()` lazily retains the prepared operation on its type entry;
it does not resolve schema extensions for each field or each call.

## JSON preparation

`json()` creates an immutable profile. `prepare(binding)` memoizes the combined
schema and physical plan on that codec:

```nupp
local codec = nupp.data.serde.json{
    unknownMembers = "ignore",
    fieldNames = function(member: nupp.data.serde.Member): string
        return member.name == "id" and "userId" or member.name
    end,
}
local prepared = codec:prepare(binding)
```

The field-name function runs during preparation, not once per value. For flat
scalar structures, the native plan retains pre-encoded output keys, compares
input key bytes directly, tracks required members, and traverses the complete
root in one native call. Known input keys are not materialized as Lua strings;
ignored values are validated and skipped without constructing a document.
`write(value, buffer)` appends the complete root to caller-owned storage in one
buffer operation; encoder scratch is pooled per worker thread.

Nested records, lists, maps, optionals, and documents use the same schema and
binding semantics and are traversed by the recursive prepared implementation.
Preparation remains the API boundary for adding more format-specific
optimizations without changing callers.

`nupp.data.json.newCodec` is a compatibility entry point for the same codec.
`nupp.data.serde.json` is the typed primary API.

## Typed extensions

Schemas, bindings, and runtime reflection descriptors are extension hosts.
`nupp.reflect.extensionKey` creates a typed provider identity, and a host computes its
value once:

```nupp
local calls = 0
local displayName = nupp.reflect.extensionKey(function(schema: any): string
    calls = calls + 1
    return schema.name or "anonymous"
end)

local first = schema:extension(displayName)
local second = schema:extension(displayName)
assert(first == second and calls == 1)
```

Metadata is supplied by a model builder or derive. Extensions differ by
computing a derived value lazily from their host. Successful extension values
and failures are cached, and recursive initialization reports an error. Each
extension key receives a dense process-local slot, and hosts cache extension
state by that integer rather than by key-object identity. Slots are acceleration
values: their numbers may change with module initialization order and are never
persistent metadata identifiers. JSON uses schema extensions for profile layouts
and binding extensions for physical access, so format facts do not leak into the
logical schema.

## Relationship to the JSON derive

`nupp.derive.JSON` remains available and retains its existing record methods
and `@json` policy. It is not silently redirected through Serde. Serde is the
language-wide abstraction for new codecs and dynamic clients; compatibility
derives can migrate only after their complete format behavior and diagnostics
have matching prepared implementations.

See [NEP 15](../../../neps/0015-schema-driven-serde.md) for the design reasoning and
the alternatives it rejected.
