---
title: Application task scopes
status: Implemented
created: 2026-08-23
---

## Summary

Application coroutine work belongs to a structured task scope. The scope owns
every child, its failures, its deadline and its cancellation, while an
installed [suspension](../learn/runtime/concurrency/suspension.md) handler continues to own only
how the aggregate parks. A host such as Tecs, the SDL-hosted ECS engine Nupp is
being adopted into, sees one bounded aggregate rather than every child: Nupp
schedules children in FIFO order under one turn budget shared by nested scopes,
and the host schedules the aggregate between its other work.

The same scope owns [worker tasks](0018-structured-worker-tasks.md). Cancelling
one is cooperative on both sides: a queued worker task is prevented from
starting, and a running one observes cancellation only where it returns or
calls `tasks.checkpoint()`. One cancellation identity, one status vocabulary
and one checkpoint cover coroutine children and worker children, without
pretending their heaps or scheduling are the same.

## Goals

- Give dynamically created coroutine work a typed result, one parent and a
  scope that settles it on every exit.
- Let the same scope own coroutine waits and isolated worker computations under
  one lifetime, one failure policy and one cancellation identity.
- Keep the existing suspension-handler contract and its blocking fallback.
- Bound work returned to a frame across arbitrarily nested task scopes.
- Preserve deterministic cleanup when a child is cancelled before it starts,
  while it is parked, or after it has acquired affine resources.
- Cancel work that has not begun without waiting for its ordinary queue turn.
- Give bounded CPU loops one explicit cooperative cancellation point.
- Bound a whole scope by a deadline without inventing a request or process to
  acquire one.
- Poll worker completion once per scheduler pass rather than once per awaiter.
- Make child failure and cancellation timing explicit rather than ambient.

## Non-goals

- Exposing each child to the host scheduler. A host cannot assign a distinct
  priority or frame budget to children hidden inside one aggregate.
- Preemption, detached tasks, durable jobs or tasks that outlive their scope.
- Preempting running Lua, C or operating-system code when a deadline passes or
  a cancellation is requested.
- Destroying and replacing a Lua state, or terminating a worker lane, to stop
  one task.
- Borrowing an affine parent capture into a `spawn` call that returns before
  the child settles.
- Affine task results in the first task surface.
- Replacing `nupp.workers.Scope:spawn` with a second callable-last intrinsic.
- Defining the clock. [NEP 21](0021-portable-time.md) owns monotonic time, the
  timer source and `sleep`; this proposal owns what a task scope does with a
  deadline.
- Channels, semaphores or new network facilities. Each is a separate decision.
- Completing the Tecs port. A focused SDL-style handler harness is enough to
  validate this contract.

## Motivation

### Neither existing family is an application scope

