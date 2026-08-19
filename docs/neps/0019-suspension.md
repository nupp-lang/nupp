---
title: Suspension
status: Implemented
created: 2026-08-19
---

## Summary

Suspension is a first-class, checked, handled effect: an operation a library
performs, a handler a host installs, and a fact the checker tracks. One call
site suspends into a scheduler where one exists and blocks where none does —
with no second API, no `async` colouring, and no library carrying a policy
parameter it did not want.

[Suspension](../concepts/suspension.md) and [effects](../concepts/effects.md)
document the surface.

## Goals

- Let a library that must wait say only that it waits, and let the host decide
  what waiting means.
- Cost nothing when nothing waits, and one context read when something does.
- Give `nosuspend` a rule the checker enforces, rather than a description.

## Non-goals

- **General algebraic effects.** One effect with handlers covers the case. A
  language where any operation can be declared and handled is a much larger
  language, and nothing here needs it.
- **A scheduler.** Nupp supplies the seam and one blocking handler. Task
  scheduling, fairness, and priority belong to whoever installs a handler.
- **Multi-shot continuations.** LuaJIT's are one-shot; a handler resumes once.
- **Async colouring**, preemption, or making compile-time evaluation suspend.

## Motivation

### The alternative is two of every API

Without this, a library that might wait either blocks — making it unusable under
a scheduler — or exposes a second asynchronous surface, doubling its API and
splitting its callers into two populations that cannot share code. The third
option, taking a policy parameter, pushes the decision onto every caller and
into every signature between them.

### It had already been built at library scope

The motivating consumer had hand-rolled the whole mechanism: a mode query
answering *blocking* outside a scheduler, *cooperative* inside a task, and
*forbidden* inside a barrier; a check turning the third into a runtime error
naming the operation; a cooperative wait parking on a gate; a scheduler polling
sources and completing it; a cancelled wait unwinding.

That is an effect handler, confined to one library. Everything in it is
machinery the language can supply once — and the library becomes a handler
rather than being replaced.

## Overview and specification

### An operation, not a function

A library that must wait subscribes for a resumption and performs the operation.
Where the value comes from is not its business, and the innermost installed
handler answers. With no handler installed the built-in one blocks, so ordinary
programs behave exactly as they did.

### The choice costs one context read, at an actual wait

Effect propagation and the forbidding region are compile-time only. An operation
already ready never reaches the suspension point; one that does reads the
current coroutine's handler slot and either calls it or takes the blocking path.

### Handled suspension is not a raw coroutine yield

This is the largest change, and the resource rule is where it shows.

Suspending with a live obligation was rejected, on reasoning that is exactly
right about raw coroutines and exactly wrong about handled suspension: a raw
yield has nobody responsible for it, where a handled suspension transfers
responsibility to a handler that owns the continuation and its cancellation
until the park returns or unwinds.

```text
 Suspension form         Obligation live?   Verdict
 ──────────────────────  ─────────────────  ────────────────────
 raw yield               yes                rejected, unchanged
 raw yield               no                 allowed, unchanged
 handled suspension      yes                allowed — new
 handled suspension      no                 allowed
```

The new row rests on a **trusted handler contract**, not on a fact the checker
proves about an arbitrary scheduler. The invariant is not that a wait eventually
completes — a wait may legitimately remain pending forever while its handler is
live — but that the continuation cannot be abandoned without being woken far
enough to run deterministic cleanup.

Being explicit that this is trust rather than proof is the honest form of the
claim, and it is what makes the boundary auditable.

### The forbidding region becomes load-bearing

The effect was already inferred. Giving it a rule — a region may forbid it, and
a suspending call inside one is refused — required the fact to cross module
boundaries and resolved function values, where the analysis had been
deliberately file-local.

## Risks and assumptions

- **The handler contract is trusted, and it is the safety argument.** A handler
  that abandons a continuation without waking it for cleanup silently breaks the
  resource guarantee, and nothing detects it. The contract is stated as a
  requirement on handler authors, of whom there will be few — which is the only
  reason this is acceptable.
- **One effect, hard-coded.** If a second effect ever wants handlers, this
  design has no room for it and the choice is between a special case and the
  general algebraic effects rejected above.
- **Effect inference now crosses modules.** That makes the fact useful and makes
  it a source of cross-module invalidation, so an edit that changes whether a
  function may wait invalidates its dependents.
- **"Blocks where no handler exists" is a silent default.** A program that
  expected to be under a scheduler and is not will still work, slowly and
  serially, rather than reporting.

## Alternatives considered

**General algebraic effects**, with user-defined operations and effect rows.
Rejected as a much larger language than anything here needs. Nupp borrows the
useful discipline — a handler owns the continuation it accepts — without the
generality.

**Async colouring**, with a keyword and a parallel API surface. Rejected: it
splits every library into two, and the split propagates up through every caller.
The property this design exists for is that one call site works both ways.

**A policy parameter on waiting operations.** Rejected: it puts scheduling into
signatures that have nothing to do with scheduling, and every intermediate
function has to thread it.

**Shipping a scheduler.** Rejected as scope. Fairness, priority, and task
lifecycle are policy, and a language that ships one makes every host either
accept it or work around it.

**Multi-shot continuations.** Rejected on the runtime: LuaJIT's coroutines are
one-shot.

**Preemption.** Rejected: a suspension happens where a call performs it, which
is what makes the resource reasoning local.

**Keeping the blanket refusal of suspension with live obligations.** Rejected
once handled suspension existed — the refusal was reasoning about raw
coroutines, and applying it to a form with a responsible handler would have made
the feature useless for exactly the code that needs it.

## FAQ

**What happens with no handler installed?** The built-in handler blocks, and the
program behaves as it did before this existed.

**Does an operation that is already ready cost anything?** No — it never reaches
the suspension point.

**Can compile-time evaluation suspend?** No. It stays deterministic and
handler-free.

**Why is the contract trusted rather than checked?** Because the checker cannot
prove anything about an arbitrary scheduler's cancellation behaviour. Naming it
as a handler obligation is more honest than a rule that appears to prove it.
