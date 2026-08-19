---
title: Fields a struct cannot hold
status: Draft
created: 2026-08-19
---

## Summary

A struct would gain three further kinds of field, none of which changes what its
layout is: booleans packed into an implicit word, fields computed on read and
stored nowhere, and fields declared and typed but held beside the instance
rather than inside it. Instances of such a struct would come from a pool owning
the block they live in.

Nothing below exists. The pooled half is **blocked**, on measurement recorded
here, and the unpooled half is worth building without it.

## Goals

- Let the compiler's own hottest data be a struct.
- Keep every field read a direct offset access the compiler understands, rather
  than a metamethod it does not.

## Non-goals

- Changing what a struct's layout is.

## Motivation

A struct is its C layout, and that is the point: fixed offsets, no hash lookup,
no per-field collector object. It is also why the compiler's own hottest data
cannot be one. A token is six numbers, twenty-three flags, two strings, and a
dozen sparse references — and the numbers are the smallest part of it.

The declarations are what would make this worth doing in the language rather
than by hand. A hand-written metatype reaches the same layout, and every field
read then goes through a metamethod the compiler knows nothing about.

## Overview and specification

Packed boolean fields, read-computed fields, and fields stored beside the
instance, with a pool owning the block and the shared data the computed fields
read.

Element references are ordinary values, not borrows. An earlier revision said
borrows and could not have type-checked, because a borrow may not be stored in a
table and the syntax tree stores every token in one.

## Why the pooled stages are blocked

**An element reference does not keep its block alive.** Measured on the proposed
shape: take a reference to an element of a block, let the block become
unreachable, collect, and allocate over the freed region. The read returns a
plausible value from reused memory. Not a crash — a wrong answer.

Chunking fixes reallocation and does nothing about this, so the claim that an
element reference may be stored wherever a token is stored today is false as
written.

Three ways out, and none is good:

**A strong registry.** Pools held by a module-level table, so an element is
valid while its pool is registered and release is a program action. Element
validity then equals pool liveness — which is exactly the ownership model,
applied at the pool rather than the element. But use after release is undefined
and unchecked, so element access becomes an unsafe operation wearing a typed
field's clothes. That contradicts the reason for doing this in the language at
all.

**A reference that carries its anchor** — a pool-and-index pair. Measured at 217
bytes a token against the table's 264, because boxing an eight-byte value as
cdata costs about 200. Dead.

**Leave tokens as tables.** No new unsafety, no saving.

A full provenance analysis — proving that every structure storing an element
also retains its pool, through locals, returns, closures, nested nodes, calls,
unions, and containers mixing pools — is a research-grade lifetime system, not a
stage.

### And the trade has moved

The pooled design saves 3.6x on lexing allocation, which is 38% of what a build
allocates. But the collector is 3–5% of build time, while the trace compiler is
about half. The escape analysis that other optimizations already want attacks
that half, costs no new unsafety, and is the smaller part of an analysis that
already exists.

On this evidence it should come first, and the pooled stages should wait for a
better reason than allocation.

The packed booleans, the read-computed fields over the instance alone, and the
identity diagnostic are unaffected by any of this. They are worth building on
their own.

## Risks and assumptions

- **The measurement is of one workload.** The allocation share and the collector
  share are this compiler's, and a different program could reverse the
  conclusion.
- **"Blocked" is not "rejected".** If a lifetime system arrives for another
  reason, this becomes available, and the reasoning above should be re-checked
  rather than assumed.

## Alternatives considered

The three ways out above, all measured or reasoned to a dead end. Beyond them:

**A hand-written metatype**, reaching the same layout outside the language.
Rejected as the thing being replaced: the layout is the easy part, and the
compiler learns nothing from it.

**Element references as borrows.** Rejected on type-checking: a borrow may not
be stored in a table, and every token is stored in one.

## FAQ

**What can be built today?** The packed booleans, read-computed fields over the
instance, and the identity diagnostic. They do not depend on pooling.

**What would unblock the rest?** A provenance analysis proving that anything
storing an element retains its pool — which is a lifetime system, not a stage of
this work.
