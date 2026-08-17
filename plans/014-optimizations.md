# Compiler optimizations

Status: living catalog, partly implemented. OPT-1 through OPT-6 have landed and
are registered in `src/nupp/compiler/optimize.nupp`; the rest of the catalog
below is unbuilt. `OPT-7` appears only as an example of the numbering
convention, not as a planned pass. Each pass keeps its code once assigned.

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

- **GC pressure, for values that escape.** LuaJIT's collector is its
  weakest component and the JIT does not help with it. Every object nupp
  keeps off the Lua heap is an object the collector never walks.

  The qualifier is load-bearing and was learned by measurement
  (`bench/scratch-reuse.lua`). A value that does not escape its trace
  costs nothing already, because allocation sinking removes it — so an
  optimization whose precondition is "proves it stays local" is aimed at
  the case the JIT has handled. What the collector actually walks is what
  escapes: kept in an array, returned, stored on something else.
  Reification is 6–9x on `bench/aos.nupp` precisely because 200,000
  particles held in an array escape as hard as a value can. The remaining
  work is extending that to values the user did not declare as structs,
  and telling the user when a declaration is one keyword away from it
  (`reifiable-record`, NUPP2509).
- **Algorithmic shape.** A trace compiler makes each step of an O(n²)
  loop fast and cannot make there be fewer steps. String building is the
  case that matters (`bench/concat.lua`), and it is worth naming
  separately from GC pressure because it is the one place where the
  compiler is not competing with the JIT at all.
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
- `cold` **Static callable binding.** Implemented as `OPT-4` for repeated
  statement-position calls in one lexical block. It binds the immutable
  dotted callee on its first use, preserving lookup order and error site.
- `cold` **Chain hoisting.** `a.b.c` bound to a local at function entry,
  not module scope. Function entry preserves resolution order relative
  to module initialization; module scope does not, and turns a working
  program with a circular `require` into a load-time nil index. One of
  the few entries that genuinely moves code to a line it was not on; see
  §Line attribution.
- `cold` **Field-read CSE.** Repeated reads of the same path collapse
  within a region containing no call, no assignment reaching the path,
  and no yield.
- `core` **Plucked call projection.** Implemented as always-on lowering
  rather than an `OPT-n` pass. A call's `(name) = path` and `(a, b) = path`
  arguments make the intended field set and arity static. Statement-level calls bind reusable dotted
  prefixes once and leave one-use leaves in the flat positional call,
  replacing the locals a performance-conscious Lua author would otherwise
  write by hand. Nested expressions repeat prefixes rather than creating an
  immediately invoked closure: the lowering never introduces a function,
  upvalue, argument table, varargs pack, or runtime arity choice. Safe calls
  retain their lazy nil guards. This is useful before tracing and removes
  dependence on whether LuaJIT happens to discover field-read CSE.
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
- `real` **Table presizing.** A `{}` literal followed by a consecutive
  run of named field assignments absorbs them into its constructor; other
  statically known writes lower to `table.new`. Landed as `OPT-1`;
  `bench/presize.lua` measures the named and fallback forms independently,
  including about 3x on four named fields, 2.5x on eight fields, and 7x
  on four array slots, with the JIT on. What it buys
  is the allocations and copies a rehash performs while the table grows
  — not heap, since LuaJIT rounds a hash part to a power of two and
  frees a replaced one immediately. Presizing is not a GC optimization,
  which is worth remembering before grouping it with the ones below.
- `real` **Concat lowering.** A loop-carried string accumulator lowers to
  `string.buffer`. The one entry the trace compiler structurally cannot
  absorb for a reason other than GC: `s = s .. piece` is O(n²), and a JIT
  makes each step fast without making there be fewer steps. Measured at
  1.8x over eight pieces rising to 3.6x over sixty-four, and it keeps
  climbing with the length (`bench/concat.lua`).

  Two decisions the benchmark settles. The lowering is **per-site**, not a
  module-scope buffer pool: pooling measures 4–14x, better throughout, and
  is only correct where the site cannot be re-entered, which recursion, a
  coroutine yield in the body, or any call reaching the same function all
  break. Pooling is therefore an upgrade gated on `yields`/`calls`/
  `external` from the effect summaries, not a default. And the trigger is
  loop-carried accumulation alone: creating a buffer costs about two
  concatenations, so the rewrite is a pessimization below three pieces, and
  straight-line `a .. b .. c` must never be touched — Lua already does a
  multi-operand concat in one operation.
