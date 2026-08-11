# Data and text

`nupp.data` groups serialization, Unicode, identifiers and byte digests. Reach it
directly from the global [`nupp` namespace](stdlib.md); the C and Rust providers remain
hidden.

## JSON

`encodeJSON` and `decodeJSON` use the mature cjson implementation without exposing its
module name:

```nupp
local encoded = nupp.data.encodeJSON({name = "Nupp", ready = true})
local decoded = nupp.data.decodeJSON(encoded)
assert(decoded.name == "Nupp")
```

`null`, `emptyArray`, `arrayMt`, and `emptyArrayMt` preserve distinctions Lua tables
cannot express by themselves. The configuration methods match cjson's established
semantics, but live on `nupp.data`. `newJSON()` returns an independent `nupp.data.JSON`
encoder/decoder with its own settings:

```nupp
local compact = nupp.data.newJSON()
compact.encodeKeepBuffer(false)
local text = compact.encodeJSON({1, 2, 3})
```

JSON selects the `cjson` native feature. No `require("cjson")` is needed or recommended.

| Member | Result | Purpose |
| --- | --- | --- |
| `encodeJSON(value)` | `string` | Encode one Lua value. |
| `decodeJSON(text)` | `any` | Decode one JSON document. |
| `newJSON()` | `nupp.data.JSON` | Create an independently configured codec. |
| `null`, `emptyArray` | sentinel values | Represent JSON values that plain Lua tables cannot distinguish. |
| `arrayMt`, `emptyArrayMt` | metatables | Mark array-shaped tables explicitly. |

Both `nupp.data` and an object returned by `newJSON` provide the configuration
methods `encodeEmptyTableAsObject`, `decodeArrayWithArrayMt`,
`decodeAllowComment`, `encodeSparseArray`, `encodeMaxDepth`,
`decodeMaxDepth`, `encodeNumberPrecision`, `encodeKeepBuffer`,
`encodeInvalidNumbers`, `decodeInvalidNumbers`,
`encodeEscapeForwardSlash`, `encodeSkipUnsupportedValueTypes`, and
`encodeIndent`. Omitting a method's setting reads the current value where the
provider supports that form; passing a setting changes only that codec.

## UTF-8

`nupp.data.utf8` treats strings and [`nupp.io.ByteView`](io.md#byte-views) values as byte
sequences. Byte offsets are 1-based here so they compose with Lua string positions.
Invalid input decodes as U+FFFD while validation remains explicit.

```nupp
local utf8 = nupp.data.utf8
assert(utf8.length("A€") == 2)

local codepoint, nextByte = utf8.decodeAt("A€", 2)
assert(codepoint == 0x20ac and nextByte == 5)

codepoint, nextByte = utf8.decodeBefore("A€", nextByte)
assert(codepoint == 0x20ac and nextByte == 2)

assert(utf8.encode(0x20ac) == "€")
assert(utf8.isValid("café"))
assert(not utf8.isValid("\xff"))
assert(utf8.truncate("A€B", 4) == "A€")
```

`validPrefixLength(value, maxBytes)` returns the largest valid prefix no longer than the
byte budget. `truncate` applies that operation to a string. The underlying lua-utf8
provider loads only when this namespace is selected and reached.

| Member | Result | Position rule |
| --- | --- | --- |
| `length(value)` | `integer` | Counts decoded scalar values, replacing malformed bytes individually. |
| `decodeAt(value, byteOffset)` | `integer?, integer` | Decodes forward from a 1-based byte offset and returns the next offset. |
| `decodeBefore(value, byteOffset)` | `integer?, integer` | Decodes the scalar ending before a 1-based byte offset. |
| `encode(codepoint)` | `string` | Encodes one Unicode scalar value. |
| `isValid(value)` | `boolean` | Validates the complete byte sequence. |
| `validPrefixLength(value, maxBytes)` | `integer` | Finds a valid prefix within a byte budget. |
| `truncate(text, maxBytes)` | `string` | Copies that valid prefix. |

## UUIDs

`uuid4()` returns a random RFC 9562 version 4 identifier. `uuid7()` returns a
time-ordered version 7 identifier, useful when identifier order should roughly follow
creation order:

```nupp
local objectID = nupp.data.uuid4()
local eventID = nupp.data.uuid7()
```

Both are lowercase canonical strings. They share one `uuid` feature and never expose a
native UUID object.

## Hashes and checksums

Each function accepts a string or immutable [`nupp.io.ByteView`](io.md#byte-views).

```nupp
assert(nupp.data.fnv1a64("hello") == "a430d84680aabd0b")
assert(nupp.data.sha256("abc") ==
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

local checksum = nupp.data.crc32(header)
checksum = nupp.data.crc32(body, checksum)
```

`fnv1a64` is a fast non-cryptographic identity rendered as 16 lowercase hexadecimal
digits. `sha256` is a cryptographic digest rendered as 64 lowercase hexadecimal digits.
`adler32` and `crc32` return unsigned 32-bit numbers and accept a previous result for
incremental checksumming. Checksums detect accidental damage; they do not authenticate
data. A supplied previous checksum must itself be an unsigned 32-bit integer.

FNV-1a, Adler-32 and CRC-32 are pure generated Lua. SHA-256 is independently gated in
the shared Rust provider. See [automatic native selection](tooling/build.md#compiler-native-features).

| Member | Result | Native provider |
| --- | --- | --- |
| `uuid4()` | canonical UUID string | shared provider, `uuid` feature |
| `uuid7()` | canonical UUID string | shared provider, `uuid` feature |
| `fnv1a64(value)` | 16 lowercase hex digits | none |
| `sha256(value)` | 64 lowercase hex digits | shared provider, `sha256` feature |
| `adler32(value, previous?)` | unsigned 32-bit number | none |
| `crc32(value, previous?)` | unsigned 32-bit number | none |
