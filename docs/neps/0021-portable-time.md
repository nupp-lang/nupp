---
title: Portable time
status: Implemented
created: 2026-08-23
---

## Summary

`nupp.time` supplies one monotonic clock, one wall clock and one
suspension-aware sleep across native and browser hosts. Every in-process
deadline is an absolute value on that monotonic basis, so HTTP timeouts,
process timeouts and [task deadlines](0020-application-task-scopes.md) are
comparable rather than three independently defined notions of now. One bounded
timer source serves every wait.

## Goals

- Give ordinary applications a portable clock and a cancellable timer wait.
- Make every in-process deadline comparable on one monotonic time base.
- Park under a handler and sleep efficiently under the blocking driver without
  changing the call surface.
- Let Tecs poll timers without sleeping or surrendering its SDL event loop.
- Use one bounded timer source rather than one native timer or thread per wait.

## Non-goals

- Calendar arithmetic, time zones, locale formatting or civil-time parsing.
- A duration type or new literal syntax.
- Deciding what a deadline does when it expires.
  [NEP 20](0020-application-task-scopes.md) owns cancellation policy; this
  proposal owns the clock the policy reads.
- Preempting Lua, worker or foreign code when a deadline passes.
- Choosing a frame rate or telling SDL when it must render.
- Making a sleep inside a worker lane useful; it remains blocking work in that
  isolated state.

## Motivation

Nupp needs monotonic time in more than one place already: the process backend
measures child deadlines through its own `now`, the HTTP provider measures
request deadlines through another, and the browser host exposes a third surface
with `now`, `wallTime` and `sleep`. Adding task deadlines alongside them without
consolidation would make related operations incomparable and duplicate timer
policy a fourth time.

A timeout is also the smallest general cancellation source. HTTP and process
options cover those exact operations, but an application needs to bound a whole
structured scope, wait between retries and run periodic work without inventing a
process or request solely to acquire a clock.

## Overview and specification

### Public time

The public module has three operations, keeping the signatures the browser
provider already publishes:

```nupp
local time = require("nupp.time")

function time.now(): number
function time.wallTime(): number
function time.sleep(milliseconds: number): nil
```

```nupp
const started = time.now()
time.sleep(25)
print(time.now() - started, time.wallTime())
```

- `now()` returns monotonic milliseconds from an unspecified process origin,
  suitable for intervals and deadlines rather than persistence.
- `wallTime()` returns Unix milliseconds and may move when the system clock is
  adjusted.
- `sleep(milliseconds)` waits for at least that duration, parking under a
  suspension handler and using the blocking source path otherwise.

Milliseconds are the unit HTTP, processes and the browser provider already use.
The value is a `number` rather than an `integer`, so a caller may express
fractions and a host honors only the resolution it has. A non-finite or negative
duration raises, as the browser provider's does today, and no epoch or precision
beyond monotonic ordering is promised for `now`.

`sleep(0)` returns without parking. It is not a yield point, does not consume
an aggregate turn budget, and is not a cancellation checkpoint;
`tasks.checkpoint()` is.

### One monotonic provider

The native host exports one monotonic clock used by `nupp.time`, HTTP, process
deadlines and the worker scheduler. Provider-specific state machines may cache
one reading during a poll pass without defining their own epoch or clock
contract.

The existing `nupp.browser.time` seam becomes the portable implementation of
this public surface rather than a browser-only parallel API. Browser worker
requests retain their current host implementation while the checked module name
becomes `nupp.time`.

Process and HTTP backend contracts migrate from a provider-owned `now` to the
selected time provider, and compatibility adapters may answer their old private
member during migration, but new checked code has one source of monotonic
time.

### Timer source

One lazy timer manager holds pending waits ordered by absolute monotonic
deadline. Its single readiness source is
[registered](../concepts/suspension.md#libraries-register-readiness) on first
use.

The nonblocking half reads `now`, removes every due timer and resumes its
subscription, while the blocking half sleeps no longer than the earlier of its
supplied maximum and the next timer deadline. Cancellation removes a timer from
the manager rather than leaving a dead entry waiting for its original time.

The manager is bounded by an authored maximum number of pending timers, past
which `sleep` raises rather than growing a process queue without limit. A task
deadline is a value rather than a registration and is compared where
cancellation is already decided, so it reaches the manager only while a scope is
parked with no earlier wakeup, and entering a scope cannot fail against this
bound.

Under an installed handler only the nonblocking source is used. A Tecs frame
calls `suspension.poll()` at its authored poll point and never reaches the
timer source's sleeping half, because hosts do not call source waits. A later
SDL adapter may use the next timer as an idle-wait hint, but fixed-frame
correctness does not depend on it.

### Lowering

Time calls are ordinary module calls: reaching `nupp.time` selects the target's
time provider and timer source, and a target that reaches no clock or deadline
carries neither.

## Risks and assumptions

- **Wall time is not monotonic.** Publishing it beside `now` may invite misuse;
  separate names and units are the defense.
- **Timer polling follows the host.** A game that polls once per frame observes
  a timer on the first poll after its deadline, not through an interrupt in the
  middle of simulation.
- **Milliseconds as `number` invite resolution assumptions.** A host that cannot
  honor a fraction rounds it, since the contract is a lower bound on the wait
  rather than an exact one.
- **Migrating private clocks crosses several providers**, and keeping
  compatibility adapters too long would preserve the duplication this proposal
  removes.
- **One timer manager is shared policy.** It must remain allocation-stable
  while polling and avoid rebuilding its order for every insertion.

## Alternatives considered

**Keep timeouts inside each I/O library.** Already works for HTTP and process,
but leaves application scopes, retries and periodic work without a timer and
multiplies monotonic-clock contracts.

**Use wall time for deadlines.** It makes a clock adjustment shorten or extend a
live timeout; deadlines use monotonic time and wall time is for timestamps.

**Create one native timer per sleep.** Hands cancellation and bounds to the
platform, at the cost of an unbounded native resource family and a different
integration path on every host, where one readiness source composes with the
protocol already in place.

**Expose only `sleep`.** Avoids clock misuse but forces HTTP, processes and task
scopes to keep private clocks, where publishing the two distinct questions makes
the shared contract explicit.

**Keep deadline policy here, beside the clock.** Deadline inheritance, the
`math.min` clamp and expiry share a handle, a status vocabulary and a
cancellation identity with task scopes, and nothing with the clock except a
reading. The policy moved to NEP 20 and left the reading behind.
