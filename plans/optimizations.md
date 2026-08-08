# Compiler optimizations

## Position

Nupp compiles to Lua source for one backend, and that backend has a
tracing JIT. Most of the optimization catalog a Lua-targeting compiler
would normally reach for — inline caching, global-chain resolution,
method-call specialization, loop-invariant motion, inlining, unrolling —
duplicates work LuaJIT's trace compiler already does, and does better,
on any code that runs often enough to matter. Implementing them buys a
soundness burden in exchange for gains that vanish once a trace warms.

The optimizations worth building are the ones the trace compiler
structurally cannot do:

- **GC pressure.** LuaJIT's collector is its weakest component and the
  JIT does not help with it. Every object nupp keeps off the Lua heap is
  an object the collector never walks. Reification already does this for
  declared structs (6–9x on `bench/aos.nupp`, 5.6x on memory); the
  remaining work is extending it to values the user did not declare as
  structs.
- **FFI overhead.** Boxed `int64_t` cdata, `ffi.C` symbol lookups,
  repeated `ffi.typeof`, pin machinery — all paid before the JIT sees
  anything, and all statically known to nupp.
- **NYI avoidance.** Falling off a trace costs more than any lookup a
  compiler could hoist. A checker that knows what the trace compiler
  will do (plans/plan.md, §Vision) can rewrite or diagnose the
  constructs that abort recording.

Every one of these depends on type and ownership information that only
nupp has. The prerequisite work in §What the compiler needs is therefore
not overhead on the way to the optimizations — it is the differentiated
part.

## Reading the catalog

Each entry is tagged with where its win lands:

```
 tag     meaning
 ──────  ──────────────────────────────────────────────────────────
 cold    The JIT already handles it on hot paths; the win is
         interpreter and startup only. Low priority, gated on a
         benchmark that shows a gain with the JIT enabled.
 real    Wins with the JIT on.
 core    Needs nupp's type, effect, or ownership information.
         Nothing that compiles untyped Lua can do it.
```

## Catalog

### Lookup and access

- `cold` **Import hoisting.** Globals and `require`d module fields bound
  to module-scope locals. The `local max = math.max` idiom, applied by
  the compiler. Requires the target binding to be provably stable; see
  §Immutability must be declared.
- `cold` **Chain hoisting.** `a.b.c` bound to a local at function entry,
  not module scope. Function entry preserves resolution order relative
  to module initialization; module scope does not, and turns a working
  program with a circular `require` into a load-time nil index. One of
  the few entries that genuinely moves code to a line it was not on; see
  §Line attribution.
- `cold` **Field-read CSE.** Repeated reads of the same path collapse
  within a region containing no call, no assignment reaching the path,
  and no yield.
- `core` **Method devirtualization.** When the checker knows the
  receiver's type, `obj:m()` resolves to the defining table's field
  without walking `__index`. Note that a metamethod contract is trusted,
  not verified (docs/metamethods.md) — the checker is told how dispatch
  behaves but does not install it, so devirtualization inherits the
  contract's trust rather than proving anything.
- `core` **Static module binding.** `require("x").y` resolved at compile
  time to a direct binding, with no table read at runtime. Interacts
  with incremental cutoff; see §Cross-module optimization breaks cutoff.
- `core` **Struct field access.** Constant-offset cdata loads. Already
  landed, and worth stating here because it makes the four items above
  moot wherever types are known: the best fix for a repeated hash lookup
  is for it not to be a hash lookup.

### Allocation

- `real` **Closure caching.** A closure with no upvalues, or only
  `const` upvalues, created at module scope, is allocated once and
  reused. Changes function identity; see §The observability contract.
- `real` **Table presizing.** A `{}` literal followed by a statically
  known set of field assignments lowers to `table.new(0, n)`. Landed as
  `OPT-1`; `bench/presize.lua` measures 2.3x on four hash fields, 2.7x
  on eight, and 7.5x on four array slots, with the JIT on. What it buys
  is the allocations and copies a rehash performs while the table grows
  — not heap, since LuaJIT rounds a hash part to a power of two and
  frees a replaced one immediately. Presizing is not a GC optimization,
  which is worth remembering before grouping it with the ones below.
