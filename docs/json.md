# JSON

`nupp.data.json` is Nupp's strict, simdjson-backed JSON runtime. It parses,
selectively pulls, serializes, and streams JSON without exposing a third-party
Lua module:

```nupp
local encoded = nupp.data.json.encode({name = "Nupp", ready = true})
local decoded = nupp.data.json.decode(encoded)
assert(decoded.name == "Nupp")
```

The codec accepts one complete UTF-8 JSON document and rejects invalid numbers,
sparse arrays, mixed-key containers, cycles, and excessive nesting. A plain empty
Lua table encodes as `{}`. Use `asArray({})` or `EMPTY_ARRAY` when it must encode
as `[]`; `EMPTY_OBJECT` is the corresponding explicit object value.

JSON null is dropped during decoding by default, including from arrays. Pass a
replacement value to preserve it. `NULL` is the standard round-trippable choice:

```nupp
local json = nupp.data.json
local value = json.decode([[{"items":[1,null,2]}]], json.NULL)
assert(value.items[2] == json.NULL)
assert(json.encode(value) == [[{"items":[1,null,2]}]])
```

| Member | Result | Purpose |
| --- | --- | --- |
| `encode(value, nullValue?)` | string | Serialize one Lua value. |
| `serialize(value, nullValue?)` | string | Alias of `encode`. |
| `decode(text, nullValue?)` | any | Materialize one complete document. |
| `pull(text, shape, nullValue?)` | any | Materialize only selected fields. |
| `arrayOf(shape?)` | table | Apply a pull shape to every array member. |
| `asArray(table)` | table | Mark a table as an array, including while empty. |
| `asObject(table)` | table | Mark a table as an object. |
| `writer(nullValue?)` | Writer | Create an incremental streaming writer. |
| `NULL` | value | Preserve and serialize JSON null. |
| `EMPTY_ARRAY`, `EMPTY_OBJECT` | values | Explicit empty containers. |

## Pulling selected values

`pull` uses simdjson's On-Demand API. `true` selects a complete value, an object
shape selects named fields, and `arrayOf(shape)` applies a shape to every member
of an array. Missing and unselected fields are omitted:

```nupp
local json = nupp.data.json
local users = json.pull(source, json.arrayOf({id = true, profile = {name = true}}))
```

This is the lower-level path for pull deserializers: it validates the complete
input but constructs only the Lua values the shape asks for.

## Streaming output

The writer emits checked JSON without first building a Lua DOM. `flush()` returns
the completed bytes since the previous flush; `finish()` closes the document and
returns the final bytes.

```nupp
local writer = nupp.data.json.writer()
writer:startObject():key("items"):startArray():write(1):write(2):close():close()
local text = writer:finish()
```

Part of the [`nupp.data`](data.md) namespace, which also holds UUIDs, hashes,
and checksums.

## Derived records

For a record deriving `nupp.derive.JSON`, `encodeRecord(value)` discovers the
record's type witness from the value. `encodeAs(Record, value)` and
`decodeAs(Record, text)` accept the visible record name directly. The derived
schema and generated `toJSON`/`fromJSON` members are documented once in
[Reflection](concepts/reflection.md#json-through-a-type-witness) and
[Declaration derives](derives.md#json).
