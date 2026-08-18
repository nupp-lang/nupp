# Counted indexed-view and place lowering

Status: implemented — follows `plans/051-structure-of-arrays.md` and
supersedes `plans/060-span-range-access-lowering.md`

## Decision

Make `#view`, `view[index]`, `view[index] = value`, and direct indexed field
projection the ordinary Nupp surface for compiler-owned checked views. Unify the
proof used by spans and SoA behind one checked `IndexedView` descriptor, then keep
separate physical adapters for contiguous AoS storage and columnar SoA storage.

These operators replace the duplicate public element APIs. The completed Span and
SoA view contracts do not export `get`, `getMut`, `set`, or `.count`, and the common
range operation is spelled only `indexed.range`. Private runtime fields and checked
helpers may continue to implement the operators, but they are not callable Nupp APIs.

This is not a generic metamethod optimization. An arbitrary `__len`, `__index`, or
`__newindex` implementation does not establish that its length bounds its indexes,
that an access is pure, or that an indexed field denotes stable storage. Only a
sealed standard type whose implementation is registered with the checker receives
the trusted indexed-view descriptor. Ordinary metamethods retain ordinary dispatch.

`Span`, `WriteSpan`, fixed spans, their slices, `soa.Span`, `soa.WriteSpan`, and
their slices are required consumers. SoA is not optional follow-up work: the change
does not land unless its direct field loops remain within the existing handwritten
FFI ceiling and allocate no row proxies.

The source surface is representation-independent:

```nupp
for index = 1, #rows do
    rows[index].x += rows[index].dx * delta
    rows[index].y += rows[index].dy * delta
end
```

The regular backend selects a physical adapter:

```text
AoS Span<Particle>:
    pointer[offset + index - 1].x

SoA Span<Particle>:
    columns[xOrdinal][offset + index - 1]
```

The checker and optimizer reason about one logical indexed place. They never make
the SoA representation pretend to contain contiguous rows, and they never make a
contiguous span pretend to own columns.

## Required outcome

The work is complete only when all of the following are true:

- `#span` and `#rows` are direct reads of their trusted logical counts and do not
  depend on whether the host LuaJIT was built with table `__len` support.
- `span[index]` and `rows[index]` are bounds-checked at arbitrary indexes.
- a canonical `for index = 1, #view` loop proves accesses to that exact stable view
  in bounds;
- `indexed.range` proves one index against several Span and SoA views;
- proved AoS access lowers to direct typed pointer access;
- proved SoA field access lowers to direct typed column access;
- direct field writes are indexed places, not mutations of temporary row values;
- nonescaping slices and other admitted view adapters can be represented as root,
  base, offset, count, and capability facts without allocating a wrapper table;
- an escaping view materializes the current safe runtime object before the escape;
- every root remains live for as long as a derived pointer or column is used;
- unproved access retains one checked operation with the same error ordering;
- removed `get`, `getMut`, `set`, `.count`, and `span.range` spellings receive a
  direct migration diagnostic rather than remaining alternate APIs; and
- warm traced AoS and SoA kernels match their handwritten direct-FFI shapes and
  timings within the benchmark gates below.

## Current state

Two high-value implementations already exist, but their common theorem is not
represented once.

`OPT-6 span-range-access` consumes `rangeProvenNoRaise` on standard `get`,
`getMut`, and `set` calls. It emits direct pointer access after an exact
same-function `span.range` witness. The committed benchmark improved 8 million
struct updates by 1.46x and matched handwritten direct FFI within measurement
noise. Its public spelling is method-oriented, and its proof reaches only the
specific range-witness idiom.

SoA already accepts the more idiomatic `rows[index].field` spelling. Generation
recognizes `for index = 1, rows.count` itself, keeps a generator-local map from the
induction definition to the view definition, and emits the appropriate column slot
without `checkedIndex`. Its committed trace gate measured generated code at 1.033x
handwritten direct cdata. This is the performance floor the generalized design must
preserve, not code to replace with a runtime protocol.

