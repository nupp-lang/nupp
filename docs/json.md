# JSON

`nupp.data.json` holds the whole JSON surface. `encodeJSON` and `decodeJSON` use
the mature cjson implementation without exposing its module name:

```nupp:playground
local encoded = nupp.data.json.encodeJSON({name = "Nupp", ready = true})
local decoded = nupp.data.json.decodeJSON(encoded)
assert(decoded.name == "Nupp")
```

`NULL`, `EMPTY_ARRAY`, `ARRAY_MT`, and `EMPTY_ARRAY_MT` preserve distinctions Lua
tables cannot express by themselves. The configuration methods match cjson's
established semantics, but live on `nupp.data.json`. `newJSON()` returns an
independent `nupp.data.json.JSON` encoder/decoder with its own settings:

```nupp
local compact = nupp.data.json.newJSON()
compact.encodeKeepBuffer(false)
local text = compact.encodeJSON({1, 2, 3})
```

JSON selects the `cjson` native feature. No `require("cjson")` is needed or
recommended.

| Member | Result | Purpose |
| --- | --- | --- |
| `encodeJSON(value)` | string | Encode one Lua value. |
| `decodeJSON(text)` | any | Decode one JSON document. |
| `newJSON()` | nupp.data.json.JSON | Create a separately configured codec. |
| `NULL`, `EMPTY_ARRAY` | sentinel values | JSON values plain Lua cannot express. |
| `ARRAY_MT`, `EMPTY_ARRAY_MT` | metatables | Mark array-shaped tables explicitly. |

Both `nupp.data.json` and an object returned by `newJSON` provide the
configuration methods `encodeEmptyTableAsObject`, `decodeArrayWithArrayMt`,
`encodeSparseArray`, `encodeMaxDepth`, `decodeMaxDepth`,
`encodeNumberPrecision`, `encodeKeepBuffer`, `encodeInvalidNumbers`,
`decodeInvalidNumbers`, and `encodeEscapeForwardSlash`. Omitting a method's
setting reads the current value where the provider supports that form; passing
a setting changes only that codec.

Part of the [`nupp.data`](data.md) namespace, which also holds UUIDs, hashes
and checksums, and bitsets.
