# Compositional capability preservation

> Aggregate preservation landed. Callable contracts retain the unique result-shape path, and
> preservation transports complete capabilities through aggregate generic results
> without copying movable obligations. The closure, mapped/projection, and join
> extensions below remain future phases.

## Decision

Generalize the original scalar-only `preserves` relation into one-to-one capability
substitution through generic result shapes. `preserves` is a conservation relation:
cleanup obligations, transfer-only obligations, pin anchors, and foreign-retention
tokens move; roots, access, and region provenance are reproduced on the result.

This plan depends on the canonical capability query in
[`047-lua-ownership-capabilities.md`](047-lua-ownership-capabilities.md). It does not
add higher-kinded types, GATs, lifetime parameters, or a second ownership wrapper.
Ordinary first-order type parameters and the existing const-function identity domain
are sufficient because the checker substitutes capability atoms through the resolved
result type after ordinary generic substitution.

## Baseline

Before this plan, `preserves` was documented and implemented for scalar generic narrowing.
The expansion begins by freezing every present use in the prelude, compiler reference,
checker, tests, generated documentation, module summaries, and incremental cache.
Existing scalar behavior must remain accepted before aggregate transport is enabled.
Present signatures such as generic `assert` and `setmetatable` that preserve an
unconstrained parameter without spelling `takes` are characterized first, then
migrated together with the mode rule in P1; they do not receive a compatibility
exception afterward.

## Public rule

```nupp
local function forward<T>(takes value: T): T preserves value
    return value
end

local function swap<A, B>(
    takes left: A,
    takes right: B
): (B preserves right, A preserves left)
    return right, left
end

local record Box<T>
    value: T
end

local function box<T>(takes value: T): Box<T> preserves value
    return new Box(value = value)
end
```

`preserves source` does not copy a capability and does not merely promise the same
static type. Checking decomposes the source capability into atoms:

- every cleanup and transfer-only obligation moves to exactly one annotated result
  component;
- every pinned anchor and foreign-retention token moves to exactly one annotated
  result component;
- roots, access, and region provenance are reproduced on the result because several
  shared views may name the same roots; and
- the source place loses every movable atom transported to the result.

No result relation may duplicate a movable atom, and no successful return may lose
one. Branches may choose different destinations, but each runtime path still moves
each atom exactly once. A union describes the possible destination shape; it does not
create one owner per alternative.

## Parameter modes and inference direction

`preserves source` requires `takes source` whenever the source type can contain a
movable atom. An unconstrained generic `T` can contain one, so a public generic
forwarder spells both `takes value: T` and `T preserves value`. A source statically
known to contain only ordinary copyable data needs neither annotation. A nonconsuming
derived result uses `borrows (source)` instead.

Inference runs in one direction:

1. body flow determines that a source capability is consumed into a result;
2. that consumption infers `takes` for a private parameter; and
3. the one-to-one result mapping infers `preserves`.

A written `preserves` clause never silently upgrades `borrows` or an unannotated
capability-bearing public parameter. The checker reports `NUPP2606` and offers one fix
that writes the consistent `takes` mode and relation together. Explicit private
contracts are checked against the same direction.

## Result-shape substitution

Capability substitution recurses through:

- generic records and structs;
- tuple elements and multiple-result packs;
- optionals, unions, and intersections;
- mapped and projected types;
- nested fields;
- closures and callable records;
- function parameters and results; and
- imported module summaries.

Each result component records which source subtree it receives. Projection recovers
the corresponding component capability. Moving `box.value` moves only that subtree
and removes it from the box's remaining obligation tree. A later drop runs only the
cleanup leaves still present; a remaining transfer-only leaf keeps the aggregate
undroppable.

A result relation names one ownership source. When a result is a nonowning view of
several possible roots, use `borrows (left, right)`. When control flow may return one
of several affine inputs, each branch maps its selected input to the same union result
position and proves that every unselected input is returned or discharged separately.
There is no ambiguous operation that merges two live obligations into one.

## Joins and closures

Branch joins union possible root sets and conservatively join access and region state.
They retain the exact set of possible movable atoms and their source identities. If
two branches reach a result with incompatible obligation shapes, checking fails
instead of erasing one shape to fit the declared union.

Closures and callable records carry the same substitutions in captures, parameters,
and results. A `takes` capture moves its capability subtree into the affine closure.
A preserved closure result transports that subtree again when called. Dropping an
uncalled closure discharges its still-live cleanup leaves and rejects any remaining
transfer-only leaf.

Function assignability compares preservation relationships after generic
substitution. It may shorten roots and forget ordinary copyable detail; it may not
duplicate an obligation, lengthen a root, or promise preservation from a source the
implementation consumes elsewhere.

