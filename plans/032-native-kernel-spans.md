# Native kernels over checked spans

Status: implemented. The Current blockers below are resolved — public code can
no longer reach a span's raw pointer or offset, and `span.Span<T>` and
`span.WriteSpan<T>` are nameable in cross-module signatures. The optional
C-declaration adapter lowering logical span arguments to the physical
pointer-and-count ABI landed too; see `docs/spans.md` and `docs/c-interop.md`.

## Goal

Make checked spans the public boundary for pointer-and-count native kernels:
their representation is hidden, their element type and count stay attached to
the view that established them, writable ranges can be partitioned without
inventing overlapping aliases, and Nupp-owned native allocations cannot forget
their length. Once those primitives have worked handwritten wrappers, add an
optional C-declaration adapter that lowers logical span arguments to the
physical pointer-and-count ABI.

This extends `nupp.span`; it does not add a second slice type. The current
`Span<T>` and `WriteSpan<T>` already retain a root, pointer, offset, and runtime
count, and `WriteSpan<T>` already keeps an affine invalidation barrier live
until `span.commit`.

## Current blockers

The current records are not yet a safe native-kernel abstraction across module
boundaries:

- `pointer`, `offset`, and `count` are public readonly fields. A checked caller
  can pass `slice.pointer` with `slice.count`, forgetting the slice offset, and
  `Span<T>.pointer` is mutable even though the span is shared.
- `Span<T>`, `WriteSpan<T>`, and their byte aliases are local declarations.
  `@export` affects documentation, not module type visibility, so another
  module cannot name them in a public signature.
- A generic field projection such as an inferred `WriteSpan<int32>.pointer`
  currently exposes un-substituted `T[?]`. The public methods added below must
  preserve the concrete element type.

Those are N0 requirements. Adding `ref` alone would leave shorter, unchecked
routes around it and make the partition guarantee unsound.

## Decisions

- Add module-private record fields. Privacy is a static checked-Nupp boundary,
  not a runtime sandbox: generated Lua and explicit gradual/unsafe interop keep
  their existing trust model.
- Make the generic span records and byte aliases genuine module-visible types.
  Their private representation is not C-reifiable and is never an ABI promise.
- Keep `count` public and immutable, but hide `anchor`, `pointer`, and `offset`.
  A count alone grants no memory access. All pointer projection goes through a
  borrowed method that applies the offset.
- Store a const pointer in `Span<T>`. Only a live `WriteSpan<T>` can project a
  mutable pointer.
- A write span can produce a shared span borrowed from itself. That view blocks
  exclusive use and commit until its scope ends.
- Make count-preserving allocation land before writable partitioning, so the
  Tecs acceptance fixture is written once against its final owner type.
- Prove writable partitions by region-tree provenance, not arbitrary integer
  inequalities.
- Introduce partition provenance through a general unsafe intrinsic, not a
  hard-coded match on the name `nupp.span.splitAt`. The standard library checks
  the range and contains the assertion; Tecs or another library may build its
  own capability only at an explicit audited unsafe site.
- Reuse `NUPP2602` for overlapping exclusive regions. Extend its explanation
  rather than creating a second aliasing diagnostic.
- Physical C declarations continue to describe physical C parameters. A span
  adapter is an explicit contract that generates an ordinary Lua wrapper; it
  does not change LuaJIT FFI or a library's ABI.
- A zero-length adapted call still invokes C exactly once with count zero and
  the span's logical-start pointer, which may be one-past-end. A mapped foreign
  contract must permit that pointer and must not dereference it when count is
  zero. APIs without that contract need a handwritten wrapper.

This plan does not validate generated machine code, dispatch CPU features, or
make a C implementation safe merely because its call boundary is checked. The
foreign implementation remains trusted.

## N0: Nameable spans with a private representation

Add module-private fields to records, using this planned spelling:

```nupp
record span.Span<T>
    private readonly anchor: any
    private readonly pointer: const T[?] borrows (anchor)
    private readonly offset: integer
    readonly count: integer
end

record span.WriteSpan<T>
    private readonly anchor: any
    private readonly pointer: T[?] borrows (anchor)
    private readonly offset: integer
    readonly count: integer
end

type span.ByteSpan = span.Span<uint8>
type span.ByteWriteSpan = span.WriteSpan<uint8>
```

A private field is readable, writable, and constructible only in the canonical
module containing its declaration. Other checked modules see the nominal type,
public fields, inline methods, and static functions, but not private members.
They cannot name a private field in `new`, a shape conversion, reflection, a
derive, completion, or generated API documentation. The compiler still
includes private fields in the declaring module's own checking and in the
nominal fingerprint needed to invalidate its dependants.

Limit the first privacy slice to record fields. C structs expose layout by
definition, and interfaces declare public contracts; both reject `private`.
`NUPP2209` reports access, initialization, or reflection of a private field
outside its declaring module and receives a complete `nupp explain` example.

Qualified generic records already parse, but none exists in the source tree.
Prove that `record span.Span<T>` survives declaration, bundled-module export,
module summaries, incremental loading, type application, construction inside
its module, and use from another module. Fix those general paths rather than
special-casing `nupp.span`. Do the same for qualified generic aliases.

### N0 implementation

- Extend the record-field CST, parser, formatter, checker, nominal metadata,
  module summaries, incremental hashes, documentation, reflection, and LSP
  member visibility with `private`.
- Make constructor checking enforce field privacy for both named and positional
  record construction. A private field also closes positional construction
  outside its module because field order would otherwise reveal it.
- Change the span declarations and aliases to module-qualified exported names.
- Make `Span<T>.pointer` internally const and preserve that constness through
  `slice` and construction.
- Fix generic nominal field projection so the span implementation sees
  `int32[?]`, not `T[?]`, when the receiver is `Span<int32>` or
  `WriteSpan<int32>`.
- Update record, module, C-interoperation, ownership, and span reference text.

### N0 tests

- Another module can name `span.Span<int32>`, `span.WriteSpan<int32>`,
  `span.ByteSpan`, and `span.ByteWriteSpan` in parameters and results.
- `pointer`, `offset`, and `anchor` work inside `nupp.span` and report
  `NUPP2209` through direct access, aliases, construction, reflection,
  completion, and derives outside it.
- `count`, `get`, `slice`, `set`, and `commit` retain their intended public
  visibility.
- A shared span's internal pointer cannot satisfy a mutable pointer even inside
  its module without an explicit unsafe cast.
- Generic field and inline-method projection substitute the concrete element
  type and constness through direct calls, aliases, summaries, and incremental
  reloads.
- Existing records without private fields generate byte-identically, and
  structs and interfaces reject the modifier.

### N0 exit criteria

Checked code outside `nupp.span` can name span types but cannot read or
construct their pointer/offset representation. The only public representation
field is the immutable count.

## N1: Borrowed native references

Add offset-adjusted pointer-and-count projection and a read view of a write
span:

```nupp
function span.Span.ref<T>(borrows self: span.Span<T>): (
    const T[?] borrows (self),
    integer
)

function span.WriteSpan.ref<T>(exclusive self: span.WriteSpan<T>): (
    T[?] borrows (self),
    integer
)

function span.WriteSpan.shared<T>(borrows self: span.WriteSpan<T>):
    span.Span<T> borrows (self)
```

Both `ref` methods return a pointer advanced by the private offset and the
logical count. The implementation performs its only unchecked pointer addition
inside `nupp.span`, then uses existing provenance machinery to root the pointer
in `self`. Raw indexing of the returned `T[?]` remains rejected outside
`unsafe`; this is a foreign-call projection, not an indexing escape hatch.

`WriteSpan.set` changes to `exclusive self`, as do `WriteSpan.ref` and every
later writable operation. Consecutive calls remain valid when no other view is
live. A span returned by `shared` stores a const pointer and borrows the write
span, so the parent rejects `set`, `ref`, `shared`, and `commit` until the read
view ends.

