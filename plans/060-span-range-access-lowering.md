# Range-proven span access lowering

Status: implemented — follows `plans/041-aot-independent-foundations.md` and
`plans/052-trace-aware-checking.md`

## Outcome

`OPT-6 span-range-access` landed after the evidence gate passed on an arm64
Apple host. For 8 million position/velocity struct element updates after
warmup, the median `span.range` loop improved from 10.749 ms with `OPT-6`
disabled to 7.345 ms enabled (1.46x, 1.344 to 0.918 ns/element). Handwritten
direct FFI took 7.588 ms in the same run, so generated direct access reached
the available regular-backend ceiling within measurement noise. Adopting
`span.range` independently was neutral: the handwritten-guard checked loop took
10.769 ms, a 0.998x checked/guard ratio.

A later run of the committed five-way harness measured 10.762 ms for the
handwritten-guard checked form, 10.800 ms for range plus checked access,
7.258 ms for `OPT-6`, 7.583 ms for handwritten direct FFI, and 4.433 ms for
forced-scalar AOT. The AOT number is backend context only; it is not included in
the pass speedup.

The benchmark trace categorized nine comparisons in the checked loop and three
in both `OPT-6` and handwritten-direct loops. External loads and stores also
matched (eight and four); repeated hash loads fell from ten to four and field
loads from sixteen to six. `nupp bc --check` found no recorder blocker.

The adoption audit confirmed the plan's hit-rate warning. No production hot
loop already used a same-function witness. The committed benchmark adapts the
position/velocity kernel without AOT, preserves its existing validation, and
captures rebindable span parameters in const aliases before forming the
witness. `tests/fixtures/native_foundations.nupp` was the only pre-existing
eligible code shape, while SoA owns a separate direct representation. The pass
therefore demonstrates a material beneficiary without claiming automatic reach
into the current AOT kernel corpus.

## Decision

Add an `-O1` pass which turns a checked `nupp.span` access inside the exact
numeric loop dominated by its `span.range` witness into an unchecked FFI array
access. The range call remains where the source wrote it and validates every
participating span once. Only the repeated `get`, `getMut` and `set` operations
whose receiver and index are already marked `rangeProvenNoRaise` are eligible.

The first implementation is specific to the sealed standard span contracts. It
uses a small generic checked representation for "this induction variable is in
bounds for this stable view", but it does not recognize arbitrary methods named
`get`, infer bounds from user-written conditionals or expose an unchecked public
span API.

The regular backend emits ordinary LuaJIT FFI pointer arithmetic. It adds no
bytecode, native helper, DynASM instruction or LuaJIT fork. With `frames`
relaxed on the containing function, a representative rewrite is:

```nupp
const rows = span.range(first, last, output, input)
for index = rows.first, rows.last do
    output:getMut(index).x = input:get(index).x + 1
end
```

```lua
local rows = span.range(first, last, output, input)
for index = rows.first, rows.last do
    output.pointer[output.offset + index - 1].x =
        input.pointer[input.offset + index - 1].x + 1
end
```

The spelling above is illustrative. Generation keeps the source's line mapping,
uses reserved names where a temporary is required and may emit pointer addition
for a `getMut` result consumed as a pointer. It does not move the range check or
an authored value expression to another line.

The pass receives the next stable optimization identity when it lands. This
plan calls it `span-range-access`; the implementation must not reserve an
`OPT-n` until the pass and its benchmark land together.

Inlining a source-level method call away trades the `frames` observable
guarantee. The direct rewrite therefore runs only where the containing function
or compilation grants `@relax("frames")` / `--relax=frames`. Without that grant,
the checked access remains unchanged and a requested remark explains the
decline. The existing proof keeps `error-site`: a successful `span.range`
establishes that the removed accessor bounds error is unreachable for the exact
receiver and induction variable.

## Why

`nupp.span` deliberately puts a rooted, one-based, bounds-checked view in front
of C memory. Its ordinary accessors perform two comparisons and then repeat the
same representation work on every element:

```lua
if index < 1 or index > self.count then
    error("span index out of bounds", 2)
end
return self.pointer[self.offset + index - 1]
```

`span.range` already validates one inclusive range against every supplied span.
The checker already transports that fact into the loop and marks an exact
matching access `rangeProvenNoRaise`. Today only effect analysis consumes the
mark: it permits the access inside `noraise`, while generation still emits the
ordinary checked method call.

This leaves a proof with no regular-backend performance consumer. AOT consumes
the same class of fact, validates each range once and emits direct native
loads/stores. SoA has the regular-backend precedent: a canonical count-bounded
row loop emits `columns[ordinal][offset + index - 1]`, while an arbitrary index
retains `checkedIndex`.

The committed Mandelbrot comparison gives a ceiling, not a prediction. Its
checked span body runs at 2.47 MPix/s, the recurrence over plain Lua locals at
about 4.6 MPix/s and forced-scalar AOT at 36.98 MPix/s. Span and struct plumbing
therefore accounts for roughly half of the elapsed-time gap to scalar C, but the
measurement does not isolate the two comparisons from method dispatch, record
field reads and pointer construction. This pass must land with an experiment
which does isolate them.

## Current reach and the same-function boundary

The proof is lexical and currently scoped to one checked function. A
`spanRangeWitness` lives on the const local definition initialized by
`span.range`; `check/control.nupp` recovers it only when that same definition is
the bare object of both loop bounds. Passing `first` and `last` to another
function passes two integers, not their originating witness. Passing the range
record itself as a parameter also loses the definition-local fact. No summary,
wrapper or call projection re-derives it on the callee side.

V1 keeps that boundary. An eligible loop must contain, in one function:

```nupp
const rows = span.range(first, last, left, right)
for index = rows.first, rows.last do
    -- matching accesses
end
```

That is narrower than the motivating benchmark corpus. At the time of this
plan, the AOT kernel subset takes checked span parameters plus plain `first` and
`last`, performs handwritten guards and loops over those integers. Mandelbrot is
one of those functions, so the source which produced the cited ceiling numbers
would not receive this optimization as written. The repository's real
`span.range` uses are documentation, checker/effect tests and a small native-
foundations fixture; there is no existing production hot loop which establishes
the pass's hit rate.

State those facts anywhere the benchmark result is presented. The Mandelbrot
numbers justify investigating span plumbing; they are not evidence that the
current proof shape reaches Mandelbrot or an existing application.

## Governing invariants

1. **One successful check justifies every removed check.** The generated direct
   access is dominated by the exact `span.range` call whose witness names the
   receiver.
2. **Identity, not spelling, connects the proof.** Receiver, range and induction
   variable match checked declaration identities. Shadowing or an equal-looking
   expression never matches by text.
3. **Only stable spans participate.** Every span supplied to the witness is a
   `const` binding, as required today. Rebindable views retain checked access.
4. **Only the canonical loop participates.** Both bounds are the same range's
   `.first` and `.last`, the step is the ordinary ascending unit step and the
   accessor index is the loop's induction variable itself.
5. **The standard sealed contract is the authority.** Recognition follows the
   resolved `nupp.span` type and member definitions, never a local table or a
   lookalike module.
6. **Unchecked access is not public.** Source outside the compiler-owned span
   implementation gains no raw indexing function, token or cast.
7. **Arbitrary access stays checked.** Arithmetic indexes, neighboring loop
   variables, calls outside the dominated loop and spans absent from the witness
   keep `get`, `getMut` or `set` exactly as written.
8. **Evaluation count and order survive.** V1 admits only the receiver and index
   name forms established by the proof. A stored value is evaluated once at the
   point of its authored `set` call.
9. **Roots survive the direct access.** Generated code continues to reach the
   span object, not only a detached raw pointer, so `anchor` keeps strings,
   arrays, parents and slices alive for the whole access.
10. **Offsets survive slicing.** Every physical index is `offset + index - 1`;
    no optimization assumes a root span begins at zero.
11. **Read and write capabilities do not widen.** `Span` emits reads only;
    `WriteSpan` emits only operations already accepted under its exclusive
    borrow. Lowering does not create a second writer or extend a borrow.
