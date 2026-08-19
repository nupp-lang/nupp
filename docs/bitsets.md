`nupp.data.bitset` holds sets of bit positions across as many 32-bit words as
they need. LuaJIT's `bit` library operates on one word at a time and has no
population count or trailing-zero operation, so the multi-word part lives here:
the word loop, range masks that span word boundaries, counting across words, and
walking set positions.

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
namespace loads on first reach, which costs about half a millisecond and 128KB
of static tables: LuaJIT exposes neither a population count nor a trailing-zero
operation, so both are half-word lookups, and paying for the tables once is
worth 1.58 times the counting speed and 1.20 times the walking speed of the
byte-sized ones. A program that never reaches a bitset pays neither.

| Member | Result | Purpose |
| --- | --- | --- |
| `create(capacityBits?)` | `nupp.data.bitset.Bitset` | An empty set. |
| `WORD_BITS` | integer | Bits per stored word. |
| `set(index)`, `clear(index)`, `get(index)` | none / boolean | One position. |
| `setRange(low, high)` | none | An inclusive range, by word masks. |
| `setOnly(index)`, `clearAll()` | none | Replace the contents. |
| `count()`, `isEmpty()` | integer / boolean | How much is set. |
| `containsAll(other)`, `overlaps(other)`, `disjoint(other)` | boolean | Compare two sets. |
| `orWith`, `andWith`, `andNotWith`, `xorWith`, `copyFrom` | none | Set algebra in place. |
| `nextSetBit(from)` | integer, or -1 | Walk set positions. |
| `positionsInto(target, capacity, from)` | written, resume | Extract every set position in one call. |
| `wordCount()`, `wordAt(index)` | integer | Walk stored words. |
| `reserve(bits)` | none | Grow ahead of use. |

Part of the [`nupp.data`](data.md) namespace, which also holds UUIDs, hashes
and checksums.
