# `nupp.regex`: compiled regular expressions

## Decision

Add `nupp.regex` as an **automatically detected native runtime feature** beneath an
**always-present global `nupp` module table**. Its public Lua/Nupp surface is
the `tecs.regex` surface verbatim, with the module prefix changed from `tecs`
to `nupp`:

```nupp
local expression = nupp.regex.compile([[(?<key>[a-z]+)=(\d+)]])
local found = assert(expression:captures("hp=100"))
print(found.named.key.value) -- hp
```

The implementation uses Rust's `regex::bytes::Regex`: patterns are valid UTF-8
Rust regex syntax; subjects are arbitrary Lua byte strings.  This is a regex
engine, not a replacement for LPeg or a general parser generator.

The implementation must be absent from a target that does not detect it. The
default Nupp host, and a binary stamped from it, contain no Rust regex code.

`nupp` itself is never optional. Generated Nupp code initializes the one
process-global table before user code runs, and the prelude declares it in every
project. Its standard namespace tables are installed even when their native
backend is absent. Thus `nupp` is always a table and `nupp.regex` is always a
typed namespace; a featureless target installs a lightweight `compile` sentinel
that raises the existing missing-feature diagnostic before attempting any native
load. No Rust regex code is linked merely to provide that error.

## Why semantic feature detection, not DCE

Nupp intentionally compiles every module in a project's source set.  It does
not treat entries as a closed `require` graph: a computed `require(name)` can
load a module that a static graph would omit, and checking only reachable files
would make `nupp check` cease to check the project.  Bundles consequently carry
the project's compiled modules rather than a guessed reachable subset.

That means ordinary dead-code elimination cannot safely decide whether a native
library is needed.  In particular, a module that appears dead may be loaded by
name at runtime, and an unused `require` is not generally removable because it
can run arbitrary initialization.

The build derives the feature set from semantic use across the selected target's
complete source set:

```lua
build = {
   targets = {
      command = {
         kind = "modules",
         entries = {"app.main"},
      },
      release = {
         kind = "binary",
         entries = {"app.main"},
         stub = "build/host/regex/release/nupp-host",
         output = "build/app",
      },
   },
}
```

The checker records a requirement when a resolved reference reaches the
compiler-owned `nupp.regex` namespace. It does not use a textual grep, so a
local named `nupp` or an unrelated field named `regex` does not enable native
code. The union of those requirements across all project modules is the
target's runtime feature set. Compiler-owned bootstrap/wrapper modules are
excluded from this collection, otherwise their own implementation would make
every target require regex.

There is no manifest `runtime` flag. `dependencies` remains for application
owned and pinned C/Cargo/LuaRocks dependencies; detected runtime features are
Nupp-owned API/ABI/runtime packages. A target with no detected feature has no
native runtime artifact or linked host code; it still receives the small,
always-present `nupp` global bootstrap described above.

A future closed-world linker may prove that a static use is unreachable and
remove the feature, but that is not this work. Such a mode needs the visible
closed-world boundary, IR, and dynamic-loading restrictions described in
`plans/optimizations.md`. It must never change the meaning of today's default
builds. Until then, any resolved static use in the source set includes regex;
this is conservative by design and does not confuse source-set checking with
link-time DCE.

## Public API contract

Port the public behavior and examples from these Tecs files without inventing a
Nupp-shaped alternative:

- `../tecs/src/tecs/regex.tl`
- `../tecs/native/rust/runtime/src/regex.rs`
- `../tecs/spec/regex_spec.lua`
- `../tecs/bench/regex.tl`

The `nupp.regex` global namespace provides the same exported records and methods:

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
nupp.regex
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

Add a `global nupp` declaration to `src/nupp/decls/prelude.d.nupp`, including
the `regex` member's exact type surface. The generator emits an idempotent
runtime bootstrap before each generated Nupp module executes: it creates
`_G.nupp` if absent, rejects a pre-existing non-table value, and installs the
public namespace wrapper once. `nupp` is reserved for this compiler-owned
global, so user declarations cannot replace its type or bind a different global
under that name.

Add the public wrapper source to the bundled-source map in `src/nupp/env.nupp`
and to the compiler/dist resource lists in `nupp.lua`. The generated startup
installs it as `nupp.regex`, instead of exposing a user-facing
`require("nupp.regex")` module. An installed Nupp binary consequently types
and compiles a project using the global from exactly the source it contains.

