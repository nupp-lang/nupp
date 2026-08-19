`nupp.data` groups serialization, Unicode, identifiers, byte digests and
bitsets. Reach it directly from the global [`nupp`
namespace](../../concepts/standard-library.md); the C and Rust providers remain
hidden.

Each nested module has a page of its own: [`nupp.data.json`](data/json.md),
[`nupp.data.utf8`](data/utf8.md) and [`nupp.data.bitset`](data/bitset.md). What
is described here is what the namespace holds directly.

```nupp
local eventID = nupp.data.uuid7()
local digest = nupp.data.sha256("payload")
print(eventID, digest)
```

## UUIDs

`uuid4()` returns a random RFC 9562 version 4 identifier. `uuid7()` returns a
time-ordered version 7 identifier, useful when identifier order should roughly
follow creation order:

```nupp
local objectID = nupp.data.uuid4()
local eventID = nupp.data.uuid7()
```

Both are lowercase canonical strings. They share one `uuid` feature and never
expose a native UUID object.

## Hashes and checksums

Each function accepts a string or immutable
[`nupp.io.ByteView`](io.md#byte-views).

```nupp
assert(nupp.data.fnv1a64("hello") == "a430d84680aabd0b")
assert(nupp.data.sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

local checksum = nupp.data.crc32(header)
checksum = nupp.data.crc32(body, checksum)
```

`fnv1a64` is a fast non-cryptographic identity rendered as 16 lowercase
hexadecimal digits. `sha256` is a cryptographic digest rendered as 64 lowercase
hexadecimal digits. `crc32` returns an unsigned 32-bit number and accepts a
previous result for incremental checksumming. Checksums detect accidental
damage; they do not authenticate data. A supplied previous checksum must itself
be an unsigned 32-bit integer.

FNV-1a and CRC-32 are pure generated Lua. SHA-256 is independently
gated in the shared Rust provider. See [automatic native
selection](../../guides/build.md#compiler-native-features).

| Member | Result | Native provider |
| --- | --- | --- |
| `uuid4()` | canonical UUID string | shared provider, uuid feature |
| `uuid7()` | canonical UUID string | shared provider, uuid feature |
| `fnv1a64(value)` | 16 lowercase hex digits | none |
| `sha256(value)` | 64 lowercase hex digits | shared provider, sha256 feature |
| crc32(value, previous?) | unsigned 32-bit number | none |
