# Root indexed-view scalar replacement

Status: proposed — follows `plans/061-counted-indexed-view-lowering.md`

## Decision

Represent nonescaping standard Span and SoA roots as compiler-owned scalar values
instead of allocating their private wrapper records. Preserve the existing safe
runtime object as the materialization form for escapes and dynamic boundaries.

The target model is a runtime fat pointer, not a compile-time-only fiction:

```text
contiguous view = anchor + typed base + offset + count + capability
SoA row view    = slab anchor + columns/layout + offset + count + capability
```

Element type, physical adapter, read/write capability, borrow lifetime, and a fixed
count where one exists are static facts. The base, count, offset, columns, and owner
anchor may be dynamic runtime values. They should normally occupy locals or flattened
arguments, not a newly allocated Lua table.

This plan extends the scalar replacement implemented by Plan 061. That pass already
virtualizes admitted `slice`, `shared`, and resolved SoA `field` results while keeping
root views materialized. Do not reopen its public API or range-proof decisions:
`#view`, `view[index]`, direct indexed fields, and `indexed.range` remain the only
ordinary element-access surface.

Land the work in three independently measured stages:

1. scalar-replace same-function roots produced by the sealed standard library;
2. flatten view parameters and returns across statically resolved Nupp calls while
   retaining materializing bridges at exported or dynamic boundaries; and
3. prove a Tecs-shaped mutable-column acquisition keeps its dirty-marking effect
   while the returned view allocation disappears.

Each stage may land only after its own correctness and performance gates pass. A
failed later stage does not justify reverting a safe earlier zero-allocation path.

## Required outcome

The plan is complete only when all of the following are true:

- a nonescaping root returned by standard Span, heap-array, or SoA acquisition
  allocates no wrapper at `-O1`;
- the same source at `-O0`, with the pass disabled, or after an uncertain escape
  retains the existing checked materialized representation;
- dynamic base, offset, count, and column values are evaluated once in source order;
- constructor validation, borrow acquisition, dirty marking, counters, and every
  other observable producer effect still executes exactly once;
- writable capability remains exclusive for the same lexical region even when no
  runtime token table exists;
- the storage owner remains strongly reachable until the final pointer or column
  access on every normal, error, and cleanup path;
- nested slices, shared downgrades, and resolved SoA projections compose directly
  from a virtual root without introducing an intermediate wrapper;
- arbitrary indexes retain the same bounds checks and failure locations;
- a statically resolved function may receive and return a virtual view through a
  flattened internal calling convention;
- an exported, dynamic, reflective, captured, heterogeneous, or otherwise escaping
  view materializes before that boundary;
- a Tecs-style `getMut` acquisition marks the exact component and archetype dirty
  before direct optimized stores execute;
- read-only acquisition never marks dirty, and a sparse/proxy column never receives
  the contiguous fast lane;
- the optimized acquisition benchmark contains no view `NEWREF`, `TDUP`, constructor
  call, or recorder abort in the hot trace; and
- repeated root acquisition is measurably better than the materialized baseline or
  the corresponding stage does not land.

There is no requirement that an owner, backing allocation, archetype, or SoA slab
itself become allocation-free. The eliminated object is the temporary view
descriptor, not the storage it views.

## Current state

Plan 061 established one checked `IndexedViewDescriptor` for the sealed standard
Span and SoA families. It lowers proved element operations to direct AoS pointer or
SoA column accesses and scalar-replaces these nonescaping derived operations:

- `Span.slice` and `WriteSpan.slice`;
- shared and writable SoA slices;
- writable `.shared()` downgrades; and
- statically resolved SoA `.field()` projections.

Its first implementation deliberately requires a const local, scans the complete
same-function use set, and declines on any unsupported use. Root constructors remain
materialized and explicitly anchor their storage. This is the correct safe fallback
for the new work, not legacy code to delete first.

The committed loop benchmark demonstrates that direct indexed access reaches the
handwritten FFI trace shape. Its slice benchmark demonstrates that eliminating a
derived wrapper can remove nearly all construction cost. Neither benchmark measures
repeated root acquisition: the root is normally created outside the timed loop. A
new benchmark must establish the value of root scalar replacement rather than
extrapolating from slice sinking.

