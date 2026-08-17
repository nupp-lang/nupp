# Switch dispatch optimization

Status: implemented — follows `plans/055-switch-expressions.md`

## Decision

Add a backend-aware planner for checked switch expressions. Ordered lexical
branches remain the semantic baseline and the fallback for every switch. The
planner may replace them only when the checked cases prove that a different
shape preserves selector-once evaluation, first-match behavior, lazy arm
evaluation, bindings, `yield`, early `return` and source-visible predicate
order.

The work divides into three unconditional corrections to the lowering that
already shipped and three benchmark-gated alternative plans.

The corrections need no plan tag, no generated data and no threshold. Each is
measured in both traced and interpreted execution:

1. a table-keyed lookup needs no range guard, because a Lua table read answers
   `nil` for every out-of-range, fractional, NaN and infinite key;
2. a missing-entry sentinel is emitted only when some arm's result is itself
   `nil`, because the extra comparison otherwise sits on every hit;
3. a nominal type case drops its `?.` when the checker has already proved the
   subject is not `nil`.

The gated plans are:

4. a dense integer lookup for a static scalar map;
5. an ordinary Lua table for a static string map;
6. an ordinary Lua table for a sparse static integer map.

A collision-free generated hash is deliberately not in this release. It is both
the largest win and the largest regression measured anywhere in this work, and
choosing it correctly needs hotness information the compiler does not have. See
"Deferred: sparse perfect hash".

An AOT switch whose selector has an established `int32` or `uint32` physical
representation lowers to native C `switch`. Ordinary binary64 numbers continue
to use comparisons. The C compiler, rather than Nupp, decides whether native
code uses branches, a search tree, bit tests or a jump table.

No optimized lookup dispatches arbitrary arm bodies. A lookup may replace the
whole decision only when every selected result is a compiler-known inert value.
Otherwise it would merely compute an arm number and still need an `if` chain or
a function call, losing the property the optimization is meant to buy.

## Why

The switch syntax gives the compiler facts which cannot be recovered safely
from arbitrary `if` statements: one selector, normalized static labels,
first-match order, exhaustiveness and explicit nominal patterns. Those facts
justify backend-specific planning, but they do not give LuaJIT an indirect jump.
Generated Lua can compare, index a table and branch; it cannot jump from a
computed case number directly into arbitrary lexical code.

The exploratory benchmarks which precede this plan reported what a lookup costs
but not the baseline it has to beat, which is the number that decides every plan
here. A lookup is flat in the number of cases. An ordered chain costs whatever
the trace cannot specialise away, and that grows with the case count as soon as
the selector stops being predictable.

Measured on arm64 LuaJIT 2.1, 400k dispatches, best of nine, every variant
assert-agreed against the ordered chain including NaN and out-of-range misses.
Nanoseconds per dispatch:

```
 dense int  jit  stream   chain   table
 ─────────  ───  ───────  ──────  ─────
 4 cases    on   biased   1.65    1.51
 64 cases   on   biased   2.32    1.47
 4 cases    on   uniform  10.57   1.02
 64 cases   on   uniform  31.78   1.04
 16 cases   off  biased   24.97   25.15
 64 cases   off  uniform  301.47  28.24
```

Two things follow. The chain is linear in the case count where the lookup is
not, which is the argument for the map plans at all. And the table is never
materially worse even at ninety-five percent first-case bias, which is the
chain's best case, so the dense plan does not need the distribution modelling
this plan originally proposed: case count and eligibility settle it.

Strings behave the same way with a smaller margin — 1.38 against 1.72 biased and
3.35 against 20.52 uniform, at 64 cases compiled — so a string map is worth
having but needs a small-arity floor for interpreted execution.

An FFI call to a C helper cost more than doing integer dispatch in generated
Lua, and much more for dense integers and strings. That result stands and is why
no plan here crosses the FFI boundary per dispatch.

These numbers are evidence for the candidate set, not portable thresholds. Add
the benchmark to the repository and measure every supported architecture before
enabling a heuristic by default.

Java and native compiler precedent informs the split without changing it. A JVM
has bytecodes which jump directly to a selected label; stock LuaJIT does not.
Nupp's AOT path can recover that opportunity by emitting native `switch`, while
regular generated Lua should optimize only decisions which end at the lookup
itself.

## Governing invariants

1. **Semantics precede shape.** The ordered branch plan is always available and
   every optimized plan has the same result, effects and exit behavior.