- ~~**Scratch reuse.**~~ Struck. Measured a pessimization
  (`bench/scratch-reuse.lua`): hoisting a loop-local table and clearing
  it each pass runs at 0.46x, and the `ffi.new` the entry was actually
  written about at 1.00x. The reason is the entry's own precondition.
  Allocation sinking removes an allocation that does not escape its
  trace, which is the same condition ownership was going to prove, so
  both allocate **zero bytes** already and `-jdump` shows no `TNEW` in
  the trace at all. What reuse adds is the `table.clear` call, which is
  why the table row is twice as slow.
- ~~**Table promotion.**~~ Struck. The compiler will not decide that a
  table should be cdata.

  Two findings killed it. Its stated precondition was backwards — "a local
  that provably does not escape" is the case LuaJIT already handles for
  free, sinking it to zero bytes (`bench/scratch-reuse.lua`), so an
  optimization gated on proving it aims at what costs nothing. And the
  case that *does* cost — a table kept in an array, measured at 43 MB
  against zero — is not distinguishable statically from one that must stay
  a table. Whether promotion pays depends on how many are built and where;
  whether it is *legal* depends on whether anything iterates it,
  serializes it, or hands it to untyped Lua. No declaration states either.

  Promotion is also observable, not transparent: `type` answers `"cdata"`,
  `pairs` needs a `__pairs`, and `string.buffer.encode` refuses cdata
  outright. In a language with no deoptimization, a compiler that silently
  changes those is a compiler that breaks a program at the boundary rather
  than at the site.

  What survives is the two halves that do not require the compiler to
  guess. `reifiable-record` (NUPP2509) says a declaration is one keyword
  from reifying and offers the edit, so the author decides; and layout
  reflection (plans/010-layout.md) makes the reified form usable at the
  boundaries reification breaks. Between them the win is available and
  nobody is surprised by it.

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

- `cold` **Exact constant folding and propagation.** Fold primitive literal
  expressions, select constant conditional arms, and propagate `const`
  bindings. Keep floating-point arithmetic, cdata, allocation, calls, and
  mutable bindings at runtime unless the target semantics are specified exactly.

  Landed as `OPT-3`, and since extended with `//`, the six bit operators, and
  removal of a loop whose constant bounds admit no first iteration. The
  operators were the cheap half: `//` folds as the `math.floor((a) / (b))` it
  lowers to, and the bit operators fold through BitOp, which
  `decls/prelude.d.nupp` states *is* their meaning rather than a model of it. In
  both cases the fold runs the primitive the emitted operator would have run, so
  the standing worry about a hand-rolled proof does not arise.

  §What folding will not absorb records five further extensions that were
  designed and then declined, each for a reason worth not rediscovering.
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

- ~~`ffi.C` **symbol hoisting.**~~ Real and already emitted. A clib index
  costs about 0.6ns on a warm trace (`bench/ffi-hoisting.lua`), so the
  local binding is worth having, and a `cdef function` has lowered to
  `const foo = ffi.C.foo` since codegen was written (`src/nupp/compiler/gen.nupp`).
  There is no pass to build.
- `cold` **ctype caching.** `ffi.typeof` results bound once, rather than a
  declaration string spelled at each `ffi.cast` or `ffi.new`. Measured at
  1.6–2.5x in the interpreter and **nothing** with the JIT on
  (`bench/ffi-hoisting.lua`): a constant string argument is resolved at
  record time and folded, so both forms compile to the same trace. Fails
  the benchmark gate below; not worth building.
- `core` **Pin elision.** Drop `pinned<T>` machinery where the checker
  proves no GC point falls between the pin and the use.
- `core` **cleanup-region pooling.** Deterministic reuse of automatic `Owned<T>`
  cleanup machinery across entries to the same lexical scope.

### Trace awareness

- `real` **NYI rewriting.** Detect constructs LuaJIT cannot record and
  either rewrite them into recordable form or diagnose them with a
  repair. The variadic-FFI trace hazards in the tecs port are the
  motivating case.
- `real` **Call-site monomorphization** to avoid trace explosion at
  polymorphic sites.

### Nested constant exports

`OPT-3` currently folds exact primitive expressions, propagates a local
`const` binding, and selects a conditional whose predicates are all constants.
The common useful extension is propagating a literal through a required
module's immutable export path:

```nupp
-- settings.nupp
local M = {}

const M.palette = {
    const accent = "#5e81ac",
}

return M

-- app.nupp
const settings = require("settings")
print(settings.palette.accent)
```

The intended output retains the require, since loading a module may have
effects, but replaces the read with its literal:

```lua
const settings = require("settings")
print("#5e81ac")
```

The returned local identifies the module table, so no `module` keyword is
needed. `const M.field = value` fixes that export slot after its one
initialization. A nested `const field = value` inside a table constructor does
the same for that table slot. This permits deliberately mixed surfaces:

```nupp
const M.state = {
    const protocol = "nupp/1",
    requests = 0,
}
```

Only `protocol` is propagated; `requests` remains ordinary mutable state.
`const... M.field = {...}` is sugar for making every newly-created named table
slot in the value graph const recursively. It is a static guarantee, not a
runtime proxy or metatable, so it does not alter LuaJIT behaviour. Positional
and computed-key fields are deliberately outside the sugar: they have no
stable named path to use for propagation.

The export interface must record both a stable path and its literal value, and
its hash must change when either changes. Consumers then rebuild when
`palette.accent` changes even if its broad type remains `string`. A path is
foldable only when every edge is const, every access is a plain field read
without an indexing metamethod, and the required module has completed its
initialization. Circular require, `package.loaded` replacement, dynamic loads,
and foreign code are explicit closed-world escape hatches, never assumptions
the optimizer makes silently.

`@stable` is removed in favour of `const`. In visible Nupp, const is checked.
In a bodyless `.d.nupp` declaration, const is the necessary trusted statement
that a host binding (such as `ipairs`) will not be replaced. It is shallow and
does not freeze a table; `module` describes exports, and const describes which
bindings and fields do not change.

## What folding will not absorb

Five extensions that look like the obvious next ones, and are not. Each was
written out before it was declined, so the reason is recorded rather than the
conclusion — a later reader who has the same idea deserves the objection, not
an unexplained absence.

- **Pure calls over constant arguments.** `string.format("%s/%d", name, 3)` and
  `string.rep("-", 8)` are exact and deterministic, and folding them is what
  removes most of the demand for a compile-time evaluator. What stops it is not
  the fold but the callee: `string` is declared `local` in
  `decls/prelude.d.nupp`, and its fields are writable, so `string.format` has no
  `immutablePath` and a program is entitled to replace it. Folding through it
  would be assuming a guarantee the language does not make.

  The prerequisite is §Immutability must be declared, applied to the pure
  standard-library surface: `const` on the binding *and* readonly fields, so
  that monkey-patching `string.format` becomes a checked error. That is a
  language policy decision, not an optimizer one, and it also turns on `OPT-4`
  for every stdlib call site as a side effect. It should be taken deliberately
  and on its own.

- **Interpolated strings.** `` `hello ${NAME}` `` looks foldable once `NAME`
  propagates, and is not, for the same reason: codegen emits
  `tostring(...)` around every interpolation, `tostring` is a replaceable
  binding, and the fold would be asserting what it returns. A backtick string
  with no `${` is already a plain literal (`[CS-9]`), so the case that does not
  need `tostring` is one the folder never sees.

- **`#` and index reads on a `const` array.** `const T = {1, 2, 3}` fixes the
  binding, not the table, exactly as `const M = {}` does. `T[4] = 4` remains
  legal, so neither `#T` nor `T[1]` is a constant. The named-field forms are
  foldable because `const M.field` and `const...` say something about the slot;
  positional entries have no such spelling, and §Nested constant exports leaves
  them out for the same reason.

- **`t["name"]` reaching a proved const path.** Sound in principle — the bracket
  form names the slot the dotted form names — but unreachable in practice. A
  const named field makes the type a record, and indexing a record with a string
  key is NUPP2004 before the optimizer runs. The fold would be code no program
  could execute.

- **`nupp.sizeof`, `nupp.alignof` and `nupp.offsetof` folded to literals.** The comptime plan
  separates cleanly here in principle: these are pure functions of a resolved
  type and want no evaluator. What they want instead is a compile-time layout
  model, and nupp deliberately does not have one. `layoutof(T)` already answers
  this question, and answers it *at run time* through the FFI, because sizes,
  offsets and padding belong to the running platform rather than the compiling
  one (`check/ffi.nupp`, and plans/010-layout.md). Folding them would bake the build
  host's ABI into generated Lua that is portable source.

  So the item is not cheap-and-deferred; it is a target layout model plus the
  semantic type fingerprint that cross-module cutoff would then require. The
  comptime plan already assumes both — it keys evaluation on "the target triple
  and ABI/layout version" — which is the honest size of the item.

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

