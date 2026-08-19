---
title: Type packs and variadic generics
status: Implemented
created: 2026-08-19
---

## Summary

A Lua value sequence is a first-class type — a pack with a fixed head and an
optional homogeneous, generic, symbolic-slice, or unknown tail — rather than an
array attached to a function type. Parameters, results, call arguments,
assignment values, and return values all use the same representation and the
same adjustment rules. Packs may be unioned, and destructuring a union
correlates its targets so testing one narrows the rest.

[Type packs](../type-system/packs.md) documents the surface.

## Goals

- Preserve heterogeneous arguments and results through generic adapters.
- Model Lua's expansion, truncation, final-expression, and parenthesized-call
  rules once, and use that model in every value-list context.
- Preserve correlation between a result discriminator and the rest of its
  result pack.
- Carry ownership mode and borrow provenance on every value in a pack.
- Type protected calls, selection, unpacking, and coroutines without collapsing
  to `any`.

## Non-goals

- General user-defined type-level computation over packs.
- Numeric indexing, concatenation, mapping, or filtering operators for packs.
- Replacing tuple table types. `{T, U}` remains a runtime table.
- Full session typing that proves the exact number or order of coroutine
  suspensions.
- Dropping arity diagnostics merely because Lua ignores extra call arguments at
  run time.

## Motivation

### Lua's value lists are the language

Multiple returns, varargs, truncation at every non-final position, expansion at
the final one — these are not an edge of Lua, they are how Lua composes.
Modelling them as an array of parameter types with a `vararg` flag beside it
means every context that handles a value list reimplements the adjustment rules,
and they drift.

### Generic adapters were where types went to die

A function that forwards its arguments — a wrapper, a memoizer, a retry — could
not preserve heterogeneous types through an array-shaped signature. The
practical result was `...any` at every adapter, so a typed call that passed
through one came out untyped, and the loss compounded with each layer.

### `pcall` is the case that forces correlation

`pcall`'s first result decides the types *and the ownership obligations* of
every later result. Without correlation the only sound typing is a union per
slot, so every use needs a cast, and the cast is exactly where the ownership
obligation gets lost. Correlation is not a convenience here; it is what makes
the standard library typeable at all.

## Overview and specification

### One representation, one set of adjustment rules

Packs are the authoritative parameter and result sequences. Array-shaped views
remain as compatibility surfaces during migration and must not become a second
source of truth — a rule worth stating because two representations of a value
list is the state this design exists to leave.

### Correlation is flow state, not type

Destructuring a pack union assigns one correlation identity to the targets and
records each target's slot in every arm. A truthiness or literal-equality test
on the discriminator selects compatible arms and narrows every sibling at once.

Correlation is deliberately not part of a local's standalone type. Storing one
result in a table, or returning results separately, drops it. Reassigning a
correlated binding invalidates that binding's correlation, and a control-flow
join keeps only the correlations present and compatible on every incoming path.

Making correlation part of the type would mean a local's type depended on where
it came from, which propagates into every signature that mentions it and makes
two identically typed values non-interchangeable. Keeping it as flow state means
it is precise where it is observable and absent where it is not.

### Syntax follows Luau where it fits

The pack grammar follows [Luau's](https://luau.org/types/basic-types/) where it
fits Nupp's existing function syntax. Nupp adds unions of complete packs, which
Luau does not have and which `pcall` requires.

Following an existing grammar was worth more than any improvement available:
this is notation people either recognise or have to learn, and there is no
version of it that is obvious.

### Effects stay separate

The existing effect and alias analysis remains the source of the boolean fact
that a function may suspend. Typed yield and resume payloads are protocol
information layered on that analysis rather than a second copy of its control
flow graph, call graph, and aliases.

## Risks and assumptions

- **Two representations coexisted during migration.** Array views were kept as
  compatibility surfaces, and the rule that they must not become a second source
  of truth is a convention, not a mechanism. Anything still reading them is a
  place the pack model can be bypassed.
- **Correlation is invisible until it is lost.** A user who stores a result and
  then tests the discriminator gets a union and an error, with nothing saying
  which earlier line dropped the correlation. The rules are principled; whether
  they are discoverable is untested.
- **The pack grammar is a second notation to learn.** It sits beside ordinary
  type syntax and looks similar enough to be confused with it. Following Luau
  limits the damage but does not remove it.
- **Arity diagnostics contradict Lua.** Lua ignores extra call arguments; Nupp
  reports them. This is deliberate and is a place where the superset property is
  about what runs, not about what is accepted.

## Alternatives considered

**Keeping value lists as arrays on function types**, with a vararg flag. This is
what existed. Rejected because the adjustment rules then live in every context
that handles a list rather than in one place, and because heterogeneous forwarding
through a generic adapter is not expressible at all.

**Typing `pcall` as a union per result slot.** The sound alternative to
correlation. Rejected: every use needs a cast to recover the real type, and the
cast is where the ownership obligation attached to a result is silently
discarded. Correlation exists because the type system carries obligations, not
only shapes.

**Making correlation part of the type.** Rejected for the propagation problem
above: it would leak into every signature mentioning a correlated local and make
two identically typed values non-interchangeable.

**Pack operators — indexing, concatenation, mapping, filtering.** Rejected as
out of scope. They are the beginning of type-level computation over packs, which
is a separate design with its own termination and diagnostic questions.

**Replacing tuple table types with packs.** Rejected: `{T, U}` is a runtime
table and a pack is a value sequence. Conflating them would make one syntax mean
two different runtime representations.

**Full session typing for coroutines** — proving the number and order of
suspensions. Rejected as far beyond what the payload typing needed, and as a
commitment that would constrain every future scheduler change.

## FAQ

**Why can packs be unioned when the non-goals refuse pack computation?** A union
of complete packs is an ordinary type constructor applied to packs, not a
computation over their contents. Nothing indexes, maps, or filters.

**What happens to an arm that has no value for a requested slot?** It
contributes `nil` for that slot, after ordinary Lua assignment adjustment.

**Does a copied discriminator still narrow?** Yes — it retains the narrowing
provenance, so testing the copy selects the original sibling set.

**Does existing untyped Lua still work?** Yes. Homogeneous varargs and bare
`thread` remain source compatible; the pack model is a more precise description
of rules Lua already had.
