---
order: 180
---

# Standard library

Nupp's standard library provides types, text, data formats, I/O, and application
tools. Its APIs live in builtin tables such as `math` and in declared modules
such as `bytes`.

```nupp:playground
local digest = bytes.digest("sha256"):computehex("payload")
print(#digest, math.lerp(10, 20, 0.25))
```

## Intrinsics and declared modules

Compiler intrinsics live in their subject namespaces, such as `types`, `simd`,
and `own`. The compiler selects their implementations from the members checked
source reaches. Typed storage uses [](table.Array); [](bytes.Buffer) owns growable
byte buffers. See [bytes.md](bytes.md) for storage, spans, ownership, and copies.

Nupp-authored libraries outside that surface are ordinary declared modules on
disk. A qualified module path loads one only when the source uses it:

```nupp
const span = bytes.span

const text = "four"
local bytes = span.fromstring(text)
```

The full qualified form reaches the same declared file without the short
binding:

```nupp
const text = "four"
local bytes = bytes.span.fromstring(text)
```

It lowers to one hidden `require` in the containing module. It does not build a
global `bytes.span` table and does not add a load check at every call. The same
rule applies to a dependency root such as `tecs`. See [modules.md](../../language/modules.md)
for how a declared module is named and resolved.

## Library modules

The standard surface is deliberately small. These pages cover both the
intrinsic namespaces and the declared modules:

- [](bytes.digest) provides incremental MD5, SHA-1, SHA-256 and SHA-512
  with algorithm lookup, output-size metadata and consuming finalization.
- [](bytes.checksum) provides Adler-32 and explicitly named CRC variants
  as numeric values; protocols choose their serialization byte order.
- [](bytes.mac) provides keyed authentication, including HMAC-SHA256.
- [](bytes.fnv1a64) hashes bytes with FNV-1a.
- [](serde.json) and [](bytes) encode and decode
  representations. [](serde.valuebuilder) supports codec authors.
- [](utf8) validates and walks UTF-8 text.
- [](serde) binds application types to reusable serialization schemas.
- [](bytes.Bitset) is a growable set of bit positions. [](table.Pool) leases
  cleared records or zero-filled struct rows of one declaration;
  [](table.Pool) creates one. Released instances become reusable immediately,
  and an idle pool resets without discarding its allocations.
- [](types.Store) is a bag of values indexed by the typed keys [](types.Key)
  creates.
- `os.info()` reports execution platform, architecture, endianness, pointer
  width and available parallelism. `os.uuid(4)` and `os.uuid(7)` generate
  identifiers; `os.monotonic()` and `os.walltime()` read the host clocks. See
  [System services](../system.md) for their contracts.
- [](os.host) asks whatever runs the program, a page or an embedding
  application, for something by kind, and carries streams between them.
  [](os.host) runs an embedded component's operations for a host-owned
  loop. See [host.md](../host.md).
- [](bytes.Buffer) owns growable byte storage. [](io) provides readers, writers,
  and typed scalar reads and writes. [](bytes.SharedBytes) shares immutable
  engine storage across workers and lends byte views without copying.
- [](os) owns the filesystem: metadata, directories, links, temporary paths, and app storage roots.
- [](io.net) owns listeners, plain connections, and TLS sessions.
- [](io) models filesystem paths and resource identifiers.
- [](debug.log) owns leveled logging over a swappable destination.
- [](math) owns scalar and two-dimensional vector helpers.
- [](bytes.span) owns rooted, bounds-checked shared and writable C array views.
- [](table.Array) holds mutable typed elements, with packed and
  [columnar](structure-of-arrays.md) layouts.
- [](io.gpu) owns resident buffers, generated kernel dispatches, and tensor views.
  [](io.gpu.Layout) provides checked layout transformations.
- [](os.randombytes) provides cryptographically secure random bytes.
  [](math.Xoshiro128) owns deterministic pseudo-random sequences with explicit,
  serializable state.
- [](coroutine.suspend) waits for a callback result. [](coroutine) owns
  application task scopes, and [](coroutine.Scope.work) provides isolated worker
  lanes. [](coroutine.sus) registers and polls readiness sources.
  [](coroutine.sus.host) is the other side of waiting: what a host
  installs to decide which coroutine runs while something is parked.
- [](os) provides monotonic and wall clocks. [](coroutine) owns sleeps and
  deadlines.

See [gpu.md](../../performance/ahead-of-time/gpu.md) for generated GPU kernels and the
browser provider, and [workers.md](../concurrency/workers.md) for the worker
scheduler and sendable values.

## Availability and initialization

Compiler namespaces and builtin-table extensions use canonical declarations.
Use builtin libraries through their qualified names. The compiler inserts the
module loads those references need. The build binds builtin implementations for
the selected target.

### Selection follows use

A member's implementation is emitted only when checked source resolves that
member, and an alias stays as precise as the name it came from:

```nupp
const uuid = os.uuid
print(uuid(4))
```

At `-O1` and above, feature effects are recomputed after constant folding, so a
facility used only in a branch or loop that dead-code elimination removed keeps
neither its adapter nor its provider. Code generation makes the final selection
from the constructs it actually writes, so comptime erasure, materialization,
and other lowering cannot leave a source-only facility in the generated
first-line bootstrap. Native FFI declarations are split by that same set:
selecting UUID does not declare the path, files, or process ABI. SHA-256
declares none of its own: it is Nupp rather than a native provider.

### Target bindings

The build binds each builtin service to its native or browser implementation.
Generated module prologues load those modules before the consumer body runs.
Exported operations perform no provider discovery.

Packages can discover implementations of their own interfaces with
`package.providers` and `package.select`. Those descriptors do not replace
builtin services. See [SPI](../../projects/spi.md) for package discovery.

Runtime implementation contracts are private. Explicit C interop APIs,
including borrowed span pointer operations, retain their own target
and lifetime requirements.

### Forcing a native feature

[`nativeFeatures`](../../projects/build.md#compiler-native-features) turns a binary
feature on or off for an unusual packaging arrangement. Leave it unset and use
automatic detection unless the packaging requires otherwise.

## Byte positions

Storage offsets count from zero; element indexes count from one. Storage is a
[](bytes.Buffer), an
[](bytes.SharedBytes) or an open file: a range in one is
a zero-based offset and a count, because an offset names a distance from the
beginning and maps directly onto a native byte range. An element view, a
[span](bytes.span) or a [SoA](structure-of-arrays.md) view, and text, a Lua
string or [](utf8), use 1-based positions, as a Lua array and
`string.sub` do. Do not pass a `string.find` position to a buffer method.

## Errors and ownership

Check each operation's return signature before handling a failure. The typed
file, process, network, TLS and HTTP services use [](io.Error), whose `kind`
identifies failures such as `"notfound"`. The Lua stream function `io.open`
and `bytes.SharedBytes.readfile` return string reasons. Invalid arguments may
raise instead of returning a failure value.

A result declared `affine(...)` has a cleanup obligation: its local scope drops
it, and `own.drop` ends its lifetime early. Other values have different storage
lifetimes. `table.Array` and struct pool pages use managed storage; shared-byte
regions retain engine references. `bytes.Buffer` is affine and releases its
storage when its owner is dropped.

A writer that buffers output reports delivery failures through `flush`. Check
that result before closing when delivery matters. See
[ownership.md](../ownership/index.md) for affine ownership and borrowing.
