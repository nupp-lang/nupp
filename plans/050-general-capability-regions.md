# General capability regions

> Core implementation landed. One stable segment algebra now answers fields, exact/unknown
> index, parent/descendant, and audited partition overlap. Loop back edges compare
> complete capability and live-region state; unrelated span compiler behavior remains.

## Decision

Replace ownership-specific span overlap rules with a general region algebra over
places. A region identifies a root plus a path of field, tuple-slot, dereference,
index, or checked-range segments. Shared regions block invalidation; exclusive regions
grant sole checked access. Ordinary Lua aliases remain outside this proof unless an API
introduces a rooted or exclusive capability.

This plan depends on the canonical loan set in
[`047-lua-ownership-capabilities.md`](047-lua-ownership-capabilities.md). It replaces
only ownership, provenance, and overlap decisions that recognize span spellings. It
does not remove unrelated compiler knowledge needed by C views, optimization, effect
analysis, fixed-width storage, or AOT lowering.

## Compatibility gate

Before changing region analysis, record every loop and kernel that checks in the
compiler, stdlib, `bench/kernel-subset-spike`, native-span fixtures, and AOT tests.
General regions may accept more programs, but no stage of this plan may newly reject
that corpus. An unavoidable rejection requires a separate reviewed language decision;
it cannot be accepted as conservative implementation fallout.

Plans [`032-native-kernel-spans.md`](032-native-kernel-spans.md) and
[`038-aot-functions.md`](038-aot-functions.md) retain their representation and AOT
gates throughout this migration.

## Region model

```text
Region {
    roots: set<flow identity>
    path: [Segment...]
}

Segment = field(stable field identity)
        | tupleSlot(integer)
        | dereference
        | index(IntegerFact)
        | range(IntegerFact, IntegerFact)
        | unknown
```

`ordinary` access means no borrow contract restricts the value or place; it is not a
uniqueness claim. `shared` means a live derived value retains roots and blocks
invalidation of the overlapping region. `exclusive` means the checker has sole access
to the region for the declared call or derived result.

Region identity uses stable roots and declaration identities in summaries, but local
flow identities during body checking. Alias names, method spellings, and source text
are not part of overlap identity.

## Overlap rules

Distinct fixed fields and tuple slots are disjoint:

```nupp
exclusive pair.left
exclusive pair.right
```

A parent overlaps every descendant:

```nupp
exclusive pair
exclusive pair.left
```

Two exact constant indexes are disjoint when their integer values differ. Two dynamic
indexes overlap unless the checker has a dominating proof that their exact values
differ. Two checked ranges are disjoint only when their bounds facts prove
non-overlap. An unknown index, unchecked pointer arithmetic, or unknown dereference
widens to the nearest rooted parent allocation.

An exclusive parameter lends the caller's sole region to the callee. A result written
`T borrows (source)` becomes an exclusive child when the selected source parameter is
exclusive. The parent becomes usable again after the child's last use or destruction.
A shared child blocks exclusive parent access but permits compatible shared access. An
exclusive child blocks both shared and exclusive overlap.

## Audited region splitting

Library code creates provably disjoint siblings through one audited intrinsic with a
stable declaration identity. It validates runtime bounds before publishing child
regions and returns paths whose non-overlap the checker can trust. User methods may
wrap the intrinsic without receiving privilege by name.

`nupp.span` migrates slicing and splitting to this intrinsic. The migration deletes
ownership branches that recognize `Span`, `WriteSpan`, `getMut`, `slice`, or `splitAt`
by spelling.

It explicitly preserves unrelated branches, including:

- `src/nupp/compiler/check/cdef.nupp` construction of a `countedBy` view type;
- `src/nupp/compiler/check/callexpr.nupp` allocation-free facts for span accessors;
- `src/nupp/compiler/analysis.nupp` write classification for `set` and `getMut`;
- `src/nupp/compiler/check/resolve.nupp` fixed-width storage rules for span generics;
  and
- `src/nupp/compiler/check/aot.nupp` AOT memory-boundary recognition for `get` and
  `getMut`.

Those branches may be generalized only by the plans that own C contracts,
optimization, effects, fixed-width storage, and AOT. Region cleanup is not authority
to delete them.

## Control-flow joins and loops

Region flow uses a finite forward dataflow fixpoint. A loop header joins the entry edge
with every back edge until root sets, access modes, and region paths stop changing.
The join is conservative but may not invent or discard a movable capability to force
convergence.

Every back edge must return the same live obligation shape expected at the header. A
shared or exclusive child created inside an iteration must end before the back edge
unless the header explicitly carries the same region state. Cleanup or transfer-only
leaves created in an iteration must likewise be discharged, returned, or moved into an
explicit loop-carried place before the edge.

Loop-carried roots union at the header. Differing dynamic indexes widen to their
common parent region unless an existing integer proof establishes one stable index or
disjoint checked ranges. A proof that indexes differ within one iteration says nothing
about different iterations: the earlier child must be dead at the back edge or a loop
invariant must prove cross-iteration disjointness.

Widening records the incoming paths and the back edge that lost precision. Diagnostics
therefore point to the actual loop-carried conflict rather than only the later access.