2. **The selector still evaluates once.** Planning never duplicates, delays or
   speculates its evaluation.
3. **Only the selected arm evaluates.** Dynamic arm expressions, destructuring
   loads and block bodies are never placed in a precomputed table.
4. **User code keeps source order.** A predicate which may call a refinement,
   metamethod or other user code is not reordered, combined or cached.
5. **Generated data is immutable and allocated outside hot execution.** A
   lookup plan creates no table, cdata object or closure each time the switch
   runs.
6. **No callback table.** An optimization never represents arms as functions.
   A switch in a loop remains trace-recordable under `nupp bc --check`.
7. **Open domains verify membership.** Every plan in this release keys a real
   Lua table, so a non-case value is simply not a key and no verification code
   is emitted. A plan which computes a slot rather than a key must verify, which
   is one reason that plan is deferred.
8. **Closed domains are proved, not assumed.** Verification may be omitted only
   when exhaustiveness and the selector type prove that every runtime value is
   one of the encoded labels.
9. **Nil is not absence.** A case whose result is `nil` remains distinguishable
   from a missing lookup and from an `else` result.
10. **Planning is deterministic.** Source order, normalized values and stable
    tie breakers determine the emitted constants, names and layout. `nupp
    fixpoint` is the enforcement: a byte-identical self-rebuild fails on any
    `pairs()` iteration reaching plan construction.
11. **Backend choices are independent.** Regular LuaJIT and AOT may select
    different physical plans from the same checked semantic facts. A regular
    plan must account for both traced and interpreted execution.
12. **Code size is a cost.** A faster microbenchmark does not justify
    unbounded generated tables, constants, locals or upvalues.

## Representation

Add `src/nupp/compiler/switchplan.nupp`. Keep semantic facts separate from the
physical backend choice so that one target's limitation does not leak into the
checker.

The checked facts for one switch contain:

- the normalized labels in source order;
- the selector's checked type and, when established, physical integer width;
- whether the cases prove a closed runtime domain;
- whether every predicate is primitive and inert;
- whether every arm is one inert scalar result;
- whether bindings, destructuring, block arms or early exits occur;
- integer minimum, maximum, span, density and signedness;
- whether a nominal run has one safely shareable runtime identity operation;
- source locations for the switch and every case.

The planner returns one explicit tagged plan:

```text
SwitchPlan
    OrderedBranches
    DenseIntegerMap
    SparseIntegerMap
    StringMap
    NativeIntegerSwitch
```

Each optimized plan records its fallback reason as structured compiler metadata.
That reason is initially for tests and future optimization inspection; it is not
a diagnostic and must not make a valid program noisy.

Do not attach backend tables or C spellings to the CST. The CST remains the
formatter and LSP source of truth. The planner consumes checked annotations and
returns immutable data to regular generation or AOT lowering.

## Eligibility

### Static result maps

A dense, sparse or string map is eligible only when:

- every case is a static scalar case;
- every arm is an expression arm with one compiler-known inert scalar result;
- the fallback, when present, is also one inert scalar result;
- there are no bindings, destructuring fields, block arms, contextual yields or
  early exits;
- evaluating the result cannot read a mutable local, call a function, allocate,
  raise or otherwise expose when it was evaluated.

Use the switch scalar normalizer already defined by plan 055 for labels. Add a
smaller result encoder for `nil`, booleans, finite binary64 values, strings and
exact scalar names. Do not treat a merely immutable local as a static result.

A table read already distinguishes a hit from a miss, so the ordinary encoding
is that `nil` means miss and costs one comparison. Emit a private sentinel only
when some arm's result is itself `nil`. The second comparison a sentinel costs
is charged to every hit, and it measured 4.60x at four cases and 1.90x at
sixteen under a uniform stream compiled — the penalty is largest at small case
counts, where the sentinel slot is a larger fraction of the hits. Prefer holding
the nil-result labels out of the table and comparing them separately over taxing
the common path. Sentinels never escape the generated switch result.

If any eligibility condition fails, use ordered branches. Do not compute a case
ordinal and then dispatch through another branch chain.

### Coverage

Under coverage instrumentation, always select `OrderedBranches`. `gen.nupp`
wraps each case condition in a `branch` call, and a lookup has no per-case
condition to instrument, so an optimized plan would silently stop reporting
per-case branch data. This is an eligibility rule, not a test assertion.

### Nominal type cases

