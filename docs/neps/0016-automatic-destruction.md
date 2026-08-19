---
title: Automatic destruction and exact affine scopes
status: Implemented
created: 2026-08-19
---

## Summary

A binding still holding a live ownership obligation at lexical scope exit is
destroyed automatically, using the exact ordered cleanup the value carries.
`with` remains beside it, meaning something automatic destruction does not
provide: it moves the owner into an inaccessible slot and exposes only a
non-escaping borrow, guaranteeing one exact extent.

[Ownership](../concepts/ownership.md) and
[exact affine scopes](../concepts/exact-affine-scopes.md) document the surface.

## Goals

- Make the shortest accepted program the error-safe one.
- Keep cleanup exact: the operations the value actually carries, in order.
- Keep a way to say "this extent, exactly, and the value cannot escape it".
- Add no second cleanup runtime, and leave code with no owner byte-identical.

## Non-goals

- Inferring a destructor from a method name.
- Replacing producer-specific cleanup with a type-level destructor.
- Attaching a finalizer.
- Choosing a terminal action for an owner that declared none.

## Motivation

### Restating cleanup stopped supplying proof

The original design kept ordinary ownership fully erased and made an explicit
construct the only opt-in to protected cleanup. That made the cost of emulating
`finally` on LuaJIT visible, and forgetting cleanup was still a compile error.

Once the checker knew, for every value slot, whether an obligation was live,
moved, discharged, retained, or opaque — along with the producer-specific
ordered operations, every borrow root, and capability transport through
generics, packs, narrowing, fields, modules, and foreign results — requiring the
programmer to restate the final cleanup no longer supplied proof the compiler
lacked. It supplied only *timing*.

At that point the useful default is the one Rust has: the binding that owns a
value destroys it at the end of its lexical scope unless responsibility moved
elsewhere.

### A diagnostic is a backstop; a safe default removes an iteration

This matters most for generated and machine-written FFI code. A compile error is
a good backstop and it still costs a repair cycle. Explicit syntax should remain
for early release, exact extents, transfer, and meaningful protocol transitions
— not for the ordinary case.

## Overview and specification

### Destruction is exact, not inferred

Automatic destruction runs the exact ordered cleanup capability the value
carries. It does not infer a method from a name, substitute a type-level
destructor for producer-specific cleanup, attach a finalizer, or pick a terminal
for an opaque owner.

Every one of those would be a guess, and a guess about how a resource ends is
the failure this whole area exists to prevent.

### One planner, and no cost when unused

Automatic locals and the explicit construct lower through one cleanup-region
planner. Equivalent source produces equivalent generated Lua, and ordinary code
with no owner is byte-identical to output from before the feature existed.

Two cleanup mechanisms would have been two sets of ordering rules, two
interactions with early exits, and two things to keep agreeing across every
future control-flow feature.

### `with` means bounded borrowed extent

An ordinary automatic owner remains movable, returnable, and explicitly
droppable. The explicit construct moves the owner into an inaccessible cleanup
slot and exposes only a borrow for one exact region: the visible binding cannot
move, escape, be returned, or be dropped early.

That is a different guarantee, not a more emphatic version of the same one.

### The prerequisites are not optional

Automatic destruction rests on the capability and value-slot model, its
transport rules, and its boundary rules. Any port of this decision to a compiler
without them must land those first, and **must not substitute payload-type or
syntax-based cleanup inference** — which is the shortcut that looks equivalent
and silently discharges the wrong obligation.

## Risks and assumptions

- **Timing became implicit.** A reader now has to know that scope exit destroys.
  That is the point, and it means the moment a resource is released is no longer
  visible at the release site — only at the declaration and the scope boundary.
- **The prerequisite list is long and unenforced.** Nothing prevents a future
  change from weakening one of the transport or boundary rules the safety
  argument depends on. The rules are the theorem; the feature is a consequence.
- **The byte-identical claim needs defending.** It is easy to state and easy to
  break, and once broken it is unlikely anyone notices from behaviour alone.
- **Two constructs for related things invites "which one?"** The answer is
  clean — automatic for ordinary ownership, explicit for a bounded borrowed
  extent — but it has to be said, because the surface similarity suggests they
  are alternatives.

## Alternatives considered

**Fully erased ownership with an explicit construct as the only opt-in.** This
was the original decision and it shipped. Superseded once the checker's
knowledge made restatement redundant: it was asking the programmer for timing
while claiming to ask for proof.

**Removing the explicit construct once automatic destruction landed.** This was
*done*, and then reversed. Automatic destruction handles the general case, so
the construct looked subsumed — but it guarantees something automatic
destruction cannot: that the value is inaccessible and cannot escape, over one
exact extent. Removing it lost that guarantee with nothing to replace it, and
it came back with parser, checker, generator, formatter, semantic tokens,
grammar, reference, and documentation restored alongside.

The transferable lesson: a general feature subsumes a specific one only if it
provides the specific one's *guarantee*, not merely its common use case.

**Finalizers.** Rejected: they run at collection time, which is neither
deterministic nor related to the scope that owned the value, and they cannot
express ordered multi-step cleanup.

**Name-based destructor inference** — treat a `close` or `drop` method as the
terminal. Rejected: it makes an ordinary method name load-bearing, so adding a
method with the wrong name changes when a resource is released.

**A type-level destructor replacing producer-specific cleanup.** Rejected for
the reason in [NEP 15](0015-ownership-in-the-type.md): the same type covers
values that must be released and values that must not.

## FAQ

**Does transferring a value still remove the scope's responsibility?** Yes.
Moving, explicitly dropping, returning, or otherwise transferring removes it
exactly as before.

**What does cleanup cost in code with no owners?** Nothing — that output is
byte-identical to the compiler's output before the feature.

**Which should I write?** Automatic for ordinary ownership. The explicit
construct when the value must not escape the region, or when the exact extent is
part of the contract.

**What happens on an early exit or a raise?** Cleanup runs on every structured
exit; that is what the shared region planner is for.