- `real` **Concat lowering.** String building in a loop lowers to
  `string.buffer`.
- `core` **Scratch reuse.** An `ffi.new` inside a loop is hoisted and
  reused when ownership proves the value does not escape the iteration.
  This is what `@owned` and non-escaping borrows already establish
  (docs/ownership.md); the optimization is reading the analysis that the
  resource model computes anyway.
- `core` **Table promotion.** A local table with a statically known,
  fixed field set that provably does not escape becomes cdata. Removes
  it from the GC graph entirely. The highest-value item in this
  document, and the one furthest from landing.
- `cold` **Varargs elimination.** Known-arity calls should not touch
  `select` or build a table.

### Loops and numerics

- `core` **Int unboxing.** LuaJIT boxes `int64_t` as cdata. Where the
  checker knows a value's range fits a double exactly, keep it a plain
  number and skip the allocation. Directly relevant to the 53-bit
  entity-id packing in the tecs acceptance test.
- `core` **`ipairs` to numeric `for`.** When the operand is a declared
  array or C array of known length.
- `real` **`#t` hoisting** out of a loop condition when the table is
  provably unmutated across the loop.
- `core` **Bounds-check elision.** Lua has no bounds checks, but nupp
  code over raw memory writes them by hand. Elide the user's guard when
  the range is provable.
- `cold` **LICM** for calls the effect system proves pure. Moves code
  across lines; see §Line attribution.
- `cold` **Unrolling** for compile-time bounds. The iterations can be
  emitted on the original line, so attribution survives.

### Functions

- `real` **Exact constant folding and propagation.** Fold primitive literal
  expressions and propagate `const` bindings. Keep floating-point arithmetic,
  cdata, allocation, calls, and mutable bindings at runtime unless the target
  semantics are specified exactly.
- `core` **Type-narrowing DCE.** Nil checks against non-nil types,
  branches made unreachable by narrowing, assertions the checker has
  already discharged.
- `core` **Monomorphization** of generic functions per instantiated
  type. Also improves trace stability by making call sites monomorphic.
- `core` **Effect-based CSE.** Two calls to a pure function with equal
  arguments collapse to one. Sound only with a sound effect system.
- `cold` **Inlining** of small local functions. The body can be emitted
  on the caller's line, so an error inside it reports the call site,
  which is the useful answer. What is lost is the callee's own frame in
  a traceback, and no mapping scheme recovers it; see §Line attribution.

### FFI

- `real` **`ffi.C` symbol hoisting.** Every `ffi.C.foo` is a lookup
  through a metatable. The hand-written idiom is a local binding; nupp
  knows the symbol statically and can always emit it.
- `real` **ctype caching.** `ffi.typeof` results bound once. Mechanical
  given that struct types are static.
- `core` **Pin elision.** Drop `pinned<T>` machinery where the checker
  proves no GC point falls between the pin and the use.
- `core` **`with`-scope pooling.** Deterministic reuse of `@owned`
  resources across entries to the same scope (plans/with.md).

### Trace awareness

- `real` **NYI rewriting.** Detect constructs LuaJIT cannot record and
  either rewrite them into recordable form or diagnose them with a
  repair. The variadic-FFI trace hazards in the tecs port are the
  motivating case.
- `real` **Call-site monomorphization** to avoid trace explosion at
  polymorphic sites.

## Constraints

Four constraints are specific to nupp and rule out approaches that would
otherwise be standard. They should be checked before any optimization is
designed, not after.

### There is no deoptimization

A compiler that owns its VM can be aggressive, because the VM can revoke
an optimization at runtime when it observes something that invalidates
it. Nupp emits Lua source. Once a binding is hoisted into the output it
is hoisted permanently, and there is no runtime signal that can take it
back.