`gen.nupp` emits `getmetatable(subject)?.__index == Record` once per nominal
case. Two separate changes hide inside that spelling and only one of them pays.

Dropping the `?.` is the win, and it is unconditional. The checker already
narrows the subject inside a switch, so a case reached only when the subject is
not `nil` does not need the guard. Measured at four cases interpreted under a
biased stream, the guarded form costs 40.45 against 20.33 nanoseconds; at
sixteen cases interpreted under a uniform stream, 118.05 against 64.60.

Hoisting the `getmetatable` read across consecutive cases is not the win. On its
own it measured 1.04x compiled, which is noise, and the faithful hoisted-and-
guarded form is a 1.99x regression interpreted under a biased stream, because it
runs unconditionally where the chain stopped at the first case. Share the read
only once the guard is gone, and treat it as tidiness rather than as an
optimization with a plan tag.

Consecutive primitive cases may similarly share one `type(subject)` result.
Destructuring stays inside the selected branch.

Do not combine:

- `where` predicates or refined interfaces;
- predicates with overloadable or user-defined behavior;
- unrelated representations such as records and FFI structs;
- a source-order run interrupted by a predicate which cannot be proven inert;
- FFI `istype` calls unless a separate public, stable runtime identity is
  available.

The first release does not install a mutable polymorphic inline cache. Exact
nominal identity sharing removes repeated work without cache invalidation,
weak-reference or hot-reload semantics.

## LuaJIT plans

### Ordered branches

Keep the existing lexical lowering for all general switches. One to three
scalar alternatives always remain branches unless a later benchmark proves a
different cutoff. Preserve authored order for a workload biased toward an early
case; a uniform synthetic benchmark must not erase that advantage from the cost
model.

Do not add a balanced comparison tree in this plan. It is useful only after the
repository benchmark demonstrates a range where it beats both the source-order
chain and a terminal lookup without harming common biased distributions.

### Dense integer map

For eligible inert-result maps, compute `index = selector - minimum + 1` and
load one compiler-owned Lua array.

Emit no range guard. A Lua table read answers `nil` for a fractional, negative,
out-of-range, NaN or infinite index, so the miss path is already correct without
one; only a NaN table *write* raises, and no plan writes. The guard measured
1.26x compiled and 1.64x interpreted for nothing.

Holes are left `nil`, which is already the miss encoding, so they need no
sentinel either. Include the table's bytes and hole count in the cost estimate:
a constructor with many interior holes can push entries into the table's hash
part, and density alone is insufficient for an enormous range.

Hoist the array once into generated chunk state through the generator's existing
prologue registry rather than adding one. `declareHelper` already dedups by
rendered body, allocates a reserved name, and emits its declarations on the
prologue's single line so no source line moves; a `declareConstant` sibling
gives hoisting, content deduplication and source-map neutrality directly. Do not
introduce a global cross-module registry.

Every prologue entry is a chunk local and therefore an upvalue for each function
that reads it. `gen.nupp` already routes all cleanup sites through one indexed
table to stay under LuaJIT's ceilings; cap the number of prologue constants and
spill to one shared indexed table beyond the cap, so the count does not depend
on how many switches a module happens to contain. Fall back to branches when
generated source limits would be worse.

An FFI dense array is not the default. The benchmark showed no material compiled
advantage over a Lua array and the Lua array behaves better when interpreted.

### String map

For eligible inert-result maps, emit one ordinary Lua table keyed by the
normalized strings. Use the missing sentinel and explicit fallback handling.
Do not synthesize a string perfect hash: verification requires the original
string comparison, and the measured implementation lost to LuaJIT's table.

Apply the same hoisting, deduplication and prologue accounting as dense arrays.
Never put arm functions in the table.

Apply a small-arity floor. At four cases under a biased stream the chain wins
interpreted, 21.36 against 26.82, and ties compiled.

### Sparse integer map

For eligible inert-result maps whose integer labels are too sparse for a dense
array, emit one ordinary Lua table keyed by the integers, under the same
hoisting, deduplication, sentinel and fallback rules as the string map.

It is the only sparse plan with bounded downside. Compiled, it costs 2.84
against the chain's 1.74 at 64 cases under a biased stream and pays 9.35 against
21.56 under a uniform one; interpreted it wins from sixteen cases upward. The
worst case is about one nanosecond and the best is better than twofold, where
the alternative in the next section risks 2.7x in the wrong direction.

## Deferred: sparse perfect hash

