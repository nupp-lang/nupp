---
title: Dialects and capability backends
status: Draft
created: 2026-08-20
---

## Summary

A dialect selects which Lua a build lowers for. `luajit` is the default and
lowers what Nupp lowers today; `lua51` lowers to Lua 5.1 syntax and holds
resolved prelude uses to the common runtime surface of 5.1 through 5.4 and
LuaJIT. Where a construct needs a runtime facility rather than syntax, that
facility is a named capability, and the dialect says how each one is satisfied:
by the compiler, by a backend module, left open for a project backend, or not at
all.

A backend is an ordinary checked value satisfying the `Backend` interface. It
contains one or more versioned `Seam` values. Each seam carries a complete
implementation and the compiler-owned conformance suite for that contract;
there is no second registry of provider strings. `nupp backend test` runs every
selected seam explicitly, while checking and building never execute a
dependency merely because a manifest named it. Selection resolves during the
build, binds one implementation per reached seam, and is recorded in the
artifact. A seam with no implementation reports a diagnostic at the construct
or standard member that needed it, and never lowers to a substitute that means
something else.

Compiler operations and standard-library facilities use the same composition
model. A compile-bound seam supplies lowering operations such as bitops or
struct values. A runtime-bound seam lazily requires a named third-party module
for JSON, SHA-256, UTF-8, UUID, bitsets or PEG and checks its runtime shape.
Both the adapter and the suite are ordinary checked source files tested in
isolation. Generated output contains only the selected backend installation;
it never contains fallback source stored in a compiler string. Nupp specifies
the contracts and may ship thin adapters for common modules, but it does not
acquire a second pure-Lua implementation of every library facility.

::: seealso
- [syntax.md](../concepts/syntax.md) for what generated Lua requires today
- [records.md](../type-system/records.md) for the `struct` contract a backend
  has to satisfy
- [NEP 14](0014-webassembly-from-aot-ir.md) for the one place a second code
  emitter is cheap
:::

## Goals

- Publish a Nupp library as Lua that a project on stock Lua 5.1 through 5.4 can
  `require`, with a check that rejects uses outside their common runtime surface.
- Keep one front end: one parser, one checker, one standard library surface,
  one set of diagnostics.
- Make substitution checkable. A seam implementation must satisfy its
  structural interface, and its `Seam` value exposes the same documented,
  compiler-owned behavioral suite to the explicit backend test command.
- Cost nothing on the native path. A `luajit` artifact binds native operations
  directly; only an artifact selecting a portable seam pays for its adapter,
  runtime check or indirection.
- Leave the default `luajit` output unchanged. Portable adapters, checks and
  modules occur only in an artifact built for a dialect that selected them.
- Report at the construct that cannot be lowered, naming the capability that is
  missing and the substitute that exists.
- Leave what a build resolved readable in the artifact it produced.
- Let portable standard-library members depend on declared third-party runtime
  modules instead of making Nupp maintain an algorithmic fallback for each one.

## Non-goals

- Emitting JavaScript or WebAssembly from the general lowering.
- Making a dialect without a capability perform like a dialect with it. A table
  behind a metatable is not cdata, and no interface makes it one.
- A capability set a project extends. A capability is a construct the compiler
  lowers to; a facility the compiler does not lower to is an ordinary module
  dependency and needs none of this.
- Partial seam implementations. A backend may collect any number of seams, but
  every seam it contains implements one contract completely.
- Changing the default. Under `luajit` the generated Lua is what it is today.
- Bundling pure-Lua implementations of every standard-library facility. A
  checked runtime seam and a precise missing-module error are sufficient.
- A per-file dialect. A dialect is a property of a build, and a source file
  that named one would be a library its consumers could not retarget.

## Motivation

### Most Lua is not LuaJIT 2.1

