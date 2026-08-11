# Suspension — design record

Status: unstarted design. The file-local effect analysis this rests on is
built; cross-module effect transport, the handler, the region rules, and the
resource interaction are not.

## Decision

Nupp will make *suspension* a first-class, checked, handled effect: an
operation a library performs, a handler a host installs, and a fact the checker
already tracks. One call site suspends into a scheduler where one exists and
blocks where none does, with no second API, no `async` colouring, and no
library carrying a policy parameter it did not want.

Concretely:

- **`suspend` is an operation, not a function.** A library that must wait
  subscribes for a resumption and performs `suspend`. Where the value comes
  from is not its business.
- **A handler is installed for a dynamic extent.** The innermost handler
  answers. With no handler installed the built-in one blocks, so ordinary
  programs and the compiler's own tools behave exactly as they do now.
- **The choice costs one context read at an actual wait.** Effect propagation
  and `nosuspend` are compile-time only. An operation that is already ready
  never reaches `suspend`; one that does reads the current coroutine's handler
  slot and either calls it or takes the built-in blocking path.
- **`yields` becomes load-bearing rather than descriptive.** The effect is
  already inferred ([effects.md](../docs/effects.md)); this gives it a rule — a
  region may forbid it, and the checker refuses a suspending call inside one.
  The fact must first cross module boundaries and resolved function values;
  the current analysis is deliberately file-local.
- **Handled suspension is a different thing from a raw coroutine yield**, and
  the resource model must stop treating them as one. That is the single
  largest change here and §Resources is about it.

The motivating consumer is tecs, whose runtime already implements all of this
by hand and would become a handler rather than be replaced. The feature is not
tecs-specific and §What Nupp gets says what the compiler itself does with it.

## Why this shape

### tecs already built it, at library scope

`tecs.io.Process` waits *contextually*: `taskruntime.waitMode()` answers
`blocking` outside a scheduler, `cooperative` inside a task, and `forbidden`
inside a barrier, and `checkWait` turns the third into a run-time error naming
the operation. A cooperative wait parks on a gate; the scheduler polls
registered sources and completes the gate; a cancelled wait unwinds.

That is an effect handler, hand-rolled and confined to one library. Everything
in it is machinery Nupp could supply once:

```
 tecs today                       what it is
 ───────────────────────────────  ────────────────────────────────────
 taskruntime.waitMode()           finding the innermost handler
 checkWait(operation)             a dynamic check the checker could do
 newGate / gate:wait / :complete  a one-shot continuation
 awaitCallback(subscribe)         the suspend operation, with cancel
 runtime.register(name, …, poll)  the handler's readiness pump
 enterBarrier / leaveBarrier      a region that forbids the effect
```

The cost of it living in a library is that every *other* library has to
re-implement it or be unusable inside a frame. That is the reason
`tecs.io.Process` cannot be a Nupp library today, and the reason a Nupp
library cannot be used by tecs.

### Lua is one of the few languages where this is possible

There is no function colouring. `coroutine.yield` crosses ordinary call frames,
so a suspending call needs no `async`, no `await`, and no duplicated API — the
effect is invisible in the signature and visible only as a checked fact. In a
coloured language contextual waiting cannot exist; every caller would have to
be rewritten twice.

This is why the feature is small. Nupp is not building continuations. LuaJIT
has them, one-shot, and calls them coroutines.

### Nupp already has the analysis half

`yields` is inferred, propagates through the directly resolved file-local call
graph, and is declarable in an `@effects` contract. "This call may suspend" is
therefore already a fact the compiler owns. What is missing is anything that
consumes the fact, anything that carries it through a module interface or an
aliased function value, and anything that answers *who resumes me*.

This plan does not need Koka's general effect rows. It needs one serialized bit
on a callable summary. A resolved function value retains that bit; an
unconstrained callback is conservatively may-yield. The first version has no
effect variables or effect-polymorphic function types. Add those only if the
conservative rule proves too restrictive for higher-order libraries.

## Goals

1. One call site that suspends under a scheduler and blocks without one.
2. A handler interface small enough that tecs's existing runtime satisfies it,
   so tecs adopts by installing rather than by rewriting.
3. Enough static checking that tecs's `forbidden` mode becomes a diagnostic
   instead of a run-time error.
4. A resource model that permits handled suspension while continuing to refuse
   the abandonment it was protecting against.