### ~~An effect system, pessimistic by default~~ — built

Nearly every entry reduces to a single question: can this call observe or
invalidate what I am about to cache. `src/nupp/compiler/analysis.nupp` answers it,
and has since numeric `ipairs` needed it. Summaries carry reads, writes,
shapes, metatables, escapes and calls, with `allocates`, `yields`,
`raises` and `external` flags and a `top` widening. `analysis.run`
iterates them to a fixed point over the call graph. The lattice is
one-sided by construction — "a fact may widen to `top`, but an unknown
operation never becomes harmless" — which is the pessimism this section
asked for. Alias classes are union-find within a body, with return
aliasing propagated through known summaries. `@effects` contracts are
checked against inference (NUPP2112) and trusted for bodyless
declarations; see docs/effects.md.

### Aliasing and escape analysis beyond resources — half built

The aliasing half exists. Alias classes are computed per body by
union-find, with return aliasing propagated through known summaries, and
they already answer questions about ordinary tables rather than only
about `Owned<T>` values.

The escape half is narrower than its name suggests, and an earlier
revision of this section claimed it whole. `escapes` is populated through
`rootOf`, which resolves a value only through `rooted` — and `rooted` is
built from a function's parameters. So a summary records **which
parameter-rooted paths leave a function**, which is the interprocedural
half and the one a caller needs. Whether a *local* escapes the body that
declared it is a different question, and nothing computes it: `rootOf`
returns nil for a purely local table, and no escape is recorded.

That missing question is exactly the one table promotion and scratch
reuse have to ask — does this table stay inside this function — so they
are further out than "escape analysis is built" would suggest. It is
still the smaller half: an intra-body walk over a body whose alias
classes are already computed, not a second interprocedural analysis. It
belongs behind §A query API onto the analysis, as the query the existing
`uses` count currently stands in for.

### ~~A query API onto the analysis~~ — built

The facts used to have exactly one consumer, and the shape of that
consumer was the problem. `proveLoops` lived inside `analysis.nupp`,
walked a body, decided the single question numeric `ipairs` lowering
asked, and stamped its verdict on the loop node; `optimize.nupp` read
that field and mentioned nothing else. So the second consumer's cheapest
route was a second prover beside the first, with its own traversal, its
own conservative reasoning and its own node field — and one had already
arrived, `discarded-result` having hand-rolled its own "does this call
reach anything" predicate over the same summaries.

The duplicated walking was never the cost. Hand-rolled proofs were: there
is no deoptimization here, so a proof that is subtly wrong is a
miscompilation with no runtime signal, and each copy is another chance at
one.

`analysis.queries` is what replaced it. `visible` separates a summary
that gave up from a body belonging to somebody else; `free` names which
effects disqualify a call, since that differs by caller; `known` resolves
a name to its callee; and a prepared body answers about alias classes,
mentions, and whether anything can change a value's shape. Each answers
`true`, or `false` with a reason and a node, because a pass that declines
owes a remark and a lint owes a caret, and a boolean carries neither.

Both existing consumers ask rather than prove. What stayed with numeric
`ipairs` is what was always its own opinion rather than a fact about
effects — that a dense literal is an acceptable bound, and that a second
mention of the array is reason to stop — and that moved to
`optimize.nupp` beside the rewrite it justifies.

Still to add, each when a caller needs it: whether a local escapes its
own body (§Aliasing and escape analysis, for table promotion and scratch
reuse, and to stop `reifiable-record` being purely syntactic), and
whether a region can yield or re-enter (for pooled concat lowering). The
`uses` count is a deliberate stand-in for the first and is documented as
one, because a query named `escapes` that answered a weaker question than
its name would be the kind of quiet wrongness this section exists to
avoid.

### Immutability must be declared