The checker also already resolves declared `__len`, `__index`, and `__newindex`
contracts. That resolution describes individual operator calls; it does not state
that the three operations share one index domain. The missing fact is the trusted
relationship among a stable receiver, its count, its element place, and its physical
adapter.

The standard library currently has separate `span.CountedSpan` and
`soa.CountedSpan` capabilities. `span.range` accepts only the former, so one checked
witness cannot yet relate an SoA view to another SoA or contiguous view.

Slices currently materialize private record instances holding an anchor, pointer or
columns, offset, and count. Per-element abstraction can disappear in proved loops,
but constructing and chaining a nonescaping view still allocates and initializes
ordinary Lua tables.

## Public source model

### Operators replace duplicate methods

Add the standard operator contracts needed for these source forms:

```nupp
const count = #values
const value = values[index]
values[index] = replacement
values[index].field = replacement
```

Conceptually the standard declarations gain:

```nupp
metamethod __len: function(self): integer
metamethod __index: function(self, index: integer): T
metamethod __newindex: function(exclusive self, index: integer, value: T): nil
```

Shared views expose `__len` and `__index`. Writable views expose all three. A
writable indexed field is accepted only under the same exclusive capability that
currently admits `getMut` or a writable SoA row place.

Remove `get`, `getMut`, `set`, and `.count` from exported Span and SoA view
interfaces after migrating this repository in the same change. Do not keep a
deprecation release in which both surfaces work. A temporary implementation branch
may accept both while tests are being migrated, but the landed compiler rejects the
old spelling with one targeted replacement:

```text
view:get(index)       -> view[index]
view:set(index, x)    -> view[index] = x
view:getMut(index).x  -> view[index].x
view.count            -> #view
```

`ref`, `slice`, `shared`, `splitAt`, `copyFrom`, and SoA `field` projection remain
because they expose different capabilities rather than a second spelling for element
access. `ref` borrows the complete contiguous pointer/count pair for foreign or bulk
work; it is not an alternate checked element getter. Do not add a public `refAt` or
renamed `getMut` unless a separate audited use cannot be expressed by direct indexed
places or the existing whole-range `ref` operation.

Private implementation records may retain a field named `count` and helpers such as
`checkedIndex`, `_read`, or `_write`. Generated Lua may call those helpers for an
unproved access. They are compiler/runtime ABI details absent from exported types,
completion, documentation, and ordinary Nupp lookup.

The compiler-owned view operators are primitives with checked-view semantics, not
replaceable calls to runtime helper bodies. At `-O0` or when proof fails, the regular
backend emits an equivalent once-only check. At `-O1`, a proof may select the direct
physical adapter. The operator's authored location owns any bounds error; a private
helper frame is not part of the public call contract.

### Common counted ranges

Add one compiler-owned standard range constructor under `nupp.indexed`:

```nupp
function indexed.range(
    first: integer,
    last: integer,
    borrows ...: trusted indexed views
): indexed.Range
```

The signature above is semantic pseudocode: there is no exported structural
`Counted` interface whose `.count` field reintroduces a second length API. Checking a
call requires every variadic argument to carry a trusted `IndexedViewDescriptor`.
The generated implementation reads each adapter's private count operation and checks
the inclusive range once.

`indexed.range` replaces `span.range`; it does not coexist as a second spelling in
the completed API. Migrate every repository caller and remove `span.range` from the
exported module. Its established bounds rules and error behavior move to the common
operation, with diagnostics and documentation updated to the new owner.

This makes multi-view SoA kernels expressible without choosing one view's count as an
unproved promise about the others:

```nupp
const range = indexed.range(first, last, particles, forces)
for index = range.first, range.last do
    particles[index].x += forces[index].x
end
```

### Direct field projection is a place

The expression `view[index].field` has two possible uses:

- in a value context it loads that field from the indexed element;
- in an assignment or compound-assignment target it denotes that exact storage
  place.

It must not be specified as `__index` returning an invisible write-back proxy. The
compiler keeps the receiver, index, and semantic field identity together until
physical lowering. A compound assignment evaluates the receiver, index, and value
once in ordinary source order.

Binding a whole indexed value still produces a value:

```nupp
local snapshot = rows[index]
snapshot.x = 0
```

For SoA this gathers an ordinary AoS struct. Mutating `snapshot` does not write back.
For a direct write, the indexed projection must remain syntactically part of the
assignment target:

```nupp
rows[index].x = 0
```

Whole-element assignment stores one contiguous AoS element for a span and scatters
one ordinary value across all SoA columns. SoA performs the bounds check and obtains
the value before the first column store, so a failed check cannot leave half a row
changed.

### Length spelling

`#view` is canonical in Nupp source. It is the logical element count and uses the
same one-based domain as `view[index]`. A fixed span's result retains its literal
count type where the existing type system can express it.

Stock LuaJIT does not honor `__len` on tables unless built with
`LUAJIT_ENABLE_LUA52COMPAT`. Trusted indexed views therefore never emit a host table
length operation: `#view` lowers to the descriptor's count operation, normally
`.count`, and to a scalar count when the view is virtual.

For an unrelated type with an exact statically resolved `__len` implementation, a
separate ordinary lowering may call that implementation directly and may be inlined
under the normal call rules. Dynamic table metamethod discovery is not part of this
optimization and must not be confused with the indexed-view proof. Full dynamic Lua
5.2 table-length behavior still requires a compatible runtime profile.

## Checked semantic representation

Introduce one compiler-owned descriptor attached during checking:

```text
IndexedViewDescriptor {
    contractIdentity
    receiverDefinition
    elementType
    indexBase                 // 1 for the first release
    lengthOperation
    readOperation
    wholeWriteOperation?      // capability-qualified
    projectOperation?         // field identity -> element place
    capability                // shared | exclusive
    representationAdapter     // AoS span | SoA rows | future sealed adapter
    stability                 // stable count/layout/root requirements
}
```

An expression using the descriptor receives semantic operation metadata rather than
being recognized later from text:

```text
IndexedLength {
    view
    descriptor
}

IndexedAccess {
    view
    index
    descriptor
    proof?
}

IndexedPlace {
    access
    fieldIdentity?
    use                         // read | write | compound | whole-value
}
```

These records contain checked declaration and field identities, never strings such
as `"get"`, `"count"`, or `"x"`. The adapter identity is compiler-owned and sealed;
source cannot assert it with an annotation, structural interface match, cast, or
lookalike metamethod table.

The descriptor is generic at the proof boundary. Physical generation dispatches on
the adapter only after checking and optimization have made their semantic decisions.
Adding a future packed vector or byte view should add an adapter and its invariants,
not another loop-bound analysis.

## Range proof

Replace the SoA generator-local counted-loop map and the span-specific consumer view
of `rangeProvenNoRaise` with one checker-produced fact:

```text
IndexedRangeProof {
    witnessIdentity
    inductionDefinition
    lowerBound
    upperBound
    admittedViewDefinitions
    domainIdentity
}
```

The first admitted proof shapes are:

1. `for index = 1, #view` for that exact stable trusted view;
2. `indexed.range` first/last witnesses for every trusted view it names.

The checker attaches a proof to an indexed access only when:

- receiver identity matches an admitted view definition;
- index identity matches the loop induction definition;
- the loop is ascending with the proven unit step;
- count, offset, root, layout, and capability are stable across the loop;
- the operation belongs to the same trusted indexed-view domain; and
- no gradual conversion erased the identity or contract.

`for index = 1, #left` proves access to `left`; it does not prove access to `right`
merely because their counts happen to compare equal at run time. Use `indexed.range`
to relate several Span and SoA views. The plan does not infer range facts from
arbitrary user conditionals in its first version.