12. **Coverage and locations remain authored.** A direct load/store stays on the
    accessor's source line. Coverage still counts the containing statement, not
    generated pointer setup.
13. **The pass is optional and inspectable.** `-O0`, a disabled pass or a held
    `frames` guarantee retains the checked source shape. `--remarks` identifies
    applications and requested declines.
14. **AOT remains independent.** The AOT checker, verified IR and generated C do
    not consume regular-backend rewrite metadata and do not change their answer
    when this pass is disabled.
15. **Proofs do not cross calls in V1.** A range local, its bounds or its spans
    passed to another function do not make that callee eligible. Only the
    checked loop which names the witness local consumes it.

## Existing proof path

Do not create a second range analysis. Extend the path which already exists:

1. `check/bindings.nupp` recognizes a const binding initialized by the resolved
   `nupp.span.range` export. It records a `spanRangeWitness` only when every span
   argument is a const name.
2. `check/control.nupp` recognizes a numeric loop whose start and stop are the
   witness's `.first` and `.last` and which has no explicit step.
3. The loop walk matches a standard span accessor whose receiver belongs to the
   witness and whose first argument is the loop induction variable. It marks the
   call `rangeProvenNoRaise`.
4. `analysis.nupp` and `check/effectregions.nupp` already consume that mark to
   remove the raising effect, while retaining read/write region summaries.

This is the concrete portion of the range-dominated foundation described in
`plans/041-aot-independent-foundations.md`. Trace validation and the requirement
that lowering introduce no recorder blocker remain owned by
`plans/052-trace-aware-checking.md`; this pass consumes both rather than adding
parallel proof or trace catalogs.

The optimization pass consumes the same mark after checking. It may reject a
generation shape more narrowly than the effect proof — for example a `set` in a
value position V1 does not know how to print without a wrapper — but it may
never manufacture a mark or broaden what the checker proved.

Replace the two loose booleans on a proven access with one checked descriptor
only if doing so makes the consumers harder to disagree:

```text
SpanAccess {
    operation          get | get-mut | set
    receiverDefinition
    indexDefinition
    elementType
    writable
    noAllocate
    rangeWitness?
}
```

`rangeWitness` names the checked range definition and its participating span
definitions. Effects ask whether it is present; optimization adds its own
physical lowering decision. The descriptor contains semantic identities and
types, never emitted field names or Lua text.

## Pass contract

Add one walk to `src/nupp/compiler/optimize.nupp`. It runs after checking and
before regular generation, alongside the other `-O1` passes.

For each `rangeProvenNoRaise` access, the pass verifies:

- the selected optimization level enables it;
- the pass is not disabled through `-Zno-opt`;
- the containing function or compilation relaxed `frames`;
- the call still resolves to `nupp.span`'s `get`, `getMut` or `set` contract;
- the receiver and index remain bare names with the definitions the proof
  recorded;
- the access has a generator shape V1 supports.

An admitted call receives generator-only metadata:

```text
SpanDirectAccess {
    operation
    receiver
    index
    source
}
```

The pass does not edit authored tokens, replace the method-call CST or attach a
raw pointer to the type. That keeps formatting and LSP semantics on the source
tree and lets `gen` choose an expression or statement spelling appropriate to
the parent.

The first applied access in one loop emits one remark such as:

```text
OPT-n span-range-access: lowers 3 checked accesses after one range proof
```

Aggregate per loop rather than reporting every element operation. A requested
remark for an otherwise proved loop names one stable decline reason:

- `frames-held`;
- `unsupported-value-position`;
- `complex-access-shape`;
- `backend-not-regular-lua`.

The proof failures that already leave `rangeProvenNoRaise` absent are not
optimization declines. The checker and span documentation explain those rules;
the optimizer should not reconstruct guesses about why a call lacked a proof.

## Regular Lua generation

Generation owns the physical representation spelling because it already owns
the compiler/runtime ABI for SoA and other standard-library intrinsics. Keep the
span facts semantic until this point.

### Reads

