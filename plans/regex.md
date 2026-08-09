# `nupp.regex`: compiled regular expressions

## Decision

Add `nupp.regex` as an **opt-in native runtime feature**.  Its public Lua/Nupp
surface is the `tecs.regex` surface verbatim, with the module prefix changed
from `tecs` to `nupp`:

```nupp
local regex = require("nupp.regex")
local expression = regex.compile([[(?<key>[a-z]+)=(\d+)]])
local found = assert(expression:captures("hp=100"))
print(found.named.key.value) -- hp
```

The implementation uses Rust's `regex::bytes::Regex`: patterns are valid UTF-8
Rust regex syntax; subjects are arbitrary Lua byte strings.  This is a regex
engine, not a replacement for LPeg or a general parser generator.

The implementation must be absent from a target that does not request it.  The
default Nupp host, and a binary stamped from it, contain no Rust regex code.

## Why a target feature, not DCE

Nupp intentionally compiles every module in a project's source set.  It does
not treat entries as a closed `require` graph: a computed `require(name)` can
load a module that a static graph would omit, and checking only reachable files
would make `nupp check` cease to check the project.  Bundles consequently carry
the project's compiled modules rather than a guessed reachable subset.

That means ordinary dead-code elimination cannot safely decide whether a native
library is needed.  In particular, a module that appears dead may be loaded by
name at runtime, and an unused `require` is not generally removable because it
can run arbitrary initialization.

The honest inclusion boundary is the selected target:

```lua
build = {
   targets = {
      command = {
         kind = "modules",
         entries = {"app.main"},
         runtime = {"regex"},
      },
      release = {
         kind = "binary",
         entries = {"app.main"},
         runtime = {"regex"},
         stub = "build/host/regex/release/nupp-host",
         output = "build/app",
      },
   },
}
```

`runtime` is a closed list of Nupp-supplied native capabilities, initially only
`"regex"`.  It is deliberately separate from `dependencies`: the latter says
that the application owns and pins an arbitrary C/Cargo/LuaRocks dependency;
the former says that Nupp owns the API, ABI, sources, tests, and distribution
contract.  A target with no `runtime` list has exactly today's output.

A future closed-world linker may prove that a requested runtime feature is
unreachable and remove it, but that is not this work.  Such a mode needs the
visible closed-world boundary, IR, and dynamic-loading restrictions described
in `plans/optimizations.md`.  It must never change the meaning of today's
default builds.

## Public API contract

Port the public behavior and examples from these Tecs files without inventing a
Nupp-shaped alternative:

- `../tecs/src/tecs/regex.tl`
- `../tecs/native/rust/runtime/src/regex.rs`
- `../tecs/spec/regex_spec.lua`
- `../tecs/bench/regex.tl`

The Nupp module provides the same exported records and methods:

```text
regex.compile(pattern) -> Regex

Regex:isMatch(subject) -> boolean
Regex:find(subject, init?) -> Match?
Regex:captures(subject, init?) -> Captures?
Regex:replace(subject, replacement) -> string
Regex:replaceAll(subject, replacement) -> string

Match = { value, first, last, index, name? }
Captures = { whole, groups, groupCount, named }
```

The compatibility details are load-bearing:

- `first` is a 1-based byte index; `last` is inclusive.  An empty match has
  `last == first - 1`.
- A negative `init` counts back from the end, as Lua string operations do;
  out-of-range starts return no match.
- `captures.groups` may have holes for unmatched optional groups.  Consumers
  iterate through `groupCount`, not `#groups`; `named` aliases the same match
  values as `groups`.
- Replacements use Rust's `$0`, `$1`, `$name`, `${name}`, and `$$` syntax.
- Invalid or non-UTF-8 patterns raise.  Subjects may contain invalid UTF-8;
  `(?-u:...)` retains the Tecs byte-mode escape hatch.
- Compilation occurs once and the returned expression is reused.  It owns its
  native allocation and is finalized by the Lua collector, exactly as Tecs's
  `ffi.gc` handle is.  Do **not** add a public `close` method or require a
  `with` scope: that would no longer be the Tecs API.

The error prefix becomes `nupp:` rather than `tecs:`, but error conditions,
return shapes, and byte-position semantics remain identical.  Port the tests
before adding convenience methods; additions belong in a later, separately
specified extension.

## Runtime architecture

### Module layers

Keep the public API independent of how a process obtains native code:

```text
require("nupp.regex")
        |
        +-- public Nupp wrapper: Match, Captures, init handling, replacement API
        |
        +-- package.preload["nupp.regex.native"]  (a regex-enabled host)
        |       |
        |       `-- statically linked Rust regex engine
        |
        `-- FFI cdylib backend                         (modules target)
                |
                `-- build/<target>/lib/libnupp_regex.*
```

The wrapper is the API authority.  Both backends implement one internal
operation table (`compile`, `captureCount`, `captureName`, `isMatch`, `find`,
`captures`, `replace`, and `destroy`), so a module build and a stamped binary
produce indistinguishable public values and errors.

Tecs's FFI bridge is the starting point for the cdylib ABI, renamed from
`tecsRegex*` to `nuppRegex*`.  Preserve its defensive contracts: null and
short buffers fail cleanly, capture spans are caller-owned storage of the
right length, returned names remain valid until regex destruction, and result
bytes have one explicit destroy operation.

Do not make the public wrapper call `ffi.C` from a host.  Exporting a Rust
executable's symbols for LuaJIT FFI is platform-specific and brittle.  Instead,
the regex-enabled host registers `nupp.regex.native` in `package.preload`, the
same way it registers `cjson`, `lpeg`, and `lua-utf8` today.  The native module
adapts the same Rust implementation to the internal operation table.  This
keeps a dynamically loaded `cdylib` and a statically linked host on the same
public contract without relying on executable-symbol lookup.

### Source layout and ownership

Add a small Rust runtime crate, for example:

```text
runtime/regex/
  Cargo.toml                 # exact Cargo.lock; regex = 1.12.x
  src/lib.rs                 # C ABI used by the cdylib backend
  src/engine.rs              # port of Tecs regex.rs, shared by both fronts
  include/nupp_regex.h       # checked C ABI, generated or hand-maintained