The private root records currently carry runtime representation and rooting fields.
Their existence does not make their object identity public. The exported sealed
interfaces expose length, indexing, slicing, sharing, pointer-range borrowing, and
ownership operations, but no supported operation requires a particular Lua table
identity. An identity-observing conversion or escape still forces materialization.

Tecs currently returns raw Teal columns, not Nupp standard views, so this compiler
change cannot optimize the existing Teal API by nominal coincidence. Its dirty model
is nevertheless the required external shape: `archetype:getMut(Component)` marks the
component dirty before returning its column, while per-row assignments do not perform
the dirty operation. A Nupp-facing adapter must preserve that acquisition effect and
may then expose dense storage as a standard writable view.

## Semantic representation

Extend the existing internal view descriptor with a checked lowered value. Use an
explicit compiler IR record rather than growing generator-only tests for constructor
spellings:

```text
LoweredIndexedView {
    descriptor                 // element, adapter, operations, capability
    anchor                     // strong owner/root reference
    base                       // contiguous typed storage, when AoS
    columns                    // SoA physical storage/layout, when row-oriented
    offset                     // zero-based physical displacement
    count                      // logical one-based length
    cleanupRegion              // affine lifetime, if writable
    producerEffects            // authored acquisition already executed
    materializationRecipe      // existing private runtime representation
}
```

The record is compiler data only. It is never emitted as a public Lua object, exposed
through reflection, accepted by FFI, or added to the Nupp type system as a source
construct.

The checker continues to type the value as its ordinary sealed Span or SoA
interface. Ownership, effects, and range analysis consume the same semantic type and
definition identities whether generation chooses the lowered or materialized form.
Optimization is therefore representation selection after checking, not a second
typing mode.

## Stage R1: same-function standard roots

### Admitted producers

Begin with exact resolved identities owned by the standard library:

- `span.fromCarray` and `span.writeCarray`;
- fixed-count C-array constructors;
- `span.fromString` and other existing rooted byte-span constructors;
- `heap.Array.read` and `heap.Array.write`;
- `soa.Array.read` and `soa.Array.write`; and
- any private standard constructor reached solely as the implementation of those
  exports.

Do not recognize names, return types alone, structural interfaces, or arbitrary
functions that happen to return `Span<T>`. The initial producer set is sealed and
compiler-versioned beside the existing indexed-view adapter descriptions.

### Admission

Reuse Plan 061's conservative all-or-nothing scan. R1 admits a root when:

- it initializes one const or affine lexical binding;
- its producer identity and physical adapter are exact;
- every use is length, indexing, a currently virtualizable derived operation,
  explicit drop, or another operation the adapter can lower;
- no use returns, captures, stores, reflects, compares, converts to `any`, or passes
  the view to an opaque call;
- control flow gives every use one dominating producer and one ownership region; and
- the producer's runtime cleanup is either compiler-known trivial or separately
  emitted without requiring wrapper identity.

A decline leaves the complete existing constructor and cleanup path untouched. R1
does not partially virtualize a candidate and does not allocate speculatively after
entering a branch.

### Generation

Evaluate the producer receiver and arguments exactly once. Emit validation and
acquisition effects at the authored source position, then bind the representation
components as locals. Conceptually:

```lua
local anchor = owner
local base = owner.pointer
local offset = 0
local count = owner.count
```

The exact fields differ by producer and are private ABI. Generation must ask the
registered physical adapter for them; it must not infer fields from a record's text.

Existing virtual slices and projections consume these components recursively. A
root followed by a slice followed by `shared()` followed by a field projection must
still contain no wrapper allocation.

### Writable roots and cleanup

The affine checker remains authoritative for exclusive access and lexical end.
Removing the writable token table does not remove its static lifetime. At region
exit:

- emit every observable cleanup action once;
- emit no runtime call for a destructor proven to be representation-only and empty;
- end the compiler-owned exclusive capability exactly where materialized `drop`
  ended it; and
- materialize before a cleanup path that needs runtime object identity.

