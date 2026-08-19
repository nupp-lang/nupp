---
title: Native kernels over checked spans
status: Implemented
created: 2026-08-19
---

## Summary

A checked span is the public boundary for pointer-and-count native kernels: the
representation is private, element type and count stay attached to the view that
established them, writable ranges can be partitioned without inventing
overlapping aliases, and a Nupp-owned native allocation cannot forget its
length. A C-declaration adapter lowers logical span arguments to the physical
pointer-and-count ABI.

[C interoperation](../concepts/c-interop.md) documents the surface.

## Goals

- Make the safe route the only route: no shorter unchecked path around the
  guarantee.
- Keep a span's element type concrete through generic projection.
- Let a writable range be split into disjoint pieces without producing
  overlapping aliases.

## Non-goals

- A second slice type. This extends the existing span, and adds no parallel
  abstraction.
- A runtime sandbox. Privacy is a static checked boundary; generated code and
  explicit unsafe interop keep their existing trust model.
- Making the private representation an ABI promise.

## Motivation

### A public field is a shorter route around the proof

With pointer, offset, and count all public and readable, a caller could pass the
pointer with the count and *drop the offset* — producing a call that checks
cleanly and reads the wrong memory. The span carried enough information to be
safe and did not require it to be used.

Adding a partitioning operation on top of that would have been unsound: the
guarantee would hold on the path that used it and be trivially avoidable beside
it.

### Module-local types cannot be a public boundary

The span types were local declarations, so another module could not name them in
a public signature — which makes them unusable as *the* boundary for native
kernels, whatever their internal guarantees.

### Generic projection was losing the element type

An inferred projection exposed an unsubstituted element type, so the concrete
type a caller established did not survive to the place it mattered.

## Overview and specification

### Privacy is what makes the guarantee hold

Module-private record fields exist because of this. The anchor, pointer, and
offset are hidden; every pointer projection goes through a borrowed method that
applies the offset.

A count stays public and immutable, because a count alone grants no memory
access — which is the test for what may be exposed.

### A shared span cannot project a mutable pointer

The shared form stores a const pointer. Only a live writable span can project a
mutable one, which is what keeps the read and write capabilities from being the
same value with different names.

### Prerequisites are not optional here either

Making the fields private, making the types module-visible, and preserving
concrete element types through projection were all prerequisites rather than
polish. Adding partitioning without them would have left shorter unchecked
routes and made the partition guarantee unsound.

That ordering — close the routes around a guarantee before adding the guarantee
— is the transferable part.

## Risks and assumptions

- **The private representation must never become an ABI promise.** It is not
  C-reifiable and nothing outside the module may depend on its shape. That is
  easy to violate accidentally the first time something wants to pass a span
  through a boundary that copies bytes.
- **Privacy is static, not enforced at run time.** Generated code and explicit
  unsafe interop can still reach the fields, and the guarantee holds only for
  checked Nupp.
- **Module-private fields are a general language feature introduced for a
  specific need.** They are useful well beyond spans, and were designed against
  one use case.
- **Method-mediated projection has a cost.** Every pointer access goes through a
  borrowed method rather than a field read, and the assumption is that this
  optimizes away wherever it matters.

## Alternatives considered

**Adding a reference or partition operation without hiding the fields.**
Rejected: shorter unchecked routes would remain, so the partition guarantee
would be sound only for callers who chose to be safe.

**A second slice type** with the stronger guarantees, leaving the existing one
alone. Rejected: two slice types is two sets of conversions, two sets of
adapters, and a permanent question about which one an API should take.

**Keeping pointer and offset public and documenting the correct usage.**
Rejected: the failure it invites — passing pointer and count without the offset
— checks cleanly and reads wrong memory.

**Exposing the representation as an ABI.** Rejected: it would freeze an internal
layout and make every future change to span internals a compatibility break.

**Runtime enforcement of privacy.** Rejected as out of character for the
language: everything else here is a static boundary with generated code trusted,
and a runtime check would cost on the path this exists to make fast.

## FAQ

**Why is the count public when the pointer is not?** Because a count alone
grants no memory access. That is the rule for what may be exposed.

**Can another module name these types in a signature?** Yes — they are genuine
module-visible types. That was a prerequisite for using them as a boundary.

**Can I get a mutable pointer from a shared span?** No. Only a live writable
span projects one.

**Does the private representation have a stable layout?** No, and nothing may
depend on it.
