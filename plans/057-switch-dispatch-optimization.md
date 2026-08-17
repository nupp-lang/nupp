# Switch dispatch optimization

Status: planned — follows `plans/055-switch-expressions.md`

## Decision

Add a backend-aware planner for checked switch expressions. Ordered lexical
branches remain the semantic baseline and the fallback for every switch. The
planner may replace them only when the checked cases prove that a different
shape preserves selector-once evaluation, first-match behavior, lazy arm
evaluation, bindings, `yield`, early `return` and source-visible predicate
order.

The first optimization release has four deliberately narrow alternatives:

1. a dense integer lookup for a static scalar map;
2. an ordinary Lua table for a static string map;
3. a collision-free generated hash for a sufficiently large sparse `int32` or
   `uint32` map, after its benchmark gate is met;
4. one shared runtime-identity read for compatible consecutive nominal type
   cases.

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

The exploratory benchmarks which precede this plan found these useful shapes on
the tested arm64 LuaJIT 2.1 build:

- dense integer Lua and FFI arrays were both about one nanosecond per lookup;
- a collision-free sparse 32-bit hash into an FFI array was also about one
  nanosecond and beat a Lua hash table in a compiled trace;
- ordinary Lua tables beat custom sparse layouts in the interpreter;
- a verified string perfect hash lost to an ordinary Lua string table;
- an FFI call to a C helper cost more than doing integer dispatch in generated
  Lua, and cost much more for dense integers and strings.

These numbers are evidence for the candidate set, not portable thresholds. Add
the benchmark to the repository and measure every supported architecture before
enabling a heuristic by default. In particular, do not choose an FFI-backed
perfect hash merely because a switch is large: code which stays interpreted may
become slower.

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
7. **Open domains verify membership.** A perfect hash or dense slot cannot turn
   a non-case value into a case merely because it lands in an occupied slot.
8. **Closed domains are proved, not assumed.** Verification may be omitted only
   when exhaustiveness and the selector type prove that every runtime value is
   one of the encoded labels.
9. **Nil is not absence.** A case whose result is `nil` remains distinguishable
   from a missing lookup and from an `else` result.
10. **Planning is deterministic.** Source order, normalized values and stable
    tie breakers determine the emitted constants, names and layout.
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
    SparseIntegerPerfectHash
    StringMap
    SharedNominalIdentity
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

A dense map, sparse perfect hash or string map is eligible only when:

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

Represent `nil` and missing entries with distinct private sentinels when the
physical table cannot distinguish them. Sentinels never escape the generated
switch result.

If any eligibility condition fails, use ordered branches. Do not compute a case
ordinal and then dispatch through another branch chain.

### Shareable type cases

Type-case sharing is a branch optimization rather than a static result map.
Consecutive concrete record cases may evaluate the subject's metatable identity
once and compare its stable `__index` identity with each declared record.
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

For eligible inert-result maps, compute `index = selector - minimum + 1`, guard
the represented range when the domain is open, and load one compiler-owned Lua
array. Holes carry the private missing sentinel. Include the table's bytes and
hole count in the cost estimate; density alone is insufficient for an enormous
range.

Hoist the array once into generated chunk state. Reuse identical immutable
arrays by content within one generated module, but do not introduce a global
cross-module registry. Account for the added chunk local and function upvalue
before choosing the plan. Fall back to branches when local, upvalue or generated
source limits would be worse.

An FFI dense array is not the default. The benchmark showed no material compiled
advantage over a Lua array and the Lua array behaves better when interpreted.

### String map

For eligible inert-result maps, emit one ordinary Lua table keyed by the
normalized strings. Use the missing sentinel and explicit fallback handling.
Do not synthesize a string perfect hash: verification requires the original
string comparison, and the measured implementation lost to LuaJIT's table.

Apply the same hoisting, deduplication and upvalue accounting as dense arrays.
Never put arm functions in the table.

### Sparse 32-bit perfect hash

Consider this plan only for established `int32` or `uint32` selectors and only
after branches, an ordinary Lua table and the candidate generated layout have
been benchmarked at that case count. Construction happens at compile time and
must either find a collision-free layout within fixed deterministic bounds or
decline cleanly.

The generated probe consists of exact LuaJIT 32-bit bit operations, an index
calculation and one data load. An open domain stores the original key beside the
result and verifies equality before accepting the slot. A checker-proved closed
domain may omit that key comparison. Signed and unsigned conversion rules are
explicit, including `INT32_MIN`, `UINT32_MAX` and values with the high bit set.

Benchmark both a Lua numeric array and an `ffi.new` fixed-width array. Select
the FFI representation only if the repository gate shows a repeatable win in a
compiled trace large enough to pay for poorer interpreter behavior and cdata
setup. Allocate it once at module initialization. Generated Lua performs the
probe directly; it does not call a C or FFI helper.

