Bytes become values and values become bytes: `nupp.data` holds serialization,
Unicode, identifiers, byte digests and bitsets. Reach it from the global [`nupp`
namespace](../../concepts/standard-library.md), which is where the C and Rust
providers behind it stay hidden.

```nupp
const uuid7 = require("nupp.data.uuid7")
const sha256 = require("nupp.data.sha256")

local eventID = uuid7()
local digest = sha256("payload")
```

Every member is a module of its own, reached by the name it has. Nothing is
re-exported here, so there is one name for each facility and one page that
documents it.

- See [json.md](data/json.md) for JSON encoding and decoding, and the values a
  Lua table cannot express by itself.
- See [utf8.md](data/utf8.md) for codepoint operations over strings and byte
  views.
- See [bitset.md](data/bitset.md) for a growable set of bit positions.
- See [](nupp.data.uuid4) and [](nupp.data.uuid7) for random and time-ordered
  identifiers, as RFC 9562 writes them.
- See [](nupp.data.valuebuilder) for ordinary Lua values built straight out of
  parsed bytes.

The digests and the UTF-8 operations take a string or a
[`ByteView`](io.md#byte-views) interchangeably, so a parser holding a buffer
passes the view rather than converting it at every call site. JSON decoding
takes text.

## Choosing a digest

Three modules reduce bytes to a short value, and they promise different things.
Use [](nupp.data.sha256) where the digest has to stand up to someone choosing
the input, [](nupp.data.fnv1a64) for keying and bucketing, and
[](nupp.data.crc32) for detecting accidental damage.

```nupp
const sha256 = require("nupp.data.sha256")
const fnv1a64 = require("nupp.data.fnv1a64")

local integrity = sha256(contents) -- 64 hex digits
local bucket = fnv1a64(key) -- 16 hex digits
```

They cost in the reverse order of what they promise, so reaching for the
strongest by default taxes every call that only needed a bucket.

## Native selection

Which of these is native is not part of the contract. Some are generated Lua,
some stand on the shared Rust provider, and a program that reaches none of them
carries neither the code nor the library. The build decides that from what the
generated code actually uses, and a caller writes the same thing either way. See
[Compiler-native features](../../guides/build.md#compiler-native-features) for
how a feature is selected and how to override the choice.
