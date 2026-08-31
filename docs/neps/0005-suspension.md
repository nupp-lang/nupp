---
title: Suspension
status: Implemented
created: 2026-08-19
---

## Summary

Suspension is a first-class, checked, handled effect: an operation a library
performs, a handler a host installs, and a fact the checker tracks. One call
site suspends into a scheduler where one exists and blocks where none does, with
no second API, no `async` coloring, and no library carrying a policy parameter
it did not want.

::: seealso
- [suspension.md](../learn/runtime/concurrency/suspension.md) for waiting as a caller meets it
- [effects.md](../learn/language/effects.md) for the contracts the checker tracks
:::

## Goals

- Let a library that must wait say only that it waits, and let the host decide
  what waiting means.
- Cost nothing when nothing waits, and one context read when something does.
- Give `nosuspend` a rule the checker enforces, rather than a description.

## Non-goals

- **General algebraic effects.** One effect with handlers covers the case, and a
  language where any operation can be declared and handled is a much larger
  language than anything here needs.
- **A scheduler.** Nupp supplies the seam and one blocking handler; task
  scheduling, fairness, and priority belong to whoever installs a handler.
- **Multi-shot continuations.** LuaJIT's are one-shot; a handler resumes once.
- **Async coloring**, preemption, or making compile-time evaluation suspend.

## Motivation

### Without handlers a library ships two APIs

A library that might wait either blocks, which makes it unusable under a
scheduler, or exposes a second asynchronous surface, which doubles its API and
splits its callers into two populations that cannot share code. The third
option, taking a policy parameter, pushes the decision onto every caller and
into every signature between them.

### Mechanism already built at library scope

The motivating consumer had hand-rolled the whole mechanism: a mode query
answering *blocking* outside a scheduler, *cooperative* inside a task, and
*forbidden* inside a barrier; a check turning the third into a runtime error
naming the operation; a cooperative wait parking on a gate; a scheduler polling
sources and completing it; a canceled wait unwinding.

That is an effect handler confined to one library, built from machinery the
language can supply once, after which the library becomes a handler rather than
being replaced.

## Overview and specification

### Syntax

A library performs the operation; a host installs a handler; a region forbids
waiting.

```nupp
nupp.suspension.suspend(subscription)

nosuspend do ... end
local f: nosuspend function(): nil
```

### Worked example

A waiting library has one API and no policy parameter:

```nupp
local files = require("nupp.io.file")

local contents = files.read("report.txt")   -- blocks, or parks, or is refused
```

The same call blocks in a command-line program, parks the current task under a
scheduler, and is a compile error inside a region that forbids waiting:

```nupp
nosuspend do
    local contents = files.read("report.txt")   -- rejected at compile time
end
```

A host installs its scheduler as the handler and resumes parked work from its
own loop:

```nupp
nupp.suspension.handle(scheduler, function(): nil
    runApplication()
end)
```

### Lowering

Effect propagation and the forbidding region are compile-time only, so a
`nosuspend` region generates nothing at all and an ordinary call generates an
ordinary call.

An operation that is already ready never reaches the suspension point. One that
does reads the current coroutine's handler slot and either calls it or takes the
built-in blocking path, which costs one context read at an actual wait:

```lua
local ready, value = subscription:poll()
if not ready then
   local handler = __nuppSuspensionHandler()
   if handler ~= nil then
      value = handler:park(subscription)
   else
      value = subscription:waitBlocking()
   end
end
```

The resource rule is a checking rule, not a runtime one: suspending with a live
obligation is permitted for a handled suspension and refused for a raw
coroutine yield, and neither emits anything to say so.

### Suspension is an operation

A library that must wait subscribes for a resumption and performs the operation.
Where the value comes from is not its business, and the innermost installed
handler answers. With no handler installed the built-in one blocks, so ordinary
programs behave exactly as they did.

### Handled suspension is not a raw coroutine yield

This is the largest change, and the resource rule is where it shows.

Suspending with a live obligation was rejected, on reasoning that is exactly
right about raw coroutines and exactly wrong about handled suspension: a raw
yield has nobody responsible for it, where a handled suspension transfers
responsibility to a handler that owns the continuation and its cancellation
until the park returns or unwinds.

| Suspension form | Obligation live? | Verdict |
| --- | --- | --- |
| raw yield | yes | rejected, unchanged |
| raw yield | no | allowed, unchanged |
| handled suspension | yes | allowed, and new |
| handled suspension | no | allowed |

The new row rests on a **trusted handler contract**, not on a fact the checker
proves about an arbitrary scheduler, and saying so is what makes the boundary
auditable. The invariant is that the continuation cannot be abandoned without
being woken far enough to run deterministic cleanup, not that a wait eventually
completes, because a wait may legitimately remain pending forever while its
handler is live.

### Forbidding regions become load-bearing

The effect was already inferred. Giving it a rule, so that a region may forbid
it and a suspending call inside one is refused, required the fact to cross
module boundaries and resolved function values, where the analysis had been
deliberately file-local.

## Risks and assumptions

- **The handler contract is trusted, and it is the safety argument.** A handler
  that abandons a continuation without waking it for cleanup silently breaks the
  resource guarantee, and nothing detects it. The contract is stated as a
  requirement on handler authors, of whom there will be few, and that scarcity
  is the only reason this is acceptable.
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
Rejected as a much larger language than anything here needs; Nupp borrows one
useful discipline, that a handler owns the continuation it accepts, without the
generality.

**Async coloring**, with a keyword and a parallel API surface. Rejected: it
splits every library into two and the split propagates up through every caller,
where the property this design exists for is that one call site works both ways.

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
once handled suspension existed: the refusal was reasoning about raw coroutines,
and applying it to a form with a responsible handler would have made the feature
useless for exactly the code that needs it.