A collision-free 32-bit hash into a fixed-width array is the largest win
measured anywhere in this work and also the largest regression. It is deferred,
and the reason is not that its benchmark gate is unwritten.

```
 sparse int  jit  stream   chain   luatable  ph_ffi  ph_lua
 ──────────  ───  ───────  ──────  ────────  ──────  ──────
 16 cases    on   uniform  10.46   9.06      1.05    1.83
 64 cases    on   uniform  21.56   9.35      1.03    1.81
 64 cases    on   biased   1.74    2.84      1.04    1.82
 16 cases    off  biased   22.03   28.08     74.96   47.29
 64 cases    off  uniform  183.52  33.27     75.16   47.29
```

Compiled it is twelve to twenty-one times better than the ordered chain.
Interpreted it is 1.7 to 2.7 times worse. A Lua array in place of the FFI array
halves the interpreted penalty and gives up most of the compiled margin without
removing the cliff, so the storage question this plan meant to ask is already
answered: FFI wins hot, Lua wins cold, and neither is safe without knowing which
the code is.

That is a hotness decision and the cost model has no hotness input. Lexical loop
presence is evidence rather than a promise, and choosing wrong here costs 2.7x
where every other plan in this release risks a fraction of a nanosecond.
Revisit it in its own plan, once a profile or another source of hotness exists,
with the key verification, `INT32_MIN` and `UINT32_MAX` conversion rules and
bounded construction search it needs.

## AOT plan

Do not add a scalar-IR statement op. `switchLocal` in `aot/lower.nupp` already
emits exactly the shape a native `switch` needs: one `Let` for the selector, one
zero-initialized `Let` for the result, and one `If` whose clauses are `eq` and
`or` chains over that selector with single-assignment bodies. Attach the
normalized integer labels to that `If` as an annotation and let the C emitter
read them.

The emitter is then reading a fact lowering already knew rather than
reconstructing a shape, which was the whole motive for a new node, and every
other consumer is untouched. A new op would need cases at seven `op == "if"`
sites in `aot/rewrite.nupp` and in `verify.nupp`, `text.nupp`, `emit.nupp` and
intensity analysis. Dropping the annotation is always safe, which also gives the
lane path its "desugar before rewriting" property for free: there is nothing to
desugar.

The annotation is attached only for an established `i32` or `u32` selector.
`switchLocal` today admits `f64` selectors with integer-valued labels, and this
plan narrows only which of them reach a native `switch`, not what is admitted.
Case constants currently lower through `lower.expression`, which yields `f64`
constants; native labels need constants at the selector's exact width, and that
conversion is the work item. Emit:

```c
switch (selector) {
case 1:
    result = first;
    break;
case 2:
case 3:
    result = second;
    break;
default:
    result = fallback;
    break;
}
```

Use exact-width C constants and preserve grouped labels. Binary64 selectors
remain scalar equality branches because C does not switch on `double` and an
implicit conversion would change Nupp semantics.

Teach C emission and source mapping about the annotation. Nothing else changes:
the annotated node is still an ordinary `If`, so SIMD lane rewriting reaches its
existing masked conditional representation without a desugaring step. The scalar
path preserves native `switch`; the lane path preserves per-lane semantics.

Do not synthesize a C perfect hash initially. Native C compilers already choose
among jump tables and comparison strategies with target information which Nupp
does not have. Revisit only with emitted assembly and end-to-end evidence for a
large stable workload. Do not call a native helper from regular Lua for one
switch; the measured FFI boundary outweighed the dispatch saving.

## Cost model

Centralize thresholds in the planner and name every input. At minimum consider:

- number of distinct labels;
- integer span, density and table bytes;
- open versus checker-proved closed domain;
- estimated comparisons for source-biased and uniform distributions;
- static-result eligibility;
- generated probe operations and verification work;
- module locals, function upvalues and source bytes;
- regular LuaJIT's traced and interpreted execution, and the AOT target;
- whether the switch occurs lexically in a loop.

The dense integer plan does not need the distribution inputs. It measured at
least as fast as the chain at ninety-five percent first-case bias and thirty
times faster under a uniform stream, so case count and eligibility settle it.
The string and sparse plans do need a small-arity floor, and it exists for
interpreted execution rather than for traced.

Lexical loop presence is evidence, not a promise that LuaJIT records the code.
Do not silently treat it as profile data. No plan in this release may depend on
that signal; the one plan which would have needed it is deferred for exactly
that reason. The initial thresholds are constants
backed by checked-in benchmark results, kept in one module and covered by
boundary tests. A later profile-guided system may supply distribution data
without changing switch semantics or plan tags.

