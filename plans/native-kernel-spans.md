# Native kernels over checked spans

Status: planned

## Goal

Make a checked Nupp function able to hand an existing `Span<T>` or
`WriteSpan<T>` to a pointer-and-count C kernel without separating its bound,
partition a writable range without manufacturing overlapping aliases, and
allocate native arrays whose bound cannot be forgotten. Once those library
contracts are proven, add an optional C-declaration adapter that erases spans
to the physical pointer-and-count ABI.

This is an extension of `nupp.span`, not a second slice type. `Span<T>` already
retains its root, pointer, offset, and runtime count. `WriteSpan<T>` already
keeps an affine barrier live until `span.commit`. The work below closes the
native-call and allocation gaps around those types.

## Decisions

- A span remains a Nupp value. It is not declared C-reifiable and its record
  layout is never an ABI promise.
- The safe native boundary exposes a pointer only as a borrow rooted in the
  span. Raw indexing remains rejected, so obtaining that pointer does not turn
  ordinary Nupp code into unchecked memory access.
- A shared span exposes a const pointer. Only a live write span can expose a
  mutable pointer.
- Writable ranges are made disjoint by `splitAt`, not by an integer theorem
  solver. The library checks the split point once and constructs the two
  ranges. The checker tracks their partition provenance as paths in one region
  tree; it does not attempt to prove facts about arbitrary indices.
- One parent `WriteSpan` continues to own the invalidation barrier. Split
  ranges borrow that parent; they do not create two independently discharged
  owners.
- `heap.allocate` preserves its count in an owned nominal value. It no longer
  returns a bare `T[?]` from which the allocation length must be remembered by
  convention.
- Physical C declarations continue to describe physical C parameters. Span
  convenience is an explicit adapter contract and never changes what
  `cheader`, LuaJIT FFI, or a native library sees.
- The first ABI adapter supports call-duration reads and writes only. Retained,
  released, consumed, output, variadic, sentinel, and strided foreign
  contracts remain explicit wrappers.

This plan does not validate generated machine code, add CPU-feature dispatch,
or make native kernels safe merely because they have a checked call boundary.
The C implementation remains a trusted foreign contract.

## N1: Borrowed native references

Add a pointer-and-count projection to both checked span types. The intended
surface is:

```nupp
function Span.ref<T>(borrows self: Span<T>): (
    const T[?] borrows (self),
    integer
)

function WriteSpan.ref<T>(exclusive self: WriteSpan<T>): (
    T[?] borrows (self),
    integer
)
```

The exact const spelling may follow the generic type grammar, but the contract
is fixed: `Span.ref` cannot satisfy a mutable C pointer, while
`WriteSpan.ref` can. Both return a pointer already advanced by `offset` and the
remaining logical `count`; callers never repeat offset arithmetic.

The implementation performs the one unchecked pointer addition inside
`nupp.span`, then uses the existing provenance assertion to root the result in
`self`. A zero-length span may produce a one-past-end pointer, but its count is
zero and the adapter must not dereference it. No public operation promises a
non-null pointer for an empty span.

`WriteSpan.set`, `WriteSpan.ref`, and every later writable operation require an
exclusive receiver. That matters once a parent has live split views: a shared
method receiver would let the parent mutate the same storage while children
were live.

### N1 implementation

- Add the two `ref` methods and share the internal checked offset calculation.
- Keep the returned pointer's borrow relation through assignment, return,
  generic calls, and a C call carrying a `borrows` contract.
- Refactor `bench/kernel-spike/checked.nupp` to accept a `WriteSpan<Position>`
  and `Span<Velocity>` at its public boundary. The private C declaration stays
  pointer-shaped and call-duration borrowed.
- Remove the raw public `T[?]` plus independent-count API from the spike. Its
  only explicit length comparison should use the span counts.
- Document that `ref` is a foreign-call projection, not an unchecked indexing
  escape hatch.

### N1 tests

- A sliced span passes the adjusted address and narrowed count to a small C
  fixture.