The existing same-function boundary remains. Proofs do not cross parameters, return
values, captures, or opaque calls. View virtualization can follow a const local alias
inside that boundary, but it cannot manufacture a bounds witness in another function.

Effects consume the same fact. A proved direct access has no bounds-raising effect;
an unproved access keeps the checked operation's effect. Do not maintain parallel
effect, optimizer, and generator interpretations of the loop.

## Physical adapters

### Contiguous AoS spans

The contiguous adapter carries:

```text
root
typed pointer
logical offset
logical count
shared or exclusive capability
element type
```

It lowers a proved access to:

```lua
pointer[offset + index - 1]
```

A field read or write composes directly:

```lua
pointer[offset + index - 1].field
```

Shared spans permit loads only. Writable spans permit loads, whole-element stores,
and direct field stores while their exclusive token is live. The indexed-place form
does not construct an intermediate pointer or call `borrowFrom`. Code that genuinely
needs a foreign pointer borrows the complete range through `ref`; ordinary mutation
has no pointer-returning element API.

Fixed spans use the same adapter. Their count may be constant-folded, but their root,
offset, ownership, and error rules remain identical.

### SoA row views

The column adapter carries:

```text
root
typed column bases by semantic field ordinal
logical offset
logical count
shared or exclusive capability
element struct and field identities
```

It lowers a proved projected field to:

```lua
columns[fieldOrdinal][offset + index - 1]
```

An arbitrary projected index keeps one `checkedIndex` decision and then uses the
selected column. A whole-row read gathers a normal struct after checking once. A
whole-row write checks once, evaluates the source value once, then scatters. No hot
direct-field path may call whole-row `get` or `set`.

The common optimizer never loops over fields for a direct projection. The SoA
adapter resolves the semantic field identity to its stable ordinal during checking,
as the current implementation already does. Renaming a field therefore continues to
work through declaration identity rather than generated strings.

The current `for index = 1, rows.count` lowering remains the semantic and performance
reference while the common proof is introduced. Remove the generator-local
`soaLoopBounds` path only after the common fact produces equivalent generated code,
source locations, ownership regions, bytecode, trace IR, and benchmark results.

### Projected column spans

`rows:field("x")` already produces a contiguous span rooted in the SoA view. When the
field identity is statically resolved and the returned span does not escape, the
view virtualizer may represent it as the selected column base, composed offset,
count, root, and capability. It must not allocate a temporary span merely to feed a
proved loop.

If it escapes, materialize the existing rooted `span.Span` or `span.Writable` value.
No public strided span is introduced: one SoA column is already contiguous.

## View virtualization and slice sinking

Treat nonescaping standard views as scalar-replaceable aggregates. This is a narrow
checked transformation, not general table escape analysis.

The virtual form contains only semantic values:

```text
VirtualView {
    descriptor
    root
    bases                       // one pointer or selected columns
    offset
    count
    capability
}
```

Admit these standard operations first:

- `Span.slice` and `WriteSpan.slice`;
- SoA shared and writable `slice`;
- writable `.shared()` downgrades;
- resolved SoA `.field(...)` projections; and
- roots produced by `fromCarray`, `writeCarray`, and `fromString` when a separate
  benchmark proves that removing their explicit runtime anchor is worthwhile.

Nested slices compose offsets and counts:

```text
child.offset = parent.offset + first - 1
child.count  = finish - first + 1
```

The slice bounds check remains at the authored slice expression and runs once. Only
the wrapper allocation and repeated record plumbing disappear. The original root is
kept live explicitly across every derived access, even when LuaJIT could otherwise
see only a detached FFI pointer.

V1 performs an all-or-nothing use scan for each candidate definition. Materialize
the current runtime object if the value is:

- returned, yielded, captured, or stored in another aggregate;
- converted to `any` or an untrusted interface;
- passed to an unresolved call or a parameter without a transported view contract;
- compared by identity or exposed to reflection;
- used by an operation the adapter cannot lower;
- carried across a control-flow join whose components disagree; or
- involved in an ownership transition the existing affine checker cannot prove.

Do not add speculative materialization, deoptimization, or partial escape recovery in
the first implementation. Declining virtualization must preserve the existing safe
object and all current behavior.

`splitAt` remains materialized initially. It creates two affine sibling views whose
disjointness and joint lifetime require a two-result virtual ownership design; it is
not necessary to prove the value of ordinary slice sinking.

## Lowering pipeline

Keep responsibilities separated:

1. **Standard declarations** expose only the indexed operator signatures for length
   and element access; duplicate public methods and count fields are removed.
2. **Checking** resolves the exact standard contract, attaches the indexed-view
   descriptor, forms indexed places, and enforces read/write capability.
3. **Control checking** creates `IndexedRangeProof` facts for canonical count loops
   and existing common ranges.
4. **Effects and ownership** consume the same access/place identities for raising,
   memory regions, field disjointness, and exclusive writes.
5. **View virtualization** scalar-replaces eligible nonescaping constructors and
   composes offsets while retaining roots.
6. **Optimization** selects checked or direct access and records one stable remark per
   loop or virtualized view.
7. **Regular generation** asks the AoS or SoA adapter for the physical expression;
   it does not rediscover proofs from CST spelling.
8. **AOT** consumes the same indexed-access and place facts so migrated kernels keep
   their existing admission and generated C without recognizing removed method names.

Prefer one semantic descriptor over adding new loose booleans beside `soaField`,
`soaRow`, `rangeProvenNoRaise`, and `spanDirectAccess`. Transitional fields may exist
on an implementation branch, but the completed compiler must have one authoritative
proof path and adapter boundary.

## Hoisting and LuaJIT interaction

The required result is the best recorded machine-code shape, not a particular amount
of generated Lua text. For each adapter, compare:

- repeated stable object-field access;
- explicit preheader locals for pointer/columns, offset, count, and root; and
- the naturally scalar form produced by a virtualized view.

Choose explicit hoisting only when it improves the committed traced benchmark or the
interpreter materially without worsening the trace. LuaJIT already performs CSE and
loop-invariant motion for many monomorphic table fields, and `OPT-6` reached the
handwritten ceiling without mandatory source-level hoisting.

If bases are hoisted, keep an explicit root local live through the last access and
prove that no visible operation can replace the physical fields during the loop.
Never trade rooting correctness for a smaller trace.

This work emits ordinary Lua and LuaJIT FFI operations. It adds no DynASM, custom
bytecode, injected profiler, or LuaJIT fork.

## Governing invariants

1. **Identity connects the operations.** Length, index, range, field, and receiver
   relationships use checked declaration identities, never spelling.
2. **One domain owns length and indexing.** Only a registered sealed descriptor can
   assert that `#view` is the upper bound of `view[index]`.
3. **Arbitrary metamethods remain arbitrary.** Matching `__len` and `__index` names do
   not grant bounds elimination or physical access.
4. **Arbitrary indexes remain checked.** Computed, neighboring, shadowed, or
   differently scoped indexes do not inherit a loop proof.
5. **Representation stays explicit.** AoS uses element pointers; SoA uses field
   columns. The common layer has no guessed layout.
6. **Indexed writes are places.** A direct field assignment reaches the underlying
   location and never a temporary proxy or gathered row.
7. **Capabilities never widen.** Shared views cannot store; exclusive views retain
   their affine lifetime and region restrictions.
8. **Slices preserve offsets.** Every nested view composes its logical offset exactly
   once.
9. **Roots survive erasure.** Scalar replacement may remove wrappers but never the
   anchor that owns the pointer, string, C array, slab, parent view, or write token.
10. **Evaluation order is unchanged.** Receiver, index, bounds, and stored values are
    evaluated once in authored order.