5. Deterministic builds, unchanged. Nothing here may reach the checker's own
   answers, comptime evaluation, or generated output.
6. `nupp.io.Process` implementable on top, with tecs's call sites unedited.

## Non-goals

- **General algebraic effects.** One effect with handlers covers the case. A
  language where any operation can be declared and handled is a much larger
  language, and nothing here needs it. Nupp borrows the useful discipline — a
  handler owns the continuation it accepts — without user-defined effects,
  effect rows, or general continuation capture.
- **A scheduler.** Nupp supplies the seam and one blocking handler. Task
  scheduling, fairness, and priority belong to whoever installs a handler.
- **Multi-shot continuations.** LuaJIT's are one-shot; a handler resumes once.
- **Async colouring.** No `async` keyword, no parallel API surface.
- **Preemption.** A suspension happens where a call performs it.
- **Making comptime suspend.** Compile-time evaluation stays deterministic and
  handler-free; see §Determinism.

## The three modes

`waitMode` is the whole user-visible model, and Nupp should keep tecs's three
answers because they are the right three:

```
 mode         when                            what a suspend does
 ───────────  ──────────────────────────────  ─────────────────────────────
 blocking     no handler installed            the built-in handler waits
 cooperative  a handler is installed          the handler is asked
 forbidden    inside a no-suspend region      a diagnostic, at compile time
```

The third is where Nupp improves on the original. tecs raises
`cannot wait while %s is active` when a task waits inside a barrier — correct,
and found at run time, in a frame, in a game. The same fact is visible to the
checker once S0 transports it: the region is lexical, `yields` is inferred,
and the directly resolved call graph is walked.

## Surface syntax

### Performing a suspension

A library never writes `coroutine.yield`. It performs the operation, and the
operation's argument is how to be resumed:

```nupp
--- Waits until the pipe has bytes, or the deadline passes.
local function awaitReadable(pipe: Pipe, deadlineMs: number): boolean
    return suspend("process pipe read", |resume, context| -> do
        local ticket = pipe:onReadable(context, deadlineMs, resume)
        return || -> pipe:cancel(ticket)      -- how to unsubscribe
    end)
end
```

`suspend` takes an operation name and a subscription. The subscription is
handed a typed, one-shot `resume` callback and the current handler's stable
`SuspensionContext`, and answers with a cancellation. The context is how the
pipe registers a readiness source without learning whether it belongs to tecs
or the built-in blocking handler. A facility with several pending operations
retains one source per context while its count is nonzero.

Synchronous completion is valid: `subscribe` may call `resume` before it
returns. The runtime installs the one-shot state before calling `subscribe`,
calls the returned cancellation at most once if cancellation wins, and rejects
a second resume. If `subscribe` raises or does not answer a function, the park
has not transferred responsibility and raises immediately. This is
`taskruntime.awaitCallback` with the name and source capability made explicit.

The operation name is not decoration. `describeWait` in tecs exists because a
wait that never completes is otherwise anonymous, and a scheduler that can say
*which* operation is outstanding is the difference between a diagnosable hang
and a frozen frame.

### Installing a handler

A handler is installed for a dynamic extent, which is what makes the effect
contextual rather than global:

```nupp
handle suspension with scheduler do
    runFrame()
end
```

Inside that extent every `suspend` — at any depth, through any library, across
any module boundary — reaches `scheduler`. Outside it, the built-in blocking
handler answers. Handlers nest; the innermost wins.

`handle ... with ... do ... end` is deliberately a statement rather than a
function taking a callback. A callback would make the extent a closure
boundary, and the resource model has rules about closures that have nothing to
do with this.

The dynamic state is coroutine-local, never one process-global stack. Each
coroutine has an inherited handler and its own nested override stack. A
`coroutine.resume` temporarily supplies the resumer's effective handler as the
target's inherited handler, restores the target's previous inherited value
when it yields or returns, and leaves the target's local overrides intact. This
gives a tecs task the scheduler handler around `runFrame()` without letting a
nested handler in one parked task leak into another. `coroutine.create` and
`coroutine.wrap` use the same context machinery; raw Lua entry points must pass
through the runtime wrappers that implement it.

### Forbidding suspension

```nupp
nosuspend do
    -- Anything reached from here that may yield is a checked error.
    commitArchetypeEdits()
end
```

This is tecs's barrier, made lexical and static. Inside, a call whose inferred
or declared effects include `yields` is **NUPP2701**, reported at the call with
the chain that reaches the suspending function as related locations.