Every `cold`-tagged item needs "this binding never changes," and
inferring that across a program is defeated by a single `load`,
`setfenv`, or write through `_G`. `const` already exists and means the
binding cannot be reassigned (plans/003-comptime.md, §Decision). Bodyless
declaration surfaces use `const` for the exceptional guarantee a visible
implementation cannot establish itself: a declared host function such as
`math.max` has stable identity by contract rather than by whole-program
analysis. Visible Nupp modules should be analyzed directly; a const binding is
not a module-freezing mechanism.

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

The gate earns its keep by being run before the work, not after it. The
FFI group sat in priority slot 2 of this document, tagged `real`, until
`bench/ffi-hoisting.lua` was written and showed 1.00x. A benchmark that
argues against a pass belongs in `bench` beside the ones that argued for
the passes that landed, and should exit non-zero if its finding stops
holding — otherwise the same entry gets rediscovered and re-prioritised
on the same wrong intuition.

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

This section originally said reification reported nothing and that a user
could be told whether a declared struct was reified. That was wrong in
both directions, and what replaced it is worth recording.

A `struct` always reifies. The lowering is unconditional
(`src/nupp/compiler/gen.nupp`) and a field with no C spelling is NUPP2201 at the
field name, so there is no silent fallback and a per-declaration remark
would fire on every struct in the program saying the same thing.

The silent case is the opposite one: a `record` whose fields would all
reify is a hash table forever, and nothing said so. That is now
`reifiable-record` (NUPP2509). It is a lint rather than an optimizer
remark because nothing is rewritten and the advice holds at `-O0`, and it
is the first member of an opt-in category (docs/lints.md) because whether
reifying pays depends on how many values are built and where — which no
declaration states, so reported unprompted it fires on every small record
of numbers.

That last point is the honest limit of the current version: the test is
syntactic. The question it cannot ask — do instances of this escape, and
are they built in bulk — is `escapes` on a summary that already exists,
and wants §A query API onto the analysis.

## Priority

0. ~~Table presizing.~~ Landed as `OPT-1`, together with the harness
   everything below reuses: the pass registry, `-O` levels in the build
   key, `-Zno-opt`, remarks, and the differential check.
1. ~~Exact constant folding and `const` propagation.~~ Landed as `OPT-3`.
   Reporting on what already exists landed too, though not as this list
   expected it to: `reifiable-record` (NUPP2509), not a reification
   remark. See §Remarks for why the item as written was wrong.
2. ~~The FFI group.~~ Struck. Measured cold — the ctype half wins nothing
   with the JIT on, and the symbol half was already emitted
   (`bench/ffi-hoisting.lua`). It sat here on the assumption that a lookup
   the JIT cannot see is a lookup worth hoisting, which the benchmark gate
   below exists to catch.
3. ~~The query API.~~ Built, against the two consumers that already
   existed rather than in advance of one. See the section above.
4. Concat lowering. Measured and superlinear (`bench/concat.lua`), and
   the entry the trace compiler cannot absorb for a reason other than GC.
5. ~~Table promotion, and the local-escape query behind it.~~ Both
   struck, together with scratch reuse, which shared the slot. The
   precondition each was gated on -- prove the value stays local -- names
   the case LuaJIT already handles for free, and the case that does cost
   is not statically separable from one that has to stay a table
   (`bench/scratch-reuse.lua`). See §Allocation.

   The win is still available; it is reached by telling the author rather
   than by guessing. `reifiable-record` (NUPP2509) reports a declaration
   one keyword from reifying and carries the edit, so an editor can apply
   it, and layout reflection (plans/010-layout.md) makes the reified form
   usable where reification currently breaks it. Those two are the work.

6. NYI rewriting and call-site monomorphization. Largest likely effect on
   real programs, and still unmeasurable: it wants the tecs `FFIStorage`
   port (plans/019-todo.md) to have something to measure against.
7. Declared module immutability.
8. The IR, and the rest of the `core` catalog behind it.
9. The `cold` catalog, only where a benchmark justifies it. Nothing in it
   has cleared that bar yet, and one entry has now failed it.

## Non-goals

- Reimplementing analyses the trace compiler performs on hot code.
- Sourcemaps. They reach only the consumers nupp itself wraps, leaving
  the profiler, coverage tools, `error(msg, 2)` prefixes, and foreign
  `debug.getinfo` reporting raw generated lines, and they do not recover
  an inlined frame in any case. See §Line attribution.
- Optimization that is unsound in the presence of dynamic constructs but
  "usually fine." Without deoptimization there is no recovery path.
