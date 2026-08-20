---
title: View and span lowering
status: Implemented
created: 2026-08-19
---

## Summary

Checked views get ordinary operator syntax — length, index, indexed assignment,
and direct indexed field projection — behind one indexed-view descriptor, with
separate physical adapters for contiguous and columnar storage. An optimization
pass turns a checked access inside the loop dominated by its range witness into
unchecked pointer arithmetic, and a further pass represents non-escaping view
roots as compiler-owned scalars instead of allocated wrapper records. None of it
applies to arbitrary user types.

[Performance](../guides/performance.md) documents the observable behaviour.

## Goals

- Make checked views cost what handwritten unchecked FFI code costs, in the
  loops where that matters.
- Give views one surface syntax regardless of physical storage.
- Validate once, per range, rather than per access.

## Non-goals

- A generic metamethod optimization.
- An unchecked public view API.
- Inferring bounds from user-written conditionals.
- New bytecode, native helpers, or a runtime fork.

## Motivation

### A checked view that costs more than a pointer does not get used

The whole argument for checked spans ([NEP 24](0024-native-kernel-spans.md)) is
that the safe route should be the only route. That holds only if it is also the
fast route — otherwise the hot loop is written with raw pointers and the
guarantee applies to the code that did not need it.

### The proof exists at the range

A range witness validates every participating view once. Every access inside the
loop it dominates is then already proved in bounds. Re-checking each one is
paying repeatedly for a fact established once.

### Two element APIs is one too many

Spans and column storage each had their own element methods, so generic code had
to pick, and the two surfaces had to be kept in step by hand.

## Overview and specification

### Syntax

Operators, not methods, and one range witness per loop:

```nupp
#view                -- length
view[index]          -- read
view[index] = value  -- write
view[index].field    -- direct indexed field projection
indexed.range(first, last, ...)
```

### Usage

```nupp
const rows = indexed.range(first, last, output, input)
for index = rows.first, rows.last do
    output[index].x = input[index].x + 1
end
```

The range call validates every participating view once, at the place the source
wrote it. The same spelling works over contiguous and columnar storage.

### Lowering

Without the range witness, each access carries its own bounds check:

```lua
for index = first, last do
   if index < 1 or index > output.count then error("out of bounds", 2) end
   if index < 1 or index > input.count then error("out of bounds", 2) end
   output.__base[output.__offset + index - 1].x =
      input.__base[input.__offset + index - 1].x + 1
end
```

Inside a loop dominated by the witness, the repeated accesses lower to ordinary
FFI pointer arithmetic — no bytecode, native helper, or runtime fork:

```lua
local __out = output.__base + output.__offset - 1
local __in = input.__base + input.__offset - 1
for index = rows.first, rows.last do
   __out[index].x = __in[index].x + 1
end
```

A non-escaping view root is represented as compiler-owned scalars rather than an
allocated wrapper record — a runtime fat pointer, not a compile-time fiction:

```text
contiguous view = anchor + typed base + offset + count + capability
SoA row view    = slab anchor + columns/layout + offset + count + capability
```

so the locals above are the whole representation. The safe runtime object is
still materialized when a view escapes or reaches a dynamic boundary.

### Element access is operators

Length, indexing, indexed assignment, and direct indexed field projection are the
ordinary surface. The previous public element methods are gone: private runtime
fields and checked helpers may implement the operators, but they are not callable
APIs.

**This is not a generic metamethod optimization.** An arbitrary length or index
implementation does not establish that its length bounds its indexes, that an
access is pure, or that an indexed field denotes stable storage. Only a sealed
standard type whose implementation is registered with the checker receives the
trusted descriptor; ordinary metamethods keep ordinary dispatch.

### One proof and two physical adapters

Contiguous and columnar storage share one checked descriptor and differ in their
physical adapter. That is what lets the source surface be
representation-independent without making the two view types interchangeable —
which [NEP 29](0029-structure-of-arrays.md) requires them not to be.

### Range-dominated accesses lower to pointer arithmetic

The range call stays where the source wrote it and validates once. Only repeated
accesses whose receiver and index are already marked as range-proven are
eligible, and the backend emits ordinary FFI pointer arithmetic — no bytecode, no
native helper, no runtime fork.

The first implementation is deliberately specific to the sealed standard
contracts, using a small generic representation for "this induction variable is
in bounds for this stable view" rather than recognising arbitrary methods.

### Non-escaping roots become scalars

A view root that does not escape is represented as compiler-owned scalar values
— anchor, typed base, offset, count, capability — rather than an allocated
wrapper record. The safe runtime object remains the materialization form for
escapes and dynamic boundaries.

The target is a runtime fat pointer, not a compile-time-only fiction: element
type, adapter, capability, borrow lifetime, and a fixed count where one exists
are static, while base, count, offset, columns, and anchor may be dynamic values
living in locals or flattened arguments.

### Column storage was a landing condition

The operator work did not land unless direct field loops over columnar storage
stayed within the existing handwritten FFI ceiling and allocated no row proxies.

Making the harder consumer a landing condition rather than later work is what
kept the descriptor from being shaped around the easy case.

## Risks and assumptions

- **The performance claim is against a handwritten FFI ceiling.** That ceiling
  is a moving target, and the guarantee is only as good as the benchmarks
  defending it.
- **Sealed-type-only is a real asymmetry.** A user type that genuinely has the
  same properties cannot get the same lowering, and there is no mechanism for it
  to prove them.
- **Scalar replacement makes escape analysis load-bearing for correctness of
  cost, not just speed.** A view that unexpectedly escapes silently materializes,
  and the loop that was supposed to be allocation-free is not.
- **Removing the public element methods was a breaking change** with the
  operators as the only replacement.

## Alternatives considered

**Keeping per-access bounds checks** and relying on the JIT to hoist them.
Rejected: the check depends on values the trace compiler cannot always prove
invariant, and the range witness already establishes the fact exactly.

**A generic metamethod-based optimization**, so any type with a length and an
index could get the same lowering. Rejected: none of the required properties —
length bounds index, access is pure, indexed field denotes stable storage —
follow from having the metamethods.

**An unchecked public view API** for hot code. Rejected: it is the shorter
unchecked route [NEP 24](0024-native-kernel-spans.md) exists to eliminate.

**Inferring bounds from user-written conditionals.** Rejected for the first
implementation: it is a much larger analysis, and the range witness gets the
same result with an explicit, auditable proof.

**Keeping separate element APIs** for contiguous and columnar views. Rejected:
generic code had to choose, and the two surfaces drifted.

**Making column storage a follow-up consumer.** Rejected: the descriptor would
have been shaped around contiguous storage and then retrofitted.

**Compile-time-only virtualization** of view roots, with no runtime
representation. Rejected: escapes and dynamic boundaries need a real object, and
a fiction with no materialization form cannot provide one.
