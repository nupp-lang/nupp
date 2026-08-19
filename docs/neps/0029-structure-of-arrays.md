---
title: Structure-of-arrays storage
status: Implemented
created: 2026-08-19
---

## Summary

An explicit container family stores the top-level fields of a reified struct in
separate contiguous columns. The struct keeps its array-of-structures layout and
value semantics: column storage is a property of a *container*, not a modifier
that changes what the struct means everywhere. Direct indexed field expressions
keep their ordinary spelling, and the two view types are deliberately not
interchangeable.

[Structure of arrays](../concepts/structure-of-arrays.md) documents the surface.

## Goals

- Make column-major storage available without changing the type of the values
  stored in it.
- Keep the reading and writing syntax identical to the row-major case.
- Make the choice local, visible in the type, and impossible to erase by a cast.

## Non-goals

- A layout modifier on the declaration.
- Reinterpreting live bytes across a layout change.

## Motivation

### One declaration needs both layouts

The same struct value passed to C, returned from a function, or stored alone
wants the canonical layout. A large simulation array wants its columns
contiguous. Both are correct uses of one declaration.

Putting the choice on the declaration forces one answer on both uses and makes
the declaration's nominal identity hide two incompatible physical meanings — so
a value's memory layout would depend on where it came from, invisibly.

### The syntax has to stay ordinary

Column storage is worth having only if the code that uses it reads like the code
that does not. A separate access syntax would make switching layouts a rewrite,
which defeats the purpose of being able to choose.

## Overview and specification

### The container owns the choice, and the type says so

Allocating row-major and column-major storage are two calls, and both load and
store ordinary struct values. Their views are *not* interchangeable: one promises
contiguous objects, the other promises contiguous fields, and no cast or
structural match may erase the difference.

That non-interchangeability is the feature. Two things with the same element
type and different physical meaning must not be substitutable, or the guarantee
is decorative.

### Ordinary field expressions, column storage

Indexed field reads and writes keep their spelling. The lowering knows which
container it is addressing; the source does not change.

### A layout change is a schema change

Changing a container from row-major to column-major is a storage-schema change
even though the value type is unchanged. Hot reload must restart or invoke an
application-owned migration rather than reinterpret live bytes.

Stating this is what keeps a layout change from being silently unsafe under
[NEP 21](0021-hot-reload.md): the value type is identical, so nothing else in
the system would notice.

## Risks and assumptions

- **The performance benefit depends on the access pattern, and nothing checks
  it.** Column storage for a workload that reads whole rows is a pessimization,
  and the type system cannot tell.
- **Two view types is a real surface cost.** Every API that takes a view must
  decide which one, or be generic over both, and the non-interchangeability that
  makes the design sound is what makes that unavoidable.
- **Only top-level fields are columns.** Nesting has to resolve to something,
  and the current answer constrains what a struct in a column container can
  usefully contain.
- **The migration requirement is a convention.** Nothing prevents an application
  from reinterpreting bytes across a layout change; the design can only say that
  it must not.

## Alternatives considered

**A layout annotation on the declaration.** Rejected: it forces one answer on
every use of the type and makes one nominal identity cover two incompatible
physical layouts. A value's memory layout would then depend on its declaration
rather than on where it is stored.

**A distinct element type for column storage** — so a column-stored particle is
a different type from a particle. Rejected: it propagates through every
signature that touches one, and the value semantics genuinely are the same.

**Interchangeable views**, with the layout as an implementation detail behind a
common interface. Rejected: the promises are different — contiguous objects
versus contiguous fields — and code that assumes the wrong one is wrong in a way
that produces plausible garbage.

**A separate access syntax for columns.** Rejected: switching layouts would
become a rewrite, which removes the reason to make the choice local.

**Reinterpreting live storage across a layout change** during hot reload.
Rejected: the value type is unchanged, so nothing else would notice the
reinterpretation was invalid.

## FAQ

**Does my struct change when I store it in columns?** No. It keeps its layout
and value semantics; the container stores its fields separately.

**Can I pass a column view where a contiguous view is expected?** No, and that
is deliberate — they promise different things about memory.

**Does the loop body change?** No. Indexed field expressions keep their ordinary
spelling.

**What happens on hot reload if I change a container's layout?** Restart, or an
application-owned migration. Live bytes are not reinterpreted.
