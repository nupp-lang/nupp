---
order: 180
---

# Standard library

Nupp's standard library provides types, text, data formats, I/O, and application
tools. Its APIs live in builtin tables such as `math` and in declared modules
such as `binary.digest`.

```nupp
local digest = binary.digest.hexdigest("sha256", "payload")
print(#digest, math.lerp(10, 20, 0.25))
```

## Intrinsics and declared modules

`nupp` names compiler intrinsics. The compiler selects their implementations
from the members checked source reaches.

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
global `nupp.mem` table and does not add a load check at every call. The same
rule applies to a dependency root such as `tecs`. See [modules.md](../../language/modules.md)
for how a declared module is named and resolved.

## Library modules

The standard surface is deliberately small. These pages cover both the
intrinsic namespaces and the declared modules:

- [](binary.digest) provides incremental MD5, SHA-1, SHA-256 and SHA-512
  with provider lookup, output-size metadata and consuming finalization.
- [](binary.checksum) provides Adler-32 and explicitly named CRC variants
  as numeric values; protocols choose their serialization byte order.
- [](binary.mac) provides keyed authentication, including HMAC-SHA256.
- [](binary.fnv1a64) hashes bytes with FNV-1a.
- [](serde.json), [](binary.base64) and [](binary.hex) encode and decode
  representations. [](serde.valuebuilder) supports codec authors.
- [](utf8) validates and walks UTF-8 text.
- [](serde) binds application types to reusable serialization schemas.
- [](binary.Bitset) is a growable set of bit positions. [](table.Pool) leases
  cleared record instances of one declared type from a free list;
  [](table.newpool) creates one.
- [](types.Store) is a bag of values indexed by the typed keys [](types.newkey)
  creates.
- `os.info()` reports execution platform, architecture, endianness, pointer
  width and available parallelism. `os.uuid4()` and `os.uuid7()` generate
  identifiers; `os.monotonic()` and `os.walltime()` read the host clocks. See
  [System services](../system.md) for their contracts.
- [](nupp.host) asks whatever runs the program, a page or an embedding
  application, for something by kind, and carries streams between them.
  [](nupp.host.pump) runs an embedded component's operations for a host-owned
  loop. See [host.md](../host.md).
- [](io) owns byte buffers, readers, writers, and typed scalar reads and writes
  over them.
- [](io.files) owns filesystem metadata and directories.
- [](io.net) owns listeners, plain connections, and TLS sessions.
- [](io) models filesystem paths and resource identifiers.
- [](log) owns leveled logging over a swappable destination.
- [](math) owns scalar and two-dimensional vector helpers.
- [](binary.span) owns rooted, bounds-checked shared and writable C array views.
- [`nupp.mem.soa`](structure-of-arrays.md) stores every top-level field of a
  reified struct in its own column.
- [](nupp.mem.arena) leases zero-filled struct rows from pages that never move.
- [](io.gpu) owns resident buffers, generated kernel dispatches, and tensor views.
  [](io.gpu.layout) owns the checked layout algebra.
- [](os.randombytes) provides cryptographically secure random bytes.
  [](nupp.random) owns deterministic pseudo-random sequences with explicit,
  serializable state.
- [](coroutine.suspension), [](coroutine), and [](coroutine.workers) provide
  waiting, application task scopes, and isolated worker lanes.
  [](coroutine.suspension.host) is the other side of waiting: what a host
  installs to decide which coroutine runs while something is parked.
- [](os) provides monotonic and wall clocks. [](coroutine) owns sleeps and
  deadlines.
- [](nupp.text.regex) matches regular expressions where Lua patterns are not enough.

See [gpu.md](../../performance/ahead-of-time/gpu.md) for GPU kernels, and [workers.md](../concurrency/workers.md) for the worker
scheduler and sendable values.

## Availability and initialization

Compiler namespaces and builtin-table extensions use canonical declarations.
Declared library modules load through qualified references or ordinary
`require` calls. Providers resolve while their facades load.

### Selection follows use

A member's implementation is emitted only when checked source resolves that
member, and an alias stays as precise as the name it came from:

```nupp
const uuid4 = os.uuid4
print(uuid4()) -- selects UUID support
```

A `binary` target's runtime links a native facility, such as compression or
the HTTP client, only when the program's image reaches a module that needs it;
see [Native runtime](../../../reference/native-runtime.md#facility-selection).
SHA-256 needs none: it is Nupp rather than a native provider.

### Provider initialization

A module selects its implementation while it is required and retains the actual
functions. Exported operations perform no SPI lookup.

Implementations satisfy the interface in the library's `.spi` module and are
advertised in `nupp/spi.json`. Standard-library consumers choose the unique highest
priority, or use their built-in fallback when discovery is empty. See
[SPI](../../projects/spi.md) for ordinary selection code and package discovery.

The public surface does not expose the JSON provider module, a provider's own
handles, or native pointers. Those are implementation details, so application code
keeps the same Nupp API when a provider changes.

## Byte positions

Storage offsets count from zero; element indexes count from one. Storage is a
[](io.Buffer), a [](io.ByteView), a
[`sharedbytes.Region`](nupp.mem.sharedbytes) or an open file: a range in one is
a zero-based offset and a count, because an offset names a distance from the
beginning and maps directly onto a native byte range. An element view, a
[span](binary.span) or a [SoA](structure-of-arrays.md) view, and text, a Lua
string or [](utf8), use 1-based positions, as a Lua array and
`string.sub` do. Do not pass a `string.find` position to a buffer method.

## Errors and ownership

An operation that can fail because of the environment returns `nil, reason`. The
files, process, network, TLS and HTTP modules give that reason as a
[](io.Error), whose `kind` names the failure the same way on every
platform, so a program branches on `err.kind == "notfound"` rather than on the
message. An invalid argument or a malformed programmer-owned value raises at the
call site. Every owner the library hands out, from a buffer to an open file, is
an `own.Closeable`: `close` consumes it and returns nothing, `own.drop` closes
it early, and the end of its scope closes it otherwise. A destination that
buffers writes reports a failure through `flush`, so a caller that has to know
flushes before it closes. Buffers and views report use after release, and a
reader or writer returns a reason once it has been closed. See
[ownership.md](../ownership/index.md) for the cleanup obligation an affine
result carries.

## FAQ

### Does an intrinsic need a `require`?

No. A member reached through the `nupp` namespace is selected by the compiler
from the source that names it, which is why the example above runs with no
imports. A declared module such as `binary.span` is a file on disk, so it is
bound with `require` or reached through its qualified name, as [Intrinsics and
declared modules](#intrinsics-and-declared-modules) shows.

### Does an unused facility cost anything in the built program?

No adapter is emitted for a member no checked source resolves, and a binary's
runtime links no facility its image does not reach. See [Selection follows
use](#selection-follows-use) for what counts as a use.

### Can a buffer offset be passed to a Lua string function?

Not directly. A buffer offset counts from zero and a Lua string position counts
from one, so the two differ by one on every call. Convert at the boundary, and
see [Byte positions](#byte-positions) for which convention an API uses.

::: seealso
- [](io) for buffers, readers, writers, and byte views
- [ownership.md](../ownership/index.md) for the affine results these modules return
- [build.md](../../projects/build.md#native-facilities) for the native
  facilities a binary links
:::