Every optimization must therefore be sound statically, or guaranteed by
the type system. "Sound in the common case, and users will not do the
unusual thing" is not available.

### Line attribution

Codegen is line-count-invariant, which is what buys correct stack traces
with no sourcemaps (plans/plan.md, §Pillars). The property optimizations
must preserve is narrower than the name suggests, and stating it
precisely frees most of the catalog.

**What the invariant is for.** Lua has no `#line`. C has one, JavaScript
has a sourcemap comment, DWARF has a full line program; Lua has nothing.
A prototype's line table is derived mechanically from the physical line
each token occupies, and there is no supported way to rewrite it after
load. The only native lever is a constant per-chunk offset, obtained by
padding with blank lines. The line-count invariant is the identity case
of that lever, and it is total: every consumer of a line number is
correct, with no runtime component and nothing to keep in sync.

**Why a sourcemap does not replace it.** A map has to be consulted by
something, and that something reaches only what it wraps. Errors routed
through a nupp-installed handler can be rewritten; `error(msg, 2)`
prefixes cannot, because LuaJIT bakes the position into the string
first. Uncaught errors crossing the C boundary, errors in coroutines the
runtime does not own, `jit.p` output, coverage tools, and any library
calling `debug.getinfo` all keep reporting generated lines. The result
is not lost debugging but non-uniform debugging, where some numbers are
right and some are wrong and nothing distinguishes them. That is worse
than either extreme.

**The property to preserve is attribution, not count.** What debugging
needs is that every emitted construct sits on the line of the source it
came from. LuaJIT records lines and not columns, so several statements
sharing a line are indistinguishable in a traceback, and Lua permits
arbitrary line density through `;` and `do ... end`. Generated lines may
therefore be as long and as ugly as an optimization requires — `-O0`
still emits the readable form. Under that reading, unrolling, field-read
CSE, table presizing, ctype caching, `ffi.C` hoisting, struct promotion,
int unboxing, narrowing DCE, and monomorphization all preserve
attribution exactly, with no map and no change to the toolchain.

**The design gate** is therefore *does this move code to a line it was
not on*, not *does this change the line count*. Only chain hoisting,
module-scope import hoisting, and LICM answer yes. Their cost is
bounded and describable — a hoisted read that throws reports the hoist
site rather than the use site — and belongs in docs/diagnostics.md as a
documented consequence of `-O2` rather than as a reason to build a map.

**Inlining is a separate question.** Emitting a callee's body on the
caller's line keeps attribution: an error inside reports the call site.
What disappears is the callee's own frame, because no call was recorded.
That is a property of inlining, not of line numbering, and a line-to-
line map cannot express one location belonging to two frames. DWARF
solves it with inline records and real debuggers synthesize the missing
frames; nothing in the Lua ecosystem does. Inlining costs traceback
fidelity whether or not a map exists, which is the strongest argument
that a map would not pay for itself.

### Cross-module optimization breaks incremental cutoff

Incremental rebuilds cut off on interface hashes: a module is not
re-checked when a dependency's interface is unchanged. An optimization
that makes module A's *output* depend on module B's *body* — inlining
across the boundary, binding a module member statically, trusting that
B's declaration bindings are stable — makes A's codegen sensitive to changes cutoff
is designed to absorb.

Either such optimizations are confined to a whole-program build mode
that incremental builds skip, or the facts they depend on are promoted
into the interface hash so that changing them invalidates dependents
correctly. The second is better and is more work.

### Metamethod contracts are trusted, not verified

The checker knows how declared metamethods behave; it does not install
them (docs/metamethods.md). Any optimization keyed on a metamethod
contract — devirtualization, treating a read as pure, assuming no
`__index` — is sound only to the extent the contract is honored at
runtime. This is acceptable and is the existing bargain, but it should
be stated explicitly at each site rather than assumed, and it means
these optimizations belong behind the same trust boundary as the
contracts themselves.

## What the compiler needs

Most of the catalog is blocked on infrastructure rather than on any
individual transformation being hard.