Cap construction attempts, emitted data bytes and probe expression size. Hash
failure, excessive layout size or unavailable FFI support selects the next
valid plan rather than reporting a source error.

## AOT plan

Add a scalar-IR node for a static integer switch rather than recognizing a
particular nest of `If` nodes in the C emitter. It contains the selector,
normalized integer labels, lexical bodies, optional fallback and source
locations.

The node is admitted only for an established `i32` or `u32` selector. Emit:

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

Teach scalar verification, textual IR output, source mapping, cost/intensity
analysis and C emission about the node. Before SIMD lane rewriting, lower it to
the existing masked conditional representation unless a future vector-specific
dispatch operation is justified. The scalar path preserves native `switch`; the
lane path preserves per-lane semantics.

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

Lexical loop presence is evidence, not a promise that LuaJIT records the code.
Do not silently treat it as profile data. The initial thresholds are constants
backed by checked-in benchmark results, kept in one module and covered by
boundary tests. A later profile-guided system may supply distribution data
without changing switch semantics or plan tags.

The planner must expose a deterministic testing entry point which accepts facts
and a target, then returns the selected plan and reason. Tests should not infer
the planner's decision by scraping generated text alone.

## Benchmark gate

Add `bench/switch-dispatch/` with a generator and a README containing exact
commands, LuaJIT version, architecture and result schema. Prevent constant
folding by consuming runtime-provided selectors and verify every result before
timing.

Measure:

- ordered chains with first-case, last-case, uniform-hit and mixed-miss input;
- dense integer Lua arrays at several spans and densities;
- sparse integer Lua tables;
- candidate perfect hashes with Lua and FFI data arrays;
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
- no per-dispatch C helper, callback table, BDD or MTBDD is introduced.

Include compiled examples of:

1. a small ordered switch with a dynamic result which remains branches;
2. a dense integer-to-string map;
3. a sparse `int32` map with an `else` proving misses are verified;
4. a string map including a `nil` result;
5. adjacent record cases with destructuring after the shared identity test;
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
- sparse `int32` and `uint32` boundaries and high-bit values;
- open and closed domains, including proof loss after widening;
- result eligibility for nil, booleans, numbers, strings, exact scalar names and
  every dynamic or effectful expression which must decline;
- code-size, table-byte, local and upvalue limits;
- perfect-hash construction success, bounded failure and fallback.

### Runtime semantics

- selector evaluates once for every plan;
- hits, misses and fallback results match the ordered lowering;
- a `nil` result differs from a missing label;
- non-case keys which hash to occupied slots take `else`;
- grouped cases and duplicate-normalization rules remain unchanged;
- NaN, infinities and binary64-only selectors never enter a 32-bit plan;
- only the selected dynamic arm evaluates when optimization is ineligible;
- early returns, yields, cleanup and affine ownership behave identically;
- exact type identity is read once per compatible run and destructuring happens
  only after a match;
- refinements and overlapping patterns execute in source order.

### Generated Lua

- lookup data is hoisted and reused without entering the user namespace;
- no table, cdata object or function is created in the dispatch loop;
- generated locals and upvalues stay within LuaJIT limits;
- source maps and coverage still point to the selected case and arm;
- ordinary and coverage-enabled generation choose semantically equivalent
  plans;
- `nupp bc --check` accepts each optimized hot-loop fixture;
- generated source is deterministic and loads under the supported LuaJIT.

### AOT

- `i32` and `u32` selectors produce scalar-IR switch nodes and native C cases;
- exact minimum, maximum and grouped labels emit valid constants;
- binary64 selectors retain comparisons;
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

1. Commit the reproducible benchmark and validate the exploratory rankings on
   supported architectures and in interpreter mode.
2. Add checked switch facts, planner tags, deterministic selection and focused
   planner tests while keeping every selection on `OrderedBranches`.
3. Implement shared primitive and nominal identity reads, then verify runtime,
   source-map, coverage and bytecode behavior.
4. Add hoisted generated-data registration, sentinel encoding, local/upvalue
   accounting and the dense integer and string static-result maps.
5. Enable thresholds only after their benchmark rows pass the documented gate.
6. Add bounded sparse 32-bit perfect-hash construction, verification and
   Lua-versus-FFI storage selection; keep it disabled when its gate is not met.
7. Add the scalar-IR integer switch, native C emission and lane desugaring for
   established `int32` and `uint32` selectors.
8. Add planner inspection metadata and the complete documentation examples.
9. Run the full suite and compiler fixpoint, record final benchmark results and
   remove superseded optimization notes from plan 055 only where this plan has
   delivered them.

The plan is complete when every valid switch has a deterministic semantic
fallback, every enabled lookup wins its checked-in benchmark gate, optimized
Lua creates no dispatch-time object or arm function, AOT fixed-width integer
switches reach native C `switch`, and all plans are indistinguishable from
ordered branches in runtime, ownership, cleanup, coverage and source mapping.