An empty span projects its logical-start pointer and count zero. `ref` itself
does not invoke or dereference C.

### N1 implementation

- Add `Span.ref`, `WriteSpan.ref`, and `WriteSpan.shared`; share the private
  offset calculation.
- Change `WriteSpan.set` to an exclusive receiver in this phase.
- Preserve the borrowed result of the first slot in the multi-return through
  assignment, return, generic calls, closures, suspension checks, and a C call
  carrying a `borrows` contract.
- Refactor the DynASM spike's public wrapper to accept
  `span.WriteSpan<Position>` and `span.Span<Velocity>`. Its private C binding
  remains pointer-shaped and call-duration borrowed.
- Remove the spike's public raw arrays and independent counts. It compares the
  two public span counts, then keeps both `ref` results in the smallest lexical
  scope around the private call.
- Document the projection, constness, and shared-view rules.

### N1 tests

- Full, empty, first-element, last-element, sliced, and nested-sliced spans
  project the adjusted address and correct count into a small C fixture.
- A shared reference is rejected for a mutable C parameter; a write reference
  is accepted for a call-duration mutable parameter.
- The pointer cannot outlive the span, cross `commit`, enter a `takes` or
  `retains` parameter, or permit its root to be resized, moved, or freed.
- Capturing a projected pointer in an escaping closure and holding it across a
  raw `coroutine.yield` report the existing ownership/suspension diagnostics.
  Checked handled suspension is accepted only where its existing cancellation
  contract preserves and discharges every live obligation.
- Raw indexing through either projected `T[?]` still reports `NUPP2604`.
- Two consecutive `set` calls and the existing string-buffer span workflow
  remain valid with an exclusive receiver.
- A live `shared` view blocks every exclusive parent operation, then releases
  the parent when its scope ends.
- Concrete element type and constness survive the multi-return, aliases,
  generic forwarding, and module summaries.
- `ownership-audit` reports the internal pointer addition, not every checked
  kernel call site.

### N1 exit criteria

The DynASM wrapper exposes only span arguments. Checked code cannot obtain a
mutable pointer from `Span<T>`, read the stored base pointer, or forget a slice
offset without entering an explicit unsafe/gradual boundary.

## N2: Count-preserving native allocation

Replace the raw result of `heap.allocate` with an owned `heap.Array<T>`:

```nupp
local values = heap.allocate(ffi.typeof<int32>(), count)
print(values.count)

do
    local writable = values:write()
    writable:set(1, 42 as int32)
    span.commit(writable)
end

local readable = values:read()
```

`heap.Array<T>` owns the malloc pointer and stores the immutable logical count.
Its pointer is module-private. `read()` returns `span.Span<T>` borrowed from the
array. `write()` requires exclusive access and returns the existing owned
`span.WriteSpan<T>` borrowed from it. The array cannot be freed, moved, or used
for another exclusive operation until that write span is committed or
automatically discharged.

This is intentionally source-incompatible for the small current `nupp.heap`
surface. Retaining a bare-pointer `allocate` convenience would preserve the
count-loss route this phase removes. Raw ownership transfer stays possible only
through the existing explicit unsafe/foreign mechanisms; there is no safe
`allocateRaw` twin.

Allocation keeps the current checks: reject negative counts, byte-size
overflow, and zero-width elements; allocate at least one byte for an empty
logical array; and report malloc failure. The stored count is the same value
used in that calculation, so a caller never supplies it twice.

`span.fromCarray` and `writeCarray` remain for external pointer-and-count APIs.
Their count is necessarily a foreign assertion because `T[?]` has no bound.

### N2 implementation

- Add module-visible generic `heap.Array<T>` with private pointer storage, a
  drop path, immutable count, and `read`/`write` methods.
- Change `heap.allocate` to construct that owner directly from the malloc
  result and allocation count.
- Migrate standard-library tests, documentation, reference text, examples,
  and the checked-kernel spike.
- Preserve generic element type and constness through allocation, both view
  constructors, `shared`, slicing, and `ref`.

### N2 tests