Generated code targets LuaJIT 2.1.1784535649 or newer, and `nupp` checks for it
rather than letting a run fail on a line nobody wrote. See [required LuaJIT
build](../concepts/syntax.md#required-luajit-build).

That floor makes a Nupp library consumable by Nupp. It does not make one
publishable to a project on stock 5.1, on 5.4, or inside a browser interpreter,
which together are most of the Lua that exists. An author who wants both
audiences today writes the library twice.

### Erasure already reaches most of the way

[Stock Lua 5.1](../concepts/syntax.md#stock-lua-51) enumerates the three things
that stop generated code from running there: a passed-through extension is a
5.1 parse error, `require("ffi")` is injected for any struct or `cdef`, and
`require("table.new")` is injected when that builtin is used. It closes by
saying a file that uses none of them does lower to plain 5.1 Lua, and that no
flag guarantees it.

The missing piece is not a lowering. Most of the typed layer erases already.
What is missing is anything that decides which Lua a build is for, checks the
program against that decision, and records the answer.

### Selection already happens, with nothing portable to check it against

`JSON_FALLBACK` in `src/nupp/compiler/stdlib.nupp` is a pure-Lua JSON
implementation used by the stage-zero compiler, and
[standard-library.md](../concepts/standard-library.md) already states that the
compiler selects each native implementation from the members checked source
reaches.

Per-program implementation selection and lazy initialization are therefore
existing machinery. What they lack is a runtime seam, a contract its adapter
has to satisfy, and an artifact requirement that tells a consumer which runtime
module to install. The stage-zero JSON copy is not the model: it remains a
bootstrap implementation rather than becoming the first of many algorithms
Nupp maintains twice.

### Truncation is worse than refusal

A `uint64` struct field holds values a Lua 5.1 number cannot represent. A
dialect that stored one in a double would lower a program that checks, builds,
runs, and returns different answers above 2^53, with nothing in the source, the
diagnostics, or the artifact saying so.

Refusing that field names one line for the reader to change. Storing it names
nothing.

## Overview and specification

### Dialects

| Dialect | Lowers to | Runs on |
| --- | --- | --- |
| `luajit` | LuaJIT 2.1's dialect, as today | LuaJIT 2.1.1784535649+ |
| `lua51` | Lua 5.1 syntax, plus a compat prologue | Common Lua 5.1–5.4 and LuaJIT surface |

`nupp build --dialect lua51`, and the same flag on `check`, so an author learns
that a library is portable without building it.

The word is `dialect` because the two obvious ones are taken. A `target` is a
build output named in `nupp.lua`, and a `platform` is a binary platform
selected by `--platform`. This is a third axis and takes a third word, matching
the sense the README already uses when it calls Nupp a superset of LuaJIT's Lua
dialect.

### Capabilities are what the compiler lowers to

Each dialect entry has one of five states. `native` means the compiler emits the
runtime's operation directly. `compiler` means a semantics-preserving source
lowering needs no runtime module. A module name is the dialect's default
backend. `open` means a project may name a backend but the dialect supplies
none, and `forbidden` means no backend can make the operation meaningful on that
runtime.

| Capability | What needs it | `luajit` | `lua51` |
| --- | --- | --- | --- |
| `structvalue` | construction, fields, copying and `is` for `struct` | `native` | `open` |
| `cstorage` | `carray`, physical layout, offsets and pointers | `native` | `forbidden` |
| `bitops` | `&`, <code>&#124;</code>, `~`, `<<`, `>>`, `~>>` | `native` | `open` |
| `int64` | `int64`, `uint64`, cdata suffixes | `native` | `open` |
| `cinterop` | `cdef`, `cheader`, `T*`, `ffi.*` | `native` | `forbidden` |
| `presize` | `table.new`, `table.clear` | `native` | `compiler` |
| `simd` | explicit `nupp.simd` values | `native` | `open` |

The set is closed and held as data, the way
`src/nupp/compiler/aot/admit.nupp` holds the admitted AOT subset. Widening it
is adding a row and the lowering that reads it, not writing a pass.

`table.new(a, h)` lowers to `{}` under `lua51`, because its capacities are an
optimization rather than an observable value. `table.clear(t)` lowers to an
in-place deletion loop, preserving the table's identity. Neither needs a
module.

`structvalue` deliberately excludes a C layout. A table backend can preserve a
struct's nominal identity, fields, copy sites, methods and width-normalized
stores. It cannot preserve byte offsets, pointer identity or contiguous
storage. A source operation observing one of those reaches `cstorage` instead
and is refused under `lua51`; the backend is not allowed to call a table a C
layout.

A project cannot add a capability, because a capability is a name for something
the compiler already lowers to. A third-party facility the compiler does not
lower to is an ordinary module; a runtime seam is needed only when adapting it
to an enumerated Nupp standard contract.

### Syntax is not a capability

`?.`, `??`, `?:`, compound assignment, `const`, short functions, named varargs,
interpolation and `continue` need no runtime facility. A dialect lowers them,
and there is nothing to substitute, so there is no backend for them.

`continue`, and the `goto` that automatic cleanup lowering emits, become a flag
and a `repeat ... until true` under `lua51`. The lowering also rewrites a
`break` in that loop so the synthetic `repeat` cannot capture it. That costs
what the deepdive under
[required LuaJIT build](../concepts/syntax.md#required-luajit-build) declined to
pay: lowering an extension the runtime already has makes output slower than the
Lua somebody would have written by hand. The reasoning holds for `luajit`,
where the extension is present. It does not reach a dialect where the extension
does not exist and the choice is between a lowering and no program at all.

An authored label or `goto` is different. An arbitrary jump does not have a
local structured lowering, and turning a function into a state machine would
change its frames and error sites. `lua51` therefore reports `NUPP3009` at an
authored label or `goto`, with help to use structured control flow. Generated
cleanup jumps are not source constructs and take the lowering above.

### Backend and seam are actual interfaces

Backend composition is part of the checked library surface, not an annotation
registry. The common interfaces are deliberately small enough to hold
heterogeneous seams:

```nupp
interface Seam
    readonly name: string
    readonly version: integer
    install: function(self: Seam): nil
    test: function(self: Seam): (boolean, string?)
end

interface Backend
    readonly name: string
    readonly seams: {Seam}
    install: function(self: Backend): nil
    test: function(self: Backend): (boolean, string?)
end
```

`install` makes the seam's functionality available to generated calls. For a
compile-bound seam it binds the already checked implementation selected by the
lowering. For a runtime-bound seam it installs a lazy boundary that requires
the selected third-party module and validates its values. `test` invokes the
compiler-owned behavioral suite against the same implementation. It is not a
callback a backend author may replace with a test that always passes.

The common `Seam` interface erases contract-specific details only inside a
compiler-owned seam factory. A compile-bound factory accepts its checked
implementation interface. A runtime-bound factory accepts an exact module name
and owns the lazy validator and adapter for that module's values. Both attach
the seam name, contract version, installer and compiler-owned conformance suite.
`Backend.new` rejects an empty collection and duplicate seam names. This lets
one backend bundle several facilities without weakening any seam's contract.

A backend descriptor must also be readable without running it. The exported
value is therefore restricted to `Backend.new` with a constant name and a
literal list of compiler-owned seam constructor calls. A runtime-bound call
contains its exact module string. Compile-bound implementation code remains in
ordinary checked modules; only the descriptor is declarative. Imports naming
`Backend` and the seam factories are immutable `const` bindings to exact
`require` strings, so reassignment cannot make the runtime value disagree with
the static descriptor. The checker writes the backend and seam identities into
the module interface, so `check`, `build` and task inspection can resolve a
backend without executing its top level or a third-party dependency.

A capability's implementation contract remains an ordinary `interface`,
checked by the machinery that already checks every other one:

```nupp
--- Two's-complement operations on the low 32 bits. Every result is
--- normalized to a signed 32-bit integer, and every shift count is
--- taken modulo 32.
interface Bitops
    band: function(a: integer, b: integer): integer
    bor: function(a: integer, b: integer): integer
    bxor: function(a: integer, b: integer): integer
    bnot: function(a: integer): integer
    lshift: function(a: integer, n: integer): integer
    rshift: function(a: integer, n: integer): integer
    arshift: function(a: integer, n: integer): integer
end
```

### Worked example: bitops through a runtime module

```nupp
module acme.compat.bitops

const Backend = require("nupp.runtime.backend")
const Bitops = require("nupp.runtime.seam.bitops")

export = Backend.new("acme.compat.bitops", {
    Bitops.seam("thirdparty.bitops"),
})
```

The adapter owns the declaration for its third-party module and its package
metadata owns the runtime dependency. It may wrap BitOp or another library; it
does not reimplement the operations. The checked call to `Bitops.seam` records
the exact runtime module; the seam lazily checks its shape and attaches the
bitops suite. Under `luajit` the same seam resolves to native operators and this
module is never loaded, never bound, and never named in the output.

### Worked example: struct values as tables

`struct` already forbids the constructs a table could not carry: metamethod
contracts, private fields, nested declarations, `{T}` fields, strings, function
types and `number?`. See [choosing](../type-system/records.md#choosing). What
remains is a closed set of scalar, nested-struct and fixed-array fields, which
is what the `structvalue` capability describes. The contract below describes
their value behavior; it makes no C-layout promise:

```nupp
--- One declared layout, as the compiler knows it.
record Layout
    name: string
    fields: {Field}
end

--- Whether a value of this representation is a reference. `true` means the
--- compiler emits `copy` where the source assigned by value.
interface StructValue
    referenceValued: boolean
    define: function(layout: Layout, methods: table): FixedType
    array: function(element: FixedType, count: integer): FixedArray
end

interface FixedType
    zero: function(): any
    of: function(...): any
    copy: function(value: any): any
    isa: function(value: any): boolean
end

interface FixedArray
    metamethod __index: function(self: FixedArray, index: integer): any
    metamethod __newindex: function(self: FixedArray, index: integer, value: any): nil
    copy: function(value: any): any
    isa: function(value: any): boolean
end
```

`Field` is a closed compiler-owned descriptor. It distinguishes a scalar, a
nested `FixedType`, and a fixed array with its element descriptor and count.
Declarations are defined in dependency order, so a nested by-value struct is
already a `FixedType`; the existing rejection of a by-value cycle remains.

`define` is called once per struct declaration, at module load. `array` creates
the descriptor for a `T[N]` field and returns a zero-based sequence whose
elements have the same store, copy and width rules as fields. It does not lower
the `carray(T, n)` storage primitive: that operation reaches `cstorage` and is
unavailable under `lua51`. `FixedArray` deliberately exposes no source-level
methods: indexing is supplied by its representation, while `copy` and `isa` are
the two operations the compiler needs when an array value crosses an assignment
or a gradual boundary.

The native backend answers `define` with `ffi.metatype` and fixed-array fields
with the cdata layout the generated code already uses. A table backend answers
the value operations with metatables:

```nupp
--- Vec2, in source.
local struct Vec2
    x: float
    y: float
end
```

```lua [luajit]
const __nuppMt_Vec2 = {__index = {}}
const Vec2 = ffi.metatype(ffi.typeof("struct { float x; float y; }"), __nuppMt_Vec2)
```

```lua [lua51]
local __nuppMt_Vec2 = {__index = {}}
local __nuppL_Vec2 = {name = "Vec2", fields = {{"x", "float"}, {"y", "float"}}}
local Vec2 = __nuppFixed.define(__nuppL_Vec2, __nuppMt_Vec2)
```

The declaration reads the same, the field access reads the same, and the
representation differs. That is the whole of what a backend is allowed to
change.

### Values that are references

A struct held in a Lua variable is a reference to its cdata, so mutating a
field through a parameter is visible to the caller. See [value or
reference](../type-system/records.md#value-or-reference). A table matches that.

Where the two diverge is assignment. `g.cells[0] = c` copies bytes through the
FFI and aliases a table, and so does `a.inner = b.inner` between struct-typed
fields. The checker knows both static types, so the compiler emits `copy` at
exactly those sites when the resolved backend declares `referenceValued`. Under
the FFI backend the flag is false and the assignment lowers unchanged.

### Field widths

`float` truncates the way a C float does, and `int32` wraps. A table backend
holds the fields privately and installs `__index` and `__newindex`, so a store
rounds or wraps before it lands.

That is the cost the dialect cannot avoid: a field read is a metamethod call
where it was an offset. Naming it here is the point. A capability that is
absent costs a diagnostic, and a capability satisfied by a backend costs
whatever that backend costs.

### SIMD has a scalar meaning

Automatic lane lowering of an ordinary scalar `@aot` loop is an optimization,
not a capability. When a build has no vector backend, the original scalar loop
is already its complete lowering. The program does not fail merely because a
target cannot vectorize it.

The explicit `nupp.simd` vocabulary also has a portable representation. Its
values are sealed, confined to the annotated function and already checked not
to escape. A `simd` backend may therefore represent a vector as a private table
of lanes and implement masks and cross-lane operations in ordinary Lua. A
backend-selected lane count is observable through `SpeciesU8.lanes`, so the
backend declares it and implements the whole vocabulary at that width. Sixteen
lanes is the portable baseline, matching the narrowest native tier.

This revisits one decision in [NEP 11](0011-simd.md). That proposal correctly
rejected public boxed vectors and a second source spelling for map loops. This
proposal keeps both rejections: emulated values remain private, non-escaping
backend values, and scalar map source remains scalar map source. It removes
only the conclusion that an explicit-SIMD function cannot execute when native
AOT is disabled. Under `luajit` with native AOT selected, the existing intrinsic
lowering remains direct and no emulation module is loaded.

### Dialect selects, `nupp.lua` composes

A dialect supplies a default backend, and a project may name checked backend
modules that add or replace complete seams:

```lua
backends = {
    "acme.compat.core",
    "acme.compat.libraries",
}
```

The module order is not precedence. A project backend replaces a dialect
default with the same seam name, but two project backends supplying the same
seam are an error. This keeps resolution explicit while allowing one package to
bundle bitops, wide integers and several library adapters in one `Backend`
value. The checked module interface records the backend name, seam names and
versions without executing the module or any dependency.

A project backend may replace `native`, a dialect default, or `open`. It may
not replace `forbidden`: a module cannot give stock Lua a C ABI or make an
ordinary Lua value carry a C pointer. A module can emulate wide integers or
packed lanes, which is why `int64` and `simd` are `open` while `cinterop` is
`forbidden`.

An explicit override of `native` is permission to pay the override's cost. In
its absence, a `luajit` build binds the native operation exactly as it does
today. Portability never inserts a common wrapper in front of that operation.

### Runtime seams adapt standard-library dependencies

A standard-library member is not a compiler capability merely because its
current implementation uses the FFI. JSON, UTF-8, SHA-256, UUID, bitsets, byte
buffers and PEG are library facilities. A portable artifact may obtain one from
a selected runtime module rather than from an implementation maintained in
Nupp.

The smallest independently selected standard contract is a runtime seam. A
backend can contain one or many of `data.json`, `data.sha256`, `data.utf8`,
`data.uuid`, `data.hash`, `data.bitset`, `io.bytes`, `io.path`, `io.uri`,
`host.files`, `host.http`, `host.process`, `host.workers`,
`crypto.hmac_sha256`, `peg` and `suspension`. Those
names are contracts, not blessed packages. A seam may be a thin adapter over
`lunajson`, BitOp, a SHA-256 or UUID rock, LPeg, a scheduler or any other
implementation. Its checked source must use the compiler-owned seam factory.
Nupp may publish small adapters for common module APIs, but the proposal does
not require Nupp to own their algorithms.

For a dependency that is intentionally unavailable while building, the seam
factory accepts an exact runtime module name:

```nupp
module acme.compat.json

const Backend = require("nupp.runtime.backend")
const JSON = require("nupp.runtime.seam.json")

export = Backend.new("acme.compat.json", {
    JSON.seam("lunajson"),
})
```

`JSON.seam` is ordinary checked Nupp source. It owns the lazy require, the
shape check, the adapter to Nupp's JSON contract and the compiler-owned suite.
It can be checked and tested in isolation. The generated artifact contains only
a call that installs `acme.compat.json`; no adapter or fallback implementation
is assembled in a string inside the compiler.

Selection remains explicit and singular. Nupp never probes an ordered list of
installed modules, because two machines with different ambient rocks would then
give the same artifact different implementations. The selected runtime seam
performs `require` for the one recorded module when the reached member is
initialized, checks the runtime values that the contract can check, and raises
an error that names both the standard facility and the missing or incompatible
module. A build does not execute the backend, and an absent runtime rock is
therefore a runtime dependency error rather than a compiler execution side
effect.

The runtime provider and checked backend may be shipped by a target dependency.
Dependency resolution precedes backend resolution, so the rock's versioned
`nupp/` root participates in checked module lookup only for the target that
selected it. A portable target can therefore select its crypto rock without
making it a dependency of the native target:

```lua
dependencies = {
    portable_crypto = {
        kind = "luarocks",
        rock = "acme-crypto",
        version = "1.0-1",
    },
}
build = {targets = {
    native = {
        dialect = "luajit",
        entries = {"main"},
    },
    portable = {
        dialect = "lua51",
        entries = {"main"},
        dependencies = {"portable_crypto"},
        backends = {"acme.crypto.backend"},
    },
}}
```

The rockspec installs `acme.crypto.backend` as checked `.nupp` source and its
exact provider module, and may pull HMAC, SHA, TLS or HTTP libraries
transitively. The consumer compiles that selected backend source for its own
dialect and writes the compiler-owned runtime support it reaches as ordinary
Lua modules beside the artifact. Nothing depends on the compiler checkout's
runtime path. The backend records the adapter module name; it does not run
LuaRocks or probe installed alternatives during checking.

Facilities with environmental authority use the same rule. Filesystem access,
processes, HTTP, secure entropy and clocks may have host seams. A seam is
allowed to be unavailable on a host; it is not allowed to replace secure
UUID entropy with `math.random` or otherwise weaken the documented contract.

Suspension policy is independently replaceable. The `suspension` seam supplies
the complete `nupp.suspension` protocol, including source polling, handler
installation, cancellation, coroutine inheritance and the `all`, `gather`,
`race` and `batch` combinators. A scheduler or event-loop adapter must pass that
whole behavioral suite; it may not replace only parking while inheriting
unverified cancellation or handler-scope behavior. The bundled implementation
is the default when no backend overrides this seam, so a program that reaches
no selected suspension backend keeps the existing direct module.

The portable standard surface is accounted for by kind:

| Surface | Portable answer |
| --- | --- |
| scalar `nupp.math` expressible on the common Lua `math` table | compiler or existing Lua source |
| exact `i32`, `u32` and binary32 operations not supplied by a chosen bit backend | selected runtime seam |
| JSON, UTF-8, hashes, checksums, UUID and bitsets | selected runtime seam per independently reached contract |
| byte buffers, readers, writers and typed scalar codecs | selected `io.bytes` seam |
| PEG | selected runtime seam, commonly an adapter over LPeg |
| suspension, scheduling and event-loop integration | bundled protocol or selected complete `suspension` seam |
| lexical URI and path operations | selected runtime seam or existing portable source |
| files, processes, HTTP and workers | independently selected host seams |
| `nupp.native`, raw heaps, C-array spans, C-layout SoA and pointer projection | unavailable without `cstorage` or `cinterop` |

This table is a completeness requirement for the dialect, not a promise to
vendor any particular third-party rock. Every public standard member must be
classified as common source, selected runtime seam, host seam, or unavailable
at a native boundary. “The module currently happens to require `ffi`” is not a
classification.

### Resolution is total and recorded

Every seam the program actually reaches resolves to exactly one implementation,
or the build fails. Nothing is discovered by scanning a
directory, nothing is ambient, and no resolution order decides between two
candidates, because there is never more than one.

`nupp build --json` reports the resolved table, and the artifact records it, the
way an artifact already records the ahead-of-time policy it was built under. A
backend entry carries the module name and digest of the checked `Backend`
value. Each reached seam entry carries its name, contract version and whether
it binds at compile time or runtime. When a selected target dependency installs
the exact runtime module, the entry also carries that dependency's package and
pinned version. Changing a checked backend cannot leave an artifact claiming it
resolved the old one. Code behind an exact third-party runtime module name is
deliberately not hashed: it may be supplied by a rock or a host after the
artifact was built, while the package lock accounts for the selected artifact.

### Missing capability reports at the use site

```text
error[NUPP3006]: the `lua51` dialect has no `cinterop` capability
  --> src/wire.nupp:14:5
   |
14 |     cdef function htons(v: uint16): uint16
   |     ^^^^ `cdef` needs `cinterop`, which `lua51` does not provide
   |
help: no backend can supply C interoperation to a runtime without a C ABI.
      Move this declaration behind a module the portable build does not reach.
```

Six codes in the `NUPP3xxx` family, where code generation cannot represent a
checked construct:

| Code | Reported when |
| --- | --- |
| `NUPP3006` | the dialect has no capability the construct needs |
| `NUPP3007` | no selected backend supplies the seam a capability needs |
| `NUPP3008` | a named module does not export a valid `Backend` or supplies an incompatible seam |
| `NUPP3009` | the dialect has no semantics-preserving lowering for authored syntax |
| `NUPP3010` | a resolved prelude use is outside the dialect's runtime surface |
| `NUPP3012` | a reached standard-library facility has no runtime seam for the dialect |

`NUPP3012` is a build-time selection error: it says which seam contract to
supply. If a runtime seam named a third-party module that is absent or
incompatible on the machine running the artifact, the lazy adapter raises a
runtime dependency error naming that module. The two cases are not collapsed,
because the compiler can prove the first and cannot inspect the second without
executing the target's dependency environment.

### Backend may change representation and cost, not meaning

This is the rule the whole design rests on. A backend chooses how a value is
stored and what it costs to touch. It does not change what a program observes.

Some things cannot be preserved without a representation. A `uint64` field in a
runtime whose numbers are doubles is one, where no `int64` backend was named.
The build reports `NUPP3007` there, rather than lowering a slow answer or a wrong
one. Naming a backend permits the slow answer only because that backend supplies
a representation and operations for the complete `int64` contract.

The checker enforces the part a type system can prove: the module exports a
valid `Backend`, every seam came through its compiler-owned factory, the
implementation satisfies that seam's complete interface, and every generated
call has the checked type. It does not claim that an arbitrary implementation
of `band` computes the right bits. A function body can lie behind any ordinary
interface, which is why structural checking and the behavioral suite are
separate evidence.

Behavior remains testable rather than ambient. Every seam factory attaches a
compiler-versioned conformance suite implemented as ordinary checked source,
and

```sh
nupp backend test acme.compat.portable --dialect lua51
```

compiles the backend under that dialect and runs each of its seams in an
isolated worker. `--runtime lua5.1` writes the checked closure as real Lua files
and launches that interpreter, so a portable suite is not accidentally tested
inside the LuaJIT compiler process. A seam can also be selected by name for a
focused run. The command reports the seam name and contract version, backend
source digest, and runtime that ran it, and exits unsuccessfully on the first
mismatch. Native seams run these same suites, making them the reference
implementation without giving them a private test path. It is an explicit
command for backend authors, package CI, and consumers auditing a dependency.
`check` and `build` never run it implicitly, never execute a module only because
`nupp.lua` named it, and never turn a cached result into a proof. The artifact
records identities and digests, not a certification claim.

### Portability floor

`lua51` names the syntax and a common prelude surface. Lua 5.1 syntax parses on
5.2 through 5.4, and the names that moved are covered by one prologue line for
the ones the generator itself emits:

```lua
local unpack = unpack or table.unpack; local loadstring = loadstring or load
```

That is one line and depends on nothing. It is not a claim that every global in
Lua 5.1 exists in later versions. The dialect holds resolved prelude identities
to a compiler-owned intersection table. Core operations with the same contract
remain available; a name used only by generated code may use the prologue; and
a source use of `setfenv`, `getfenv`, `package.loaders`, a LuaJIT module, or any
other runtime-specific identity reports `NUPP3010` at that use. A local or module
field with the same spelling is not a prelude identity and is left alone.

The table is data beside the capability table and is exercised by running the
portable generated corpus under Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT in CI. Adding
an identity requires the same semantics on that matrix or an explicit compiler
lowering; availability on only one runtime does not widen the intersection.
This is what makes `check --dialect lua51` a portability check rather than only
a parser check, and what lets the same published artifact reach a 5.4 project
or a browser interpreter once the artifact's recorded runtime modules are
available there.

## Proof order

The implementation proceeds through independently falsifiable seams. A later
step does not compensate for a failure in an earlier one.

1. **Backend composition.** Check the real `Backend` and `Seam` interfaces,
   reject duplicate seams, install a selected backend with one generated call,
   and keep all adapter and suite behavior in separately checked source. Prove
   it with one native JSON seam, one third-party module name, and one
   structurally valid adapter that the behavioral suite rejects.
2. **Static backend metadata.** Restrict the exported descriptor, record its
   constant name and seam versions in the checked module interface, and prove
   that `check`, task inspection and `build` resolve it without executing the
   backend or requiring its runtime dependency.
3. **Dialect plumbing.** Add `luajit` and `lua51` to check, build, cache keys,
   task output and artifact metadata. A generated-output corpus must show that
   an omitted dialect and explicit `luajit` remain byte-identical to today's
   output.
4. **One compile-bound seam and one lowering.** Use `bitops`: preserve direct
   LuaJIT operators on the default backend, bind a complete checked BitOp-style
   adapter for `lua51`, and report a missing seam at the operator. Run the same
   bit-vector suite against native and adapted implementations.
5. **Syntax and prelude floor.** Lower generated `continue` and cleanup jumps,
   reject authored labels and runtime-specific prelude identities, and run the
   portable corpus under Lua 5.1, 5.2, 5.3, 5.4 and LuaJIT.
6. **Representation seams.** Prove `structvalue` with table-backed identity,
   copy sites and width-normalized stores before attempting `int64`. Refuse
   `cstorage` and `cinterop` at their exact uses.
7. **SIMD emulation.** Implement the complete confined `nupp.simd` seam with
   sixteen scalar lanes and run its suite against native and emulated backends.
   Ordinary vectorizable loops remain scalar when vectorization is unavailable.
8. **Standard and host accounting.** Classify every public standard member,
   adding checked runtime seam adapters for JSON, SHA, UTF-8, UUID, bitsets,
   PEG, suspension and host facilities as projects need them. These adapters
   may perform runtime checks for third-party modules; this step does not add
   duplicate algorithms to Nupp.
9. **Backend test command and artifact audit.** Expose isolated all-seam and
   focused runs on an explicitly requested Lua executable, report versions,
   runtime and digests, and verify the artifact records exactly the reached
   resolution and dependency package without claiming certification. Finish
   with one same-source library whose LuaJIT artifact retains direct operators
   and FFI representation while its Lua 5.1 artifact uses checked adapters.

## Risks and assumptions

- **Nothing dogfoods `lua51`.** The compiler needs `cinterop` and will never
  build under it, so the dialect has no self-hosting check behind it. The CI
  runtime matrix specified above is the only thing that keeps the common
  surface true, and without that matrix it rots quietly.
- **The standard library is FFI-shaped.** Seventeen modules under `src/nupp/`
  reach the FFI, including all of `io` and `mem`, and much of `data`. The
  seam accounting above prevents those modules from becoming an unnamed
  portability hole, but it moves availability into package management. A
  portable artifact can build successfully and then fail at first use when its
  declared runtime module was not installed on the target host.
- **Third-party APIs do not share one shape.** A checked runtime seam or thin
  adapter has to normalize each chosen module to Nupp's contract. Nupp avoids
  maintaining SHA-256, UTF-8, JSON and PEG algorithms, but somebody still owns
  each adapter and its compatibility range.
- **Runtime validation is necessarily shallow.** An adapter can check that a
  module loads and exports values of the promised shapes. It cannot prove that
  a SHA implementation hashes correctly or a UTF-8 implementation agrees on
  every invalid sequence; the explicit conformance suite remains the evidence
  for those behaviors.
- **A conformance suite is evidence, not a proof.** A contract that does not
  state a behavior cannot test it, a finite suite cannot prove an arbitrary
  implementation, and `build` deliberately does not pretend otherwise. The
  explicit command makes regressions reproducible without making dependency
  execution a side effect of checking.
- **A backend can be correct and unusably slow.** The structural check covers
  shape, not speed. A field read behind `__index` is a metamethod call, and
  nothing in this design tells an author that in advance of measuring.
- **Portable SIMD can allocate.** A table-backed vector preserves the confined
  vocabulary but may allocate per operation. That cost belongs only to an
  artifact that selected the emulation backend; native AOT retains direct
  vector lowering.
- **Two dialects double what every future lowering answers for.** Each new
  construct now has to say what it does where the capability is absent, and the
  cost lands on features that have nothing to do with portability.
- **`referenceValued` assumes the divergences are enumerable.** By-value
  assignment and width truncation are the two found by reading
  [records.md](../type-system/records.md). A third that nobody enumerated
  becomes a silent difference, which is the failure this design exists to
  prevent.

## Alternatives considered

**A directory convention, where `foo.lua51.nupp` beside `foo.nupp` overrides
it.** Rejected: adding a file would change what a build lowers to, and
[standard-library.md](../concepts/standard-library.md) already refuses a shape
whose answer depends on a load order the source does not show. A filename also
cannot be checked against a contract, and the safety argument here is entirely
that the contract is checked.

**Partial seams, supplying some members and inheriting the rest.** Rejected:
the result is semantics nobody wrote down and a conformance suite has nothing
complete to run against. A `Backend` may intentionally contain a subset of all
known seams so packages compose, but each `Seam` value is a complete contract.

**Lower `struct` to a table automatically wherever the FFI is absent.**
Rejected: the deepdive under [choosing](../type-system/records.md#choosing)
already says the record-or-struct decision is a declaration rather than an
optimization the compiler makes, because a compiler picking for you would be
choosing a memory representation from an annotation. A dialect that chose
silently would be doing exactly that, one layer further away from the reader.

**Erase `struct` to `record`.** Rejected: they are different nominal types with
different `is` behavior, different assignability, and different rules about
private fields and metamethod contracts. A program that checked as one and ran
as the other would be a second type system.

**A project setting that enables emulation globally.** Rejected: the same
reason the strictness floor is an extension rather than a setting. One switch
governing every file makes the meaning of a file depend on something the file
does not show.

**Make `lua51` the default and require opting into the FFI.** Rejected: it
changes the output of every program that exists today, and gives up the speed
the pass-through design bought, for an audience that most projects do not have.

**A user-extensible capability set.** Rejected: a capability names a construct
the compiler lowers to, so a capability the compiler does not know has nothing
to lower. Swapping an implementation the compiler does not lower to is
`require`, and needs no mechanism.

**Bundle a pure-Lua implementation of every standard facility.** Rejected: it
would make Nupp maintain second implementations of JSON, Unicode, hashes,
identifiers, byte codecs and PEG despite mature Lua modules already existing.
The portable contract needs a selected runtime seam and a useful missing-dependency
error; it does not need every algorithm to live in this repository.

**Probe for several well-known runtime modules and use the first installed.**
Rejected: an artifact would change behavior when an unrelated rock was added to
the host. A checked runtime seam selects one exact module, and the artifact
records and requires that exact name.

**Reuse `target` or `platform` as the name.** Rejected: `nupp.lua` already
names build targets, and `--platform` already selects a binary platform. A
third meaning for either word makes every existing sentence about them
ambiguous.

## FAQ

### Does this change what a build produces today?

No. `luajit` is the default dialect, every capability it declares is native, and
its output is what it is now. A project that never passes `--dialect` never
loads a portable backend or standard-library adapter. A byte-for-byte generated
output corpus enforces that claim; it is not only a performance intention.

### Why not one mechanism for this and for retargeting to WebAssembly?

They are different seams. A capability substitutes an implementation behind a
contract while the output language stays Lua. Retargeting replaces the emitter
and keeps the program. [NEP 14](0014-webassembly-from-aot-ir.md) covers the
second one, which is reachable only where an IR and a verifier already sit
between the checker and the output.