A declaration may carry the same contract for its whole body:

```nupp
@effects(yields = false)
function m.commit(world: World): nil
```

which is the existing contract syntax doing the work, not a new one.

## The handler interface

Small on purpose. A thin adapter over tecs's gates and runtime registry
satisfies it; those data structures remain tecs's.

```nupp
--- The handler-specific capability handed to a subscription.
interface SuspensionContext
    --- Registers a readiness pump while a facility has work. `priority`
    --- orders sources; `shutdown` cancels the producer and settles its waiters.
    --- The returned handle releases this registration.
    source: function(
        self: SuspensionContext,
        name: string,
        priority: integer,
        poll: function(): integer,
        shutdown: function()
    ): Source
end

type Subscribe<T> = function(
    resume: function(T), context: SuspensionContext
): function()

--- What a host installs to answer suspensions. A handler owns every park it
--- accepts until that continuation returns or unwinds through cancellation.
interface Suspension
    --- Parks the caller. `subscribe` is handed a resume callback and answers a
    --- cancellation. Returns what `resume` was given, or raises the
    --- cancellation reason.
    park: function<T>(
        self: Suspension, operation: string, subscribe: Subscribe<T>
    ): T

    --- Whether a suspension may happen here at all. A host with regions of its
    --- own — tecs's barriers — answers false inside them, and the run-time
    --- check backs up the static one for calls the checker could not see.
    canPark: function(self: Suspension): boolean

    --- Cancels every owned park, drives each continuation through unwinding,
    --- invokes active source shutdowns in reverse order, and refuses to return
    --- while either remains registered.
    shutdown: function(self: Suspension)
end
```

The context's `source` is the piece that is easy to leave out and then discover
missing. A handler that can only park has no way to *make progress*: something
has to poll the pipes. Passing the context to `subscribe` gives a library a
route to that pump without exposing or naming the handler. tecs's
`runtime.register("processes", 20, pollAll, shutdown)` maps directly; priority
orders pumps within a frame, and shutdown is what makes ownership rather than
eventual good behavior the resource guarantee.

The built-in blocking path supplies its own context, calls `subscribe`, and
drives the registered sources until the park settles. It does not need a Lua
handler object or a coroutine yield. Its source loop may sleep between
nonblocking polls, while a platform source that can wait efficiently may do so
within the deadline the blocking context supplies internally.

## Cost model

Effect checking is static. `yields` adds one bit to the serialized callable
summary, `nosuspend` erases, and neither threads a dictionary or policy argument
through ordinary calls. Libraries attempt their immediate path first, so a
buffered read, completed process, or expired deadline does not touch suspension
machinery at all.

An actual wait lowers conceptually to:

```lua
local handler = nupp_effective_suspension_handler()
if handler == nil then
    return nupp_blocking_park(operation, subscribe)
end
return handler:park(operation, subscribe)
```

The lookup is one coroutine-context read, not a walk. Entering `handle` saves
and sets one override; every exit restores it. A whole-program build that proves
no handler can be installed may specialize `suspend` directly to the blocking
path, but a reusable library retains the branch so the identical artifact also
works under tecs.

Correct inheritance turned out to need none of that. Inheriting at *creation* --
`suspension.create` records the handler in force where the coroutine was made --
leaves resumption alone entirely: `coroutine.resume` is used unwrapped and costs
what it always did, and creation costs about 19ns with no allocation. The
paragraph below is what was expected and is kept because the expectation is worth
contrasting with the answer.

An inheritance keyed on resumption would add a fixed save/switch/restore around
`coroutine.resume` while a handler is active. With no effective handler and no
target override, the wrapper tail-calls the raw resume fast path. A scheduler
adapter may fuse the switch with the current-task assignment it already makes;
tecs has exactly that point in `resumeTask`. This cost is per resumed task, not
per ordinary function call, and it must be measured rather than described away.

Baselines were captured before any of this existed, against tecs's own
`taskruntime` loaded from its compiled Lua tree with no SDL and no engine
(`bench/suspension-baseline.lua`). On one machine, median of seven, with
allocation sampled separately under a stopped collector:

```
 path            ns/op  bytes/op  what it measures
 ─────────────   ─────  ────────  ───────────────────────────────────
 direct            0.5       0.0  a traced loop, not a call
 blocking          1.5       0.0  a wait-mode check, then calling through
 task-direct       0.4       0.1  the same work inside a task
 gate-only       155.8     296.1  newGate, complete, wait
 handled-ready   348.3     568.1  awaitCallback resumed synchronously
 park-resume     448.0     613.2  a park, a scheduler round trip, a resume
```

`direct` and `task-direct` are traced loops, not calls: LuaJIT compiles and
inlines them, so they are the floor of the apparatus rather than the cost of
calling anything, and nothing should be compared against them. `handled-ready`
is compared against `task-direct`, which shares its context, and `gate-only`,
which differs from it by one protocol.

The measurement method is part of the result here, and worth stating because
getting it wrong reverses the answer. `collectgarbage("count")` reports the
current heap, not a cumulative total, so sampling it with the collector running
measures what *survived* a collection — which reads a path that allocates
heavily and collects promptly as one that allocates nothing. The collector has
to be stopped around the sample, which is why allocation runs fewer operations
than timing: the garbage is retained for the duration.

What the numbers say:

- **The handler lookup is not the risk.** A wait-mode check costs about 1.5ns.
- **The ready path allocates, and substantially.** 568 bytes per await that never
  parks. `taskruntime.newGate` builds a fresh table with a metatable on every
  call and nothing pools it; the pooling elsewhere in tecs is `process.tl`
  recycling *pipe waiters*, which is a different thing one layer up.
- **Both layers cost, in both currencies.** The gate is about 156ns and 296
  bytes; the wrapper around it adds about 192ns and 272 bytes. A real park adds
  only about 100ns and 45 bytes on top of the ready path, so the ready path is
  most of the cost of waiting even when waiting actually happens.

So S2 has two levers on the row that matters, and they are worth about the same:
not building a gate for a subscription that completes during the call, and not
building the closures the wrapper needs. The first is available outright. The
second is bounded by the protocol — a subscription and a one-shot resume have to
exist before synchronous completion can be known — but the *cancellation* need
not, and letting a synchronously-resumed subscription answer none is the change
that makes a third of the wrapper's allocation optional.

What S2 must therefore avoid on the synchronous path is a **gate or retained
park state**. "Allocate nothing" was never available and should not be the bar.

The runtime built to that bar (`src/nupp/suspension.nupp`) is measured by the
same harness, which carries its own rows so the gate is reproducible rather than
recorded. After S4's correctness work, on one machine:

```
 path                     ns/op  bytes/op
 ──────────────────────   ─────  ────────
 tecs handled-ready       534.9     568.1
 nupp-ready               414.1     560.0
 …with the subscription   321.3     520.0
   hoisted out of the loop
```

About 1.25x the speed and level on allocation. An earlier revision measured
2.3x and half the allocation, and that number was partly bought with defects:
no context for the subscription to see, state on upvalues that a cancellation
could not reach, no ticket, no protected subscribe. Correctness took most of the
margin back, and the honest claim is now **parity with a small margin** rather
than clearing the bar comfortably.

Both rows moved together, so the comparison holds even though this machine ran
slower than when the baselines were taken — which is the reason the harness
measures tecs and Nupp in the same process on the same pass.

What the ready path pays for is the context and the shared state table: a library
is entitled to see who is handling suspensions *while* it subscribes, and a
cancellation has to be able to reach the park's state. Pooling the context per
coroutine would recover part of it, at the price of a context a subscription
could capture and outlive. Headroom with a hazard attached, not a floor.

For tecs the cooperative slow path replaces `waitMode`/`checkWait` with the
context read and then reaches the same gate, scheduler, and readiness pump it
uses today. No handler work occurs in ordinary calls and no allocation is
required beyond the gate/subscription the existing path already needs. The
handler-aware task-resume switch above is the only new frame-path instruction
sequence. S2 benchmarks it against tecs's hand-written path; a measurable
regression in ready operations, frame pumping, task resumption, or cooperative
parks fails the milestone.

## Resources: the rule that has to change

Nupp currently rejects suspending while an obligation is live:

> Raw coroutines may be abandoned forever, and LuaJIT has no general static join
> or cancellation guarantee. Suspending with a live owner, borrow, pin, or
> retained handle is therefore rejected.
> — `docs/ownership.md`, and NUPP2603

That reasoning is exactly right *about raw coroutines* and exactly wrong about
handled suspension, and the difference is the whole reason to build this.

