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

A backend is an ordinary module carrying `@backend` and checked against the
capability's interface. Each capability also publishes a conformance suite that
`nupp backend test` runs explicitly; checking and building never execute a
dependency merely because a manifest named it. Selection resolves during the
build, binds one implementation per capability the program reaches, and is
recorded in the artifact. A capability with no implementation reports a
diagnostic at the construct that needed it, and never lowers to a substitute
that means something else.

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
- Make substitution checkable. A module claiming a capability must satisfy its
  structural interface, and the same documented behavioral contract is
  available as an explicit, compiler-owned conformance suite.
- Cost nothing at run time. A dialect binds one implementation during the
  build, so no program pays for a dispatch, a branch, or an indirection.
- Report at the construct that cannot be lowered, naming the capability that is
  missing and the substitute that exists.
- Leave what a build resolved readable in the artifact it produced.

## Non-goals

- Emitting JavaScript or WebAssembly from the general lowering.
- Making a dialect without a capability perform like a dialect with it. A table
  behind a metatable is not cdata, and no interface makes it one.
- A capability set a project extends. A capability is a construct the compiler
  lowers to; a facility the compiler does not lower to is an ordinary module
  dependency and needs none of this.
- Partial backends. A backend implements one capability completely.
- Changing the default. Under `luajit` the generated Lua is what it is today.
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

### Substitution already happens, with nothing to check it against

`JSON_FALLBACK` in `src/nupp/compiler/stdlib.nupp` is a pure-Lua JSON
implementation installed where a compiled dependency is absent, and
[standard-library.md](../concepts/standard-library.md) already states that the
compiler selects each implementation from the members checked source reaches.

Per-program implementation selection is therefore existing machinery. What it
lacks is a name for what is being selected, a contract the selection has to
satisfy, and a way for a second implementation to demonstrate that it does.

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

Each dialect entry has one of four states. `native` means the compiler emits the
runtime's operation directly. A module name is the dialect's default backend.
`open` means a project may name a backend but the dialect supplies none, and
`forbidden` means no backend can make the operation meaningful on that runtime.

| Capability | What needs it | `luajit` | `lua51` |
| --- | --- | --- | --- |
| `fixedlayout` | `struct`, `carray`, `T[N]` | `native` | `nupp.compat.fixedlayout` |
| `bitops` | `&`, <code>&#124;</code>, `~`, `<<`, `>>`, `~>>` | `native` | `nupp.compat.bitops` |
| `int64` | `int64`, `uint64`, cdata suffixes | `native` | `open` |
| `cinterop` | `cdef`, `cheader`, `T*`, `ffi.*` | `native` | `forbidden` |
| `presize` | `table.new`, `table.clear` | `native` | `nupp.compat.presize` |
| `simd` | `@aot` lane lowering | `native` | `forbidden` |

The set is closed and held as data, the way
`src/nupp/compiler/aot/admit.nupp` holds the admitted AOT subset. Widening it
is adding a row and the lowering that reads it, not writing a pass.

A project cannot add a capability, because a capability is a name for something
the compiler already lowers to. A facility the compiler does not lower to is a
module, and swapping one of those is `require`.

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

### Capability contract is an interface

A capability's contract is an ordinary `interface`, checked by the machinery
that already checks every other one:

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

### Backend declares the capability it implements

A backend is a module carrying the built-in `@backend` annotation:

```nupp
@backend(bitops)
module acme.compat.bitops
```

Where the file sits means nothing. A backend ships from whatever rock its
author publishes, and is found because a build named it, not because it was
discovered.

This adds `module` to the annotation registry's semantic attachment targets; it
does not add a keyword or grammar production. `@backend` takes exactly one name
from the compiler-owned capability set and may attach only to the file's module
declaration. It is reserved rather than user-defined because it changes
lowering. An ordinary user-defined annotation remains erased metadata and can
never become a backend by colliding with the spelling.

### Worked example: bitops without a bit library

```nupp
@backend(bitops)
module acme.compat.bitops

const WORD = 4294967296

local function wrap(v: number): integer
    v = v % WORD
    return (v >= 2147483648 and v - WORD or v) as integer
end

export function band(a: integer, b: integer): integer
    local out, bit = 0, 1
    local x, y = a % WORD, b % WORD
    for _ = 1, 32 do
        if x % 2 == 1 and y % 2 == 1 then out = out + bit end
        x, y, bit = math.floor(x / 2), math.floor(y / 2), bit * 2
    end
    return wrap(out)
end
```

`bor`, `bxor`, `bnot`, `lshift`, `rshift` and `arshift` follow the same shape.
Under `luajit` the same capability resolves to native operators and this module
is never loaded, never bound, and never named in the output.

### Worked example: struct as table