The planner must expose a deterministic testing entry point which accepts facts
and a target, then returns the selected plan and reason. Tests should not infer
the planner's decision by scraping generated text alone.

## Benchmark gate

Add `bench/switch-dispatch.lua`, in the shape of `bench/match-lowering.lua`,
which already establishes the axes this needs: arm counts, a biased stream
against a uniform one, `jit.on()` against `jit.off()`, an agreement check before
timing, and a `NUPP_BENCH_MODE` escape for a machine too loaded to time. The
flat `.lua` convention holds for everything under `bench/` except the `*-spike`
trees. Record exact commands, LuaJIT version and architecture in the file
header. Prevent constant folding by consuming runtime-provided selectors and
verify every result before timing.

Measure:

- the ordered chain baseline at every case count and stream, which is the
  comparison every plan is against and which the exploratory run omitted;
- ordered chains with first-case, last-case, uniform-hit and mixed-miss input;
- dense integer Lua arrays at several spans and densities;
- guarded against unguarded dense indexing, and sentinel against plain
  encodings, so the two unconditional corrections stay measured rather than
  assumed;
- nominal cases with and without the `?.` guard;
- sparse integer Lua tables;
- string Lua tables and the rejected verified perfect-hash baseline;
- direct generated Lua versus one C helper through FFI;
- warm compiled traces and `jit.off()` interpreter execution;
- AOT ordered comparisons versus emitted native C `switch`;
- code size, module initialization cost and steady-state nanoseconds per lookup.

Use case counts at least `2, 4, 8, 16, 32, 64, 128` and include adversarial
integer spans and strings with deliberate hash clustering. Report medians and
dispersion across repeated samples; retain raw machine-readable output. A plan
is enabled by default only when it wins beyond noise on supported CI benchmark
machines and does not regress the interpreter path beyond the documented bound.

Record trace behavior beside the timings. Side-trace exits are the mechanism
behind every number in this plan, and nanoseconds per dispatch will not explain
a result that trace counts and aborts would.

Benchmarks are not correctness tests. Separately assert generated bytecode and
runtime behavior in the ordinary suite.

## Diagnostics and observability

Optimization eligibility does not affect whether source is valid, so declining
an optimization produces no diagnostic. Existing switch diagnostics and fixes
remain unchanged.

Extend an existing compiler inspection surface, or add a machine-readable
optimization inspection flag in a separate tooling change, before promising
users a particular plan. It should report the plan tag, case count, density,
encoded bytes and fallback reason without exposing generated private names.
Until that surface exists, planner unit tests provide observability.

`nupp bc --check` remains the authoritative test that regular lowering creates
no function inside a hot loop. Add bytecode fixtures for every Lua plan and
assert that table/cdata construction occurs at module initialization rather than
inside the loop.

## Documentation

Update `docs/switch-expressions.md` and its source reference material with a
performance section which explains:

- source order and first-match semantics never depend on the chosen plan;
- small and general switches remain lexical branches;
- only inert scalar-result maps can become direct lookups;
- integer, string and exact nominal cases have different eligible strategies;
- a lookup implementation is not part of the language contract;
- regular LuaJIT cannot directly jump from a computed ordinal to an arbitrary
  arm body;
- AOT `int32` and `uint32` selectors may become native C `switch`;
- a lookup wins by being flat in the case count, not by being a faster single
  operation, so a small switch has nothing to gain;
- no per-dispatch C helper, callback table, BDD or MTBDD is introduced.

Include compiled examples of:

1. a small ordered switch with a dynamic result which remains branches;
2. a dense integer-to-string map;
3. a sparse integer map with an `else`, and the miss which reaches it;
4. a string map including a `nil` result and the sentinel it forces;
5. adjacent record cases with destructuring after the unguarded identity test;
6. a refinement case which must retain source-order predicate evaluation;
7. an `@aot` `int32` switch and its generated C shape;
8. a block arm with `yield` demonstrating why arbitrary bodies are not table
   entries.

Document performance as conditional on target, case shape and workload. Do not
promise a case-count threshold in the language reference; thresholds are an
optimizer implementation detail measured by the benchmark suite.

## Test matrix

### Planner

- every plan tag and every fallback reason;
- thresholds immediately below, at and above each boundary;
- deterministic results under repeated runs and different Lua table insertion
  orders;
