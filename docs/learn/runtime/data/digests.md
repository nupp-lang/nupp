---
order: 190
title: Digests and checksums
---

# Digests and checksums

Message digests produce fixed-size opaque bytes. Checksums produce numeric
error-detection values. General-purpose hashes such as FNV are
[](binary.fnv1a64).
Base64 and hexadecimal are reversible codecs.

## Incremental digests

```nupp
local algorithm = binary.digest.algorithm("sha256")
assert(algorithm.digestsize == 32)
local rolling = algorithm:newdigest()
rolling:write("first chunk")
rolling:write("second chunk")
local raw: string = rolling:digest()
```

`binary.digest.newdigest(name)` is shorthand for
`algorithm(name):newdigest()`.
`lookup(name)` returns nil when an algorithm is unavailable; `algorithm` and
`newdigest` raise instead. `algorithms()` returns sorted canonical names.
Descriptors expose `name` and `digestsize` before construction; a created
digest exposes `algorithm()` and `digestsize()`.

The built-ins are `md5` (16 bytes), `sha1` (20), `sha256` (32), and
`sha512` (64). MD5 and SHA-1 are legacy interoperability algorithms and
must not be used where collision resistance is required.

A digest is an [`io.Writer`](io.Writer): `write(string)` and
`writespan(ByteSpan)` accept chunks without retaining input views, and the state
stays bounded as the message grows. Anything that fills a writer fills a digest,
so `reader:transferto(rolling)` hashes a file or a response body a window at a
time.

## Finalization and caller storage

`digest()` returns raw bytes, `digest(destination)` writes a writable byte span
and returns the byte count, and `hexdigest()` returns lowercase hexadecimal.
Every finalization consumes the digest; it neither snapshots nor resets it.
Scope exit closes an unfinished digest context.

```nupp
local rolling = binary.digest.newdigest("sha256")
rolling:write("payload")
local bytes = nupp.mem.array.bytes(rolling:digestsize())
local output = bytes:write()
local written: integer = rolling:digest(output)
assert(written == 32)
own.drop(output)
local readable = bytes:read()
assert(#readable == 32)
```

A destination must contain at least `digestsize()` bytes. Only that prefix
is written; pass a slice to choose an offset. A short destination raises before
any output is written. The digest is consumed and the digest context is closed
even when finalization fails. The destination remains owned by the caller.

One-shot conveniences are `binary.digest.digest(name, bytes)` and
`binary.digest.hexdigest(name, bytes)`. Encoding is also available
separately:
`binary.hexencode(raw)` or `binary.base64encode(raw)`.

## Checksums and MACs

```nupp
local sum = binary.checksum.newchecksum("crc32c")
assert(sum:width() == 32)
sum:write("1234")
local partial = sum:value()
sum:write("56789")
assert(sum:value() == 0xe3069283ULL)
```

A checksum is an `io.Writer` too. `value()` is a non-consuming numeric
snapshot, returned as `uint64`.
`width()`, and the descriptor's `width` field, specify meaningful bits.
Built-ins are `adler32`, `crc32`, `crc32c` and `crc64-ecma`.
`crc32` is the reflected IEEE variant. The digest names and `crc32`/`crc32c`
match Smithy's `httpChecksum` algorithm names in lowercase.
CRC64 uses ECMA-182 with no reflection, zero initialization and zero final xor.
It differs from Smithy's `CRC64NVME` algorithm.
The checksum API chooses no byte order: a protocol writes the value using its
own scalar serialization rules. Checksums provide no authentication.

`binary.mac.newmac("hmac-sha256", key)` accepts a raw-byte key and returns
the same writer and consuming finalization as a digest. Its descriptor has
`digestsize = 32`. The one-shot forms are `mac.digest(name, key, bytes)` and
`mac.hexdigest(name, key, bytes)`.

`hmac-sha256` names the HMAC construction over SHA-256. Smithy's `httpChecksum`
trait defines no MAC algorithms. AWS KMS uses `HMAC_SHA_256` for this
construction; SigV4's `AWS4-HMAC-SHA256` names the complete signing scheme.

## Algorithm catalogs

Each family uses its builtin algorithm catalog. Descriptors are retained during
module initialization, so lookup, listing, context creation, writes, and
finalization resolve no implementation again.

Every descriptor agrees with its map key and reports a positive fixed output
size, or a checksum width from 1 through 64. Each digest or MAC creates fresh
state. Writes borrow input bytes without retaining their views; finalization
writes exactly the advertised number of bytes and closes the state on success
or failure. A failure propagates without retrying another implementation.