11. **Failure order is unchanged.** Slice and arbitrary-index failures occur before
    physical loads or the first store; proved accesses have no reachable bounds
    failure.
12. **Whole-row SoA stores are atomic with respect to validation.** All failure-prone
    checks precede the first column mutation.
13. **Source locations remain authored.** Direct loads and stores map to the indexed
    expression or assignment, not a generated preheader.
14. **Optimization is optional.** `-O0`, disabled passes, or a declined escape proof
    retain checked semantics and safe materialized objects.
15. **SoA cannot regress.** The common proof and place model must meet the existing
    direct-column trace and throughput gate before its private path is removed.

## Remarks and inspection

Assign stable optimization identities only when implementation and benchmarks land.
The common indexed-range pass supersedes `OPT-6 span-range-access`; do not keep both
passes recognizing two source surfaces. Preserve the historical benchmark result in
documentation, migrate the disable/remark tests, and retire the old catalog identity
under the repository's normal optimization-compatibility policy.

Report decisions at useful granularity, for example:

```text
indexed-range: lowers 4 accesses to 2 AoS places after one count proof
indexed-range: lowers 6 accesses to 4 SoA column places after one count proof
view-scalar-replacement: virtualizes 2 nested slices
```

Requested declines use stable reasons such as:

- `unstable-view`;
- `unrelated-length`;
- `computed-index`;
- `untrusted-contract`;
- `view-escapes`;
- `unsupported-view-operation`;
- `ownership-join`;
- `backend-not-regular-lua`.

Proof absence is primarily a checker fact, not an optimizer guess. Remarks should
identify why an otherwise relevant standard view missed the fast lane without
reconstructing a second type or range analysis.

`nupp bc --check` must report no new recorder blocker. A benchmark-only trace report
categorizes comparisons, calls, allocations, table/hash loads, FFI loads/stores, and
side exits without making unstable upstream IR numbers part of the language contract.

## Performance gates

Extend the existing span and SoA benchmarks rather than replacing their historical
baselines. Add one shared harness with verified results for:

1. checked operator access at an arbitrary index;
2. canonical `for index = 1, #view` operator access;
3. the new common proof and adapter;
4. the new common proof over a nonescaping slice;
5. the same slice forced to escape and materialize; and
6. handwritten direct FFI.

Keep the committed old method/count measurements as historical comparison data, not
as a still-compiling public benchmark variant. A private generated-Lua fixture may
preserve a checked-helper baseline when needed to isolate code shape.

Measure at least:

- AoS scalar reads, stores, and multi-field struct updates;
- SoA two-field and four-field read/modify/write kernels;
- whole-row SoA gather and scatter separately from projected hot access;
- root views, nonzero-offset slices, and nested slices;
- shared and exclusive capabilities;
- empty, one-element, short, and large loops;
- several Span views related by `indexed.range`;
- an `indexed.range` loop relating AoS and SoA views;
- JIT after warmup, with interpreter-only results reported as context; and
- native arm64 and x86-64 profiles where CI provides them.

Landing gates:

- proved AoS is within 10% of handwritten direct FFI and does not regress the
  committed `OPT-6` median beyond benchmark noise;
- proved projected SoA is within 10% of handwritten columns and does not regress the
  committed SoA baseline beyond benchmark noise;
- no proved direct-field trace constructs a span, slice, row, pointer-borrow, or
  closure;
- a nonescaping sliced-view kernel performs no wrapper allocation after warmup;
- arbitrary access still executes one bounds decision and agrees on failures; and
- `#view` introduces no table `__len` dependency or call in a proved hot loop.

If the abstraction descriptor causes worse IR or throughput than the existing SoA
path, retain the old path and stop: generic architecture is not sufficient reason to
slow the primary workload. If virtualization does not remove construction or improve
a slice-heavy representative workload, do not land speculative escape machinery;
keep only the checked operator and common-proof portions that pass independently.