A raw `coroutine.yield` has no one responsible for it. A handled suspension
transfers responsibility to a handler that owns the continuation and its
cancellation until the park returns or unwinds. tecs relies on this: a
cancelled gate raises, lexical scopes unwind, and `@drop` runs. That is a
trusted handler contract rather than a fact the checker can prove about an
arbitrary scheduler.

The proposed rule:

```
 suspension form           obligation live?   verdict
 ────────────────────────  ─────────────────  ──────────────────────────
 raw coroutine.yield       yes                NUPP2603, unchanged
 raw coroutine.yield       no                 allowed, unchanged
 handled suspend           yes                allowed — new
 handled suspend           no                 allowed
```

with three conditions on the new row, all of which have to be real:

1. **A handler owns every accepted park.** A wait may legitimately remain
   pending forever while its handler is live; eventual completion is not a
   credible contract. The invariant is instead that the continuation cannot be
   dropped or outlive the handler that owns it.
2. **Shutdown settles ownership.** Before a handler stops owning its scheduler,
   it invokes source shutdowns, cancels every parked continuation, resumes each
   with a cancellation reason, and drives it through unwinding. It refuses to
   report successful shutdown while a source or park remains. A tecs handler
   may therefore keep tasks parked between frame-sized `handle` extents because
   the scheduler object, not one frame extent, owns them.
3. **Cancellation unwinds.** A cancelled park raises, so every scope it passes
   through ends and every `@drop` and other obligation discharges on the way
   out. Silently abandoning a task
   violates the handler contract rather than merely choosing scheduling policy.

The contract is trusted and named at the `handle` installation, in the same
category as a metamethod contract ([metamethods.md](../docs/metamethods.md)).
The built-in path owns no detached continuation: it returns or raises before
its `suspend` call does.

This is the highest-risk decision in this document. It trades a static
guarantee for a contract, which §There is no deoptimization in
[optimizations.md](optimizations.md) warns about in a different context. The
argument for taking the trade is that the alternative is not safety but
uselessness: a suspension that may not cross a scope holding an owner cannot
be used by a
library that opens a pipe, which is every library this feature exists for.

### The region is what makes the trade narrow

How much is trusted depends on a detail of S2's syntax, and it is worth stating
because the difference is large.

`handle suspension with h do ... end` elaborates to installing an `Installed`
owner whose scope discharges it. If that were all, "is this suspension
handled" would be an ambient run-time fact, and permitting a live obligation
across one would rest entirely on the contract above.

It is not all. The construct additionally marks its body as a **checked
handled-suspension region**, which is a lexical fact the checker owns. So the
permission is not ambient:

```
 question                                    answered by
 ──────────────────────────────────────────  ──────────────────────
 is this suspension handled at all           the region, statically
 is it a handled suspension or a raw yield    the construct, statically
 does the handler eventually resume or cancel the contract, trusted
```

Only the third line is trust, and it is the one line no static system on LuaJIT
could take. `coroutine.yield` inside such a region is still NUPP2603 — a raw
yield has nobody responsible for it wherever it appears, which is exactly the
distinction the region exists to draw.

That is also why S2's syntax is not merely sugar over `suspension.install`. The
function is the mechanism; the construct is the mechanism plus a fact about the
extent, and S4 rests on the fact rather than on the mechanism.

## The C boundary

The hard constraint, and the one that should shape the design rather than be
discovered by it. LuaJIT cannot yield when non-yieldable C code has called back
into Lua. Known examples are:

- an FFI callback invoked from C;
- `table.sort` comparators and `string.gsub` function replacements; and
- the rest of the C or standard-library surface that invokes a Lua callback
  without a yieldable continuation.

The boundary belongs to the *invocation*, not to every kind of callback body.
On Nupp's LuaJIT 2.1 baseline ordinary `__index`, `__add`, `__call`, and
`__tostring` metamethods can yield, as can a generic-loop body using the C
`ipairs` iterator: the iterator returns before the body runs. Neither a
metamethod declaration nor a generic `for` is therefore an implicit
`nosuspend` region by itself.

A `suspend` reached from inside one fails at run time with
*attempt to yield across a C-call boundary*, which is a bad error in a good
language.