Do not generalize this into arbitrary destructor elision. Only the sealed indexed
view recipe may separate a representation-only wrapper from real cleanup effects.

## Owner liveness

The anchor is a semantic component, not optional optimization metadata. A detached
FFI pointer or selected SoA column must never outlive the object that owns its bytes.

R1 must choose and document a regular-backend keepalive mechanism that survives both
Lua bytecode generation and LuaJIT optimization. Merely assigning an anchor local
before the loop is insufficient evidence: the VM or recorder may consider it dead
after its last observable use.

The implementation spike must compare at least:

- keeping accesses rooted through the owner expression;
- an explicit compiler-generated last use at cleanup-region exit; and
- a narrow runtime keepalive barrier outside the hot loop.

Choose the least expensive mechanism that passes forced collection and finalizer
tests in interpreted and JIT modes. A once-per-region barrier outside a hot loop is
acceptable. A per-element keepalive call, recorder abort, or reliance on undocumented
accidental cdata rooting is not.

Test normal fallthrough, early return, raised error, nested `with`, and derived views
whose lexical last access differs from the root binding's textual last use.

## SoA roots

A virtual SoA root retains its slab anchor, logical offset/count, and the physical
column/layout source. It does not flatten every column into a Lua local eagerly.

For a statically resolved projected field, select the column ordinal directly. For a
whole-row read, gather the declared fields after one bounds decision. For a whole-row
write, evaluate and validate before scattering, as Plan 061 requires. Hoist column
bases only when trace and timing evidence improves over stable owner-field access.

The SoA array owner still owns the slab and layout. Scalar replacement removes only
the temporary shared or writable row-view record. Field spans derived from that row
view reuse the slab anchor and selected column; they do not materialize the row view
to obtain a parent anchor.

R1 does not introduce a general strided view, dynamic field projection, or row proxy.

## Stage R2: flattened static calling convention

Same-function sinking cannot remove a wrapper constructed in a statically resolved
helper and returned to its caller. R2 adds an internal aggregate calling convention
for checked Nupp functions whose Span/SoA parameters or results remain within a
static call graph.

Conceptually a view parameter is flattened:

```text
process(view)

process$view(anchor, base-or-columns, offset, count, capability)
```

and a view result returns the same components as multiple internal results. This is
an implementation ABI only. Source signatures, reflection, diagnostics, hover, AOT
signatures, and exported module types continue to show the ordinary view type.

Generate a materializing bridge when a function is:

- exported or otherwise callable dynamically;
- stored as a function value or selected through an overload dynamically;
- called through `any`, an untrusted interface, or foreign Lua;
- recursive in a way the internal ABI analysis cannot close;
- separately compiled without a compatible lowered-signature summary; or
- required by tooling to retain its ordinary Lua-callable ABI.

Static callers use the flattened entry only when every participating module was
checked against the same adapter ABI version. Include that version and optimization
mode in incremental and build cache keys. A caller compiled without R2 must always be
able to use the materializing bridge.

Producer effects remain in the producer body. Flattening changes how its result is
returned, not whether the body runs. Errors, coverage, profiling frames retained by
the selected relaxation policy, and source locations must remain authored.

R2 should reuse the compiler's function summaries and call identities. Do not build
a general Lua function specializer or whole-program escape analyzer to transport one
sealed aggregate.

## Stage R3: Tecs dirty acquisition

R3 is an acceptance workload for effectful library producers, not permission to
hard-code Tecs module names in the Nupp compiler.

A Nupp-facing dense-column adapter should have semantics equivalent to:

```nupp
function Archetype.getMut<T>(
    exclusive self,
    component: Component<T>
): span.WriteSpan<T> borrows (self)
    self:markComponentDirty(component)
    return span.writeCarray(self:column(component), self.length)
end
```

The actual storage API may differ. The required ordering does not:

1. resolve the component and dense column;
2. mark that component on that archetype dirty exactly once per authored acquisition;
3. obtain the column base and current live row count;
4. return flattened view components to a static caller; and
5. perform direct stores only after those steps succeed.