A proved `view:get(index)` emits:

```lua
view.pointer[view.offset + index - 1]
```

The expression composes naturally with a struct field read:

```lua
view.pointer[view.offset + index - 1].field
```

No ctype string or runtime cast is needed. The pointer field already carries the
ctype established when the span was constructed, and LuaJIT records the array
and constant-offset field access through its existing FFI path.

### Mutable references

A proved `view:getMut(index)` used as a pointer emits the implementation's
existing unchecked expression:

```lua
view.pointer + view.offset + index - 1
```

When its immediate parent selects or assigns a struct field, prefer the indexed
element form:

```lua
view.pointer[view.offset + index - 1].field
```

That avoids materializing a derived pointer in source and gives LuaJIT the same
shape as a handwritten FFI element access. A bound pointer result keeps the
pointer-add form and the ownership checker remains the authority on how long it
may live.

### Stores

A statement-position proved `view:set(index, value)` emits:

```lua
view.pointer[view.offset + index - 1] = value
```

V1 leaves `set` in expression, return, argument or multi-result position
checked. Turning an assignment into an expression there would require a wrapper
or the general expression-normalization plan, neither of which belongs in this
pass.

### Rooting and hoisting

Do not explicitly hoist `pointer` or `offset` in V1. Reaching them through the
span on every generated access matches the existing SoA strategy, preserves the
runtime root visibly and lets LuaJIT perform trace-local CSE and loop-invariant
motion under its own guards.

An explicit preheader such as:

```lua
local pointer = view.pointer
local offset = view.offset
```

is a later optimization only if trace inspection shows LuaJIT failed to hoist
the reads. It needs a complete `gc-timing` and root-liveness argument for
`fromString`, slices and externally rooted pointers, plus an effect proof that
nothing can replace the physical fields. This plan does not assume either.

`borrowFrom` needs no runtime rewrite: regular generation already erases it to
its pointer operand. The measurable changes are bounds branches, call/dispatch
shape, repeated record reads and pointer expression shape, not a borrowing
wrapper.

## Why this is span-specific first

The reusable theorem is generic:

```text
dominating checked range
  + stable view identity
  + matching induction variable
  + known physical access contract
  = direct in-bounds access
```

The physical contract is not generic. `nupp.span` has one compiler-owned
array-of-structs representation. SoA has columns and a different canonical
proof. A future packed array or byte cursor will have its own offset, width,
alignment, mutability and rooting rules.

V1 therefore reuses declaration-identity and loop-dominance utilities where
they are genuinely common, while leaving span and SoA emission adapters
separate. Extract a shared `IndexedRangeProof` only when both consumers can use
it without conditionals for one representation inside the other. Do not add an
annotation which lets arbitrary user code claim an unchecked physical layout.

Normal Lua tables are not a consumer. They have no Nupp bounds exception to
remove, no public array-part pointer, and retain holes, `nil`, arbitrary keys,
metatables, resizing and GC barriers. Numeric `ipairs`, presizing and future
length hoisting remain their optimizations.

## Observability and gradual boundaries

The pass trusts exactly the same standard declaration contract the checker
already trusts for effects and ownership. A value counterfeited through `any`,
an unchecked `as`, foreign Lua or mutation of private runtime fields has crossed
a documented gradual escape hatch; it does not cause the optimizer to insert a
new runtime type verifier.

Holding `frames` keeps the ordinary call. Granting it permits the compiler to
remove that call from interpreted stack inspection and tracebacks caused by
asynchronous/debug machinery. The pass does not require `error-site`: under the
checked contract the accessor's own bounds error cannot occur, and the one
range failure remains at `span.range` where the source wrote it.

The optimization must not silently turn a standard method into a general
promise that method tables are immutable. Recognition is closed over the
resolved standard module, sealed span types and exact accessor members. If hot
reload or a future supported extension makes those implementations replaceable,
the stable-contract predicate must refuse before this pass ships with that
feature.

## Adoption audit before implementation commitment

Before adding a pass identity, audit the repository's span loops and classify
each one by why it is or is not reachable:

- already contains a same-function `span.range` witness;
- can adopt the witness locally without changing validation, errors or API;
- receives plain bounds from a caller and would need a local range validation;
- hides the loop behind a helper/function boundary which V1 cannot cross;
- is AOT-only and therefore not a regular-backend beneficiary; or
- uses SoA or another representation whose existing lowering already owns it.

Start with every function in `bench/kernel-subset-spike/`, then inspect library
and example code using `Span`, `WriteSpan`, `get`, `getMut` or `set`. Record the
source-ordered inventory and select at least one representative kernel that can
run with AOT disabled. SoA row loops are comparison evidence for the direct
code shape, not span-range beneficiaries.

For each plausible candidate, adopting `span.range` is a separate change to
measure. It performs one variadic validation and constructs a range record; on
a short loop that setup may cost more than repeated checks would have. It may
also differ from a handwritten precondition. Mandelbrot, for example, separately
requires equal input/output counts; replacing that error with a range check
would change its contract. A candidate variant must preserve such checks and
their error sites before its throughput is compared.

Do not treat a newly invented microbenchmark as evidence of natural hit rate.
It proves the mechanism and supplies a ceiling. Implementation proceeds only
after the audit finds either a representative existing loop or a measured,
semantics-preserving adoption in one committed workload.

## Benchmark before implementation commitment

Add `bench/span-range-lowering/` before choosing the final emitted shape. It
builds five implementations from the same operations and verifies every result:

1. the candidate's existing handwritten guard and checked access under
   `-O1 --relax=frames`, with this pass disabled;
2. `span.range` with ordinary checked access under the same settings and this
   pass disabled;
3. `span.range` with the proposed lowering under the same settings and this
   pass enabled;
4. handwritten direct FFI indexing as the regular-backend ceiling; and
5. forced-scalar AOT as context, not as the acceptance target.

Measure at least:

- shared reads, exclusive writes and read/modify/write;
- scalar `uint8`, `float`, `int32` and a multi-field struct;
- root spans and nonzero-offset slices;
- one, two and four participating spans;
- empty, one-element, small and large ranges;
- arithmetic-light streaming and arithmetic-heavy kernels;
- JIT enabled after warmup, plus interpreter-only context;
- x86-64 and arm64 where CI has native machines; and
- `-O0`, `-O1` with the pass disabled and `-O1` with it enabled.

Report time per element and throughput, not a synthetic aggregate speedup. Keep
the pass only if the JIT-enabled direct form produces a stable material win on a
span-bound workload. Compare rows 2 and 3 to isolate the pass from adoption of
`span.range`; compare rows 1 and 2 to price that adoption separately. If
handwritten direct indexing and the proposed output agree in LuaJIT IR and
timing, the regular backend has reached its available ceiling. If both direct
forms also match checked access, LuaJIT already removed the cost and the pass
does not land. If the pass wins after one range proof but adopting that proof
loses overall on every representative candidate, the current proof shape has no
payoff and implementation stops pending broader evidence.

Use `nupp bc --check` to prove the rewrite introduces no recorder blocker. Add a
benchmark-only trace inspection which counts the relevant comparison, call and
external-load/store IR shapes; do not make exact upstream IR numbering a public
test contract.

## Correctness tests

### Proof admission

- one shared span and one writer named by the same range;
- several spans checked by one range;
- fixed and dynamic spans;
- root spans and nested slices;
- empty ranges represented as `first, first - 1`;
- a canonical unit-step numeric loop;
- a read, mutable reference, direct field read/write and statement `set`;
- several accesses aggregated into one remark; and
- local `@relax("frames")` and compilation-wide `--relax=frames`.

### Proof refusal

- a mutable span binding;
- a span omitted from `span.range`;
- a different induction variable or a computed index;
- an explicit, descending or non-unit step;
- only one bound taken from the witness;
- a shadowed range, span or loop name;
- a lookalike `range` function or `get` method;
- access before or after the dominated loop;
- `set` in a value or pack position;
- a held `frames` guarantee; and
- regular accesses when the pass is disabled.

