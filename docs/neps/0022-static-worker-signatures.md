---
title: Statically refused worker signatures
status: Implemented
created: 2026-08-22
---

## Summary

A submitted function's parameter and result types are checked where the task is
written. A type no copy between isolated Lua states could reproduce is refused
there, naming the path to it. Types that describe values which may or may not be
copyable are left to the copy, which keeps its walk.

## Goals

- Report a signature that can never cross, at the call site, with the path.
- Refuse nothing that works today.
- Turn an internal-sounding failure about an ownership mode into a reason.

## Non-goals

- Deriving the codec from the signature. That is a separate performance change,
  and it stays in the backlog.
- Deciding whether a record can cross. That question is about the receiving
  state, not about the sender's types.
- Removing the run-time walk.

## Motivation

[NEP 20](0020-structured-worker-tasks.md) copies arguments and results between
lanes, and `unsendable` walked every value to decide whether a copy was possible.
A function-typed parameter therefore reported a mistake once a call reached it,
though the signature said so before the program ran.

[NEP 21](0021-addressable-callables.md) settled the same question for the
callable itself. The values it takes and returns are the other half.

## Overview and specification

### What is refused

A type is refused when no value of it could ever be copied: a function, a
thread, userdata, cdata, a C pointer or array, and a parameter carrying an
ownership mode. The walk descends arrays, tuples, unions, intersections, and
shapes, so the refusal reports `argument 1.hook` rather than `argument 1`.

### What is not

`any`, a bare `table`, and a record are left to the copy. None of them says from
the type alone that no copy could arrive, and a record is the sharpest case: the
same declared type is a plain table when it was built from a table literal and
carries a metatable when it was built with `new`, so refusing the type would
refuse programs that work today.

Identity is a property of values rather than of types. A cycle, a repeated
table, and depth are therefore decided while copying whatever a signature said,
and a recursive shape is a valid type that builds a cyclic value. The static
rule is necessary, never sufficient.

### Where it is checked

At submission, not on the handle. `workers.Task<F>` derives a handle from a
signature and describes no crossing, so naming one is not held to this; the
parameter pack `spawn` takes is.

### Ownership modes first

A pack carrying a mode other than `plain` cannot be rebuilt by the type
blueprint at all, and reported that rather than the reason. The mode is
therefore checked before the types are walked, so `takes value: File` reports
that argument 1 is an owner.

## Risks and assumptions

- The rule is a comptime function rather than a nameable bound. A caller's own
  generic wrapper around `spawn` therefore reports inside the wrapper rather
  than at its caller. A `nupp.Sendable` bound would move it, and needs a
  structurally satisfied marker interface the bounds checker does not have.
- Leaving records dynamic keeps the surprise that construction decides whether
  one crosses. The fix is for the receiving lane to re-attach a metatable by
  nominal name, the way it already requires a module to find an entry point;
  until then the type cannot honestly refuse or accept them.
- Anything reaching a task through `any` is unchecked by construction, which is
  the gradual bargain rather than a hole to close.

## Alternatives considered

**Refusing records.** It would make the static rule match today's copy exactly,
at the cost of refusing `{x = 1, y = 2} as Point`, which crosses correctly now.
Matching an implementation's current limits is not the same as describing what
can never work.

**Checking inside `Task<F>`.** One place instead of two, but it makes naming a
handle type an error when nothing is being submitted, and a handle is derived
from results alone.

**Leaving it to the derived codec.** The encoding change in the backlog would
compute the same answer as a by-product, but it is a much larger change and the
diagnostic is the part that is worth having first.