`struct` already forbids the constructs a table could not carry: metamethod
contracts, private fields, nested declarations, `{T}` fields, strings, function
types and `number?`. See [choosing](../type-system/records.md#choosing). What
remains is a closed set of scalar, nested-struct and fixed-array fields, which
is what the capability describes:

```nupp
--- One declared layout, as the compiler knows it.
record Layout
    name: string
    fields: {Field}
end

--- Whether a value of this representation is a reference. `true` means the
--- compiler emits `copy` where the source assigned by value.
interface FixedLayout
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

`define` is called once per struct declaration, at module load. `array` is the
lowering of `carray(T, n)` and returns a zero-based sequence whose elements have
the same store, copy, and width rules as fields. A `T[N]` field is created from
the fixed-array descriptor passed to `define`; it is not a host Lua array and
remains zero-based. `FixedArray` deliberately exposes no source-level methods:
indexing is supplied by its representation, while `copy` and `isa` are the two
operations the compiler needs when an array value crosses an assignment or a
gradual boundary.

The FFI backend answers `define` with `ffi.metatype` and `array` with the cdata
array allocation the generated code already uses. A table backend answers them
with metatables:

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

### Dialect selects, `nupp.lua` overrides

A dialect supplies a default per capability, and a project names an override:

```lua
backends = {
    bitops = "acme.compat.bitops",
    int64 = "acme.compat.int64",
}
```

An override is per capability. There is no setting that turns emulation on
generally, for the reason `.nupp` and `.g.nupp` are extensions rather than a
project flag: what a file means is visible where the file is.

An override may replace `native`, a dialect default, or `open`. It may not
replace `forbidden`: a module cannot give stock Lua a C ABI or vector registers.
This is why the `int64` entry above is `open` while `cinterop` is `forbidden`.

### Resolution is total and recorded

Every capability the program actually reaches resolves to exactly one
implementation, or the build fails. Nothing is discovered by scanning a
directory, nothing is ambient, and no resolution order decides between two
candidates, because there is never more than one.

`nupp build --json` reports the resolved table, and the artifact records it, the
way an artifact already records the ahead-of-time policy it was built under. A
backend entry carries the module name and the digest of the checked module
interface, so changing the module cannot leave an artifact claiming it resolved
the old one.

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

Five codes in the `NUPP3xxx` family, where code generation cannot represent a
checked construct:

| Code | Reported when |
| --- | --- |
| `NUPP3006` | the dialect has no capability the construct needs |
| `NUPP3007` | a capability has no implementation and no backend was named |
| `NUPP3008` | a named backend does not satisfy the capability interface |
| `NUPP3009` | the dialect has no semantics-preserving lowering for authored syntax |
| `NUPP3010` | a resolved prelude use is outside the dialect's runtime surface |

### Backend may change representation and cost, not meaning

This is the rule the whole design rests on. A backend chooses how a value is
stored and what it costs to touch. It does not change what a program observes.

Some things cannot be preserved without a representation. A `uint64` field in a
runtime whose numbers are doubles is one, where no `int64` backend was named.
The build reports `NUPP3007` there, rather than lowering a slow answer or a wrong
one. Naming a backend permits the slow answer only because that backend supplies
a representation and operations for the complete `int64` contract.

The checker enforces the part a type system can prove: the annotation names one
known capability, the module exports its complete interface, and every generated
call has that checked type. It does not claim that an arbitrary implementation
of `band` computes the right bits. A function body can lie behind any ordinary
interface, and a special annotation does not change that fact.

Behavior remains testable rather than ambient. Each capability's documentation
owns a compiler-versioned conformance suite generated by `doctest`, and

```sh
nupp backend test bitops acme.compat.bitops --dialect lua51
```

compiles the module under that dialect and runs the suite in an isolated worker.
The command reports the capability contract version, backend source digest, and
runtime that ran it, and exits unsuccessfully on the first mismatch. It is an
explicit test command for backend authors, package CI, and consumers auditing a
dependency. `check` and `build` never run it implicitly, never execute a module
only because `nupp.lua` named it, and never turn a cached test result into a
proof. The artifact records identities and digests, not a certification claim.

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
or a browser interpreter.

## Risks and assumptions

- **Nothing dogfoods `lua51`.** The compiler needs `cinterop` and will never
  build under it, so the dialect has no self-hosting check behind it. The CI
  runtime matrix specified above is the only thing that keeps the common
  surface true, and without that matrix it rots quietly.
- **The standard library is FFI-shaped.** Seventeen modules under `src/nupp/`
  reach the FFI, including all of `io` and `mem`, and much of `data`. A dialect
  that lowers programs but not the library gives an author a language with no
  library. Declaring a portable subset, and writing portable implementations
  for the parts worth having, is larger than the lowering work and is not
  scoped here.
- **A conformance suite is evidence, not a proof.** A contract that does not
  state a behavior cannot test it, a finite suite cannot prove an arbitrary
  implementation, and `build` deliberately does not pretend otherwise. The
  explicit command makes regressions reproducible without making dependency
  execution a side effect of checking.
- **A backend can be correct and unusably slow.** The structural check covers
  shape, not speed. A field read behind `__index` is a metamethod call, and
  nothing in this design tells an author that in advance of measuring.
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

**Partial backends, supplying some members and inheriting the rest.**
Rejected: the result is semantics nobody wrote down and a conformance suite has
nothing to run against. `src/nupp/compiler/build/aot.nupp` already makes this
call for ahead-of-time policy, refusing a mode that mixes compiled functions
with fallbacks, because a build whose speed nobody can reason about is not
worth the flexibility.

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

**Reuse `target` or `platform` as the name.** Rejected: `nupp.lua` already
names build targets, and `--platform` already selects a binary platform. A
third meaning for either word makes every existing sentence about them
ambiguous.

## FAQ

### Does this change what a build produces today?

No. `luajit` is the default dialect, every capability it declares is native, and
its output is what it is now. A project that never passes `--dialect` never
resolves a backend and never loads one.

### Why not one mechanism for this and for retargeting to WebAssembly?

They are different seams. A capability substitutes an implementation behind a
contract while the output language stays Lua. Retargeting replaces the emitter
and keeps the program. [NEP 14](0014-webassembly-from-aot-ir.md) covers the
second one, which is reachable only where an IR and a verifier already sit
between the checker and the output.