Nupp can do better than the error, and this is where the effect system earns
its place rather than merely enabling the feature. Known non-yieldable callback
positions are implicit `nosuspend` regions. A visible callback contributes its
inferred `yields`; a resolved function value contributes its serialized bit;
an unconstrained callback is conservatively may-yield. That turns a run-time
failure into **NUPP2702** at the C-to-Lua invocation site without rejecting a
safe metamethod merely because it is a metamethod.

Coverage will not be total — a callback stored in a table and reached through
an unknown C API escapes the analysis — so `suspend` catches LuaJIT's failure
and adds the operation name and "unknown non-yieldable C callback" context. The
runtime cannot reliably name an intervening C frame LuaJIT does not expose.

## Determinism

Nothing here may reach the compiler's own answers.

- **Comptime does not suspend.** The evaluator has no handler and no
  `coroutine`; a `suspend` inside a block is NUPP2411, the code it already
  gets for anything outside its vocabulary. Compile-time evaluation stays a
  pure function of its inputs, which is what repeated-build byte identity
  rests on.
- **Checking does not suspend.** The checker may *use* suspension in its own
  tools — see below — but a suspension may not influence what a module checks
  to. A handler is a property of a program's execution, never of its meaning.
- **Generated code is unchanged by the presence of a handler.** `handle` lowers
  to saving and restoring one coroutine-local override; `nosuspend` erases
  entirely, being a checked region with no run-time component. Neither changes
  what any other statement compiles to, and handler state is never consulted
  while checking or generating a module.

## What tecs adopts, precisely

The compatibility requirement is that tecs's *call sites* do not change. Its
runtime becomes a handler:

```
 tecs today                          after
 ──────────────────────────────────  ────────────────────────────────────
 taskruntime.awaitCallback(sub)      suspend(name, sub)
 taskruntime.waitMode()              supplied by the language
 checkWait(op) → "forbidden"         NUPP2701, at compile time
 enterBarrier / leaveBarrier         nosuspend do ... end
 runtime.register(name, pri, poll,   context:source(name, pri, poll,
                  shutdown)                         shutdown)
 newGate / gate:wait / gate:complete  handler-internal; not language surface
 scheduler drives frames             unchanged, and still tecs's
```

Two things tecs keeps that Nupp deliberately does not take:

- **Gates stay tecs's.** They are a scheduler's data structure. The language
  needs `park`, not the queue behind it.
- **The scheduler stays tecs's.** Priorities, fairness, frame budget, and the
  ordering of sources within an update are policy, and a game engine's policy
  at that.

What tecs gives up is the hand-rolled `waitMode` dispatch in every waiting
library, and the run-time barrier error. What it gains is that *any* Nupp
library that waits works inside a frame without knowing tecs exists.

The speed requirement is equally strict. Immediate operations keep their
current early return. A cooperative park uses tecs's existing gate; Nupp does
not allocate a general effect object, capture a new continuation, or walk a
handler stack. tecs installs the handler once around each task coroutine (and
once per reusable-task cycle), releases it as the task leaves, and polls Nupp's
ordered readiness sources at the start of `SchedulerImpl:step`. A standalone
tecs runtime that does not load Nupp keeps its original task-start path.

## Porting `tecs.io.Process`

The port is the acceptance test for this document, and it splits cleanly.

**What ports unchanged.** The API surface, which is good and hard-won:
`Process.new{args, timeoutMs, stdin/stdout/stderr = pipe|inherit|null}`, the
`Reader`/`Writer` vocabulary shared with files and buffers, `Exit:succeeded()`
and the `killed` fields, and above all `communicate()`. That last one exists
because reading one pipe at a time deadlocks against a child that writes both,
and that lesson should be copied rather than re-learned.

**What ports directly.** `Process.Reader` and `Process.Writer` satisfy the
prelude's completion-oriented `nupp.io.Reader` and `nupp.io.Writer` contracts. Their
concrete `poll` and `offer` operations remain alongside that surface for
`communicate`: completion-oriented calls alone cannot multiplex stdin, stdout
and stderr without risking the same sequential deadlock the method exists to
avoid. If more streams need readiness, the answer is a narrow
readiness-capable subinterface, not a wider base `Reader` whose every
implementation owes irrelevant operations.

**What does not port at all.** The implementation. `tecs/internal/process.tl`
is 48 `C.SDL_*` calls — `SDL_CreateProcessWithProperties`, `SDL_ReadIO`,
`SDL_KillProcess`, SDL's property and environment systems. Nupp cannot link
SDL to run `nupp check`. The platform layer is new code:

- POSIX: `poll`, `waitpid` and `kill` directly, with spawning delegated to
  `std::process::Command` in the native crate. That last part is a change from
  this plan's original `posix_spawn`, and worth stating as one rather than
  reading as satisfied: `Command` makes no contractual promise about how it
  starts a child. It uses `posix_spawn` where it can and a fork path where it
  cannot, but that is a standard-library implementation detail which may change.
  What the requirement was really about is kept — no `fork` followed by our own
  Lua or allocating code, which is the thing that deadlocks in a threaded host —
  and delegating gets it from an implementation with far more testing behind it
  than a hand-rolled one would have. Pipes are made in the crate so their ends
  are close-on-exec from the moment they exist, and only the end this process
  keeps is made nonblocking.
- Windows: spawning remains delegated to `std::process::Command`; bounded
  native workers perform the blocking anonymous-pipe reads and writes without
  blocking Lua, signal manual-reset events, and `WaitForMultipleObjects`
  implements readiness over opaque stream handles. `Child::try_wait` and
  `Child::kill` settle exits without exposing a `HANDLE` through the ABI.

with the usual list of things that bite: partial writes, `EAGAIN`, `EINTR`,
`SIGPIPE`, zombie reaping, and descriptor leaks across `exec`.

**What this document is responsible for.** That the library performs `suspend`
when a pipe is not ready and has no other opinion about waiting. No policy
parameter, no `waitMode` check, no `SDL_Delay`. Then tecs installs its handler
and the same module serves both — which is the point.

Nupp's existing [build/process.nupp](../src/nupp/compiler/build/process.nupp)
is 117 lines of shell quoting over `os.execute` and says plainly that there is
no `exec` to reach for. It is not a foundation; it is what a foundation would
replace.

## What Nupp gets

A feature justified only by another project's needs is a feature Nupp should
not build. Four uses inside this repository, in the order they would pay:

- **The comptime worker.** `plans/comptime.md` C4 wants evaluation out of
  process so a hang, a crash, or a memory blowup cannot take the language
  server with it. That needs spawn-with-kill and a wait that does not block the
  LSP's loop — which is this feature plus §Porting.
- **The language server.** Every request that shells out — `cheader` invoking a
  C compiler, `import-c` reading a header — blocks the loop today. With a
  handler installed by the LSP, the same code parks instead.
- **The test runner and build system.** `nupp test` runs one configured command
  and waits. Running a suite in parallel across cores wants exactly
  `communicate()` over several children with a readiness pump.
- **Watch mode.** Nothing in the toolchain can wait on a filesystem event
  without a blocking loop.

None of these needs tecs, and the first two are the ones this repository would
notice.

## Diagnostics

Reserve NUPP27xx. The range is free; `plans/comptime.md` records what happens
when a range is reserved without checking.

- `NUPP2701`: a suspending call inside a `nosuspend` region
- `NUPP2702`: a suspending call across a C-call boundary

`NUPP2701` and `NUPP2702` carry the call chain from the region to the
suspending function as related locations. A one-line "this may yield" is not
actionable when the yield is four modules away; S0 is what makes that chain
available outside one file.

A missing cancellation, a second resume, an unyieldable dynamic C callback, or
a handler that finishes shutdown with live parks is a run-time contract
violation. Its error names the operation and handler or source involved; it is
not assigned a checker diagnostic code merely to make the ranges look full.

## Milestones

### S0: the effect, transported

- Serialize `yields` in the cross-module callable summary and include it in the
  interface hash.
- Retain the bit through resolved function-value aliases. Treat an
  unconstrained callback as may-yield; do not add general effect rows or effect
  polymorphism.
- Preserve the direct-call predecessor chain needed for related locations.

Exit test: direct and aliased calls propagate `yields` across a module boundary;
a known non-yielding value stays clear; an unconstrained callback is
conservatively may-yield; an unchanged summary is cache-stable.

### S1: the effect, checked

- `nosuspend do ... end`, and `@effects(yields = false)` on a declaration.
- NUPP2701 with its call chain, from the existing inferred `yields`.
- No handler, no run-time component, nothing lowered.

Exit test: a region rejects a transitively suspending call and names the path;
a non-suspending one is silent; the generated code is byte-identical to the
same file without the region.

This milestone is worth landing alone after S0. It converts one of tecs's
run-time errors into a checked one and needs no handler or run-time component.

### S2: the handler and the operation