The compiler distribution also needs the checked Rust runtime source and lock
file available as an embedded resource.  On a source checkout the build uses
the tracked tree; from a stamped compiler it materializes the exact source into
its build cache after verifying a content digest.  Never fetch an unpinned
crate source or silently use a machine-global copy.

## Build and distribution contract

### 1. Modules and `nupp run`

Extend checked-module records with their resolved Nupp runtime requirements.
After checking the complete source set, project orchestration unions the cached
and newly checked requirements, resolves `regex` to the embedded Cargo crate,
builds a locked `cdylib`, and stages it under the target's `outDir/lib` beside
ordinary native dependencies. `nupp tasks --json` reports this derived list as
an observed build property, not user configuration.

`nupp check` records and reports detected requirements but does not invoke
Cargo, write a library, or require a host. A build, run, test, bundle, or
binary-stamp operation consumes the recorded requirements after checking.

Add a generated, target-local native-library registry. The `nupp.regex`
wrapper asks that registry for the exact staged path instead of trusting the
process working directory or platform loader search paths. `nupp run`,
`nupp test`, and a directly run generated entry initialize the same registry,
so a program works from a subdirectory and reports a precise
missing-feature/missing-library error rather than an opaque `ffi.load` failure.

The cache key includes the derived runtime-feature list, the embedded crate
digest, Cargo version, target triple, profile, and feature set. Removing the
last resolved `nupp.regex` use removes its staged library through the existing
target-output cleanup path. Reused module records retain their requirement
metadata, so a warm build reaches the same answer without rechecking source.

A dynamic field lookup cannot be proved at build time. If it reaches
`nupp.regex` in a target with no detected use, the always-present wrapper raises
an actionable message explaining that native runtimes are detected from static
`nupp.regex` use and naming a direct call or another static reference as the
remedy. This is deliberately conservative under Nupp's source-set build model.

### 2. Bundles

Keep the present one-file promise. A `kind = "bundle"` target with a detected
native runtime feature must fail before emitting its bundle, explaining that a
Lua payload cannot carry a shared library and recommending either a modules
target or a feature-matched binary host. Do not silently create a sidecar while
still calling the result a one-file bundle.

Sidecar bundle directories are a possible future packaging kind, but are not
part of this feature.

### 3. Stamped binaries

A binary payload cannot add code to its prebuilt executable. The selected stub
must therefore have exactly the same derived native-runtime feature set as the
target.

Add a host metadata command, for example
`nupp-host --nupp-host-features`, that prints a deterministic feature list
without starting Lua or reading a payload.  Before stamping a binary target,
`nupp build` queries the configured stub and rejects either case:

- static `nupp.regex` use requires `regex`, but the stub lacks it;
- the stub supplies `regex`, but the target has no detected regex use.

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

3. **Install the global and add `nupp.regex`.** Add the reserved, always-present
   `nupp` prelude/global initialization path, implement the public regex
   wrapper beneath it, and wire the wrapper source into embedded runtime
   resolution. Port all API behavior tests. Verify a plain LuaJIT/modules target
   through the staged cdylib, not only through a host that happens to be linked
   already.

4. **Teach project builds to infer native runtimes.** Record resolved global
   namespace uses during checking, preserve those records through incremental
   reuse, union them after the complete source set is checked, and build/stage
   the matching runtime artifacts. Add cache fingerprints, task reporting,
   runtime registry, automatic cleanup, and dynamic-miss diagnostics. Cover
   detected/undetected targets, a shadowed local `nupp`, and a dynamic request.

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
| Existing target with no static regex use | `nupp` is initialized as a global table; no `nupp_regex` library or host symbol exists. |
| Static `nupp.regex` use in a modules target | Locked cdylib is detected and staged under `outDir/lib`; `nupp run` and tests load it from a non-root working directory. |
| Local `nupp` or unrelated `.regex` field | Does not enable the runtime; semantic resolution avoids textual false positives. |
| Static use removed | A warm build drops the staged library and selects the featureless host requirement. |
| Dynamic `nupp["regex"]` without static use | Build stays conservative; an executed request explains how automatic detection works. |
| `bundle` with detected regex | Refuses before writing an artifact; no pretend single-file output. |
| Static regex use plus a default binary host | Refuses before stamping and names the stub/feature mismatch. |
| Static regex use plus a regex binary host | Stamps and runs with no shared-library sidecar; public API results match the modules target. |
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
