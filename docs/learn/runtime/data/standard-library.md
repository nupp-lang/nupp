---
order: 180
---

# Standard library

`nupp` is the compiler-provided intrinsic namespace, present in every checked
file. Reach for it when a program needs bytes, text, digests, logging, math, or
a parser and does not want a dependency for them.

```nupp:playground
local digest = nupp.digest.hexDigest("sha256", "payload")
print(#digest, nupp.math.lerp(10, 20, 0.25))
```

## Intrinsics and declared modules

The namespace is a language surface, not an ambient source module and not a
package tree assembled from declaration files. The compiler selects each
implementation from the members checked source actually reaches, so nothing is
loaded on a program's behalf.

Nupp-authored libraries outside that surface are ordinary declared modules on
disk. A qualified module path loads one only when the source uses it:

```nupp
const span = nupp.mem.span

local storage = carray(int32, 4)
local values = span.fromCarray(storage, 4)
```

The full qualified form reaches the same declared file without the short
binding:

```nupp
local values = nupp.mem.span.fromCarray(storage, 4)
```

It lowers to one hidden `require` in the containing module. It does not build a
global `nupp.mem` table and does not add a load check at every call. The same
rule applies to a dependency root such as `tecs`. See [modules.md](../../language/modules.md)
for how a declared module is named and resolved.

::: deepdive
Keeping the intrinsic surface out of the module graph is what lets the compiler
decide, per program, which implementations exist at all. A package tree would
have to answer every parent-package import with a table whose members are all
present, so either every program carries every facility or the answer depends
on a load order the source does not show. A language surface hands out no such
table: the members a file names are the members that get emitted.
:::

## Library modules

The standard surface is deliberately small. These pages cover both the
intrinsic namespaces and the declared modules:

- [](nupp.digest) provides incremental MD5, SHA-1, SHA-256 and SHA-512 with
  provider lookup, output-size metadata and consuming finalization.
- [](nupp.checksum) provides Adler-32 and explicitly named CRC variants as
  numeric values; protocols choose their serialization byte order.
- [](nupp.hash) provides general-purpose FNV-1a hashing.
- [](nupp.mac) provides keyed authentication, including HMAC-SHA256.
- [](nupp.crypto) provides cryptographically secure random bytes.
- [](nupp.uuid) generates version 4 and version 7 identifiers.
- [](nupp.codec.json), [](nupp.codec.base64) and [](nupp.codec.hex) encode and
  decode representations. [](nupp.codec.valuebuilder) supports codec authors.
- [](nupp.text.utf8) validates and walks UTF-8 text.
- [](nupp.serde) binds application types to reusable serialization schemas.
- [](nupp.store) owns typed keys and stores; [](nupp.bitset) owns bitsets.
- [](nupp.system) reports execution platform, architecture, endianness, pointer
  width and available parallelism, independently of the worker scheduler.
- [](nupp.io.storage) provides persistent key-value storage through the require-time
  provider.
- [](nupp.io) owns byte buffers, readers, writers, and typed scalar reads and
  writes over them.
- [](nupp.io.files) owns filesystem metadata and directories.
- [](nupp.io.net) owns listeners and the connections they accept, and
  connections a program opens itself.
- [](nupp.io.tls) encrypts one of those connections.
- [](nupp.io.path) models filesystem paths, and [](nupp.io.uri) models resource
  names.
- [](nupp.log) owns leveled logging over a swappable destination.
- [](nupp.math) owns scalar and two-dimensional vector helpers.
- [](nupp.mem.span) owns rooted, bounds-checked shared and writable C array
  views.
- [`nupp.mem.soa`](structure-of-arrays.md) stores every top-level field of a
  reified struct in its own column.
- [](nupp.mem.pool) leases cleared record instances from a free list, and
  [](nupp.mem.arena) leases zero-filled struct rows from pages that never move.
- [](nupp.gpu) owns resident buffers, generated kernel dispatches, and
  tensor views. [](nupp.gpu.layout) owns the checked layout algebra.
  [](nupp.browser.gpu) supplies the bounded browser `xorU32` operation.
- [](nupp.random) owns deterministic pseudo-random sequences with explicit,
  serializable state.
- [](nupp.suspension), [](nupp.tasks), and [](nupp.workers) provide waiting,
  application task scopes, and isolated worker lanes.
- [](nupp.time) owns monotonic time, wall time, sleeps, and deadlines.
- [](nupp.peg) compiles byte-oriented parsing-expression grammars.

See [gpu.md](../../performance/ahead-of-time/gpu.md) for generated GPU kernels and the
browser provider, and [workers.md](../concurrency/workers.md) for the worker
scheduler and sendable values.

## Availability and initialization

`nupp` and `nupp.math` are intrinsic namespaces. The other standard modules
have their own declared module identities and are loaded through qualified
references or ordinary require calls. Providers resolve while their facades load.

### Selection follows use

A member's implementation is emitted only when checked source resolves that
member, and an alias stays as precise as the name it came from:

```nupp
local uuid = nupp.uuid
print(uuid.v4()) -- selects UUID support
```

At `-O1` and above, feature effects are recomputed after constant folding, so a
facility used only in a branch or loop that dead-code elimination removed keeps
neither its adapter nor its provider. Code generation makes the final selection
from the constructs it actually writes, so comptime erasure, materialization,
and other lowering cannot leave a source-only facility in the generated
first-line bootstrap. Native FFI declarations are split by that same set:
selecting UUID does not declare the path, files, or process ABI. SHA-256
declares none of its own: it is Nupp rather than a native provider.

### Provider initialization

A service-backed module resolves its provider while it is required. Generated
module prologues bind those modules before the consumer body runs. Exported
operations retain the resolved implementation and call it directly.

A setup entry imports canonical handles from `nupp.runtime.services`, registers
or selects implementations, and then requires its consumer entry. Importing a
contract defines its handle without loading a provider. Once a facade resolves,
its default selection is fixed for that Lua state. See
[service providers](../../projects/service-providers.md) for typed contracts and
package discovery.

The public surface does not expose the JSON provider module, a provider's own
handles, or FFI pointers. Those are implementation details, so application code
keeps the same Nupp API when a provider changes.

### Forcing a native feature

[`nativeFeatures`](../../projects/build.md#compiler-native-features) turns a binary
feature on or off for an unusual packaging arrangement. Leave it unset and use
automatic detection unless the packaging requires otherwise.

## Byte positions

String functions inherited from Lua use 1-based positions. The byte container
APIs use zero-based offsets, because an offset names a distance from the
beginning and maps directly onto a native byte range. Each API page states its
convention; do not pass a `string.find` position to a buffer method.

## Errors and ownership

An operation that can fail because of the environment returns `nil, reason`. An
invalid argument or a malformed programmer-owned value raises at the call site.
Buffers and views implement `close` and report use after release, and a reader
or writer returns a reason once it has been closed. See
[ownership.md](../ownership/index.md) for the cleanup obligation an affine result
carries.

## FAQ

### Does an intrinsic need a `require`?

No. A member reached through the `nupp` namespace is selected by the compiler
from the source that names it, which is why the example above runs with no
imports. A declared module such as `nupp.mem.span` is a file on disk, so it is
bound with `require` or reached through its qualified name, as [Intrinsics and
declared modules](#intrinsics-and-declared-modules) shows.

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
- [](nupp.io) for buffers, readers, writers, and byte views
- [ownership.md](../ownership/index.md) for the affine results these modules return
- [build.md](../../projects/build.md#compiler-native-features) for native feature
  detection and its override
:::