## Module summaries and invalidation

Export summaries encode preservation as source-parameter identity plus result-shape
path, not as expanded flow-state snapshots. Cleanup declaration identities use the
existing stable const-function key. Root and region relationships use stable parameter
and field paths. This keeps summaries deterministic across processes and avoids
embedding local flow IDs.

Fingerprints change when the public mapping, result shape, cleanup identity, or
capability-bearing generic bound changes. A private body edit that proves the same
contract does not invalidate importers. Deserialization validates that every stored
path still selects a compatible generic component before admitting the cache entry.

## Diagnostic inventory

Reserve `NUPP2606` for preservation failure. Its variants cover:

- a movable atom lost on one return path;
- one atom mapped to two result components;
- a result component claiming an atom from the wrong source;
- `preserves` paired with a nonconsuming parameter mode;
- incompatible obligation shapes at a branch join; and
- an imported mapping that no longer fits its result shape.

The primary location is the result relation or return expression. Related locations
identify the source declaration, every competing destination, and the move or cleanup
that made a path inconsistent. The code lands with `nupp explain`, a generated
reference entry, a correction example, and a `docs/diagnostics.md` row.

## Implementation order

### P0 — Freeze scalar behavior

- Inventory all current `preserves` syntax, checker state, generated signatures, and
  summaries.
- Add scalar characterization and negative tests.
- Record warm-check, invalidation, summary-size, and memory baselines.
- Verify that `NUPP2606` is unallocated.

### P1 — Conservation IR

- Add source identities and result paths to the canonical capability substitution.
- Represent movable and provenance atoms separately.
- Prove one-to-one movement for the existing scalar case before changing syntax
  acceptance.
- Migrate every scalar preserving signature to an explicit consistent parameter mode
  and delete implicit mode derivation from the result clause.

### P2 — Aggregates and packs

- Recurse through records, structs, tuples, packs, optionals, and nested fields.
- Implement projection, partial moves, and remaining obligation trees.
- Add cleanup-order and transfer-only aggregate tests.

### P3 — Unions, mapped types, and joins

- Implement branch-specific mappings and conservative joins.
- Reject ambiguous ownership merges.
- Add mapped, projected, union, and intersection fixtures.

### P4 — Closures and callable types

- Carry mappings through captures, callable records, assignment, and overloads.
- Implement function relationship assignability.
- Cover nested generic callbacks and returned closures.

### P5 — Modules, tooling, and deletion

- Serialize stable mappings and update fingerprints.
- Add hover, definition, references, inlay, and contract-writing support.
- Delete the scalar-only parallel representation.
- Update reference, ownership, generic, and diagnostic documentation.

Each phase deletes its superseded representation after the final consumer moves. No
subsystem leaves a phase with two authoritative preservation answers.

## Performance gates

Use the baseline and methodology from plan 047:

- unchanged warm checking and private-body invalidation may regress by at most 5%;
- exported-signature invalidation may regress by at most 10%;
- serialized summaries may grow by at most 10% on the compiler-plus-stdlib corpus;
- cache deserialization may regress by at most 10%; and
- checker peak resident memory may regress by at most 10%.

The benchmark reports cache hits, invalidated modules, and summary bytes. Generated
Lua for direct generic forwarding remains byte-identical: preservation adds no
dictionary, wrapper, tag, closure, or runtime branch.

## Verification matrix

Tests must prove:

- all baseline scalar uses retain their behavior;
- obligations and anchors move exactly once while roots and regions propagate;
- an unconstrained capability-bearing source requires `takes`;
- ordinary copyable generic values need no ownership annotation;
- boxes, nested records, tuples, packs, optionals, unions, and mapped types preserve
  the selected subtree;
- partial moves leave the exact remaining obligation tree;
- branch joins never lose or duplicate an atom;
- closures and callable records retain mappings through assignment and invocation;
- mappings survive import, incremental cache reuse, and overload selection;
- malformed or stale summaries are rejected deterministically;
- every preservation failure reports `NUPP2606` with actionable related locations;
  and
- generated direct-call representation and ABI remain unchanged.

## Completion criteria

This plan is complete when:

- `preserves` is defined as conservation rather than copying;
- parameter-mode consistency has one direction and one diagnostic;
- every supported generic result shape substitutes complete capabilities;
- projections and partial moves update obligation trees exactly;
- closures and callable types carry preservation relationships safely;
- public summaries are deterministic and private proof changes do not invalidate
  importers;
- the scalar-only implementation is deleted;
- `NUPP2606`, documentation, tooling, and fixes are complete; and
- the full suite, fixpoint, bootstrap, representation, and performance gates pass.