- Allocation handles zero, one, a large valid count, a negative count, byte
  overflow, zero-width elements, and malloc failure.
- `read().count` and `write().count` always equal the allocation count without
  another argument.
- A live read blocks write; a live write blocks read, move, drop, and a second
  write until commit.
- Normal return and error unwinding discharge an uncommitted write span before
  freeing its array, exactly once.
- Moving `heap.Array<T>` transfers pointer and count together.
- Concrete element type and constness survive every view operation.
- No checked external code can access or construct the allocation pointer.

### N2 exit criteria

Nupp-owned native arrays cannot forget or substitute their allocation count in
checked code. Explicit pointer-plus-count constructors remain visibly foreign
boundary assertions.

## N3: Disjoint writable partitions

Add a checked binary partition rather than arbitrary writable slicing:

```nupp
local split = writable:splitAt(mid)
use(split.left)
use(split.right)
-- split leaves scope; writable becomes exclusively usable again
```

`splitAt(mid)` uses a zero-through-count element count: `mid` elements go left
and the rest go right. This differs deliberately from the existing one-based,
inclusive `Span.slice(first, last)` and is documented at both methods. The name
`splitAt` follows the count/boundary convention; `splitAfter` would misleadingly
suggest a one-based element index.

For a parent with private `(offset, count)`, the module constructs:

```text
left.offset  = parent.offset
left.count   = mid
right.offset = parent.offset + mid
right.count  = parent.count - mid
```

The borrowed `span.WriteSplit<T>` contains left and right write spans and keeps
the one parent write token alive. The parent cannot be committed or used
exclusively while the split or either child is live.

Ordinary field identity cannot prove two pointer-bearing values disjoint. Add
partition provenance to borrow state: a root write span has region path `r`;
splitting path `p` produces `p/L` and `p/R`. Siblings are disjoint, while a
path overlaps its ancestors and descendants. Nested splits extend the path and
need no arithmetic solver.

Add `nupp.partition(parent, left, right)` as an unsafe ownership intrinsic. It
returns/marks the two child capabilities as sibling regions borrowed from the
parent. It performs no runtime arithmetic and proves nothing about arbitrary
pointers; the caller is asserting that the values cover disjoint parts of the
parent. `WriteSpan.splitAt` performs the runtime bounds check and exact offset
construction before making that assertion in its one audited unsafe block.
Other libraries, including Tecs, may use the same intrinsic only at an explicit
unsafe site listed by `ownership-audit`. The checker never matches a function
name or trusts a freely applicable annotation.

Conceptually the assertion site is:

```nupp
unsafe do
    left, right = nupp.partition(self, left, right)
end
```

The intrinsic is erased at runtime like `nupp.borrowFrom`. Its result borrows
from `self`, preserves the concrete types of `left` and `right`, and adds only
the sibling region identities. It rejects an owned child, a child already tied
to an unrelated root, and a parent that is not the sole live writable region at
the assertion site.

Region paths travel through the same assignments, calls, packs, projections,
closures, and module summaries as existing provenance. Losing a path through a
gradual/unsafe boundary conservatively returns to the nearest known ancestor.
The sole-live-borrow rule and argument-overlap rule both compare overlapping
regions: a sibling no longer blocks a child's exclusive use, while the parent
and same/ancestor/descendant paths still do.

There is no public writable `slice(first, last)` in this phase. Two separately
requested ranges could overlap, which is the general proof this design avoids.

### N3 implementation

- Add `span.WriteSplit<T>` with private representation and public borrowed
  `left`/`right` views, plus `WriteSpan.splitAt`.
- Add the unsafe partition-provenance intrinsic and list its assertions in
  `ownership-audit`.
- Extend ownership entries, transport, the sole-live-view check, and exclusive
  argument overlap with region paths, sibling disjointness, and ancestor
  overlap.
- Preserve region paths through generic specialization, fields, packs,
  closures, module summaries, incremental caches, and nested splits.
