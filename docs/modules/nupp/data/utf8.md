`nupp.data.utf8` reads Unicode scalars out of strings and
[`nupp.io.ByteView`](../io.md#byte-views) values. Reach for it to count, decode,
validate or truncate text whose bytes came from somewhere else.

```nupp
const utf8 = nupp.data.utf8

assert(utf8.length("A€") == 2)
assert(utf8.encode(0x20ac) == "€")
```

`length` counts scalars, replacing each malformed byte with one replacement
scalar rather than refusing the string. `encode` goes the other way, from one
scalar value to its bytes.

## Byte offsets

Offsets here are 1-based, so they compose with Lua string positions and with
`string.sub` on the same text. This is the opposite of the zero-based offsets a
[buffer](../io.md#buffers) uses, because those are offsets into storage rather
than positions in text.

## Decoding a scalar

`decodeAt` decodes forward from an offset and answers the scalar with the
offset after it. `decodeBefore` decodes the scalar ending before an offset and
answers it with the offset it starts at, so the two walk in opposite
directions over the same positions:

```nupp
const utf8 = nupp.data.utf8

local codepoint, nextByte = utf8.decodeAt("A€", 2)
assert(codepoint == 0x20ac and nextByte == 5)

codepoint, nextByte = utf8.decodeBefore("A€", nextByte)
assert(codepoint == 0x20ac and nextByte == 2)
```

A malformed byte answers `0xFFFD` and advances exactly one byte, so a walk over
damaged text makes progress rather than stalling. Nil is the end of the value,
and that is what stops the walk:

```nupp
const utf8 = nupp.data.utf8

local at = 1
while true do
    local codepoint, nextAt = utf8.decodeAt(text, at)
    if codepoint == nil then break end
    at = nextAt
end
```

One past the end is an accepted offset; anything further raises.

## Validating and truncating

Validation is explicit, because decoding never refuses. `isValid` checks a
complete byte sequence:

```nupp
const utf8 = nupp.data.utf8

assert(utf8.isValid("café"))
assert(not utf8.isValid("\xff"))
```

Overlong forms, surrogate halves and codepoints above the maximum are
malformed even though their lead bytes are well formed, so they are rejected
on the value rather than on the shape.

`validPrefixLength(value, maxBytes)` answers the length of the largest valid
prefix no longer than a byte budget, which is what keeps a fixed-width field
from splitting a scalar in half. `truncate` applies that to a string and copies
the prefix:

```nupp
const utf8 = nupp.data.utf8

assert(utf8.validPrefixLength("A€B", 4) == 4)
assert(utf8.truncate("A€B", 4) == "A€")
```

`truncate` takes a string, since it answers one. Everything else on this page
takes a string or a byte view.

::: seealso
- [io.md](../io.md#byte-views) for the byte views these operations accept
- [data.md](../data.md) for the rest of the namespace, which also holds UUIDs,
  hashes and checksums
:::
