`nupp` is the always-available standard-library namespace. Reach its fields
directly without `require`; each implementation loads only if the checked
program actually uses it.

## The `nupp` global

`nupp` is a table the prelude declares, so it is in scope everywhere without a
`require`. A binding called `nupp` shadows it deliberately, the way a binding
called `string` would.

Its public namespaces are:

| Namespace | What it provides |
| --- | --- |
| [`nupp.data`](data.md) | JSON, UTF-8, UUIDs, hashes and checksums. |
| [`nupp.io`](io.md) | Buffers, byte views, readers and writers. |
| [`nupp.io.Path` and `nupp.io.URI`](path-uri.md) | Filesystem paths and resource identifiers. |
| [`nupp.math`](math.md) | Scalar helpers and two-dimensional vectors. |
| [`nupp.regex`](regex.md) | Compiled Rust regular expressions. |

See the [standard-library overview](stdlib.md) for lazy loading, automatic
native-feature detection, dead-code elimination, and provider hiding.

## Ownership intrinsics

The compiler-provided ownership operations also live under this global:

| Intrinsic | Operation |
| --- | --- |
| `nupp.dispose(value)` | Consume an owner and run its cleanup list. |
| `nupp.borrow(value)` | Take an explicit lexical borrow. |
| `nupp.intoRaw(value)` | Abandon tracking inside `unsafe`. |
| `nupp.fromRaw(value, cleanup...)` | Assert fresh ownership inside `unsafe`. |
| `nupp.borrowFrom(raw, source)` | Assert raw provenance inside `unsafe`. |
| `nupp.pin(pointer, anchor)` | Bind a managed pointer to its Lua anchor. |

The six ownership entries are intrinsics: the compiler implements them, so they
type nothing like ordinary functions and are not values you can pass around.
The old bare spellings remain aliases, but new code should use `nupp.*`. See
[ownership](ownership.md#intrinsics-live-under-nupp) for their lifetime rules.

## Shipped modules

The API tree below also contains ordinary modules shipped with the compiler,
including `nupp.profile`, `nupp.resources`, and `nupp.zone`. Those are reached
with `require` and are separate from the fields of the ambient global:

```nupp
local zone = require("nupp.zone")
```

There is no module to require by the bare name `nupp`. `nupp.compiler` contains
the self-hosted compiler implementation and is hidden from public API
documentation by its `@!internal` namespace root.