- Reuse `ref`, `set`, `shared`, and recursive `splitAt` on child regions.
- Add a Tecs-shaped fixture backed by `heap.Array<Transform2D>` that partitions
  a component column, calls a native kernel on both halves, and rejoins by
  ending the split scope.
- Extend the existing `NUPP2602` explanation, ownership documentation, span
  reference, completion, hover, and ownership-flow diagnostics with region
  paths. Do not allocate a new diagnostic code for the same aliasing rule.

### N3 tests

- Split points zero, one, count minus one, and count produce exact halves;
  negative and greater-than-count points raise before constructing views.
- Boundary writes land only in their intended half; empty children are valid;
  nested splits retain offsets relative to the original pointer.
- A single exclusive use of `left` is accepted while `right` is live. Two
  siblings are accepted as distinct exclusive arguments.
- The same child twice, a child plus an ancestor, and a parent operation while
  either child lives report `NUPP2602`.
- The parent accepts `set`, `ref`, `shared`, `splitAt`, and `commit` after the
  child scope ends.
- Returning or moving a child beyond its split/parent reports the existing
  borrow-escape diagnostic.
- Assignment, generic forwarding, packs, fields, closures, modules,
  incremental reloads, and nested partitions retain their region paths.
- A gradual/unsafe-erased path never gains a disjointness fact accidentally.
- No checked caller can access a child's stored base pointer and bypass the
  partition through a plain C call.
- A false `nupp.partition` assertion requires `unsafe` and appears in the audit;
  no annotation or symbol spelling can introduce region siblings.

### N3 exit criteria

One write token can be recursively partitioned into checked non-overlapping
kernel inputs without copying data or solving range inequalities. Every custom
partition constructor has one explicit audited unsafe assertion.

## N4: Counted C pointer adapters

After N1 through N3 establish the handwritten pattern, add an explicit adapter
contract directly to physical C pointer types. `countedBy` names another
parameter semantically rather than using annotation strings:

```nupp
cdef function ks_integrate(
    borrows positions: Position* countedBy(count),
    borrows velocities: const Velocity* countedBy(count),
    count: uint64,
    dt: float
) from"kernel"
```

The count reference resolves only against this cdef's physical parameters, so
a lexical binding named `count` cannot capture it. Const pointers become
logical shared spans; mutable pointers become logical writable spans. The
qualifier is erased from the C declaration and has no ABI effect.

The logical checked signature is:

```nupp
function(
    exclusive positions: span.WriteSpan<Position>,
    borrows velocities: span.Span<Velocity>,
    dt: float
): nil
```

A caller holding a write token may pass `writable:shared()` to a read mapping;
that read view blocks simultaneous exclusive access in the ordinary way.

The generated wrapper checks exact length equality for every pointer group
sharing a physical count, projects adjusted borrowed pointers, range-checks
conversion to the physical count type, and invokes one hidden FFI binding in
the original order. Independent counts form independent groups. Prefix
relations, strides, capacities, byte counts, sentinel termination, retention,
and output pointers remain handwritten contracts in the first release.

For count zero the wrapper still projects the pointer and calls C once. It does
not short-circuit, substitute null, or suppress foreign side effects. The
adapter contract includes the zero-count no-dereference requirement.

The hidden physical declaration is exactly what `ffi.cdef` and `ffi.load`
receive. The wrapper allocates no descriptor and installs no callback. The safe
module export exposes only the logical span signature; obtaining the hidden raw
symbol requires a separately declared foreign contract that remains visible to
`ownership-audit`.

### N4 validation rules

- A read mapping requires a const physical pointer and produces
  `span.Span<T>`.
- A write mapping requires a non-const pointer and produces an exclusive
  `span.WriteSpan<T>` parameter.
- Every mapped pointer's physical mode is call-duration `borrows`. `plain`,
  `exclusive`, `takes`, `retains`, `releases`, and `out` are rejected.
- Every mapped count is a non-variadic integer C parameter. Begin with
  `uint64`/`size_t`; narrower supported types require an emitted upper-bound
  guard before conversion.
