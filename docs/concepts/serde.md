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

Nested records, lists, and maps use the same schema and binding semantics. The
current JSON implementation falls back to a generic document traversal for a
root that contains those kinds while recursive native traversal is developed.
Preparation remains the API boundary, so that optimization does not change
callers.

`nupp.data.json.newCodec` is a compatibility entry point for the same codec.
`nupp.data.serde.json` is the typed primary API.

## Typed extensions

Schemas, bindings, and runtime reflection descriptors are extension hosts.
`nupp.extensions.key` creates a typed provider identity, and a host computes its
value once:

```nupp
local calls = 0
local displayName = nupp.extensions.key(function(schema: any): string
    calls = calls + 1
    return schema.name or "anonymous"
end)

local first = schema:extension(displayName)
local second = schema:extension(displayName)
assert(first == second and calls == 1)
```

Successful values and failures are cached. Recursive initialization reports an
error. Each key receives a dense process-local slot, and hosts cache extension
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

See [NEP 15](../neps/0015-schema-driven-serde.md) for the design reasoning and
the alternatives it rejected.
