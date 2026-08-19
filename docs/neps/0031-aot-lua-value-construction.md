---
title: Lua-value construction in AOT functions
status: Implemented
created: 2026-08-19
---

## Summary

A second calling convention for ahead-of-time functions. One that only consumes
and produces native scalars, structs, and spans keeps the existing kernel ABI;
one that constructs fresh Lua tables or strings lowers to a Lua C function and
builds its result through a verified construction IR. The source stays ordinary
Nupp — no VM state pointer, raw VM calls, collector pointers, stack indexes, or
second embedded language.

## Goals

- Let a native function return a Lua value graph without giving up the
  ordinary-Nupp-source invariant.
- Prove every managed value is created, rooted, populated, and returned safely.

## Non-goals

- Arbitrary table operations, metatables, dynamic calls, callbacks, coroutines,
  userdata, or general Lua execution inside an ahead-of-time function.
- Exposing the VM's C API in any form.

## Motivation

### The kernel ABI stops exactly where the useful work ends

A native kernel that fills a span is fast and returns nothing a program can hand
to ordinary Lua code. A parser, a decoder, or any function whose output *is* a
Lua value graph has to either return through a span and rebuild the graph in Lua
— paying the cost the native path existed to remove — or be excluded.

### Exposing the VM's C API is the wrong answer

The obvious mechanism is to let the body call the VM directly. That reintroduces
everything [NEP 28](0028-checked-aot-functions.md) exists to avoid: a second
language in the body, unchecked stack discipline, and rooting rules the compiler
cannot verify.

## Overview and specification

### A checked object-graph constructor, not a native Lua VM

The compiler recognises a small set of ordinary operations by resolved identity
and proves the safety properties itself. The initial subset is primitives, fresh
table literals and capacity-hinted table construction, raw-equivalent writes to
fresh tables, strings copied from proved ranges of rooted inputs, a checked
strictly-local buffer path for derived strings, structured control flow, admitted
pure helpers, and returning the completed graph.

The boundary is stated as what it *is*, not as a list of exclusions: a
constructor for a value graph the function itself creates. Anything that would
observe or mutate pre-existing managed state is outside it.

### Two conventions, one annotation

Which convention a function gets follows from what it consumes and produces, not
from a second annotation. A function that stays in native types keeps the kernel
ABI; one that constructs managed values gets the VM-aware one.

## Risks and assumptions

- **The recognised-by-identity approach is brittle to refactoring.** The
  compiler matches specific resolved operations, so an equivalent
  hand-written spelling is not admitted, and the reason will not be obvious.
- **The subset will be asked to grow toward general Lua.** Each addition looks
  small and the aggregate is a native VM implementation. The stated boundary —
  values the function creates — is what each request has to be tested against.
- **Two calling conventions is a real complexity cost** in the backend, the
  wrapper generation, and everything that reasons about an ahead-of-time
  function's ABI.
- **Rooting correctness is proved, not tested.** A defect there is a
  collector-visible memory error rather than a wrong answer.

## Alternatives considered

**Returning through a span and rebuilding in Lua.** The status quo. Rejected: it
pays exactly the cost the native path existed to remove, on the output side.

**Exposing the VM's C API inside the body.** Rejected: unchecked stack
discipline, unverifiable rooting, and a second language in a body that is
supposed to be ordinary Nupp.

**A separate annotation for value-constructing functions.** Rejected: the
distinction follows from what the function consumes and produces, so requiring
the programmer to state it would be asking them to repeat something already
known.

**Admitting general Lua operations** — metatables, dynamic calls, coroutines —
so the subset is less surprising. Rejected: that is a native implementation of
the VM, which is a different project with a different risk profile.

## FAQ

**Can an ahead-of-time function return a table?** Yes, if it constructed it, and
if every operation building it is in the admitted subset.

**Can it modify a table the caller passed in?** No. The subset covers values the
function creates.

**Does my source change?** No. It is ordinary Nupp; the convention follows from
the types.

**Why can't I call an equivalent function I wrote myself?** Operations are
recognised by resolved identity, so only the admitted ones lower. That is a real
limitation of the current subset.