### An effect system, pessimistic by default

Nearly every entry reduces to a single question: can this call observe
or invalidate what I am about to cache. Parameter-effect inference
(docs/ownership.md) is the seed. It needs to carry reads, writes,
allocations, yields, and calls-to-unknown, propagated across the call
graph, defaulting to the worst case for anything it cannot see. An
effect system that is optimistic about unknown callees is worse than no
effect system, because it produces confident wrong answers.

### Aliasing and escape analysis beyond resources

This is the structural advantage. Affine ownership with non-escaping
borrows is an aliasing discipline, and a compiler for untyped Lua has
none. The work is extending the analysis from C resources to plain
tables and locals, so that table promotion and scratch reuse can ask the
questions the resource checker already answers for `@owned` values.

### Immutability must be declared

Every `cold`-tagged item needs "this binding never changes," and
inferring that across a program is defeated by a single `load`,
`setfenv`, or write through `_G`. `const` already exists and means the
binding cannot be reassigned (plans/comptime.md, §Decision). What is
missing is an exceptional guarantee for bodyless declaration surfaces:
`@stable` bindings, so a declared host function such as `math.max` is stable
by contract rather than by whole-program analysis. Visible Nupp modules should
be analyzed directly; `@stable` is not a module-freezing mechanism.

This is the highest-leverage language change in this document. It
converts a class of optimizations from "requires an analysis that any
dynamic construct invalidates" to "sound by construction."

### A closed-world boundary with a visible escape hatch

`load`, `loadstring`, `dofile`, dynamic `require`, `setfenv`, FFI
callbacks re-entering Lua, and foreign code holding Lua references all
break the assumptions above. Because there is no deoptimization, the
boundary has to be static and it has to be visible in source — an
annotation, not an inference — so that a reader can see where
optimization stops.

### An IR with a control flow graph and def-use

CSE, LICM, DCE, and escape analysis over a lossless CST are miserable
and subtly wrong. This is the largest single piece of engineering here,
and most of the `core` catalog sits behind it. It should be designed
against the query core so that IR construction is cacheable per function
and participates in cutoff.

### Control and reporting

Named optimizations, flags that name guarantees rather than passes,
declaration-level annotations, and reporting for optimizations that did
not fire. See §Naming and control and §Remarks.

### Differential testing against the fixpoint

The existing self-hosting check generalizes into the strongest available
correctness gate: **the compiler built at `-O2` must produce output
byte-identical to the compiler built at `-O0`.** That exercises every
optimization against a large, real, self-referential program and fails
loudly on any observable difference, and it reuses infrastructure that
already exists.

Alongside it: run the full suite at every level and assert identical
behavior, and add a program generator so the corpus is not limited to
code that was written by hand.

### Benchmarks as a gate, not a report

No optimization lands without a `bench` entry showing a gain **with the
JIT enabled**. Most `cold` items will show large numbers in an
interpreter microbenchmark and approximately none in a real measurement,
because the trace compiler already did the work. An optimization that
cannot demonstrate a win under realistic conditions is complexity and
risk with nothing on the other side of the ledger.

### The observability contract

Before any of this lands, nupp has to decide and write down what counts
as observable behavior:

- function identity, and whether two closures from one site may be equal
- error timing, and error message content
- module initialization order
- finalizer and collection timing
- table iteration order
- stack trace shape

Every optimization in the catalog trades one of these away. Closure
caching trades identity. Import hoisting trades resolution order.
Inlining trades trace shape. Without the contract each one is an ad hoc
judgment call, and when a user reports a difference there is no
principled answer about whether it was a bug.

## Naming and control

Three separate needs get conflated under "let users turn optimizations
off." They want different mechanisms and should not share one.

### Stable identifiers, independent of exposure

Every optimization gets a code in the existing diagnostic convention —
`[OPT-7]` beside `[CS-13]` — assigned when it lands and never reused.
The compiler's own differential testing requires disabling one pass at a
time; without per-pass identity, an `-O2` against `-O0` failure reports
that something broke and nothing about what. Codes stay stable where
names do not, so a pass can be split, merged, or renamed without
invalidating a bug report or a test.