src/nupp/regex.nupp          # public wrapper and type surface
```

`host/Cargo.toml` gains an optional `regex` feature and a path dependency on
the runtime crate.  `host/src/lua.rs` preloads `nupp.regex.native` only with
that feature enabled.  The feature must not be a default feature.

Add `nupp.regex` to the bundled-source map in `src/nupp/env.nupp` and to the
compiler/dist resource lists in `nupp.lua`.  An installed Nupp binary then
types and compiles a project that requires it from exactly the source it
contains, as it already does for `nupp.std.resources`, `nupp.std.zone`, and
`nupp.std.profile`.

The compiler distribution also needs the checked Rust runtime source and lock
file available as an embedded resource.  On a source checkout the build uses
the tracked tree; from a stamped compiler it materializes the exact source into
its build cache after verifying a content digest.  Never fetch an unpinned
crate source or silently use a machine-global copy.

## Build and distribution contract

### 1. Modules and `nupp run`

Extend target validation and task reporting with `runtime = {"regex"}`.  The
feature registry resolves `regex` to the embedded Cargo crate, builds a locked
`cdylib`, and stages it under the target's `outDir/lib` beside ordinary native
dependencies.

Add a generated, target-local native-library registry.  `nupp.regex` asks that
registry for the exact staged path instead of trusting the process working
directory or platform loader search paths.  `nupp run`, `nupp test`, and a
directly run generated entry initialize the same registry, so a program works
from a subdirectory and reports a precise missing-feature/missing-library error
rather than an opaque `ffi.load` failure.

The cache key includes the runtime-feature list, the embedded crate digest,
Cargo version, target triple, profile, and feature set.  Removing `regex` from
a target removes its staged library through the existing target-output cleanup
path.

If a module statically requires `nupp.regex` but the selected target lacks
`runtime = {"regex"}`, fail the build with a diagnostic that names the missing
target feature.  A computed `require` cannot be proved at build time; if it
requests `nupp.regex` at runtime without the feature, the wrapper raises the
same actionable message.  This is deliberately conservative under Nupp's
source-set build model.

### 2. Bundles

Keep the present one-file promise.  A `kind = "bundle"` target that requests a
native runtime feature must fail before emitting its bundle, explaining that a
Lua payload cannot carry a shared library and recommending either a modules
target or a feature-matched binary host.  Do not silently create a sidecar
while still calling the result a one-file bundle.

Sidecar bundle directories are a possible future packaging kind, but are not
part of this feature.

### 3. Stamped binaries

A binary payload cannot add code to its prebuilt executable.  The selected stub
must therefore have the same native-runtime features as the target.

Add a host metadata command, for example
`nupp-host --nupp-host-features`, that prints a deterministic feature list
without starting Lua or reading a payload.  Before stamping a binary target,
`nupp build` queries the configured stub and rejects either case:

- target requests `regex`, but the stub lacks it;
- stub supplies `regex`, but the target does not request it.

The second rejection is important: it prevents an accidentally regex-linked
binary from looking like a DCE win.  A default host has an empty feature list;
the feature host is built deliberately:

```sh
cargo build --release --manifest-path host/Cargo.toml --features regex
```

The regex-enabled host statically links the runtime crate and preloads the
internal native module.  It needs no Cargo installation, shared library, or
loader path when the stamped application runs.  The default `dist` target in
Nupp's own manifest remains featureless, preserving its present footprint and
its binary fixpoint.

The standard compiler distribution may carry the *source* needed to build an
optional feature host, but its ordinary executable contains no linked regex
machine code.  Document the distinction clearly.

## Delivery stages

1. **Set the compatibility baseline.** Port Tecs's regex specs and benchmark
   fixtures unchanged except for module names and test harness plumbing.  Add
   a compatibility table for pattern syntax, bytes, match positions, captures,
   replacement expansion, invalid patterns, and GC cleanup.  Record baseline
   results for short/early/late/miss searches and each replacement lane.

2. **Build the shared engine.** Extract/port Tecs's Rust byte-regex engine into
   `runtime/regex`; give it a small, tested C ABI.  Build it as a locked Nupp
   Cargo runtime artifact and test memory ownership under repeated compile,
   match, replace, and collection cycles.

3. **Add `nupp.regex`.** Implement the public wrapper, type it from its Nupp
   source, wire it into embedded standard-module resolution, and port all API
   behavior tests.  Verify a plain LuaJIT/modules-target execution through the
   staged cdylib, not only through a host that happens to be linked already.

4. **Teach project builds about native runtimes.** Add the closed `runtime`
   target key, validation, cache fingerprints, target task output, runtime
   registry, diagnostics, and cleanup.  Cover selected/unselected target
   pairs, a static missing declaration, and a dynamic missing request.

5. **Make binary inclusion exact.** Add the optional host feature, its native
   preloader, feature metadata command, and stamp-time compatibility check.
   Preserve the host/payload trailer format.  Reject native bundle targets in
   the same change so the three artifact kinds have explicit behavior.

6. **Package and document it.** Embed the pinned runtime source in a stamped
   compiler, materialize it safely for development builds, document the Cargo
   requirement for modules targets, and document feature-host construction for
   binaries.  Regenerate `docs/reference.md` and add the module API to the
   generated docs.

## Verification matrix

| Case | Expected result |
| --- | --- |
| Existing target with no `runtime` | Byte-identical generated Lua and no `nupp_regex` library or host symbol. |
| `modules` target with `regex` | Locked cdylib staged under `outDir/lib`; `nupp run` and tests load it from a non-root working directory. |
| Static `require("nupp.regex")`, no feature | Build fails with the target and required `runtime = {"regex"}` named. |
| Dynamic `require`, no feature | Build stays conservative; an executed request fails with the same remedy. |
| `bundle` plus `regex` | Refuses before writing an artifact; no pretend single-file output. |
| Binary target plus a default host | Refuses before stamping and names the stub/feature mismatch. |
| Binary target plus a regex host | Stamps and runs with no shared-library sidecar; public API results match the modules target. |
| Default Nupp `dist` | `nupp fixpoint --binary` remains byte-identical and the host feature list is empty. |
| Regex host | Feature list is exactly `regex`; symbol/size inspection and a smoke program prove the engine is linked. |
| Performance | The ported benchmark records medians and p95s, includes FFI/backend overhead, and establishes where it wins and where LPeg remains faster. |

Run `./bin/nupp check --strict`, `./bin/nupp test`, and
`./bin/nupp fixpoint` throughout.  Run `nupp fixpoint --binary` for the default
host and the corresponding feature-host stamp test separately; do not compare
feature and non-feature host bytes to each other.

## Non-goals

- General DCE, a closed-world linker, or changing source-set compilation.
- Bundling arbitrary native shared libraries into a Lua payload.
- Replacing LPeg, Lua patterns, or parser combinators.
- Exposing Rust regex's internal automata, allocator, or FFI handles as a
  public Nupp API.
- Adding convenience operations beyond the Tecs regex surface before API
  compatibility and binary inclusion are proven.
