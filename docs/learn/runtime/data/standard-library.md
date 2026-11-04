---
order: 180
---

# Standard library

Nupp's standard library provides types, text, data formats, I/O, and application
tools. Its APIs live in builtin tables such as `math` and in declared modules
such as `binary.digest`.

```nupp:playground
local digest = binary.digest.hexdigest("sha256", "payload")
print(#digest, math.lerp(10, 20, 0.25))
```

## Intrinsics and declared modules

Compiler intrinsics live in their subject namespaces, such as `types`, `simd`,
and `own`. The compiler selects their implementations from the members checked
source reaches. Typed storage uses [](nupp.array), [](nupp.heap) and
[](nupp.soa); [](string.buffer) owns FIFO byte buffers.

Nupp-authored libraries outside that surface are ordinary declared modules on
disk. A qualified module path loads one only when the source uses it:

```nupp
const span = binary.span

const text = "four"
local bytes = span.fromstring(text)
```

The full qualified form reaches the same declared file without the short
binding:

```nupp
const text = "four"
local bytes = binary.span.fromstring(text)
```

It lowers to one hidden `require` in the containing module. It does not build a
global `binary.span` table and does not add a load check at every call. The same
rule applies to a dependency root such as `tecs`. See [modules.md](../../language/modules.md)
for how a declared module is named and resolved.

## Library modules

The standard surface is deliberately small. These pages cover both the
intrinsic namespaces and the declared modules:

- [](binary.digest) provides incremental MD5, SHA-1, SHA-256 and SHA-512
  with algorithm lookup, output-size metadata and consuming finalization.
- [](binary.checksum) provides Adler-32 and explicitly named CRC variants
  as numeric values; protocols choose their serialization byte order.
- [](binary.mac) provides keyed authentication, including HMAC-SHA256.
- [](binary.fnv1a64) hashes bytes with FNV-1a.
- [](serde.json) and [](binary) encode and decode
  representations. [](serde.valuebuilder) supports codec authors.
- [](utf8) validates and walks UTF-8 text.
- [](serde) binds application types to reusable serialization schemas.
- [](binary.Bitset) is a growable set of bit positions. [](table.Pool) leases
  cleared records or zero-filled struct rows of one declaration;
  [](table.newpool) creates one. Released instances become reusable immediately,
  and an idle pool resets without discarding its allocations.
- [](types.Store) is a bag of values indexed by the typed keys [](types.newkey)
  creates.
- `os.info()` reports execution platform, architecture, endianness, pointer
  width and available parallelism. `os.uuid4()` and `os.uuid7()` generate
  identifiers; `os.monotonic()` and `os.walltime()` read the host clocks. See
  [System services](../system.md) for their contracts.
- [](os.host) asks whatever runs the program, a page or an embedding
  application, for something by kind, and carries streams between them.
  [](os.host) runs an embedded component's operations for a host-owned
  loop. See [host.md](../host.md).
- [](io) owns byte buffers, readers, writers, and typed scalar reads and writes
  over them. [](io.Bytes) shares immutable engine storage across workers and
  lends byte views without copying.
- [](io.files) owns filesystem metadata and directories.
- [](io.net) owns listeners, plain connections, and TLS sessions.
- [](io) models filesystem paths and resource identifiers.
- [](debug.log) owns leveled logging over a swappable destination.
- [](math) owns scalar and two-dimensional vector helpers.
- [](binary.span) owns rooted, bounds-checked shared and writable C array views.
- [`nupp.soa`](structure-of-arrays.md) stores every top-level field of a
  reified struct in its own column.
- [](io.gpu) owns resident buffers, generated kernel dispatches, and tensor views.
  [](io.gpu.layout) owns the checked layout algebra.
- [](os.randombytes) provides cryptographically secure random bytes.
  [](math.random) owns deterministic pseudo-random sequences with explicit,
  serializable state.
- [](coroutine.suspend) waits for a callback result. [](coroutine) owns
  application task scopes, and [](coroutine.workers) provides isolated worker
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
const uuid4 = os.uuid4
print(uuid4()) -- selects UUID support
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
including native `string.buffer` pointer operations, retain their own target
and lifetime requirements.

### Forcing a native feature

[`nativeFeatures`](../../projects/build.md#compiler-native-features) turns a binary
feature on or off for an unusual packaging arrangement. Leave it unset and use
automatic detection unless the packaging requires otherwise.

## Byte positions

Storage offsets count from zero; element indexes count from one. Storage is a
[](io.Buffer), a [](io.ByteView), a
[](io.Bytes) or an open file: a range in one is
a zero-based offset and a count, because an offset names a distance from the
beginning and maps directly onto a native byte range. An element view, a
[span](binary.span) or a [SoA](structure-of-arrays.md) view, and text, a Lua
string or [](utf8), use 1-based positions, as a Lua array and
`string.sub` do. Do not pass a `string.find` position to a buffer method.

## Errors and ownership

Check each operation's return signature before handling a failure. The typed
file, process, network, TLS and HTTP services use [](io.Error), whose `kind`
identifies failures such as `"notfound"`. The Lua stream function `io.open`
and `io.Bytes.readfile` return string reasons. Invalid arguments may
raise instead of returning a failure value.

A result declared `affine(...)` has a cleanup obligation: its local scope drops
it, and `own.drop` ends its lifetime early. Other values have different storage
lifetimes. `nupp.array` and struct pool pages use managed storage; shared-byte
regions retain engine references; `string.buffer.Buffer` provides `free` to
discard retained capacity. None of those APIs promises automatic cleanup merely
because a local leaves scope.

A writer that buffers output reports delivery failures through `flush`. Check
that result before closing when delivery matters. See
[ownership.md](../ownership/index.md) for affine ownership and borrowing.

## FAQ

### Does an intrinsic need a `require`?

No. Use builtin APIs directly, such as `types.sizeof`, `debug.log.info`, or
`binary.span.fromstring`. The compiler resolves the qualified name and inserts
any required module load. See [Intrinsics and declared
modules](#intrinsics-and-declared-modules) for the distinction.

### Does an unused facility cost anything in the built program?

No adapter and no native artifact are emitted for a member no checked source
resolves. Selection is recomputed after constant folding at `-O1` and above, so
a facility whose only use was eliminated drops out with it. See [Selection
follows use](#selection-follows-use) for what counts as a use.

### Can a buffer offset be passed to a Lua string function?

Not directly. A buffer offset counts from zero and a Lua string position counts
from one, so the two differ by one on every call. Convert at the boundary, and
see [Byte positions](#byte-positions) for which convention an API uses.

::: seealso
- [](io) for buffers, readers, writers, and byte views
- [ownership.md](../ownership/index.md) for the affine results these modules return
- [build.md](../../projects/build.md#compiler-native-features) for native feature
  detection and its override
:::