Use R2's checked function-body summary and flattened result. Do not add an unsafe
annotation through which arbitrary code can merely assert a pointer/count/anchor
relationship. If a future foreign library cannot be expressed as checked Nupp, its
trusted producer annotation needs a separate plan and safety contract.

The acceptance fixture must cover:

- `get` producing a shared view without dirtying anything;
- `getMut` dirtying exactly one requested dense component;
- two component columns related with `indexed.range`;
- direct struct-field writes through a contiguous AoS component column;
- a resolved SoA projection if Tecs adopts columnar fields;
- acquisition inside a conditional that performs no call on the untaken branch;
- a materialized escape retaining the same dirty behavior;
- sparse relationship proxies declining the contiguous adapter;
- table-backed components retaining ordinary checked table behavior; and
- structural barriers invalidating view use according to the borrow/lifetime API,
  not according to an optimizer guess.

Current Tecs loops commonly use a separate `length` returned by query iteration.
That integer does not prove a returned view's bound. The Nupp-facing API must either
use `for row = 1, #column` or establish the relationship once with
`indexed.range(1, length, column, ...)`. Do not infer equality between an archetype
length and a column count from naming or adjacent return positions.

R3 is complete only when generated optimized Lua still contains the dirty acquisition
and no view-wrapper allocation between acquisition and the hot loop.

## Materialization

Every lowered view retains a recipe for constructing the exact existing private
runtime implementation. Materialize before the first unsupported use, and only when
the complete dominance/use analysis proves doing so preserves evaluation order.

R1 may use the simpler all-or-nothing policy: if any use escapes, materialize at the
original producer. R2 may materialize at a bridge boundary. Do not introduce
speculative on-demand materialization inside arbitrary control flow until a separate
measurement justifies its complexity.

Materialization must preserve:

- the original anchor, base/columns, offset, count, and capability;
- fixed-count nominal information where the runtime representation carries it;
- exactly-once cleanup ownership;
- the same bounds and constructor errors;
- object identity from the first point identity can be observed; and
- compatibility with existing generated/private helper methods.

No public `materialize`, `unsafeView`, raw descriptor, or unchecked constructor is
added.

## Effects, ownership, and error order

The optimizer may erase representation work but not authored effects. Classify each
producer step as one of:

```text
validation
borrow/capability acquisition
library-visible effect
representation construction
cleanup effect
```

Only representation construction is unconditionally removable. A validation may be
removed only by an existing proof that already removes its raising effect. A
library-visible effect such as dirty marking or a value-count increment always runs.
A cleanup effect runs at the same lexical exit or error edge as before.

Evaluation order remains receiver, arguments, validation/acquisition, then uses.
Direct stores cannot move before a dirty mark, capacity check, component lookup, or
range check. Whole-row SoA writes still complete all failure-prone work before their
first column store.

The ownership checker continues to reject a second writer, owner mutation while a
view is borrowed, use after drop, and a view surviving its owner. R1 and R2 consume
those facts; they do not reconstruct lifetime from generated locals.

## Optimization and inspection

Extend the existing indexed-view scalar-replacement identity rather than adding one
pass per producer. Remarks should distinguish decisions:

```text
view-scalar-replacement: virtualizes standard write root (anchor=region-last-use)
view-scalar-replacement: transports view through static call
view-scalar-replacement: materializes at exported bridge
view-scalar-replacement: declines root (view-escapes)
view-scalar-replacement: declines producer (observable-cleanup)
```

Every accepted virtual root remark must name the selected anchor strategy. Use one
stable value from a small inspected vocabulary, such as `rooted-access`,
`region-last-use`, or `runtime-barrier`; settle the final names with the liveness
spike rather than exposing a private helper name. This is correctness-load-bearing
inspection, not optional verbose diagnostics: two generated forms that keep the
same view virtual but anchor it differently must produce different remarks. The
remark belongs to the root decision, so derived slices and projections do not repeat
it unless they introduce a different anchor.

Add stable decline reasons for at least:

- `untrusted-producer`;
- `view-escapes`;
- `dynamic-call-boundary`;
- `incompatible-view-abi`;
- `identity-observed`;
- `ownership-join`;
- `unsupported-cleanup`;
- `unstable-anchor`; and
- `proxy-or-noncontiguous-storage`.

