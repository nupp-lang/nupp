# `nupp` standard library

`nupp` is the compiler-provided intrinsic namespace. It is present in checked
source, so intrinsic facilities do not need `require`:

```nupp
local buffer = nupp.io.newBuffer("hello")
local digest = nupp.data.sha256(buffer:view())
```

This is a language surface, not an ambient source module or a package tree
assembled from declaration files. Its implementations are selected by the
compiler from the members checked source actually reaches. Nupp-authored
libraries outside this intrinsic surface are real declared modules on disk:

```nupp
const {Array as HeapArray} = require("nupp.mem.heap")
const span = require("nupp.mem.span")

local values = nupp.mem.span.fromCarray(pointer, count)
```

The explicit bindings use ordinary Lua `require`. The qualified access selects
the same declared `nupp.mem.span` file and lowers to one hidden `require` in the
containing module; it does not build a global `nupp.mem` table or inject a load
check at every call. The same generic rule applies to dependency roots such as
`tecs`.

The standard surface is deliberately small; these pages cover both intrinsic
namespaces and declared modules:

- [`nupp.data`](../modules/nupp/data.md) owns JSON, UTF-8, identifiers, hashes
  and checksums.
- [`nupp.io`](../modules/nupp/io.md) owns byte buffers, readers, writers, and
  typed scalar reads and writes over them.
- [`nupp.io.files`](../modules/nupp/io/files.md) owns filesystem metadata and
  directories.
- [`nupp.io.Path` and `nupp.io.URI`](paths-and-uris.md) model paths and resource
  names.
- [`nupp.log`](../modules/nupp/log.md) owns leveled logging over a swappable
  destination.
- [`nupp.math`](../modules/nupp/math.md) owns scalar and two-dimensional vector
  helpers.
- [`nupp.mem.span`](../modules/nupp/mem/span.md) owns rooted, bounds-checked
  shared and writable C array views.
- [`nupp.peg`](../modules/nupp/peg.md) compiles byte-oriented parsing-expression
  grammars.

## Availability, detection and selection

The `nupp`, `nupp.data`, `nupp.io` and `nupp.math` intrinsic tables always
exist. A member's implementation is emitted only when checked source resolves
that member. Aliases remain precise:

```nupp:playground
local data = nupp.data
print(data.sha256("payload")) -- selects SHA-256, but not UUID or JSON
```

The generated intrinsic implementation then loads its native provider on first
access. This is provider laziness inside a selected intrinsic, distinct from
declared-module loading. It gives two levels of omission: an unused facility
contributes no generated adapter and no native artifact; a selected but
unvisited lazy member does not initialize its provider. At `-O1` and above,
feature effects are recomputed after constant
folding, so a facility used only in a branch or loop eliminated by DCE does not
retain its adapter or provider. Code generation makes the final selection from
the constructs it actually writes, so comptime erasure, materialization, and
other lowering cannot leave a source-only facility in the generated first-line
bootstrap. Native FFI declarations are split by that same set; selecting UUID,
for example, does not declare the path, files, process, or SHA-256 ABI.

The public surface does not expose simdjson's native module, `lua-utf8`, Rust
handles, or FFI pointers. Those are implementation details. Application code can
therefore keep using the same Nupp API if a provider changes.

[`nativeFeatures`](../guides/build.md#compiler-native-features) can force a
binary feature on or off for unusual packaging arrangements. Normal applications
should leave it unset and use automatic detection.

## Byte positions

String functions inherited from Lua normally use 1-based positions. The byte
container APIs use zero-based offsets because an offset names a distance from
the beginning and maps directly to native byte ranges. Each API page calls out
its convention; do not silently pass a `string.find` position to a buffer
method.

## Errors and ownership

Operations that can fail because of the environment return `nil, reason`.
Invalid arguments and malformed programmer-owned values raise at the call site.
Buffers and views implement `close` and report use after release; readers and
writers return a reason after they have been closed.

Continue with [data and text](../modules/nupp/data.md), [byte
I/O](../modules/nupp/io.md), [paths and URIs](paths-and-uris.md), or
[parsing-expression grammars](../modules/nupp/peg.md).