- A read reference is rejected for a mutable C parameter.
- A write reference is accepted for a call-duration mutable C parameter.
- The pointer cannot outlive the span, cross `commit`, or permit its root to be
  resized, moved, or freed.
- Raw indexing through the returned `T[?]` still reports `NUPP2604` outside
  `unsafe`.
- Empty, full, first-element, last-element, and nested shared slices project
  the correct address and count.
- `nupp ownership-audit` reports only the internal pointer adjustment as new
  unsafe implementation, not every checked kernel call site.

### N1 exit criteria

A checked wrapper can call the existing DynASM spike with no `unsafe`, no
separate public count, and no mutable pointer obtainable from `Span<T>`.

## N2: Disjoint writable partitions

Add a checked binary partition rather than arbitrary writable slicing:

```nupp
local split = writable:splitAt(mid)
use(split.left)
use(split.right)
-- split leaves scope; writable becomes exclusively usable again
```

`mid` is the number of elements placed in `left`, so it is valid from zero
through `self.count`. The results are:

```text
left.offset  = self.offset
left.count   = mid
right.offset = self.offset + mid
right.count  = self.count - mid
```

The return is a borrowed nominal `WriteSplit<T>` containing `left` and `right`
`WriteSpan<T>` fields tied to one borrowed source field. The parent remains the
one owned write token. A split result cannot escape it, and the parent cannot
be committed or used exclusively while the split or either projected child is
live.

Ordinary field identity is not enough to prove that two pointer-bearing values
refer to disjoint memory. Add narrow partition provenance to the borrow state:
the root write span has region path `root`; splitting path `p` produces `p/L`
and `p/R`. Siblings are disjoint, while a path overlaps its ancestors and
descendants. Thus `left` and `right` may each be used exclusively, but the
parent overlaps both. Nested splitting extends the path and needs no integer
reasoning.

Only the sealed standard-library `splitAt` constructor may introduce sibling
region paths. There is no user annotation that asserts arbitrary pointers are
disjoint. Region paths follow values through the same assignments, calls,
packs, projections, and module summaries as existing borrow provenance; losing
one conservatively returns to the common ancestor rather than guessing
disjointness.

Both child fields use the existing `WriteSpan<T>` operations and may themselves
be split, producing a lexical partition tree. There is no public writable
`slice(first, last)` in this phase: two independently requested slices could
overlap, and proving otherwise is exactly the general range problem this design
avoids.

### N2 implementation

- Add `WriteSplit<T>` with borrowed-field relations to its parent write span.
- Add `WriteSpan.splitAt`, the range check, and construction of the two child
  views.
- Make all mutating `WriteSpan` methods exclusive-receiver methods.
- Extend ownership entries and argument-overlap checks with partition paths,
  including sibling disjointness and ancestor overlap.
- Reuse `ref` for either a root write span or a borrowed child view; the pointer
  remains rooted through the complete parent chain.
- Preserve partition paths through ordinary provenance transport. Do not add
  symbolic arithmetic or infer disjointness from two arbitrary record fields.
- Add a Tecs-shaped fixture that partitions a `Transform2D` column, calls a
  native kernel on each half, and rejoins only by ending the split scope.

### N2 tests

- Split points zero, one, count minus one, and count produce the exact halves.
- Negative and greater-than-count points raise before constructing a view.
- Writes at both boundary elements land in the intended half and nowhere else.
- Empty children are valid and project count zero.
- Nested partitions keep offsets relative to the original pointer.
- The parent rejects `set`, `ref`, `splitAt`, and `commit` while a child is
  live, then accepts them after the child scope ends.
- Moving or returning a child beyond its split or parent reports the existing
  borrow-escape diagnostic.
- Two children can be passed as distinct exclusive arguments; passing the same
  child twice is rejected.
- Passing a child and any ancestor as exclusive arguments is rejected; passing
  children from unrelated roots remains valid under the ordinary rules.
- Assignment, generic forwarding, packs, fields, module boundaries, and nested
  splits preserve region paths. A gradual or erased route is conservative.
- A deliberately overlapping constructor remains impossible through the
  exported checked API.

### N2 exit criteria