Inspection should show logical view components and the selected adapter without
printing private field names as language guarantees. Generated Lua tests may assert
private shapes narrowly, but documentation and diagnostics must remain
representation-independent.

This work emits ordinary Lua and LuaJIT FFI operations. It requires no DynASM,
custom bytecode, LuaJIT patch, or fork.

## Performance gates

Extend `bench/span-range-lowering` with acquisition-focused cases. Construct and use
the view inside the repeated workload so the benchmark measures allocation rather
than one setup operation outside the timer.

Measure at least:

1. materialized and virtual `span.fromCarray` shared roots;
2. materialized and virtual writable C-array roots;
3. `heap.Array.read` and `write` roots;
4. SoA shared and writable row roots;
5. root plus nested slice/shared/projection chains;
6. one direct static helper parameter and one returned view;
7. a forced dynamic/escaping bridge;
8. an effectful Tecs-style `getMut` producer; and
9. handwritten scalar locals as the regular-backend ceiling.

Report separately:

- elapsed time and acquisitions per second;
- bytes or objects allocated where a stable counter is available;
- collector CPU time and collection count over fixed work where the runtime exposes
  stable measurements;
- hot-trace `NEWREF`, `TDUP`, calls, comparisons, hash loads, FFI loads/stores, and
  side exits;
- interpreter-only behavior as context;
- compilation/code-size change for R2 bridges; and
- arm64 and x86-64 results where CI provides them.

Landing gates:

- R1's hot acquisition traces contain no view allocation or constructor call;
- R1 improves a repeated standard-root workload by at least 10%, unless allocation
  and collector evidence on a representative repeated-acquisition workload shows
  all of the following instead: at least 90% fewer view-attributable allocated bytes
  or objects, at least 20% less collector CPU time or 20% fewer collections over
  fixed work, and no median elapsed-time regression greater than 2%; if stable
  allocation and collector measurements are unavailable, this exception is
  unavailable;
- an ordinary loop over one long-lived root does not regress beyond benchmark noise;
- SoA projected access remains within Plan 061's handwritten-column gate;
- R2 removes both callee construction and caller materialization on the static path;
- a bridge is paid only at an actual dynamic/export boundary;
- R3 performs the same dirty operations and direct stores as its handwritten scalar
  oracle; and
- no admitted benchmark introduces a LuaJIT recorder blocker.

If LuaJIT already scalar-replaces a root reliably and R1 shows neither timing nor GC
benefit, do not land redundant compiler complexity. If R2 bridge proliferation or
code size outweighs its measured allocations, retain R1 and stop. If the Tecs
producer cannot preserve dirty semantics without unsafe metadata, retain standard
view optimization and reject that adapter design.

## Correctness tests

### Standard roots

- every admitted shared, writable, fixed, string, heap, and SoA producer;
- dynamic and fixed counts, zero length, and nonzero physical offsets;
- arbitrary checked access and proved direct access;
- nested slice/shared/field composition from a virtual root;
- whole-element and direct-field reads/writes;
- normal drop, explicit drop, automatic cleanup, early return, and raised error;
- one evaluation of complex producer receivers and arguments;
- interpreted, JIT, pass-disabled, and `-O0` equivalence; and
- materialized and virtual executions producing bit-identical storage.

### Liveness

- string and C-array roots surviving forced collection;
- heap and SoA owners with finalizer sentinels surviving through final access;
- anchors retained through nested calls, errors, and cleanup regions;
- every accepted virtual root remark naming the keepalive strategy actually emitted;
- no detached pointer surviving after its legal borrow ends; and
- materialized escape retaining its parent root exactly as before.

### Escape refusal

- return, capture, aggregate store, dynamic call, `any`, reflection, identity
  comparison, heterogeneous union, unsupported ownership join, and recursion;
- ordinary object construction on every decline;
- no partial cleanup or double drop after decline; and
- stable optimization remarks for each reason.

### Static ABI

