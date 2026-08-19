`nupp.data` groups serialization, Unicode, identifiers, byte digests and
bitsets. Reach it directly from the global [`nupp`
namespace](../../concepts/standard-library.md); the C and Rust providers remain
hidden.

Every facility is a module of its own, and each one documents itself. What a
member guarantees, what it costs, and what it is not suitable for are written
where it is implemented rather than repeated here.

```nupp
const uuid7 = require("nupp.data.uuid7")
const sha256 = require("nupp.data.sha256")

local eventID = uuid7()
local digest = sha256("payload")
```

## What it holds

- [`nupp.data.json`](data/json.md) — JSON encoding and decoding, and the values
  a Lua table cannot express by itself.
- [`nupp.data.utf8`](data/utf8.md) — codepoint operations over strings and byte
  views.
- [`nupp.data.bitset`](data/bitset.md) — a growable set of bit positions.
- `nupp.data.uuid4` and `nupp.data.uuid7` — random and time-ordered
  identifiers, as RFC 9562 writes them.
- `nupp.data.sha256`, `nupp.data.fnv1a64` and `nupp.data.crc32` — a
  cryptographic digest, a fast identity, and a damage check, in that order of
  what they promise.
- `nupp.data.valuebuilder` — ordinary Lua values, built straight out of parsed
  bytes.

Which of these is native is not part of the contract. Some are generated Lua and
some stand on the shared Rust provider; a program that reaches none of them
carries neither. See [automatic native
selection](../../guides/build.md#compiler-native-features).
