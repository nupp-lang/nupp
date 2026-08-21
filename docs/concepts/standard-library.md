# Standard library

`nupp` is the compiler-provided intrinsic namespace, present in every checked
file. Reach for it when a program needs bytes, text, digests, logging, math, or
a parser and does not want a dependency for them.

```nupp:playground
local digest = nupp.data.sha256("payload")
print(#digest, nupp.math.lerp(10, 20, 0.25))
```

## Intrinsics and declared modules

The namespace is a language surface, not an ambient source module and not a
package tree assembled from declaration files. The compiler selects each
implementation from the members checked source actually reaches, so nothing is
loaded on a program's behalf.

Nupp-authored libraries outside that surface are ordinary declared modules on
disk, bound with Lua's `require`:

```nupp
const span = require("nupp.mem.span")

local storage = carray(int32, 4)
local values = span.fromCarray(storage, 4)
```

The qualified form reaches the same declared file without the binding:

```nupp
local values = nupp.mem.span.fromCarray(storage, 4)
```

It lowers to one hidden `require` in the containing module. It does not build a
global `nupp.mem` table and does not add a load check at every call. The same
rule applies to a dependency root such as `tecs`. See [modules.md](modules.md)
for how a declared module is named and resolved.

::: deepdive
Keeping the intrinsic surface out of the module graph is what lets the compiler
decide, per program, which implementations exist at all. A package tree would
have to answer `require("nupp.data")` with a table whose members are all
present, so either every program carries every facility or the answer depends
on a load order the source does not show. A language surface hands out no such
table: the members a file names are the members that get emitted.
:::

## Library modules

The standard surface is deliberately small. These pages cover both the
intrinsic namespaces and the declared modules:

- [](nupp.data) owns JSON, UTF-8, identifiers, hashes and checksums.
- [](nupp.io) owns byte buffers, readers, writers, and typed scalar reads and
  writes over them.
- [](nupp.io.files) owns filesystem metadata and directories.
- [](nupp.io.path) models filesystem paths, and [](nupp.io.uri) models resource
  names.
- [](nupp.log) owns leveled logging over a swappable destination.
- [](nupp.math) owns scalar and two-dimensional vector helpers.
- [](nupp.mem.span) owns rooted, bounds-checked shared and writable C array
  views.
- [`nupp.mem.soa`](structure-of-arrays.md) stores every top-level field of a
  reified struct in its own column.
- [](nupp.peg) compiles byte-oriented parsing-expression grammars.

## Availability, detection and lazy loading

The `nupp`, `nupp.data`, `nupp.io` and `nupp.math` intrinsic tables always
exist. What varies is which of their members reach the generated program, and
when a member's native provider is initialized.

### Selection follows use

A member's implementation is emitted only when checked source resolves that
member, and an alias stays as precise as the name it came from:

```nupp
local data = nupp.data
print(data.sha256("payload")) -- selects SHA-256, but not UUID or JSON
```

At `-O1` and above, feature effects are recomputed after constant folding, so a
facility used only in a branch or loop that dead-code elimination removed keeps
neither its adapter nor its provider. Code generation makes the final selection
from the constructs it actually writes, so comptime erasure, materialization,
and other lowering cannot leave a source-only facility in the generated
first-line bootstrap. Native FFI declarations are split by that same set:
selecting UUID does not declare the path, files, process, or SHA-256 ABI.

### Provider laziness

A selected member loads its native provider on first access, which is a second
level of omission inside the first. An unused facility contributes no generated
adapter and no native artifact, and a selected but unvisited member never
initializes its provider.

The public surface does not expose simdjson's native module, `lua-utf8`, Rust
handles, or FFI pointers. Those are implementation details, so application code
keeps the same Nupp API when a provider changes.

### Forcing a native feature

[`nativeFeatures`](../guides/build.md#compiler-native-features) turns a binary
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
[ownership.md](ownership.md) for the cleanup obligation an affine result
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
- [ownership.md](ownership.md) for the affine results these modules return
- [build.md](../guides/build.md#compiler-native-features) for native feature
  detection and its override
:::