## Correctness tests

### Operator contracts

- `#`, read indexing, whole-element assignment, and direct field assignment on every
  dynamic and fixed span variant;
- the same operations on shared and writable SoA row views;
- writable indexed reads and compound field assignments;
- fixed-span length retaining its literal count where expected;
- `ref`, slicing, sharing, splitting, copying, and field-column projection remaining
  valid as distinct capabilities;
- `get`, `getMut`, `set`, `.count`, and `span.range` rejected with precise operator
  or `indexed.range` replacements;
- shared-view writes rejected with the existing ownership explanation;
- wrong key and value types rejected through the operator contract;
- a user type with lookalike metamethods receiving no trusted descriptor; and
- exported interface and completion snapshots containing none of `get`, `getMut`,
  `set`, or `count` for standard indexed views.

### Range admission and refusal

- `for index = 1, #view` bounds;
- one-view, multi-Span, multi-SoA, and mixed-view `indexed.range` bounds;
- untrusted counted or lookalike values rejected by `indexed.range`;
- exact receiver and induction identity through const aliases;
- refusal for a different view, mutable binding, computed index, explicit non-unit
  step, reversed bound, shadowed name, or access outside the loop;
- no proof transport through parameters, returned views, captures, or opaque calls;
- nested loops selecting the correct induction definition; and
- no relationship inferred merely from equal dynamic counts.

### AoS generation

- direct scalar and struct loads;
- whole-element and field stores;
- no temporary borrowed pointer for an indexed field place;
- correct nonzero and nested slice offsets;
- fixed and dynamic counts;
- `fromString` roots surviving forced collection; and
- C-array roots and writable tokens surviving forced collection.

### SoA generation

- each field identity selecting the correct typed column ordinal;
- direct reads, writes, and compound assignments using no row proxy;
- complex receiver and index expressions evaluated once;
- whole-row gather returning an independent AoS value;
- whole-row scatter checking before its first store;
- shared and writable slices composing column offsets;
- projected field spans rooting the parent slab; and
- field-level ownership regions remaining disjoint where already proved.

### View virtualization

- nested slice, shared downgrade, and projected-column candidates;
- root constructors remaining materialized and explicitly anchored;
- zero-length and one-past-empty slice representations;
- materialization on return, capture, aggregate store, `any`, unknown call,
  reflection, identity observation, and unsupported ownership join;
- materialized and virtual executions returning bit-identical values;
- destructors and affine drops occurring exactly once;
- source coverage and error locations remaining authored; and
- no virtual descriptor exposed to Lua, FFI, reflection, LSP, or generated APIs.

### Tooling and build

- optimization catalog, disable flags, remarks, and JSON schemas;
- formatter, hover, completion, definition, and references for operator uses;
- semantic field rename through indexed SoA places;
- incremental keys covering optimization level, adapter version, and relaxations;
- `nupp bc --check` on every benchmark loop;
- AOT off/emit/require accepting the operator spelling and rejecting the removed
  method spelling while preserving the existing verified IR and generated C;
- full test suite; and
- compiler fixpoint.

## Documentation

Update the span and SoA guides around the shared source idiom:

```nupp
for index = 1, #view do
    use(view[index])
end
```

Explain separately:

- operators are the sole public length and element-access surface;
- canonical loops can remove repeated checks for the exact view;
- `indexed.range` validates one range across several Span and SoA views;
- arbitrary indexes are checked;
- nonescaping slices may allocate no wrapper without changing lifetime semantics;
- indexed field projection is a place only in direct read/write syntax; and
- SoA uses columns even though source looks like row indexing.

The optimization guide must report AoS and SoA results side by side. Do not advertise
only the easier scalar span benchmark, and do not describe AOT or SIMD results as a
regular-backend speedup.

Document host behavior precisely: Nupp's trusted `#view` does not require LuaJIT's
`LUAJIT_ENABLE_LUA52COMPAT`, while arbitrary dynamic table `__len` behavior remains
dependent on the selected runtime profile.

