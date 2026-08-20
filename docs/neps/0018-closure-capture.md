---
title: Closure capture
status: Implemented
created: 2026-08-19
---

## Summary

A closure states what it takes, and borrows everything else. A capture is a
tracked borrow by default, leaving the obligation with the enclosing scope. A
closure with a `takes` list moves those values in, becomes affine itself, is
called at most once, and discharges what it took whether it is called or
dropped.

[Ownership](../concepts/ownership.md) documents the surface.

## Goals

- Let a closure use an owned value without the enclosing scope losing its proof.
- Let a closure own a value when that is what is meant, without weakening the
  discharge guarantee.
- Reuse the borrow rules that already exist rather than inventing capture-shaped
  ones.

## Non-goals

- A closure that owns a resource and runs repeatedly.
- Anonymous table storage for borrow-carrying closures.

## Motivation

### An ordinary closure cannot own

A copyable closure may be called twice, never called, or stored past the scope
that was to discharge what it captured. None of those are compatible with a
value that must be released exactly once. So an ordinary closure could not
capture an owner at all, which made a large class of ordinary code
unexpressible.

### But the capability model already had the answer

An affine value has exactly the discharge discipline the proof needs. A closure
that takes ownership can simply *be* affine — not copyable, called at most once,
its call being its discharge — and then no new rule is required. What moved is
what closures may express, not what the checker proves:

```text
 Fact                                   Before                  After
 ─────────────────────────────────────  ──────────────────────  ────────────────
 Ordinary closure reads an owner        Rejected                Tracked borrow
 Ordinary closure captures a borrow     Rejected outside a      Allowed, tracked
                                        non-escaping parameter
 Affine closure captures an owner       Inexpressible           Discharge travels
```

## Overview and specification

### Syntax

```nupp
function(): R takes (names) borrows (names)
```

Both clauses take a parenthesised list and compose. The borrow contract is
required in type position and optional on a literal.

### Usage

A capture is a tracked borrow unless the closure says otherwise:

```nupp
local scratch = buffers.acquire()

local read = function(): string
    scratch:clear()          -- borrowed; the enclosing scope still owns it
    return handle:read(8)
end
```

`takes` moves, and a closure that takes anything is itself affine — called at
most once, with the call as its discharge:

```nupp
local send = function(): nil takes (handle)
    handle:write(payload)
end

send()                       -- discharges handle
```

The two clauses compose when a closure moves one capture and borrows another:

```nupp
function(): any takes (handle) borrows (scratch)
```

### Lowering

Capture is Lua's own upvalue capture, so a borrowing closure generates exactly
what an untyped one would:

```lua
local read = function()
   scratch:clear()
   return handle:read(8)
end
```

A taking closure is an affine value, so the enclosing scope's obligation moves
into it and its discharge is the closure's. A closure built and never called is
dropped at scope exit, running the drop of everything it took:

```lua
local send = function() handle:write(payload) end
-- at scope exit, if send was never called:
__nuppCleanup1(handle)
```

The clauses themselves erase; nothing records a capture list at run time.

### Borrow is the default because it is the common case

Naming an owner in a body borrows it; the enclosing scope keeps the obligation
and the closure stays an ordinary copyable function. Moving requires saying so.

The default is the one that preserves the most: a borrow can be turned into a
move by writing a clause, where the reverse would mean the enclosing scope
silently lost a value by mentioning it.

### Capturing closures are affine

A closure with a `takes` list is affine by the same rule that already makes a
record with an affine field affine. Nothing new is asserted about closures
specifically.

Dropping such a closure discharges what it took. Called or dropped, the
obligation is discharged exactly once, which is the whole requirement.

### A borrowing closure is governed by the borrow rules that already exist

Capturing by borrow gives the closure a borrowed callable capability rooted at
the source. Every rule already governing a borrow governs it: not returned
without a contract, not outliving its source, no anonymous storage.

A non-escaping callback parameter previously admitted such a closure on the
strength of the callee proving non-escape. Giving the closure a borrow contract
extends that proof through the general provenance rules instead of a
special case.

### The clauses compose

A closure may take some captures and borrow others in one signature. A single
clause cannot express that, which is the concrete reason the design is not one
list with a modifier.

The contract is required in type position and optional in expression position: a
field or parameter has no body to infer from and must name its sources, while a
literal borrows by default and pins the contract only when it says so.

### Where a borrow-carrying closure may be stored

A nominal record may hold one, because a record may hold a declared borrow and
is transitively constrained by it, and the provenance names a sibling field
rather than a caller's local — so it crosses a function boundary without naming
anything out of scope. A runtime number of them has a container that moves an
owner in and hands back a borrow tied to that container.

Anonymous table storage stays rejected: there is no declaration to carry the
constraint, so nothing propagates the provenance.

## Risks and assumptions

- **Affine closures are single-shot, permanently under this design.** No closure
  form owns a resource and runs repeatedly. A repeatable callback may borrow its
  captures, which covers most cases and not all, and the gap is real rather than
  temporary.
- **The default is invisible in the source.** A closure that mentions an owner
  borrows it, and nothing at the mention says so. That is the right default and
  it means understanding the lifetime of a captured value requires knowing this
  rule.
- **Provenance through closures is where the model is hardest to explain.** A
  rejected program here involves a root the programmer never named, inside a
  value whose captures are implicit.

## Alternatives considered

**Making capture-by-move the default.** Rejected: an enclosing scope would
silently lose a value by mentioning it in a nested function, and recovering it
would require a clause on every ordinary closure.

**Giving closures their own ownership rules** rather than making a capturing
closure affine. Rejected: affine values already have the exact discipline
required, so a separate rule set would be a second implementation of the same
theorem with its own gaps.

**A single capture list with per-name modifiers.** Rejected because the two
clauses genuinely compose — a closure may take one value and borrow another —
and a single list would need per-entry syntax to say the same thing.

**Allowing anonymous table storage for borrow-carrying closures.** Rejected:
nothing declares the constraint, so the provenance has nowhere to live. The
motivating case is instead a contextual aggregate consumed immediately by its
callee.

**Requiring a borrow contract on every closure literal.** Rejected: literals
have a body to infer from, and requiring the clause everywhere would put
ownership plumbing into closures that never touch an owned value.

**Bare `takes name` without parentheses.** Deferred rather than rejected. It
reads well, adds a grammar branch, and changes nothing about soundness or
expressiveness — so it is not worth doing before the model is complete.
