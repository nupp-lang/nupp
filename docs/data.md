# Data and text

`nupp.data` groups serialization, Unicode, identifiers, byte digests and
bitsets. Reach it directly from the global [`nupp` namespace](stdlib.md); the C
and Rust providers remain hidden.

The two nested modules large enough to need a page of their own have one:
[`nupp.data.json`](json.md) and [`nupp.data.utf8`](utf8.md). What is described
here is what the namespace holds directly.

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
selection](tooling/build.md#compiler-native-features).

| Member | Result | Native provider |
| --- | --- | --- |
| `uuid4()` | canonical UUID string | shared provider, uuid feature |
| `uuid7()` | canonical UUID string | shared provider, uuid feature |
| `fnv1a64(value)` | 16 lowercase hex digits | none |
| `sha256(value)` | 64 lowercase hex digits | shared provider, sha256 feature |
| crc32(value, previous?) | unsigned 32-bit number | none |

## Bitsets

`nupp.data.bitset` holds sets of bit positions across as many 32-bit words as
they need. LuaJIT's `bit` library operates on one word at a time and has no
population count or trailing-zero operation, so the multi-word part — the word
loop, range masks that span word boundaries, counting across words, and walking
set positions — lives here.

Positions count from 0. Reading, clearing and testing a position past the end
are defined and cheap; setting one grows.

```nupp:static
local visible = nupp.data.bitset.create(1024)
visible:set(37)
visible:setRange(64, 127)

local culled = nupp.data.bitset.create(1024)
culled:set(100)
visible:andNotWith(culled)

local index = visible:nextSetBit(0)
while index >= 0 do
    consider(index)
    index = visible:nextSetBit(index + 1)
end
```

`count` is resolved when it is read rather than maintained as the set changes.
`orWith`, `andWith`, `andNotWith` and `xorWith` are one bitwise operation per
word and mark the population for recount, because a per-word population count
costs more than the operation itself. A caller that never reads `count` never
pays for one.

`wordCount` and `wordAt` expose the storage a word at a time, which is how a
walk over a large set avoids one call per position. `wordCount` is an upper
bound: every word at or above it is zero, but it is not narrowed by `clear` or
by intersection, because keeping it exact would cost a backwards scan on every
one of those. Derive word arithmetic from `WORD_BITS` rather than assuming the
width.

`nextSetBit` holds no state on the set, so walks may be nested and a mutation
between two calls cannot invalidate one in progress.

`positionsInto` writes every set position into an array in one call, which is
what a per-frame extraction should use: a walk pays a call and a word read for
each position it returns, and one call measured 1.3 to 1.6 times faster than the
same walk over a few thousand positions. It takes a pointer and a count rather
than allocating, so nothing is allocated per frame, and returns how many it
wrote alongside the position to resume from when the destination filled first.

```nupp:static
local ffi = require("ffi")
local live = ffi.new("int32_t[?]", capacity)

local written, resume = visible:positionsInto(live, capacity, 0)
for index = 0, written - 1 do
    consider(live[index])
end
if resume >= 0 then
    -- The destination filled; the next call carries on from here.
end
```

This is pure generated Lua with no native provider, so it stays available in a
one-file `bundle` target. It is an ordinary checked Nupp module that the
namespace loads on first reach, which costs about half a millisecond and 128KB of
static tables: LuaJIT exposes neither a population count nor a trailing-zero
operation, so both are half-word lookups, and paying for the tables once is worth
1.58 times the counting speed and 1.20 times the walking speed of the byte-sized
ones. A program that never reaches a bitset pays neither.

| Member | Result | Purpose |
| --- | --- | --- |
| `create(capacityBits?)` | `nupp.data.bitset.Bitset` | An empty set. |
| `WORD_BITS` | integer | Bits per stored word. |
| `set(index)`, `clear(index)`, `get(index)` | — / boolean | One position. |
| `setRange(low, high)` | — | An inclusive range, by word masks. |
| `setOnly(index)`, `clearAll()` | — | Replace the contents. |
| `count()`, `isEmpty()` | integer / boolean | How much is set. |
| `containsAll(other)`, `overlaps(other)`, `disjoint(other)` | boolean | Compare two sets. |
| `orWith`, `andWith`, `andNotWith`, `xorWith`, `copyFrom` | — | Set algebra in place. |
| `nextSetBit(from)` | integer, or -1 | Walk set positions. |
| `positionsInto(target, capacity, from)` | written, resume | Extract every set position in one call. |
| `wordCount()`, `wordAt(index)` | integer | Walk stored words. |
| `reserve(bits)` | — | Grow ahead of use. |
