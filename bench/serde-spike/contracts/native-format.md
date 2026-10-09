# Native persistence format

Version 1 is a LuaJIT-local tree format selected with an explicit binding.
It uses LuaJIT `string.buffer` serialization for inert tagged arrays.

```nupp
local binding = declaration.binding(Save)
local codec = native.codec()
local bytes = codec:encode(binding, save)
local restored = codec:decode(binding, bytes)
```

The implementation is `nupp.serde.native`.

## Frame

A frame starts with the eight bytes `NUPP\0LJ\1`. The remainder is exactly one
`string.buffer` value, with no dictionary or metatable registration. Trailing
bytes, unknown frame versions, and old JSON store data are refused. Input and
output have a 16 MiB limit; trees have a one-million-node and 128-level limit.

Selecting the codec on a host without LuaJIT, or in the browser, fails before
binding traversal or input decoding. This version makes no cross-target or
independent-implementation compatibility promise. A portable format would use
a different frame version and its own specification.

## Nodes

Every node is a dense array. Its first element is a logical kind string.
The remaining elements are the payload below.

| Kind | Payload |
| --- | --- |
| `null` | None |
| `boolean` | One boolean |
| `string`, `bytes` | One string; the two logical kinds remain distinct |
| `numberToken` | One validated JSON numeric lexeme |
| `bigInteger` | One canonical signed decimal integer string |
| `integer` | Decimal integer string, width (8/16/32/64), signedness |
| `float` | Lua number, width (32/64); NaN and infinities are permitted |
| `decimal` | Canonical integer coefficient string, integral exponent |
| `timestamp` | Signed 64-bit seconds string, nanoseconds in [0, 1000000000) |
| `document` | One contents node, retaining the logical document boundary |
| `structure` | Alternating logical member name and value node |
| `union` | Exactly one logical member name and value node |
| `list`, `tuple` | Value nodes in order |
| `map` | Alternating key node and value node; keys retain their logical kinds |

Coefficients, seconds, and exact integers never pass through a floating-point
conversion. Decimal negative zero and scale remain distinct. Float width is
retained; this version does not promise NaN payload-bit preservation. Aggregate
shape, tag, width, arity, and scalar ranges are checked during decoding.

Names are durable member identities. Field reordering does not change them;
dense runtime slots and declaration fingerprints never appear in the frame.
Missing fields use the selected binding's defaults and construction rules.
Unknown fields follow its explicit rejection, skip, or capture behavior.

Atoms, resources, pointers, executable functions, and opaque protocol content
require an explicit adapter to supported values. The codec never writes raw
addresses, struct padding, a metatable, or executable module names. Runtime
schema and protocol context are not serialized: decoding establishes native
source context, and an explicitly supplied model binding reconstructs its own
schema context. Persisting a discriminator requires an explicit registry.

## Graph and construction rules

This is a tree format. Shared values are copied independently, and cycles are
refused. Constructors and binding-owned restoration hooks recreate transient
state. No type acquires universal persistence participation from its declaration.

The writer emits tagged arrays directly through the shared value visitor.
The decoder validates the complete wire tree before invoking model construction.
Typed readers consume the tagged arrays directly. A semantic document is
materialized when a document or unknown-value adapter requests one; ordinary
typed reconstruction creates no intermediate document tree. This specification
makes no throughput claim.

A codec owns a bounded cache of read/write schema extensions. Initialization is
lazy; recursive initialization and clearing during initialization are refused.
Failures are cached. `clear()` releases the cache's references, and no input
value is stored in an extension.

## Store snapshots

A persistence registry owns each persistent name, typed store key, explicit
binding, version, and optional migration. Ordinary anonymous store keys remain
ordinary store keys. Saving includes only keys registered with that registry.

Snapshots have their own format version (`1`) and entries containing `name`,
`version`, and `value`. The snapshot has an explicit binding and can be carried
by the selected codec. Loading returns a new store only after every selected
entry has been reconstructed. Duplicate names and unsupported versions fail;
unknown names follow the caller's `reject` or `skip` choice. A migration receives
the old version and its semantic value and produces the current semantic value.
It does not load executable code or mutate a live destination store.