One write token can be partitioned recursively into checked, non-overlapping
kernel inputs without copying data, using `unsafe`, or teaching the checker to
solve range inequalities.

## N3: Count-preserving native allocation

Replace the raw result of `heap.allocate` with an owned `HeapArray<T>`:

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

`HeapArray<T>` owns the malloc pointer and stores its immutable logical element
count. `read()` returns a `Span<T>` borrowed from the array. `write()` requires
exclusive access to the array and returns the existing owned `WriteSpan<T>`
borrowed from it. The array cannot be freed, moved, or exposed for another
exclusive operation until that write span is committed or automatically
discharged.

This is intentionally a source-incompatible break for the small current
`nupp.heap` surface. Keeping `allocate` as a bare-pointer convenience would
preserve the exact count-loss trap this phase is meant to remove. Code that
must transfer raw malloc ownership can do so in an explicit `unsafe` block or
declare the actual foreign allocator contract; there is no second safe
`allocateRaw` spelling.

The allocation checks remain as they are now: reject negative counts, reject
byte-size overflow, require a nonzero element width, allocate at least one byte
for an empty logical array, and report malloc failure. The stored count is the
same value used for the allocation calculation, so no caller supplies it a
second time.

`span.fromCarray` and `writeCarray` remain for external pointer-and-count APIs.
Their count is necessarily a foreign assertion because `T[?]` has no bound.
This phase fixes Nupp-owned heap allocations; it does not invent a bound for an
arbitrary imported pointer.

### N3 implementation

- Add the generic owned `HeapArray<T>` record, its drop path, immutable count,
  and `read`/`write` methods.
- Change `heap.allocate` to construct that owner directly from the malloc
  result and allocation count.
- Migrate standard-library tests, documentation, reference text, examples, and
  the checked-kernel spike.
- Preserve generic element types through allocation, both view constructors,
  splitting, and `ref`.
- Regenerate the bootstrap only after the source compiler and tests agree.

### N3 tests

- The allocated byte count is checked for zero, one, large valid, negative,
  and overflowing element counts.
- `read().count` and `write().count` always equal the allocation count without
  another user argument.
- A live read blocks `write`; a live write blocks read, move, drop, and a second
  write until commit.
- Automatic scope cleanup frees an uncommitted write span before freeing the
  backing allocation, exactly once on normal return and error unwinding.
- Element type and constness survive all view operations.
- Moving a `HeapArray` transfers its pointer and count together.
- The Tecs-shaped fixture allocates its component column once and never repeats
  the capacity when constructing kernel views.

### N3 exit criteria

Nupp-owned native arrays cannot forget or substitute their allocation count in
checked code. The remaining explicit pointer-plus-count constructors are
visibly foreign-boundary assertions.

## N4: Declarative span ABI adapters

After N1 through N3 establish the ordinary wrapper pattern, add an explicit
annotation to physical C declarations. The illustrative contract is:

```nupp
@spanabi(
    write = { positions = count },
    read = { velocities = count }
)
cdef function ks_integrate(
    borrows positions: Position*,
    borrows velocities: const Velocity*,
    count: uint64,
    dt: float
) from"kernel"
```

The annotation names physical pointer parameters, the physical count parameter
paired with each, and whether the logical argument is read or written. The
checker exposes this logical signature to Nupp callers:

```nupp
function(
    exclusive positions: WriteSpan<Position>,
    borrows velocities: Span<Velocity>,
    dt: float
): nil
```

The exact annotation grammar should follow the existing annotation parser, but
the mapping above is the schema and should be emitted by `--schema`, docs, and
LSP inspection in one stable form.

The generated adapter checks every group sharing a count for exact length
equality, projects adjusted borrowed pointers with `ref`, converts the count to
the declared integer C type with a range check, and invokes a hidden physical
FFI binding in the original parameter order. Independent count parameters form
independent groups. Kernels that accept a prefix (`read.count >= write.count`),
strides, capacities, byte counts, or sentinel termination continue to use a
handwritten checked wrapper in the first release.