## Integer-proof boundary

This plan consumes existing integer constants, equality facts, range checks, and
dominance. It does not add a theorem prover. A new fact producer must be independently
sound, reusable outside ownership, and covered by its own narrowing tests before
regions trust it.

When proof is unavailable, widening is the answer. `unsafe` remains available for
pointer arithmetic whose root and bounds are externally guaranteed, but unsafe code
does not manufacture a reusable safe region fact without the audited splitting
intrinsic.

## Module summaries

Exported region relationships serialize parameter or field roots and stable path
segments. Local dynamic-index facts never enter a public summary. A callable result
may state that it returns a child of parameter `source`; its caller instantiates that
path with the caller's roots and current integer facts.

Fingerprints change when a public root relation, access mode, or stable path changes.
Private widening and last-use decisions do not invalidate importers when the public
contract is unchanged. Summary deserialization rejects a field path whose declaration
identity or shape no longer matches.

## Diagnostic inventory

Reserve two ownership-family codes:

| Code | Failure class |
| --- | --- |
| `NUPP2607` | shared or exclusive regions overlap incompatibly |
| `NUPP2609` | a loop back edge changes roots, obligations, or region state unsafely |

`NUPP2607` identifies both paths, their nearest common parent, access modes, and the
last use keeping each child live. `NUPP2609` identifies the header expectation, back
edge, widened path, and obligation or borrow that failed to end. Both land with
`nupp explain`, corrections, generated reference entries, related locations, and
`docs/diagnostics.md` rows.

## Implementation order

### R0 — Freeze current behavior

- Inventory every ownership-specific span name check and every unrelated span branch.
- Record the no-new-rejections corpus and generated output.
- Record warm-check, private-edit, full-invalidation, summary-size, and memory
  baselines.
- Verify that `NUPP2607` and `NUPP2609` are unallocated.

### R1 — Places and field regions

- Add stable field, tuple-slot, parent, and descendant paths.
- Implement shared and exclusive overlap without changing dynamic-index behavior.
- Migrate fixed-field borrows and partial affine-field moves.

### R2 — Indexes and checked ranges

- Consume existing constant, equality, range, and dominance facts.
- Implement exact-index, range, unknown-index, and pointer widening.
- Add the audited splitting intrinsic and its runtime bounds validation.

### R3 — Loop fixpoint

- Join roots, access, regions, and obligation shapes at loop headers.
- Enforce back-edge lifetime and obligation invariants.
- Record widening provenance for diagnostics.
- Run the entire R0 corpus as a blocking no-new-rejections gate.

### R4 — Span ownership migration

- Rebuild span slice and split ownership on the audited intrinsic.
- Delete ownership, provenance, and overlap spelling checks.
- Assert that C-view, allocation, effect, fixed-width, and AOT branches remain.

### R5 — Summaries, tooling, and deletion

- Serialize stable public paths and update fingerprints.
- Add hover region paths, related locations, and last-use display.
- Delete the old span-specific ownership representation after its final consumer.
- Update ownership, span, FFI, diagnostics, and generated reference documentation.

No subsystem leaves a phase with old and new overlap answers both authoritative.

## Performance gates

Use the baseline methodology from plan 047:

- unchanged warm checking and private-body invalidation may regress by at most 5%;
- full invalidation may regress by at most 10%;
- summaries and peak checker memory may grow by at most 10%; and
- native-kernel generated code and runtime benchmarks may not regress.

Add focused checker benchmarks for a thousand fixed fields, nested projections, a hot
loop with iteration-local borrows, dynamic indexes that widen, and checked ranges that
remain disjoint. Report dataflow iterations per loop so a time result cannot hide a
failure to converge precisely.

## Verification matrix

Tests must prove:

- ordinary aliased Lua tables remain outside region checking;
- fixed sibling fields and tuple slots are disjoint;
- parents overlap descendants;
- exact unequal indexes and proven ranges are disjoint;
- unknown indexes and pointer arithmetic widen to a safe parent;
- shared children block invalidation but permit compatible shared mutation;
- exclusive children block every overlapping access;
- audited splits publish disjoint siblings only after bounds validation;
- iteration-local children end before the back edge;
- loop-carried children converge or report `NUPP2609` with the widening edge;
- every R0 compiler, stdlib, span, kernel, and AOT fixture still checks;
- unrelated span compiler branches remain intact;
- public region summaries are stable and stale paths are rejected;
- `NUPP2607` reports both conflicts and their last uses; and
- generated representation, C ABI, and native-kernel performance remain unchanged.

## Completion criteria

This plan is complete when:

- one place algebra answers all ownership overlap questions;
- loops have a convergent, documented back-edge rule;
- span ownership uses the audited splitting intrinsic without name privilege;
- C-view, allocation, effect, fixed-width, and AOT behavior remains owned by its
  existing subsystem;
- the complete baseline corpus has no new rejection;
- public summaries carry stable region paths without local flow IDs;
- old span-specific ownership state is deleted;
- `NUPP2607`, `NUPP2609`, tooling, and documentation are complete; and
- the full suite, fixpoint, bootstrap, kernel, ABI, and performance gates pass.