- flattened shared and writable parameters;
- flattened single and multiple view results;
- nested static helpers and separately checked modules;
- materializing exported/dynamic bridges;
- a directly recursive function and a mutually recursive static call group declining
  flattened transport, materializing at the ordinary call boundary, and preserving
  exactly-once cleanup;
- ABI-version mismatch falling back safely;
- function values and overloads retaining ordinary callable behavior;
- incremental invalidation when a lowered signature or adapter changes; and
- source-level reflection and LSP signatures remaining unchanged.

### Tecs-shaped effects

- dirty mark before the first direct store;
- exact component/archetype selection;
- read acquisition staying clean;
- repeated authored `getMut` calls retaining their existing counter semantics;
- no mark on an untaken acquisition path;
- dense FFI storage admitted, sparse proxy and table storage declined;
- `#column` and explicit `indexed.range` bounds forms; and
- structural lifetime violations rejected independently of optimization.

### Tooling and build

- optimization catalog, remarks, disable flag, and JSON schemas;
- `nupp bc --check` for every benchmark loop;
- coverage and authored source locations for producer effects and failures;
- AOT remaining independent of regular-backend virtual representation;
- full test suite; and
- compiler fixpoint.

## Delivery order

1. Add acquisition benchmarks and trace/allocation categorization before changing
   root generation.
2. Define `LoweredIndexedView` and standard producer recipes beside the existing
   indexed-view descriptors.
3. Admit one same-function shared `span.fromCarray` root and prove checked behavior,
   escape fallback, and anchor liveness.
4. Add writable and fixed contiguous roots with exact affine cleanup.
5. Add heap-array `read`/`write` producers.
6. Add SoA shared/writable roots and compose existing slice/shared/field
   virtualization from them.
7. Run R1 gates on arm64 and available x86-64 CI; land R1 only if it pays.
8. Define the versioned flattened internal view ABI and materializing bridge.
9. Transport parameters, then returns, through simple nonrecursive static calls.
10. Extend to separately checked modules through function summaries and cache keys.
11. Run R2 allocation, code-size, incremental, and dynamic-boundary gates; retain R1
    alone if R2 does not pay.
12. Add a checked Nupp Tecs-shaped dense-column fixture whose `getMut` marks dirty
    before returning a standard writable view.
13. Verify R2 removes that returned wrapper while preserving dirty and counter
    effects, and verify sparse/table refusal.
14. Update Span, SoA, optimization, ownership, and Tecs integration documentation
    with measured results and materialization boundaries.
15. Run the full suite, benchmarks, trace checks, and compiler fixpoint before each
    independently landing stage.

## Non-goals

- eliminating backing arrays, heap owners, archetypes, SoA slabs, or necessary
  cleanup allocations;
- promising that a dynamic first-class view has no runtime representation;
- general table scalar replacement or arbitrary Lua escape analysis;
- trusting user `__index`, `__newindex`, or `__len` metamethods as physical storage;
- inferring a producer from its return type or from fields named pointer/count;
- an unsafe public annotation that asserts anchor or dirty-effect correctness;
- optimizing sparse relationship proxies as contiguous arrays;
- inferring that a query length equals a column count without `#view` or
  `indexed.range`;
- changing the public Span/SoA source API established by Plan 061;
- changing AOT's verified native calling convention as part of the regular backend;
- speculative deoptimization or partial materialization inside arbitrary control
  flow; or
- a LuaJIT fork, DynASM path, or custom VM opcode.

## Completion boundary

R1 is useful and independently landable when standard same-function roots become
zero-allocation with proven anchoring and no long-lived-loop regression. R2 is
complete when statically resolved Nupp calls transport those components without an
intermediate object and retain ordinary bridges elsewhere. R3 is complete when an
effectful Tecs-shaped producer keeps exact dirty semantics and emits no wrapper on
the static dense-column path.

Do not describe all spans as allocation-free merely because R1 lands. The accurate
claim at each stage is:

```text
R1: nonescaping standard roots and derived views are scalar-replaced in one function
R2: the same representation crosses statically resolved Nupp calls
R3: effectful dense-column acquisition, including Tecs-style dirty marking, uses it
```

Escaping and dynamic views continue to materialize by design.
