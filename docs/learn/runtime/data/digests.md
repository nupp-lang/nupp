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

An installed target dependency may advertise `service = "nupp.digest"`,
`name = "sha256"`, `api = 1`, and an entry exporting a
`nupp.digest.provider.Algorithm`. Its descriptor supplies `name`,
`digestSize`, and `create(self): State`. State implements incremental
`update(ByteSpan)`, `finish(ByteWriteSpan)`, and consuming `close()`.
The facade owns finalization allocation, hex formatting and state cleanup.
State must not retain input or destination views, and each create must return
independent state. A finish implementation writes exactly the descriptor's size.

An installed algorithm takes precedence over the built-in with the same name.
Built-in names require their standard output sizes; malformed descriptors raise.
Provider failures propagate without silently retrying another implementation.
Two dependencies registering the same service/name fail the build. Without a
registered service, the standard built-in answers.

Checksums use `nupp.checksum.provider.Algorithm` under `nupp.checksum`;
their state implements `update(ByteSpan)`, `value(): uint64`, and `close()`.
MACs use `nupp.mac.Provider` under `nupp.mac`, whose factory also takes the key.
See [Service providers](../../projects/service-providers.md) for dependency
descriptors and deterministic build composition.