- A mapped count disappears from the logical signature. One pointer and one
  count may appear in only one mapping; multiple pointers may share a count.
- Invalid symbolic names, duplicate maps, non-pointers, mutable reads, const
  writes, unsupported counts, and conflicting ownership contracts receive one
  stable span-ABI diagnostic family with `nupp explain` examples and complete
  fixes where the correction is unambiguous.

### N4 implementation

- Parse and resolve each dependent count reference, then preserve physical and logical
  signatures on the cdef definition.
- Carry both signatures through checking, generation, aliases, module
  summaries, incremental hashes, hover, definition, completion, documentation,
  formatting, and schema output.
- Generate/cache the hidden physical FFI binding exactly as an ordinary `from`
  declaration and emit the logical wrapper with guards before the call.
- Report the physical symbol, counted pointer maps, zero-count promise, and remaining
  trusted implementation in `ownership-audit`.
- Replace the DynASM spike's handwritten equal-length wrapper with `countedBy`;
  retain one handwritten prefix wrapper to demonstrate the deliberate limit.

### N4 tests

- Check, generation, runtime, aliasing, module-summary, incremental, formatter,
  documentation, LSP, schema, and audit coverage for one read, one write,
  independent counts, and a shared count.
- Equal shared-count spans call C; unequal spans raise before pointer projection
  or C. A sliced span passes its adjusted pointer.
- A zero-count call reaches a stateful C fixture exactly once with count zero;
  the fixture does not dereference the pointer.
- Mutable/shared, const/writable, ownership-mode, symbolic-name, duplicate-map,
  and count-width errors are rejected at the declaration.
- Count overflow raises before narrowing or entering C.
- A `count` binding in lexical scope has no effect on the symbolic map.
- A write token passed through `shared()` is accepted for read and remains
  unavailable exclusively until that view ends.
- Generated Lua contains one wrapper and one physical call, with no allocation,
  callback, per-element work, or zero-count branch.

### N4 performance gate

Compare generated and handwritten wrappers in the same process and against the
same freshly built optimized native library. Alternate AB/BA order, perform
four warmups, then collect 15 paired samples; each sample batches enough calls
to last at least 100 ms. Run the matrix after two clean release builds.

- At 262,144 and 1,048,576 rows, the median paired generated/handwritten ratio
  must be at most 1.05 in both builds.
- For the zero-count fixture, the generated wrapper's median added cost must be
  at most 50 ns per call after subtracting the handwritten wrapper.
- Inspect generated Lua in the same test so a benchmark pass cannot hide an
  allocation or extra native call.

Failure of either numeric threshold blocks automatic lowering; handwritten
`ref` wrappers remain the supported path.

### N4 exit criteria

The integration kernel is callable as a span-to-span operation while the
library continues to export `(Position*, const Velocity*, size_t, float)`.
Checked callers cannot substitute a count, access a stored base pointer, forget
a slice offset, pass a shared view to a writer, or bypass shared-count equality
through the safe binding.

## Delivery order

Land each slice independently:

1. N0 seals and exports the existing span representation.
2. N1 adds handwritten native projections and updates the spike.
3. N2 makes Nupp-owned native allocation retain its count.
4. N3 adds compiler-supported partition provenance and the final Tecs-shaped
   fixture.
5. N4 removes repetitive equal-length wrapper code only after multiple worked
   examples establish its semantics.

N0, N3, and N4 change compiler sources. N1 and N2 change self-hosted standard
library sources, and may expose general compiler bugs through their generic
APIs. Run focused ownership, standard-library, cdef, generation, tooling,
suspension, incremental, and Tecs acceptance suites for each applicable slice;
run the full suite before each merge. Run `./bin/nupp fixpoint` for every slice
and require a byte-identical second compiler build.

The plan is complete when the DynASM spike and Tecs-shaped acceptance fixture
use checked, nameable spans from owned allocation through partitioning and
native call; no checked external module can read a span's stored pointer or
offset; and every unsafe operation is confined to the span/heap implementation
or an audited custom partition constructor.
