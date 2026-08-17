# `nupp` standard library

`nupp` is an ambient global. It is present in every generated module, so
standard facilities do not need `require`:

```nupp
local buffer = nupp.io.newBuffer("hello")
local digest = nupp.data.sha256(buffer:view())
```

Its namespaces are deliberately small:

- [`nupp.data`](data.md) owns JSON, UTF-8, identifiers, hashes and checksums.
- [`nupp.io`](io.md) owns byte buffers, readers, writers, and typed scalar
  reads and writes over them.
- [`nupp.io.files`](files.md) owns filesystem metadata and directories.
- [`nupp.io.Path` and `nupp.io.URI`](path-uri.md) model paths and resource
  names.
- [`nupp.log`](logging.md) owns leveled logging over a swappable destination.
- [`nupp.math`](math.md) owns scalar and two-dimensional vector helpers.
- [`nupp.span`](spans.md) owns rooted, bounds-checked shared and writable C
  array views.
- [`nupp.peg`](peg.md) compiles byte-oriented parsing-expression grammars.

## Availability, detection and lazy loading

The `nupp`, `nupp.data`, `nupp.io` and `nupp.math` tables always exist. A
member's implementation is emitted only when checked source resolves that
member. Aliases remain precise:

```nupp:playground
local data = nupp.data
print(data.sha256("payload")) -- selects SHA-256, but not UUID or JSON
```

The generated implementation then loads its provider on first access. This gives
two levels of omission: an unused facility contributes no generated adapter and
no native artifact; a selected but unvisited lazy member does not initialize its
provider. At `-O1` and above, feature effects are recomputed after constant
folding, so a facility used only in a branch or loop eliminated by DCE does not
retain its adapter or provider. Code generation makes the final selection from
the constructs it actually writes, so comptime erasure, materialization, and
other lowering cannot leave a source-only facility in the generated first-line
bootstrap. Native FFI declarations are split by that same set; selecting UUID,
for example, does not declare the path, files, process, or SHA-256 ABI.

The public surface does not expose `cjson`, `lua-utf8`, Rust handles, or FFI
pointers. Those are implementation details. Application code can therefore keep
using the same Nupp API if a provider changes.

[`nativeFeatures`](tooling/build.md#compiler-native-features) can force a binary
feature on or off for unusual packaging arrangements. Normal applications should
leave it unset and use automatic detection.

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

Continue with [data and text](data.md), [byte I/O](io.md),
[paths and URIs](path-uri.md), or [parsing-expression grammars](peg.md).
