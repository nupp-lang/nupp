`nupp.data.bitset` holds a set of bit positions across as many 32-bit words as
it needs. Reach for it where a program tracks membership over a dense range of
integers, such as which entities a frame culled.

```nupp
const bitset = nupp.data.bitset

local visible = bitset.create(1024)
visible:set(37)
visible:setRange(64, 127)
assert(visible:get(37) and visible:count() == 65)
```

LuaJIT's `bit` library operates on one word at a time and has neither a
population count nor a trailing-zero operation, so everything that makes a
bitset a bitset lives here: the word loop, range masks that span word
boundaries, counting across words, and walking set positions.

## Positions and growth

Positions count from 0, because bit `i` lives in word `i / WORD_BITS`. Reading,
clearing and testing a position past the end are defined and cheap; setting one
grows the storage. `reserve` grows ahead of use, and `create` takes an initial
capacity in bits.

`setOnly` replaces the contents with one position and `clearAll` empties the
set. Derive word arithmetic from `WORD_BITS` rather than assuming the width.

## Set algebra

`orWith`, `andWith`, `andNotWith` and `xorWith` are one bitwise operation per
word, and `copyFrom` replaces one set with another:

```nupp
const bitset = nupp.data.bitset

local visible = bitset.create(1024)
visible:setRange(0, 99)

local culled = bitset.create(1024)
culled:set(50)
visible:andNotWith(culled)
assert(not visible:get(50))
```

`containsAll`, `overlaps` and `disjoint` compare two sets without building a
third. `count` is resolved when it is read rather than maintained as the set
changes, so a caller that never reads it never pays for one: a per-word
population count would otherwise cost more than the operation it followed.

## Walking set positions

`nextSetBit(from)` answers the lowest set position at or after `from`, or -1
when there is none. It holds no state on the set, so walks may be nested and a
mutation between two calls cannot invalidate one in progress:

```nupp
local index = visible:nextSetBit(0)
while index >= 0 do
    consider(index)
    index = visible:nextSetBit(index + 1)
end
```

`wordCount` and `wordAt` expose the storage a word at a time, which is how a
walk over a large set avoids one call per position. `wordCount` is an upper
bound: every word at or above it is zero, but it is not narrowed by `clear` or
by intersection, because keeping it exact would cost a backwards scan on every
one of those.

## Extracting every position at once

`positionsInto` writes every set position into an array in one call, which is
what a per-frame extraction should use. It takes a pointer and a count rather
than allocating, so nothing is allocated per frame, and it answers how many it
wrote alongside the position to resume from when the destination filled first:

```nupp
local ffi = require("ffi")
local live = ffi.new("int32_t[?]", capacity)

local written, resume = visible:positionsInto(live, capacity, 0)
for index = 0, written - 1 do
    consider(live[index])
end
if resume >= 0 then
    -- `live` filled first, so the next call starts here.
end
```

::: deepdive Cost of the lookup tables
This is pure generated Lua with no native provider, so it stays available in a
one-file `bundle` target. Loading it costs about half a millisecond and 128KB
of static tables, because LuaJIT exposes neither a population count nor a
trailing-zero operation and both are therefore half-word lookups. Paying for
the tables once buys 1.58 times the counting speed and 1.20 times the walking
speed of byte-sized tables, and one `positionsInto` call measured 1.3 to 1.6
times faster than the same walk over a few thousand positions. A program that
never reaches a bitset pays none of it.
:::

::: seealso
- [data.md](../data.md) for the rest of the namespace, which also holds JSON,
  UUIDs, hashes and checksums
- [build.md](../../../guides/build.md#compiler-native-features) for why a
  module with no native provider survives into a bundle unchanged
:::
