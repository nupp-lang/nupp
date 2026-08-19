---
title: Fixed-width names as checked refinements
status: Implemented
created: 2026-08-19
---

## Summary

`float`, `int32`, and `uint32` are refinements of `number` denoting unboxed Lua
numbers in the corresponding value set. Widening to `number` is implicit and
emits nothing; entering a refinement requires an establishing operation. The
narrower names — `int8` through `uint16` — become storage-position-only, valid
in struct fields, C arrays, span elements, and `cdef` declarations, and
diagnosed on ordinary values. No operator acquires binary32 or wrapping
semantics, and no scalar becomes cdata.

[Refinements](../type-system/refinements.md) and
[primitives](../type-system/primitives.md) document the surface.

## Goals

- Make a fixed-width annotation mean something a reader can rely on.
- Keep every one of these a plain unboxed Lua number.
- Give AOT lowering and reified storage a value fact they can act on.

## Non-goals

- Binary numeric promotion. Ordinary arithmetic over these refinements yields
  `number`.
- `int64` and `uint64`. Their value sets are not representable in binary64 and
  LuaJIT boxes them as cdata, which is a different design.
- Changing what any accepted program computes.

## Motivation

### The annotation was a claim nothing established

A fixed-width name in a value position asserted a property that nothing checked
and nothing produced. Annotating a local as `float` and casting a `number` to
`float` both generated exactly the same Lua as writing neither, so the
annotation carried no fact — not for the reader, not for the checker, and not
for any consumer downstream.

That is the worst state for a type to be in. An absent feature is a limitation;
a feature that reads as a guarantee and is not one is a source of wrong beliefs,
and everything built on top of it inherits them.

### Downstream consumers need the fact to be real

Reified struct layout, C array elements, span element types, and AOT scalar
lowering all want to know that a value is in a fixed-width set. Each of them can
only use that if establishing it is an operation rather than an assertion.

## Overview and specification

### Establishment is a dataflow fact, not an annotation

A value enters a refinement through an establishing operation —
narrowing, rounding, wrapping, or reinterpreting bits. An erased assertion may
claim the type and does not establish the value.

This is the whole design. Everything else follows from separating "this
expression is known to be in the set" from "someone wrote the name down".

### Arithmetic deliberately does not change

Every ordinary arithmetic operator over these refinements yields `number`.
Container origin, lexical position, and whether the code is AOT-compiled play no
part; storing a result into reified fixed-width storage performs the final
narrowing.

There is no binary numeric promotion, because introducing one would mean an
existing expression started computing something different depending on how its
operands were annotated. The fixed-width namespaces remain the one explicit
spelling for same-width operations, with checked signatures requiring
established inputs and producing established results.

### Narrow names become storage-only

`int8`, `int16`, `uint8`, and `uint16` are valid where a storage width is the
point and diagnosed where a value type is. A load widens them into a value
refinement: signed storage produces `int32`, unsigned produces `uint32`.

These widths have no distinct unboxed value representation in Lua — every one of
them is a binary64 number at rest. Naming them as value types would recreate
exactly the empty claim this design removes, while naming them as storage widths
says the thing that is true.

### Nothing becomes cdata

No scalar acquires a box, a metatable, or a metamethod. This constrains the
design permanently and is the reason `int64` stays outside it.

## Risks and assumptions

- **Existing source breaks.** Any unproved fixed-width claim now reports, and
  must either widen its annotation or establish its value. That is the intended
  outcome and it is still a migration with no deprecation window.
- **"Arithmetic yields `number`" will read as a bug.** A user who writes
  `float * float` and gets `number` will assume the refinement is not working.
  It is working; the alternative is promotion, which changes results. This needs
  to be said wherever the refinements are documented, not only here.
- **Establishment is easy to lose.** Passing an established value through
  anything typed `number` and back requires re-establishing it. Whether that is
  a papercut or a wall depends on how much of the standard library is typed in
  terms of the refinements, and that is not settled.
- **The value/storage split is a second thing to know.** A reader has to learn
  that `uint8` is a legal field type and an illegal local type, which is not
  guessable from either name.

## Alternatives considered

**Leaving the names as erased annotations.** The status quo. Rejected: an
annotation that reads as a guarantee and establishes nothing produces wrong
beliefs, and every downstream consumer that wanted the fact could not use it.

**Making fixed-width scalars cdata**, with real widths and real wrapping. This
is what LuaJIT does for 64-bit integers and it is the only way to get true
binary32 semantics. Rejected: it boxes every value, adds a metatable, changes
what arithmetic computes, and would make a `float` local slower than a `number`
one — trading the entire performance story for exactness that almost no caller
asked for.

**Binary numeric promotion**, so operations over refinements stay in the
refinement. Rejected because it silently changes computed results based on
annotations, which contradicts the rule that types do not change what a program
computes. Explicit same-width namespaces give the same capability where it is
actually wanted, at a call the reader can see.

**Keeping the narrow names as value types.** Rejected: they have no distinct
unboxed representation, so they would be exactly the empty claim being removed.

**Including `int64` and `uint64`.** Rejected on representation: their complete
value sets do not fit in binary64, and LuaJIT already boxes them. Bringing them
in would mean either lying about the value set or admitting cdata into the
model.

## FAQ

**Why is widening implicit and narrowing explicit?** Widening to `number` loses
no information and emits nothing. Narrowing is where a value can change, so it
is an operation with a name.

**Does an `as` cast establish a refinement?** No. It may claim the type; it does
not establish the value. That distinction is the design.

**What does a fixed-width struct field give me, then?** A real storage width and
a load that produces an established value refinement — which is the fact AOT
lowering and reified layout need, obtained where it is genuinely true.

**Does any of this change generated code for programs that already checked?**
Only where a program made an unproved claim, which now reports rather than
compiling. No accepted program silently changes bits.
