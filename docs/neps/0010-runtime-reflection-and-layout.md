---
title: Runtime reflection and struct layout
status: Implemented
created: 2026-08-19
---

## Summary

A declaration is a first-class value whose type is `Type<T>`, and calling
`reflect()` on it allocates and caches one versioned descriptor of the
declaration's facts. `layoutof(T)` answers how a reified `struct` sits in
memory. Format-specific behaviour — a JSON codec, for instance — is a runtime
extension allocated against the descriptor rather than embedded in it. Neither
defines a serialization format or an interface a declaration must implement.

[Reflection](../concepts/reflection.md) and
[C interoperation](../concepts/c-interop.md) document the surface.

## Goals

- Let runtime code ask a declaration what it declares.
- Let a library learn a reified struct's layout — field order, C types, offsets,
  sizes, padding, total size, and a fingerprint over all of it.
- Take one argument. A caller supplies the declaration, never the declaration
  plus a separate witness.
- Pay for a descriptor only when something asks for one.

## Non-goals

- A serialization format or wire protocol.
- An interface a declaration has to implement to be serializable.
- Replacing the comptime reflection surface. The two are distinct and are named
  so they cannot be confused.

## Motivation

### Reification broke the snapshot path

A reified `struct` instance is cdata. `string.buffer.encode` raises on it with
no hook to install, `pairs` needs a metamethod on the metatype, and `type`
answers `"cdata"`. So the largest speedup the language offers is also the change
that breaks saving state — which is why the lint that suggests reification has
to warn about it rather than recommend it freely.

Fixing what reification broke is a different obligation from adding a
serialization framework, and only the first one is the language's.

### The fast path is not a per-value method

In the workload that motivated this, saving a column of components is one
`putcdata` over the whole column — a size and a contiguity guarantee, not a
method call per value. A `Serializable` interface with a `save(buf)` method
would have optimized the case that does not matter and left the case that does
needing exactly what it needed before.

### Two arguments is the design that spreads

The alternative to a first-class declaration value is passing a separate type
witness beside every value. That witness then has to be threaded through every
generic that forwards the call, so a signature that had nothing to do with
reflection acquires a parameter because something three layers down wanted one.

## Overview and specification

### One argument, with hidden evidence

`User` is the only value a caller supplies, and a generic parameter infers
through it. The compiler may pass a descriptor or a codec as hidden evidence at
a typed call site; the public spelling does not change.

This is what keeps reflection from leaking into unrelated signatures. The
evidence is an optimization the caller never writes.

### Descriptors are declaration facts; behaviour is an extension

The descriptor holds what the declaration declares. Format-specific behaviour is
allocated against it on first request and cached there.

A derive therefore declares that a record *admits* an extension and supplies its
checked configuration; it does not materialize or embed a complete codec, and
its generated members are wrappers that obtain the extension at run time.

The alternative — generating a full codec per derive per record — pays for every
format on every declaration that mentions it, at build time and in the shipped
artifact, whether or not the program ever encodes one value.

### Descriptors are allocated on first use and cached

Nothing is built for a declaration nobody reflects on. The descriptor is
versioned, so a consumer can reject a shape it does not understand rather than
misread it.

### Layout answers, and does not prescribe

`layoutof` reports how a struct sits in memory. What to do with that is the
library's business. Only a `struct` has a layout; a record is a table.

The opt-out is load-bearing: a declaration that holds something non-portable
must be able to say so, and a design that assumed every reified struct was
snapshot-safe would be wrong for the first component that holds a pointer.

### Runtime and comptime reflection are separate surfaces

The comptime surface answers during compilation and erases. The runtime surface
allocates a descriptor a program can hold. They are deliberately spelled
differently so a diagnostic or a document cannot be ambiguous about which one is
meant.

## Risks and assumptions

- **Two reflection surfaces is a real confusion risk.** They answer overlapping
  questions at different times and the distinction is not visible from a call
  site alone. Naming is the entire mitigation.
- **The extension cache is open-ended runtime state.** Each descriptor
  accumulates extensions for the formats something requested. Nothing evicts
  them, which is correct for a process that uses a fixed set of formats and is
  unbounded in principle.
- **Descriptor caching is per-declaration global state.** It is immutable once
  built, so it is safe to share, but it is state that outlives any particular
  use and is not obviously so from the call.
- **The layout fingerprint is a compatibility contract nobody declared.**
  Consumers will persist it and compare it across builds. What changes it — and
  therefore what silently invalidates saved data — is determined by the layout
  rules rather than by any versioning policy.

## Alternatives considered

**A `Serializable` interface with a `save(buf)` method.** The obvious
object-oriented answer, and rejected on measurement: the path that matters is a
single bulk copy over a whole column, which needs a size and a contiguity
guarantee. A per-value method optimizes the slow path and does nothing for the
fast one, while adding an interface every declaration has to implement.

**Defining a serialization format in the language.** Rejected as scope. The
consumer that motivated this has thousands of lines of archetype filtering,
custom entries, save listeners, and migration policy — application concerns the
compiler cannot see and should not try to. The language's obligation stops at
answering what a declaration is.

**Passing a separate type witness beside every value.** Rejected: it propagates
into signatures that have nothing to do with reflection, and it gives callers
two things to keep consistent where one would do.

**Embedding a complete codec per derive.** Rejected: it pays for every format on
every declaration at build time and in the artifact, regardless of use. Declaring
admission plus configuration, and allocating the codec on first request, moves
the cost to the programs that incur it.

**Building the descriptor eagerly at declaration.** Rejected for the same
reason at a smaller scale — a program that never reflects should allocate
nothing.

**Reusing one spelling for comptime and runtime reflection.** Rejected: the two
answer at different times with different lifetimes, and a shared name would make
every diagnostic mentioning it ambiguous.

## FAQ

**Why is a declaration's value not an instance of itself?** Because they are
different things, and treating them as one made `Foo is Foo` unaskable. See
[NEP 5](0005-declaration-identity.md).

**What does `layoutof` do for a record?** Nothing — a record is a Lua table with
a metatable and has no layout to report.

**Does reflecting on a declaration cost anything if nobody does?** No. The
descriptor is allocated on the first `reflect()` and cached from then on.

**Can a library add its own extension kind?** That is what the extension model
is for: the descriptor holds declaration facts, and anything format-specific is
allocated against it under its own key.