Add a migration table for removed spellings, but do not document them as deprecated
working alternatives. Generated/private runtime fields are not a user-facing Lua ABI
and do not appear in the language reference.

## Delivery

1. Add benchmark cases for operator syntax, AoS, SoA, slices, forced escape, and
   handwritten ceilings before changing the common lowering.
2. Introduce checked `IndexedViewDescriptor`, `IndexedAccess`, and `IndexedPlace`
   records without changing generated code.
3. Attach them to existing SoA row operations and prove that checked types, regions,
   field identities, and generated output remain unchanged.
4. Attach them to all standard span variants and add `#`, read index, whole write,
   and direct field-place typing behind a temporary implementation-only migration
   bridge.
5. Add `indexed.range`, migrate every `span.range` caller, and accept only trusted
   indexed-view participants.
6. Lower trusted `#view` directly to count, independent of host table `__len`.
7. Move canonical `#view` loop recognition into checking and emit one
   `IndexedRangeProof` consumed by effects and optimization.
8. Route the existing SoA direct-column path through the common proof and its SoA
   adapter. Run trace and throughput gates before deleting `soaLoopBounds`.
9. Route span operator access and common range access through the contiguous adapter
   without regressing `OPT-6`.
10. Implement whole-element and projected indexed-place writes with once-only
   evaluation and capability checks.
11. Update the AOT checker, rewrite, IR lowering, fixtures, and kernel corpus to
    consume indexed access/place facts instead of `get`, `getMut`, `set`, and
    `.count` spellings.
12. Migrate all remaining source, tests, benchmarks, explanations, and documentation;
    then remove the public methods, public count field, `span.range`, their
    name-specific compiler recognition, and superseded `OPT-6` compatibility path.
13. Add narrow all-or-nothing virtualization for slices, shared downgrades, and
    projected columns; materialize on every uncertain escape. Keep root constructors
    materialized until a separate root-construction benchmark justifies replacing
    their explicit runtime anchors.
14. Measure explicit base/offset/count hoisting against LuaJIT's trace CSE and retain
    only the winning shape while keeping roots live.
15. Add decline remarks, trace inspection, source-map, forced-GC, ownership, and
    gradual-boundary tests.
16. Update span, SoA, metamethod, optimization, and language-reference documentation
    with the measured results and runtime-profile distinction.
17. Run focused checker, effects, ownership, optimizer, generation, span, SoA, AOT,
    trace, and benchmark suites; then the full suite and compiler fixpoint.

Each delivery step must leave the current checked fallback working. The SoA adapter
transition is independently revertible from operator surface work, and view
virtualization lands only after the nonescaping allocation and performance evidence
passes.

## Non-goals

- inferring a bounds relationship for arbitrary user metamethods;
- exposing an unchecked index, raw pointer, column table, or compiler descriptor;
- making normal Lua tables contiguous, bounds checked, or eligible for physical
  lowering;
- changing struct ABI or silently choosing AoS versus SoA;
- adding invisible row proxies or escaping mutable row references;
- general table scalar replacement or whole-program escape analysis;
- virtualizing `splitAt` before two-child affine ownership has its own design;
- transporting range proofs or virtual views across function boundaries;
- relying on LuaJIT's optional table `__len` compatibility mode;
- adding DynASM, custom bytecode, a LuaJIT fork, SIMD, or new AOT admission; or
- claiming that scalar direct access closes arithmetic, vectorization, cache-layout,
  or memory-bandwidth gaps outside these views.

The plan is complete when one checked semantic relationship connects length,
indexing, range proof, field projection, and capability; spans and SoA retain distinct
optimal physical adapters; nonescaping slices can disappear while roots remain live;
both AoS and SoA pass their handwritten direct-FFI trace and throughput gates; and
the exported indexed-view API has exactly one spelling for length, read, write, and
common range formation.