### Runtime agreement

- boundary elements at one and `count`;
- invalid first/last values still failing once at `span.range` with the same
  message and source position;
- slices reading and writing the correct physical offset;
- `fromString` surviving forced collections during a long read loop;
- C arrays surviving forced collections during shared and write loops;
- exclusive writers retaining their borrow barrier and cleanup;
- struct field loads/stores of every admitted physical width;
- value expressions and compound assignments evaluated once;
- nested loops not inheriting the wrong induction proof;
- coverage and source maps retaining authored lines; and
- `-O0` / optimized output returning bit-identical values.

### Tooling and build

- pass catalog, `--remarks`, schema and `-Zno-opt` identity;
- generated Lua contains direct `.pointer[...]` only at admitted sites;
- generated Lua outside the proof still contains the checked method call;
- no direct physical fields appear in formatter, hover or source reflection;
- incremental cache keys include optimization level and relaxations as today;
- packaged modules carry the matching compiler-owned `nupp.span` runtime;
- AOT off/emit/require answers remain unchanged; and
- full suite plus compiler fixpoint.

## Documentation

Update the span guide to distinguish three facts clearly:

- `span.range` always checks the range once;
- under an enabled optimization and the required frames relaxation, matching
  accesses may lower directly; and
- every arbitrary access remains checked.

Add the pass to the optimization guide with its exact source and generated Lua,
remark examples, required `frames` grant and benchmark results. Do not advertise
the forced-scalar AOT ratio as the pass's speedup. The benchmark section reports
checked versus direct regular LuaJIT first, with AOT shown separately.

The language reference continues to describe the proof independently of the
optimization. `noraise` relies on the semantic fact whether or not `-O1` is
enabled; direct generation is one consumer, not the meaning of `span.range`.

## Delivery

1. Audit every repository span loop, record its proof/adoption category and
   identify at least one representative non-AOT candidate.
2. Add a semantics-preserving `span.range` variant of that candidate and measure
   the adoption cost independently from access lowering.
3. Add the isolated benchmark and inspect checked, handwritten-direct and AOT
   traces before editing the optimizer.
4. Record both results in this plan. Stop if there is no credible beneficiary,
   the witness idiom loses overall, stock LuaJIT already erases the relevant
   cost or direct indexing has no material JIT-enabled advantage.
5. Consolidate the existing span accessor facts into one checked descriptor if
   that removes duplicated identity tests without disturbing effects.
6. Add the pass identity, frames-relaxation gate, per-loop remarks and disable
   path.
7. Emit proved shared reads and immediate struct field reads.
8. Emit mutable-reference field accesses and pointer-valued `getMut` results.
9. Emit statement-position `set`, retaining other positions as checked calls.
10. Add rooting, slices, evaluation-order, gradual-boundary, coverage and source-
   map tests.
11. Update span, optimization and reference documentation with measured results.
12. Run focused optimizer, span, ownership, effects, generation and trace tests;
    then the full suite and compiler fixpoint.

The plan is complete when a proved regular-backend span loop performs one
authored range validation and direct FFI element accesses, every unproved access
retains its checked method, the pass is observable and independently disabled,
the rooting and ownership tests survive forced collection, and a committed
JIT-enabled benchmark demonstrates the gain that justified retaining it.

## Non-goals

- changing `span.range`'s source API or indexing convention;
- removing checks from arbitrary indexes or user-defined containers;
- automatically converting Lua tables or records to packed storage;
- adding a public unchecked span, pointer escape or ownership bypass;
- teaching LuaJIT about Nupp types;
- adding DynASM, custom bytecode, vector IR or a VM fork;
- explicit pointer/offset hoisting before trace evidence requires it;
- SIMD, lane lowering or fixed-width arithmetic specialization;
- changing AOT admission, IR or generated C;
- transporting `spanRangeWitness` through parameters, returned range records,
  call summaries or wrappers in V1. Cross-function witness transport is a V2
  opportunity only after same-function adoption demonstrates demand; or
- claiming that span lowering closes the remaining scalar-C or SIMD gap.