- `suspend(operation, subscribe)` and the built-in blocking handler.
- `handle suspension with h do ... end`, nesting, and restoration on unwind.
- Coroutine-local inherited handlers and overrides across `create`, `resume`,
  and `wrap`.
- Generic one-shot subscriptions, `SuspensionContext`, ordered sources, source
  shutdown, and the `Suspension` interface.
- The O(1) handler lookup and nil-to-blocking fast path in §Cost model.

Exit test: one library, written once, blocks under no handler and parks under a
test handler; synchronous completion works; a second resume fails; nested
handlers do not leak between coroutines. Benchmarks show no measurable
regression against tecs's ready path, frame pump, or hand-written cooperative
park.

### S3: the C boundary

- Implicit `nosuspend` for known non-yieldable FFI and standard-library callback
  invocation sites, not for metamethods or generic loops as categories.
- NUPP2702, and a run-time failure that names the boundary for what static
  analysis cannot reach.

Exit test: a suspend inside an FFI callback is refused at compile time; one
reached dynamically fails with a diagnosable message rather than LuaJIT's; a
direct metamethod and an `ipairs` loop body may suspend.

### S4: resources

- Permit handled suspension with a live obligation; keep NUPP2603 for raw
  yields.
- Enforce the handler contract at its checkable edges: one owner per accepted
  park, source shutdown, cancellation through unwinding, and shutdown refusing
  success while parks or sources remain.

Exit test: an owner held across a handled suspension is dropped when its lexical
scope ends, whether that scope ends by resuming normally or by cancellation
unwinding it; a raw yield in the same position is still refused.

### S5: `nupp.io.Process`

The platform layer and the API. Separable from S1–S4 in every respect except
that it is what proves them.

The implementation is joined end to end: requiring the public module selects
the native provider and suspension runtime; the private ABI stays out of the
public surface; blocking and handled waits share the state machine; and the
streams satisfy `nupp.io.Reader` and `nupp.io.Writer` without removing the concrete
nonblocking operations `communicate` needs. Real-child tests run on macOS and
Linux, including Linux's signal-mask `SIGPIPE` path. The Windows provider and
its tests cross-check for `x86_64-pc-windows-gnu`; the native-process workflow
executes them on Windows because this macOS machine has neither a Windows
linker nor Wine.

tecs installs Nupp's handler around its tasks and pumps Nupp readiness from its
scheduler. Thirty-two public Process tests pass with only the import changed,
including application shutdown with a live child. The one excluded test
inspects tecs's old private `runtime.registered("processes")` source and is
therefore not a Process call-site compatibility assertion.

Exit test: tecs's `Process` call sites compile and pass against the Nupp
module with only the import changed.

## Test matrix

- region checking: direct, transitive, through a declared contract, through a
  function value and a module interface, and the negative case at each
- handler: install, nest, restore on normal exit, restore on error, restore on
  cancellation, inherit across resume, and isolate overrides between tasks
- subscription: generic result, synchronous completion, cancellation winning,
  second resume, subscribe raising, and a missing cancellation
- blocking handler: parks that settle, parks that time out, several sources
- cancellation and shutdown: unwind the lexical scope, run `@drop`, discharge
  owners, invoke sources in reverse order, reject remaining parks, report names
- C boundary: each identified non-yieldable invocation refused statically; the
  dynamic case fails with context; safe metamethod and generic-loop cases pass
- performance: ready operations do not touch suspension machinery; a handler
  adds no idle frame work; blocking and tecs parks meet §Cost model
- determinism: a file's checked output, its generated Lua, and the fixpoint all
  identical with and without a handler installed in the compiling process
- comptime: `suspend` inside a block is NUPP2411 and nothing else changes
- tecs compatibility: its runtime as a handler, against its own Process tests

## Open questions

- Whether `handle` should bind a name for the handler, or only install it.
  Binding invites reaching for the handler directly, which is the coupling this
  removes.
- Whether a suspending call should be visible at the call site — a sigil — or
  only in the checked effect. Visible costs colouring's readability benefit
  without its cost; invisible is what makes tecs's design work.
- Whether the blocking handler should be replaceable, so a CLI can supply a
  poll loop of its own without pretending to be a scheduler.
- Whether the source context eventually needs a blocking deadline hint in its
  public interface. The first process source can keep deadlines in its own
  waiter set; adding policy before a second source needs it would be premature.
