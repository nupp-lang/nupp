# UTF-8

`nupp.data.utf8` treats strings and [`nupp.io.ByteView`](io.md#byte-views)
values as byte sequences. Byte offsets are 1-based here so they compose with Lua
string positions. Invalid input decodes as U+FFFD while validation remains
explicit.

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

`validPrefixLength(value, maxBytes)` returns the largest valid prefix no longer
than the byte budget. `truncate` applies that operation to a string. The
underlying lua-utf8 provider loads only when this namespace is selected and
reached.

| Member | Result | Position rule |
| --- | --- | --- |
| `length(value)` | integer | Counts scalars, replacing malformed bytes one by one. |
| decodeAt(value, byteOffset) | integer?, integer | Decodes forward from a 1-based offset, then the next. |
| decodeBefore(value, byteOffset) | integer?, integer | Decodes the scalar ending before a 1-based offset. |
| `encode(codepoint)` | string | Encodes one Unicode scalar value. |
| `isValid(value)` | boolean | Validates the complete byte sequence. |
| validPrefixLength(value, maxBytes) | integer | Finds a valid prefix within a byte budget. |
| truncate(text, maxBytes) | string | Copies that valid prefix. |

Part of the [`nupp.data`](data.md) namespace, which also holds UUIDs, hashes
and checksums, and bitsets.
