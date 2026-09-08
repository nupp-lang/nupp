---
order: 190
title: Digests and checksums
---

# Digests and checksums

Message digests produce fixed-size opaque bytes. Checksums produce numeric
error-detection values. General-purpose hashes such as FNV live in `nupp.hash`.
Base64 and hexadecimal are reversible codecs.

## Incremental digests

```nupp
local algorithm = nupp.digest.algorithm("sha256")
assert(algorithm.digestSize == 32)
local rolling = algorithm:create()
rolling:update("first chunk")
rolling:update("second chunk")
local raw: string = rolling:digest()
```

`nupp.digest.create(name)` is shorthand for `algorithm(name):create()`.
`lookup(name)` returns nil when an algorithm is unavailable; `algorithm` and
`create` raise instead. `algorithms()` returns sorted canonical names.
Descriptors expose `name` and `digestSize` before construction; a created
digest exposes `algorithm()` and `digestSize()`.

The built-ins are `md5` (16 bytes), `sha1` (20), `sha256` (32), and
`sha512` (64). MD5 and SHA-1 are legacy interoperability algorithms and
must not be used where collision resistance is required.

`update(string)` and `updateSpan(ByteSpan)` accept chunks without retaining
input views. The state stays bounded as the message grows.

## Finalization and caller storage

`digest()` returns raw bytes, `digest(destination)` writes a writable byte
span and returns the byte count, and `hexDigest()` returns lowercase hexadecimal.
Every finalization consumes the digest; it neither snapshots nor resets it.
Scope exit closes an unfinished provider context.

```nupp
local rolling = nupp.digest.create("sha256")
rolling:update("payload")
local bytes = nupp.mem.array.bytes(rolling:digestSize())
local output = bytes:write()
local written: integer = rolling:digest(output)
assert(written == 32)
drop output
local readable = bytes:read()
assert(#readable == 32)
```

A destination must contain at least `digestSize()` bytes. Only that prefix
is written; pass a slice to choose an offset. A short destination raises before
any output is written. The digest is consumed and the provider context is closed
even when finalization fails. The destination remains owned by the caller.

One-shot conveniences are `nupp.digest.digest(name, bytes)` and
`nupp.digest.hexDigest(name, bytes)`. Encoding is also available separately:
`nupp.codec.hex.encode(raw)` or `nupp.codec.base64.encode(raw)`.

## Checksums and MACs

```nupp
local sum = nupp.checksum.create("crc32c")
assert(sum:width() == 32)
sum:update("1234")
local partial = sum:value()
sum:update("56789")
assert(sum:value() == 0xe3069283ULL)
```

`value()` is a non-consuming numeric snapshot, returned as `uint64`.
`width()`, and the descriptor's `width` field, specify meaningful bits.
Built-ins are `adler32`, `crc32-ieee`, `crc32c` and `crc64-ecma`.
CRC64 uses ECMA-182 with no reflection, zero initialization and zero final xor.
The checksum API chooses no byte order: a protocol writes the value using its
own scalar serialization rules. Checksums provide no authentication.

`nupp.mac.create("hmac-sha256", key)` accepts a raw-byte key and returns the
same consuming update/finalization vocabulary as a digest. Its descriptor has
`digestSize = 32`. The one-shot forms are `mac.digest(name, key, bytes)`
and `mac.hexDigest(name, key, bytes)`.

## Service providers

Each family has a canonical typed catalog under `nupp.runtime.services`:

| Facade | Contract module | Provider contents |
| --- | --- | --- |
| `nupp.digest` | `nupp.runtime.services.digest` | `algorithms: {[string]: Algorithm}` |
| `nupp.checksum` | `nupp.runtime.services.checksum` | `algorithms: {[string]: Algorithm}` |
| `nupp.mac` | `nupp.runtime.services.mac` | `algorithms: {[string]: Algorithm}` |

Import the contract's `service` handle in an ordinary setup module, register a
checked loader returning its `Provider`, and select its implementation name before
requiring the public facade. An implementation name identifies a catalog, such as
`acme`, independently of the algorithm names its map contains.

```nupp
local contract = require("nupp.runtime.services.digest")
contract.service:register("acme", function(): contract.Provider
    return require("acme.digests")
end)
contract.service:select("acme")
local digest = require("nupp.digest")
```

A target dependency can advertise the same provider without executing its loader
during discovery. Its schema 2 capability names `service = "nupp.digest"`,
`name = "acme"`, `api = 1`, `contract = "nupp.runtime.services.digest"`,
`export = "service"`, and the implementation's module in `entry`. Lua providers
supply a matching `.d.nupp` declaration or a typed adapter. The compiler checks the
export against the canonical `Provider`, including the owned state signatures.

The facade resolves its selected catalog while being required and retains its
algorithm descriptors. Explicitly selected entries override matching built-ins
and can add names; other built-ins remain available. Without explicit selection,
the built-in catalog supplies all algorithms. Discovery order never chooses a
provider. Selection freezes at facade initialization, and later changes raise.
Lookup, listing, context creation, updates, and finalization make no SPI calls.

Descriptors must agree with their map keys and report a positive fixed output
size, or a checksum width from 1 through 64. Built-in names retain their standard
sizes and widths. Invalid descriptors fail the facade's require. Provider failures
propagate without retrying another implementation. Duplicate implementation names
are rejected.

Each digest descriptor creates a fresh canonical `State`. Its `update` borrows
input bytes, `finish` borrows the caller's writable destination exclusively, and
`close` consumes ownership without suspension. The facade allocates final output,
encodes hexadecimal, and closes state on both successful and failed finalization.
Providers must not retain input or output views and must write exactly their
advertised byte count. Checksums use their canonical `State` with a non-consuming
`value(): uint64`; MAC factories additionally accept the raw-byte key and return
the shared digest state. Reuse these interfaces rather than defining public
nominal identities in a provider.

See [Service providers](../../projects/service-providers.md) for setup, dependency
metadata, and worker-state initialization.