- dense spans with holes, negative minima and signed zero normalization;
- open and closed domains, including proof loss after widening;
- result eligibility for nil, booleans, numbers, strings, exact scalar names and
  every dynamic or effectful expression which must decline;
- a sentinel emitted only when an arm result is `nil`, and not otherwise;
- coverage instrumentation forcing `OrderedBranches`;
- code-size, table-byte and prologue-constant limits, including the spill to one
  shared indexed table.

### Runtime semantics

- selector evaluates once for every plan;
- hits, misses and fallback results match the ordered lowering;
- a `nil` result differs from a missing label;
- fractional, negative, out-of-range, NaN and infinite selectors reach `else`
  through an unguarded table read;
- grouped cases and duplicate-normalization rules remain unchanged;
- only the selected dynamic arm evaluates when optimization is ineligible;
- early returns, yields, cleanup and affine ownership behave identically;
- exact type identity is read once per compatible run and destructuring happens
  only after a match;
- refinements and overlapping patterns execute in source order.

### Generated Lua

- lookup data is hoisted and reused without entering the user namespace;
- no table, cdata object or function is created in the dispatch loop;
- generated locals and upvalues stay within LuaJIT limits;
- source maps still point to the selected case and arm;
- coverage-enabled generation selects `OrderedBranches` and reports per-case
  branch data unchanged;
- `nupp bc --check` accepts each optimized hot-loop fixture;
- generated source is deterministic and loads under the supported LuaJIT.

### AOT

- `i32` and `u32` selectors carry the label annotation and emit native C cases;
- exact minimum, maximum and grouped labels emit valid exact-width constants;
- binary64 selectors retain comparisons;
- an annotated `If` behaves identically when the annotation is ignored;
- lane rewriting preserves switch results for every lane;
- C compilers supported by the build accept dense and sparse forms;
- emitted source maps, scalar IR text and diagnostics retain case locations;
- runtime results match regular Lua for hits and misses.

### Repository verification

- focused planner, generator, bytecode and AOT suites;
- benchmark correctness preflight;
- `./bin/nupp test`;
- `./bin/nupp fixpoint` after compiler sources change.

## Non-goals

This plan does not add:

- conversion of arbitrary `if` trees into switches;
- a general BDD or MTBDD optimizer;
- a generated perfect hash, which is deferred rather than rejected;
- user-visible perfect-hash declarations;
- range, guard, nested or user-defined deconstruction patterns;
- callback tables or closures for arm bodies;
- a mutable polymorphic inline cache;
- a C/FFI helper call for each regular switch;
- a custom LuaJIT bytecode instruction or VM fork;
- profile-guided optimization;
- a guarantee that a particular source switch uses a particular physical plan.

An endpoint resolver or another generated decision program may still use an
MTBDD deliberately. That is a whole-program decision representation whose
traversal can be optimized or moved across one AOT boundary; it is not a sound
default lowering for arbitrary source conditionals.

## Delivery

1. Land the three unconditional corrections: no range guard, a conditional
   sentinel, and no `?.` on a nominal subject the checker has proved non-nil.
   None of them needs a plan tag, generated data or a threshold, and each is an
   edit to the lowering that already shipped.
2. Commit `bench/switch-dispatch.lua` with the ordered-chain baseline and
   validate the rankings on supported architectures and in interpreter mode.
3. Add checked switch facts, planner tags, deterministic selection and focused
   planner tests while keeping every selection on `OrderedBranches`.
4. Add hoisted generated-data registration through the prologue registry,
   sentinel encoding and the dense integer map.
5. Add the string map and the sparse integer map behind their small-arity
   floors.
6. Enable each threshold only after its benchmark rows pass the documented gate.
7. Annotate the AOT `If` with normalized labels and emit native C `switch` for
   established `int32` and `uint32` selectors.
8. Add planner inspection metadata and the complete documentation examples.
9. Run the full suite and compiler fixpoint, record final benchmark results and
   remove superseded optimization notes from plan 055 only where this plan has
   delivered them.

The plan is complete when the three unconditional corrections have landed and
are covered by the benchmark, every valid switch has a deterministic semantic
fallback, every enabled lookup wins its checked-in benchmark gate, optimized
Lua creates no dispatch-time object or arm function, AOT fixed-width integer
switches reach native C `switch`, and all plans are indistinguishable from
ordered branches in runtime, ownership, cleanup, coverage and source mapping.
