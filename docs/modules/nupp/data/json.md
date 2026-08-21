`nupp.data.json` is a strict, simdjson-backed JSON codec. It parses, pulls
selected fields, serializes, and streams, without exposing a third-party Lua
module.

```nupp:playground
local encoded = nupp.data.json.encode({name = "Nupp", ready = true})
local decoded = nupp.data.json.decode(encoded)
assert(decoded.name == "Nupp")
```

The codec accepts one complete UTF-8 JSON document and rejects invalid numbers,
sparse arrays, mixed-key containers, cycles, and excessive nesting.
`serialize` is an alias of `encode`.

## Empty containers

A plain empty Lua table has no shape to read, so it encodes as `{}`. Mark it
when it must encode as an array, or use the two sentinels:

```nupp
const json = nupp.data.json

assert(json.encode({}) == "{}")
assert(json.encode(json.asArray({})) == "[]")
assert(json.encode(json.EMPTY_ARRAY) == "[]")
assert(json.encode(json.EMPTY_OBJECT) == "{}")
```

`asObject` is the corresponding mark for a table that must encode as an object.

## JSON null

Decoding drops JSON null by default, including from inside an array. Pass a
replacement value to preserve it. `NULL` is the round-trippable choice, because
it encodes back as null:

```nupp
const json = nupp.data.json

local value = json.decode([[{"items":[1,null,2]}]], json.NULL)
assert(value.items[2] == json.NULL)
assert(json.encode(value) == [[{"items":[1,null,2]}]])
```

::: deepdive Dropping null by default
A Lua table cannot hold nil as a value, so a decoded null has to become either
an absence or a sentinel. An absence is what most callers mean, and it keeps a
decoded document indexable without every read testing against a sentinel first.
A sentinel is what a caller round-tripping somebody else's document means, and
that caller says so once, at the `decode` call, rather than everywhere the
value is read.
:::

## Pulling selected values

`pull` uses simdjson's On-Demand API. `true` selects a complete value, an object
shape selects named fields, and `arrayOf(shape)` applies a shape to every member
of an array. Missing and unselected fields are omitted:

```nupp
const json = nupp.data.json

local users = json.pull(source, json.arrayOf({id = true, profile = {name = true}}))
```

This is the lower-level path for pull deserializers: it validates the complete
input but constructs only the Lua values the shape asks for.

## Streaming output

The writer emits checked JSON directly into caller-owned storage without first
building a Lua table or a complete result string. `finish()` verifies that the
document is complete:

```nupp
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
writer:startObject():key("items"):startArray():write(1):write(2):close():close()
writer:finish()
```

`encoded(value)` performs ordinary encoding once. `verified(text)` instead
validates an existing immutable JSON string without decoding or re-encoding it.
Both return a value that `write` appends without another walk or validation.
`encodedString(value)` and `verifiedString(text)` provide the corresponding
string-only form accepted by both `key` and `write`; these handles are interned,
so repeated schema keys share their encoded representation.

## Derived records

For a record deriving `nupp.derive.JSON`, `writeRecord(value, writer)` discovers
the record's type witness from the value. `writeAs(Record, value, writer)` and
`decodeAs(Record, text)` accept the visible record name directly. `encodeRecord`
and `encodeAs` allocate and return a complete string for callers that
specifically need one.

The generated `writeJSON(writer)` member writes through the same checked API, so
a derived record can occupy the root or any value position in a larger document.
Derived schemas lazily cache their encoded field names and literal values.

::: seealso
- [reflection.md](../../../concepts/reflection.md#json-through-a-type-witness)
  for the derived schema and the generated `writeJSON` and `fromJSON` members
- [derives.md](../../../reference/derives.md#json) for what `nupp.derive.JSON`
  adds to a declaration
- [data.md](../data.md) for the rest of the namespace, which also holds UUIDs,
  hashes and checksums
:::