The adapter is generated as direct Lua around the existing FFI symbol. It does
not pass the Nupp record to C, allocate a C descriptor, install a callback, or
promise the record's layout. The hidden physical declaration remains what
`ffi.cdef` and `ffi.load` receive. The safe binding exposes only the logical
span signature; an unchecked caller must declare its own raw C contract and is
then visible to `ownership-audit`.

### N4 validation rules

- A read mapping requires a const pointer and produces `Span<T>`.
- A write mapping requires a non-const pointer and produces
  `WriteSpan<T>` with an exclusive logical parameter.
- Every mapped count is an integer C parameter. Begin with `uint64`/`size_t`;
  narrower types require an emitted upper-bound check before conversion.
- A mapped pointer's physical ownership mode is call-duration `borrows`.
  `plain`, `exclusive`, `takes`, `retains`, `releases`, and `out` mappings are
  rejected rather than assigned surprising semantics.
- A mapped count cannot remain independently callable or participate in a
  variadic tail.
- One physical pointer and one count may appear in only one mapping. Multiple
  pointers may deliberately share the same count.
- Invalid names, non-pointer parameters, mutable reads, const writes,
  incompatible element types, unsupported count types, and conflicting maps
  receive stable diagnostics with complete fixes where one spelling is
  unambiguous.

### N4 implementation

- Extend annotation parsing and cdef checking with a normalized span-ABI map.
- Preserve both physical and logical signatures on the cdef definition so
  checking, generation, hover, definition, documentation, incremental hashes,
  and module summaries all read the appropriate one.
- Generate and cache the hidden physical FFI binding exactly as an ordinary
  `from` declaration does today.
- Generate the logical wrapper with length and conversion guards before
  pointer projection or the foreign call.
- Teach `ownership-audit` to report the physical symbol, its span mappings, and
  the fact that the foreign implementation remains trusted.
- Refactor the DynASM spike from its handwritten adapter to `@spanabi` and keep
  a handwritten unequal-length/prefix wrapper as a negative comparison.
- Add the new diagnostics to `nupp explain`, the language reference, C interop
  documentation, semantic tokens, completion, and formatter fixtures.

### N4 tests

- Check, generation, runtime, module-summary, incremental, formatter, docs,
  hover, definition, and ownership-audit coverage for one read span, one write
  span, independent counts, and a shared count.
- Shared-count calls accept equal spans and raise before C for unequal spans.
- A sliced span passes its adjusted pointer rather than its allocation base.
- Mutable/shared and const/writable mismatches are rejected statically.
- Count overflow raises before narrowing or entering C.
- The logical write argument is unavailable through another borrow during the
  call and remains usable afterward.
- `from"library"`, the default namespace, aliases of the declaration, and
  generic element instantiations retain the adapter contract.
- Generated Lua contains one wrapper and one physical FFI call, with no heap
  allocation, callback, or per-element work.
- The kernel benchmark shows the adapter within noise of the handwritten
  `ref` wrapper; otherwise the automatic lowering does not ship.

### N4 exit criteria

The checked integration kernel is callable as a span-to-span operation while
the native library continues to export the ordinary
`(Position*, const Velocity*, size_t, float)` symbol. Callers cannot substitute
an unrelated count, forget a slice offset, pass a shared view to a writer, or
bypass the length equality check through the safe binding.

## Delivery order

Land each numbered slice independently:

1. N1 makes handwritten checked native wrappers correct and updates the spike.
2. N2 enables safe component-column and job partitioning using the same
   projection.
3. N3 removes repeated counts from Nupp-owned native storage.
4. N4 removes repetitive wrapper code only after its semantics have multiple
   worked examples.

Run focused ownership, standard-library, cdef, generation, tooling, and Tecs
acceptance suites while implementing each slice. Run the full suite before
each merge. N1 through N3 change self-hosted standard-library sources, and N4
changes compiler sources, so run `./bin/nupp fixpoint` for every slice and
require a byte-identical second compiler build.

The plan is complete when the DynASM spike and the Tecs-shaped acceptance
fixture use checked spans from allocation through partitioning and native call,
with no public raw pointer/count pair and no `unsafe` outside the span and heap
implementation modules.