### User flags name guarantees, not passes

Roughly half the catalog is semantically transparent: presizing, ctype
caching, int unboxing, narrowing DCE. Nothing observable changes, and
the only reason to disable one is to bisect a compiler defect. The other
half gives up an observable property by design, and those properties are
already enumerated in §The observability contract.

```
 flag                            disables
 ──────────────────────────────  ──────────────────────────────────
 --preserve=function-identity    closure caching
 --preserve=load-order           import hoisting, static binding
 --preserve=error-site           chain hoisting, LICM
 --preserve=frames               inlining
```

A user asks whether their program still behaves, not whether a
particular pass ran. Guarantee flags answer that question, stay stable
while the passes behind them change, are few enough to test in
combination, and turn the observability contract from a document into
something the compiler enforces.

### Per-pass disable is a debugging aid in an unstable namespace

Bisecting a miscompile does want `-Zno-opt=OPT-7`. Exposing it under a
prefix documented as unstable gives the bisection tool without
committing to a flag namespace before 0.1, and without promising that
any particular pass continues to exist.

### Annotations carry declaration granularity

A miscompile is usually one function, not a build. `@preserve(identity)`
on a declaration is more precise than a global flag and is checked:
unknown annotations and invalid targets are already errors
(docs/annotations.md), so a misspelled opt-out fails loudly rather than
silently doing nothing.

### Levels

`-O0`, `-O1`, `-O2`, and a documented promise that `-O0` performs none
of this. When an optimization miscompiles a program, the user needs a
way to keep working that does not involve waiting for a release.

### Wiring

The active flag set is part of the incremental build key. Without that,
artifacts cached under one configuration are reused under another and a
build silently mixes levels. `fixpoint` is verified at `-O0` and `-O2`
plus the differential between them; per-flag fixpoint is not worth the
matrix.

## Remarks

The pillar is that types make code faster, which makes *did the
optimization fire* the more pressing question, ahead of *let me turn it
off*. A user who declares a struct and sees no speedup because the value
escapes has types that silently failed to do their job, and nothing
tells them so.

Report it as a diagnostic. The machinery exists: stable codes, spans,
related locations, and repair help (docs/diagnostics.md). A missed
optimization has exactly that shape — promotion did not fire here, the
value escapes at this related location, and this is the change that
would let it. Remarks stay off by default and are requested per
category.

This is worth building ahead of most of the catalog, because it applies
to work already landed. Reification exists and nothing reports whether
it fired; a user could be told today that a declared struct is or is not
being reified, and why.

## Priority

0. ~~Table presizing.~~ Landed as `OPT-1`, together with the harness
   everything below reuses: the pass registry, `-O` levels in the build
   key, `-Zno-opt`, remarks, and the differential check.
1. Exact constant folding and `const` propagation, plus remarks for the
   optimizations that already exist. Reification has
   landed and nothing reports on it. The reporting path exists now, so
   this is a matter of deciding what reification should say.
2. The FFI group. Real wins, small analyses, no new IR, and they target
   costs the JIT never sees.
3. NYI rewriting and call-site monomorphization. Largest measured effect
   on real programs; aligns with the trace-aware checker already on the
   roadmap.
4. Effect system, then escape analysis beyond resources.
5. Declared module immutability.
6. The IR, and the `core` catalog behind it.
7. The `cold` catalog, only where a benchmark justifies it.

## Non-goals

- Reimplementing analyses the trace compiler performs on hot code.
- Sourcemaps. They reach only the consumers nupp itself wraps, leaving
  the profiler, coverage tools, `error(msg, 2)` prefixes, and foreign
  `debug.getinfo` reporting raw generated lines, and they do not recover
  an inlined frame in any case. See §Line attribution.
- Optimization that is unsound in the presence of dynamic constructs but
  "usually fine." Without deoptimization there is no recovery path.