`nupp.suspension` runs a fixed family through its
[combinators](../learn/runtime/concurrency/suspension.md#combinators-interleave-waits), each call
owning its complete family and returning only after that family has settled,
while `suspension.create` supplies the lower-level operation and deliberately
says nothing about the created coroutine's result, failure or lifetime.

A server, loading pipeline or scene owns children discovered over time, and
needs one place that answers what happens when its body returns, one child
fails, or the scene is cancelled.

`nupp.workers` has the typed handle and lexical parent for CPU work, but its
[terminal cleanup](../learn/runtime/concurrency/workers.md#structured-scopes) is necessarily
non-suspending and blocks until unawaited children finish — correct for a worker
scope and wrong as the shortest application spelling inside an SDL frame. An
application scope needs to drain while its enclosing handler can keep parking
the current coroutine.

### An aggregate is the smaller host boundary

Making every child a host task would require a task-creation ABI in addition to
the existing suspension ABI, and would make Nupp task identity part of a game
engine's priority and lifecycle policy. The smaller boundary is an aggregate:
the host owns when the enclosing task runs, and Nupp owns a bounded amount of
child work each time it does.

### Worker cancellation is task state, not a work item

A worker scope waits for every task because abandoning a native thread or
isolated Lua state would be a lie about resource lifetime, which also means a
queued task no caller wants still runs and a bounded CPU loop has no authored
place to notice that its enclosing scene or request ended.

Sending cancellation through the ordinary inbox does not solve this: a bounded
channel that is full refuses the message, a frame queued behind a task cannot
stop that task from starting, and a lane executing a task or blocked in
`channelPop(inbox, -1)` cannot give a second control channel useful ordering.
Cancellation is task state, and belongs in the native scheduler registry both
sides can read.

### Waiting does not currently scale

Each `Task:await` under a handler registers a fresh readiness source, which
sorts the global source list and polls one lane, so many awaiters repeat source
registration and native channel locks for the same scheduler. The scheduler,
rather than each waiter, should own reply ingress.

## Overview and specification

### Running a scope

`nupp.tasks.run` calls one body with a scope and returns the body's result
after the scope has settled:

```nupp
local tasks = require("nupp.tasks")

local result = tasks.run(function(scope: tasks.Scope): string
    const page = scope:spawnNamed("fetch page", function(): string
        return fetchPage()
    end)

    const parallel = scope:workers()
    const digest = parallel:spawn(bytes, jobs.hash)

    return page:await() .. digest:await()
end)
```

The entry points are:

- `tasks.run(body)` runs a scope under the ordinary application failure policy.
- `tasks.runFor(milliseconds, body)` adds a deadline.
- `Scope:spawn(body)` starts an unnamed coroutine child.
- `Scope:spawnNamed(name, body)` starts a named one.
- `Scope:workers()` answers the one worker scope this task scope owns.

A name is the operation string a stuck host reports for that child, and the
label cancellation and failure values render. Being metadata rather than an
input, it gets its own entry point: overloading `spawn`'s first parameter would
make the one-argument form's arity diagnostics answer about a name the caller
never intended to pass.

### Task-owned worker scope

`workers.scope()` returns an [affine](../learn/runtime/ownership/index.md) scope, so a
task scope that owns one owns it as a field and answers a borrow rooted in
itself:

```nupp
function tasks.Scope:workers(borrows self): workers.Scope borrows (self)
```

`T borrows (source)` is the existing way [a rooted value leaves the scope that
made it](../learn/runtime/ownership/borrowing.md#borrowing-and-pinning). The borrow carries
no close obligation, because the task scope's field holds it, and it carries
provenance, so the same escape analysis that keeps a task handle inside its
`run` body keeps the worker scope there too. The scope is created on first call
rather than by `tasks.run`, so a body that never reaches parallel work starts no
scheduler.

`tasks.run` closes that worker scope through the suspension-aware `Scope:close`
before its field terminal could run, and `close` is idempotent, so the
synthesized terminal that would otherwise drain without suspending finds nothing
to do. That ordering is the whole reason the task scope owns the worker scope
rather than the body.

Worker submission keeps its existing authored form,
`parallel:spawn(arguments..., callable)`, and the compiler continues to
recognize only `nupp.workers.Scope:spawn` as callable-last, so `nupp.tasks` adds
no second method-name special case.

The worker scope is created with a private observer through which the task scope
learns about submission and settlement, while its public type and call surface
remain `nupp.workers.Scope` and `nupp.workers.Task<F>`.

### Task handles

`tasks.Task<F>` derives its `await` result pack from `F`, as a worker task
does. It exposes:

- `await`, which settles the caller against this task;
- `isDone`, which reports whether the child has settled;
- `status`, which reports `queued`, `running`, `done`, `failed` or `cancelled`;
  and
- `cancel(reason: string?): boolean`, which idempotently requests cancellation
  and answers whether this call made the first request.

Coroutine children and worker children share that vocabulary and that
signature, and a child is `queued` until it first runs, whether it is waiting
for a turn in the aggregate's runnable queue or for a scheduler lane.

Repeated and concurrent awaits observe the same settlement, and cancelling one
coroutine that is awaiting a task does not cancel the task, because another
awaiter may still want it and the scope remains its owner. `Task:cancel`, scope
cancellation or an operation that explicitly owns its losing tasks cancels the
underlying work.

A task handle cannot escape the `run` body whose scope owns it, and the checker
tracks that scope provenance on the handle and on aggregates containing it.

### Ownership of local work

`spawn` takes its body: a plain closure transfers no obligation, and a
single-shot closure with `takes` captures moves those captures into the child.
If the child is cancelled before it starts, the scope drops the uncalled closure
and its captures; once it starts, invocation moves the captures into its frame
and ordinary unwinding owns their cleanup.

A closure with borrowed affine captures is refused, because a `scoped` callback
proves only that a borrow does not outlive the call to `spawn` while the
returned task does, so accepting it would end the proof before the use. The
settling combinators may continue accepting borrowed closures because their call
does not return until every entered body has settled.

Task result packs are plain in the first version. A task may acquire affine
resources internally and use them across handled suspension, and must consume or
drop them before returning; making a handle own an unawaited affine result
requires a separate handle-ownership design.

### Failure and cancellation

The ordinary application scope is fail-fast: the first child failure is owned by
the scope, whether or not a caller has reached that child's `await`, and the
scope records it and requests cancellation of unfinished siblings.

That ownership decides what `await` does, as one rule rather than a per-handle
one. A task operation settles the caller against the scope first and the named
task second:

- If the scope owns a failure or a cancellation, the operation raises it. This
  is the case where `page:await()` raises the failure of a sibling it never
  named.
- Otherwise `await` returns the awaited task's cached result pack, including
  nil positions, or raises its cached failure or cancellation.

A parent that is not inside a task operation observes the scope's failure at
its next suspension boundary or at scope exit. No error is injected into
running Lua instructions.

If the scope body raises first, that body failure remains primary: the scope
cancels and drains its children before re-raising it, and cleanup and later
child failures are attempted and retained for reporting without replacing the
primary problem.

An explicit supervisor uses the existing settle-all operations rather than
changing this default, so `all`, `gather`, `race`, `batch` and direct
`workers.scope()` retain their current failure behavior. Racing two task awaits
abandons the losing awaiter, not the task it observed, and a task that remains
in a fail-fast scope may still fail that scope later, so a caller that wants
owned losers cancelled uses `Task:cancel` or a later task-owning race operation.

Cancellation raises a nominal cancellation value that `tasks.isCancelled`
recognizes and `tostring` renders with the operation and reason. Existing
handled-extent shutdown continues raising its existing text, so introducing task
identity does not change the observable value returned by old `pcall` sites.

### Cancellation checkpoints

`nupp.tasks.checkpoint()` is the one authored cancellation point, and means the
same thing on both sides of the worker boundary:

```nupp
nupp.tasks.checkpoint()
```

It raises the nominal cancellation value when the current task has a
cancellation request or an expired deadline, and otherwise returns. It never
suspends, so it is callable from a `nosuspend` region and from a worker lane,
and outside any task it is a no-op.

A parked coroutine child does not need it, because cancellation unsubscribes the
park, marks it ready with cancellation and resumes it far enough to unwind,
where a child that computes without parking is reached only here. Cancellation
never drops a started coroutine or lets the parent scope return while its
cleanup is outstanding.

`time.sleep(0)` is not a checkpoint: it returns without parking, so a compute
loop that wants to be interruptible calls `checkpoint`.

### Worker task state

Every submitted worker task has one native state keyed by scheduler identity
and task ID:

```text
queued ──────────────► running ──────────────► done
   │                      │      ╲
   │                      │       ╲──────────► failed
   ▼                      ▼                 ╱
cancelled ◄──── cancellation-requested ────╯
```

`cancellation-requested` is not terminal: the task continues until it returns,
raises or reaches a checkpoint, and settles as `done`, `failed` or `cancelled`
accordingly.

Submission creates the state before publishing the work frame, and removes it if
publishing fails. The registry holds only scalar state and native
synchronization, while Lua arguments and results continue crossing through the
existing bounded byte messages.

`Task:cancel` writes that state atomically, never writing a Lua control frame,
so it cannot fail because a work channel is full.

### Queued and running worker cancellation

The compare-and-change from `queued` to `running` is the race boundary. Either
the parent settles a queued cancellation or the lane owns a running task; both
cannot win.

If cancellation wins, the task settles as cancelled in the parent immediately.
Its work frame may remain in the bounded inbox until the lane reaches it in
queue order, where the lane consults the registry and discards the frame without
loading the function or decoding its arguments. Nothing wakes the lane to do
this: a lane blocked in `channelPop(inbox, -1)` owns no task, so waking it would
only make it observe an unchanged queue, and a lane that is running work reaches
the frame when it next pops. The scheduler owns that stale physical frame, not
the closed application scope, so its bounded bytes are recovered in queue order
and it can never execute the cancelled body.

If the lane already owns the task, cancellation changes its state to
`cancellation-requested` and the task runs to its next checkpoint, return or
failure. A worker function that neither returns nor checks remains live, and its
parent scope remains live with it, so code requiring hard termination runs
through `nupp.io.process`, where killing the isolated process is an honest
operation.

A cooperative cancellation raised by `checkpoint` becomes a distinct cancelled
reply rather than a worker failure string. An application error that happens
after cancellation was requested remains an application failure if it reaches
the worker boundary first, so cancellation does not rewrite an error the
function actually raised, and a normal result that wins the same race remains a
normal result.

### Deadlines

`tasks.runFor(milliseconds, body)` computes an absolute deadline from
[`time.now()`](0021-portable-time.md). If the parent has no deadline, the
requested one becomes the child's. If it has one, the effective deadline is
`math.min(parent, requested)`:

```nupp
local answer = tasks.runFor(5000, function(scope: tasks.Scope): string
    return fetchAndIndex(scope)
end)
```

The minimum is a runtime clamp: a diagnostic may reject a negative literal, or
explain that a literal child duration cannot extend a literal parent, but
runtime values are never justified by a compile-time promise.

`tasks.deadline()` answers the effective absolute deadline of the current task,
or nil where there is none, so a body can size its own work rather than
discovering the bound by being cancelled.

Children inherit the absolute effective deadline, including worker submission
state. When it passes, the scope requests ordinary structured cancellation: a
parked child unwinds, a running one reaches `checkpoint`, and a queued worker
task is cancelled without invocation. A deadline does not detach work,
interrupt native code, or let a scope return before running children have
settled.

A deadline is a value rather than a registration, compared where cancellation is
already decided, and it registers a timer only while the scope has parked work
and no earlier wakeup, releasing it when the scope resumes. Entering a scope
therefore cannot fail against the timer manager's bound, which
[NEP 21](0021-portable-time.md) applies to `sleep`.

An operation-specific timeout may be earlier than the enclosing task deadline,
and whichever expires first supplies the result or cancellation that its
existing API promises. Task cancellation uses the task cancellation identity;
HTTP and process timeouts retain their operation-specific result fields and
reasons.

### Shared reply readiness

The first worker scheduler creates one suspension readiness source, and awaiters
associate their waits with it and register a task waker in the scheduler's Lua
state rather than registering another source.

One poll pass drains available replies from every lane, updates task states and
wakes the waiters whose tasks settled. The blocking half waits for any worker
completion, bounded by the next worker deadline where one exists, and a host
such as Tecs calls only the nonblocking half through `suspension.poll()`.

A later native aggregation may replace the per-lane channel checks with one
completion queue, but the observable contract is already one scheduler poll
rather than one poll per awaiter.

### Aggregate scheduling

The scope owns a FIFO runnable queue and one driver. Under no handler the driver
retains the existing blocking behavior, running children and then driving
registered readiness sources when every child is parked.

Under an installed handler the budget is a turn-budget token held by the
current coroutine rather than by one scope. The first aggregate to run in a
poll generation installs it; every nested aggregate, every later sibling
aggregate in the same generation, and every child driver uses that exact token,
inheriting it through the coroutine `suspension.create` produces exactly as
they inherit the handler. Starting or resuming one child consumes one unit. The
authored first version is 64 child activations per host turn. One activation
may run until it returns or parks; the budget is cooperative and is not an
instruction or wall-clock limit.

When the token is exhausted, drivers at every depth stop selecting runnable
children, and exhaustion propagates to the outermost aggregate, which performs
one ordinary suspension until the next readiness-poll generation wakes it and
replenishes the token. Nested and sequential scopes therefore divide one budget
rather than multiplying independent limits.

One lazy process-wide readiness source provides that deferral. Its poll swaps
the current waiter queue before resuming it, so a driver that exhausts its new
turn cannot re-enter during the same poll pass; cancellation removes a queued
waiter, and the source is registered once rather than once per driver or defer.

Tecs consequently schedules and prioritizes the aggregate task, while within one
aggregate Nupp owns FIFO ordering and per-child Tecs priority is deliberately
unavailable. Applications needing independently prioritized work create
independent Tecs tasks rather than children of one Nupp scope.

### Private handlers preserve barriers

A private branch handler changes where a child yields without granting
permission an outer handler refused: its `canPark` delegates dynamically to the
installation it displaced, and nested private handlers form a delegation chain
to the host barrier.

This rule applies to the existing combinator driver as well as task scopes, so a
Tecs barrier remains visible inside arbitrarily nested `all`, `race` and task
families. Readiness callbacks only enqueue or mark work, never resuming a task
inside an SDL callback, native callback or ECS barrier.

### Compatibility lint

The automatic `workers.Scope.drop` remains a non-suspending native drain, and a
`blocking-worker-drop` lint reports a direct `workers.scope()` in a handled
application path where an explicit suspension-aware close is not proved before
terminal cleanup. Direct `workers.Scope:close` retains its settle-all behavior,
and cancelling one task there does not cancel its siblings.

When a worker scope is owned by `nupp.tasks`, application-scope cancellation
requests cancellation for every unfinished worker child, then awaits the running
ones: queued tasks settle without running, cooperative running tasks settle at
checkpoints, and non-cooperative running tasks keep the application scope
open.

### Lowering

`tasks.run(body)` lowers to a protected invocation of `body(scope)`, where normal
return suspends until every child settles and failure requests cancellation then
suspends until every child has unwound before re-raising the primary error.
`tasks.runFor(duration, body)` reads the monotonic clock once, clamps the
absolute result against the ambient deadline, and invokes the same machinery
with that effective value.

Local `spawn` creates a handler-inheriting coroutine around the transferred body
and records it in the scope driver, and worker submission keeps its existing
compiler lowering on `nupp.workers.Scope:spawn`.

`tasks.checkpoint()` becomes a call to the selected task runtime. In a worker
state the compiler-owned bootstrap installs the current native task ID before
invocation and clears it after the reply is produced.

No new syntax and no new member-name lowering are introduced.

## Risks and assumptions

- **One activation is not a time bound.** A child that computes without parking
  can still consume a frame, leaving the worker boundary and profiling as the
  answer.
- **The aggregate hides priority.** This is the chosen cost of keeping task
  creation out of the host ABI, and a later per-child host scheduler would be a
  different contract rather than an optimization of this one.
- **Fail-fast differs from the settling combinators.** The application scope is
  for mutually owned child work while supervisors continue using an explicit
  settle-all boundary, and an `await` that raises a sibling's failure is the
  visible edge of that choice.
- **Plain results are conservative.** They postpone useful affine producer
  tasks, but avoid pretending a repeatable handle can own and return one value
  exactly once.
- **A fixed quantum is observable through races.** Concurrent winner order was
  never a stable ordering contract, but deterministic tests must control their
  readiness rather than depend on running more than one turn at once.
- **Cooperation may be forgotten.** Profiling and documentation must make long
  checkpoint-free bodies visible, because the runtime cannot infer safe
  interruption points.
- **Queued cancellation leaves a physical frame temporarily resident.** It is
  bounded and cannot execute, but a lane occupied by non-cooperative work also
  delays reclaiming those queued bytes.
- **One registry is shared native state.** It contains only scheduler control,
  not Lua values, and its synchronization must stay off hot task code except at
  submission, settlement and authored checkpoints.
- **Polling every lane remains proportional to lane count.** One source removes
  multiplication by awaiters, and a shared native completion queue remains a
  compatible throughput optimization if the per-lane locks are still material.
- **The terminal compatibility API can still block a frame.** The lint and the
  application task surface reduce that hazard without changing what an existing
  structured worker scope promised.

## Alternatives considered

**Add task creation to `suspension.Handler`.** Gives Tecs every child and its
initial scheduling, at the cost of turning a waiting contract into an
application task ABI and making host priority part of Nupp task identity.
Rejected for the first task layer; independent Tecs tasks remain available where
that control matters.

**Let every private driver have its own quantum.** Simple and wrong under
nesting: work per host turn grows as the product of the nesting depths, and a
body that opens two scopes in sequence doubles its frame, where one token on the
coroutine makes the outer host bound real.

**Run every runnable child before returning to the host.** Preserves the current
combinator loop and lets a large ready family monopolize an SDL frame, so it is
rejected for handled aggregates.

**Return an affine task scope from `tasks.scope()`.** Matches worker syntax, but
automatic terminal cleanup cannot suspend and would reproduce the blocking frame
hazard this layer exists to avoid, where a protected `run` call can cancel and
drain before it returns.

**Hand the worker scope to the body as an owner, or through a callback
borrow.** An owner puts the blocking terminal back in the body, and a
`scope:parallel(function(borrows parallel) ... end)` callback keeps ownership
correct but costs the body its multi-value results and forces every await inside
the callback. A provenance borrow expresses the same lifetime without either
cost.

**Accept borrowed affine captures.** The borrow proof ends when `spawn` returns,
before the child is required to settle; settling combinators retain that ability
and returning spawn does not.

**Duplicate callable-last worker submission on `tasks.Scope`.** Requires a
second exact compiler special case or a new signature policy solely to hide a
boundary the source benefits from seeing, where the task scope owns the existing
worker scope instead.

**Send worker cancellation through the inbox.** A saturated bounded queue can
refuse it, and a frame behind the task cannot stop that task from starting, so
one native task-state registry answers instead.

**Add a second control channel.** A lane blocked on or draining the work channel
does not simultaneously consume another without a native multiplexing layer, and
the registry already supplies the needed shared scalar state.

**Terminate the worker lane.** Stops foreign and Lua code by destroying the
entire isolated state, loses unrelated queued work and cannot promise resource
cleanup; processes are the hard-termination boundary.

**Treat a cancelled awaiter as task cancellation.** Breaks repeated and
concurrent awaits, since one observer could end work another still owns, so task
and scope cancellation are explicit.

**Keep one readiness source per await.** Simple and currently implemented, but
sorts the global source list and repeats native polling for one shared
scheduler, where one source is the ownership-correct and cheaper boundary.

**Split the task scope, its cancellation and its deadlines across three
proposals.** They share one handle type, one status vocabulary, one cancellation
identity and one checkpoint, so three files disagreed about all four. The clock
stays separate because a program that never opens a task scope still needs
one.

## 2026-08-23: what the task-owned worker scope costs

The scope, its cancellation identity, its checkpoint, its deadlines and its turn
budget are built. `Scope:workers()` is not, and the reason is worth recording
because it is not the ownership question this proposal spent its
[alternatives](#alternatives-considered) on.

`nupp.tasks` ships inside the compiler's own bundle, and reaching `nupp.workers`
from a bundled module selects the workers seam, which requires a binary target
with the compiler-owned host. So a static require would put that requirement on
every program that opens a task scope, including ones that never spawn a worker
-- and on the compiler build itself, which is not such a target.

That does not revisit the design: the borrow rooted in the scope remains the
right shape and `borrows (self)` remains the way to spell it. What it says is
that the task layer needs a way to name the worker scope without linking it,
which is a module-graph question rather than an ownership one, and the decision
belongs to whoever answers it.

## 2026-09-02: one scope, opened with `with`

Three things this proposal left open are now settled, and the answers belong
here because each reverses a reason given above.

**The module-graph question.** A task scope names the worker provider's
submission contract through a checker-only edge: `nupp.workers.Submitted(F)` in
a type position resolves through the selected provider's exports and emits
nothing, and the runtime edge is still activated only by the `native.workers`
effect the compiler records for `fork`. So `Scope:fork` exists beside `spawn`,
with one argument shape and one `Task<F>`, and `Scope:workers()` is the
lower-level handle rather than the way in.

**The affine scope.** The alternative rejected above -- an affine scope from
`tasks.scope()` -- was rejected because automatic terminal cleanup could not
suspend. That was checker policy rather than a lowering limit, and it is gone: a
terminal may suspend, and one that parks until the resource's work has settled
is a settling terminal, refused only where suspending is refused. So the scope is
opened with `with scope = nupp.tasks.open(...) do ... end` and `run` and `runFor`
are no longer there; the block is the body. The block is not a coroutine child,
so `open` installs a transparent driver in front of the host that runs the
children while the block waits, and a failure the block itself raises drains the
children rather than cancelling them.

**Bounded fan-out.** A batch type with a pull-based iterator yielding completions
was designed and rejected. A scope with a `limit`, which parks `spawn` and `fork`
while it is full, gives the same backpressure with the loop as the source, no
new type, no overloads over sources, and no completion queue, because a child
holds its own result when it finishes. `scope:cancel()` is what first-result-wins
needs, and it is the scope's own decision, so the block's exit stays quiet.
