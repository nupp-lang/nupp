Bytes become values and values become bytes: `nupp.data` holds serialization,
Unicode, identifiers, byte digests and bitsets. Reach it from the global [`nupp`
namespace](../../concepts/standard-library.md), which is where the C and Rust
providers behind it stay hidden.

```nupp
local eventID = nupp.data.uuid7()
local digest = nupp.data.sha256("payload")
local visible = new nupp.data.Bitset(1024)
visible:set(37)
```

The small byte algorithms and identifiers live directly on `nupp.data`:
`fnv1a64`, `crc32`, `sha256`, `uuid4`, and `uuid7`. `Bitset` is its growable
set of bit positions. The facilities with their own substantial runtime remain
modules of their own.

- See [json.md](data/json.md) for JSON encoding and decoding, and the values a
  Lua table cannot express by itself.
- See [utf8.md](data/utf8.md) for codepoint operations over strings and byte
  views.
- See [](nupp.data.valuebuilder) for ordinary Lua values built straight out of
  parsed bytes.

The digests and the UTF-8 operations take a string or a
[`ByteView`](io.md#byte-views) interchangeably, so a parser holding a buffer
passes the view rather than converting it at every call site. JSON decoding
takes text.

## Choosing a digest

Three functions reduce bytes to a short value, and they promise different
things. Use `nupp.data.sha256` where the digest has to stand up to someone
choosing the input, `nupp.data.fnv1a64` for keying and bucketing, and
`nupp.data.crc32` for detecting accidental damage.

```nupp
local integrity = nupp.data.sha256(contents) -- 64 hex digits
local bucket = nupp.data.fnv1a64(key) -- 16 hex digits
```

They cost in the reverse order of what they promise, so reaching for the
strongest by default taxes every call that only needed a bucket.

## Bitsets

`new nupp.data.Bitset(bits)` creates a growable, zero-based bitset. Reading,
clearing, and testing beyond its current capacity are defined; setting beyond
it grows the private storage. Set algebra works a word at a time, and `count`
computes the population on demand.

## Native selection

Which functions are native is not part of the contract. The build selects the
UUID or SHA-256 provider only when generated code reaches that exact member. See
[Compiler-native features](../../guides/build.md#compiler-native-features) for
how feature selection works and how to override it.
