# Suspension — design record

Status: unstarted design. The effect analysis this rests on is built; the
handler, the region rules, and the resource interaction are not.

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
- **`yields` becomes load-bearing rather than descriptive.** The effect is
  already inferred (`docs/effects.md`); this gives it a rule — a region may
  forbid it, and the checker refuses a suspending call inside one.
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

`yields` is inferred, propagates through the call graph, and is declarable in an
`@effects` contract. "This call may suspend" is therefore already a fact the
compiler owns. What is missing is anything that consumes the fact, and anything
that answers *who resumes me*.

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
  language, and nothing here needs it.
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
checker: the region is lexical, `yields` is inferred, and the call graph is
already walked.

## Surface syntax

### Performing a suspension

A library never writes `coroutine.yield`. It performs the operation, and the
operation's argument is how to be resumed:

```nupp
--- Waits until the pipe has bytes, or the deadline passes.
local function awaitReadable(pipe: Pipe, deadlineMs: number): boolean
    return suspend("process pipe read", |resume| -> do
        local ticket = pipe:onReadable(resume)
        return || -> pipe:cancel(ticket)      -- how to unsubscribe
    end)
end
```

`suspend` takes an operation name and a subscription. The subscription is
handed a `resume` callback, and answers with a cancellation. This is
`taskruntime.awaitCallback` with the name moved to the front, deliberately: the
name is what a stuck task reports, and tecs learned to demand it.

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

Small on purpose. tecs's runtime already satisfies every line of it.

```nupp
--- What a host installs to answer suspensions.
interface Suspension
    --- Parks the caller. `subscribe` is handed a resume callback and answers a
    --- cancellation. Returns what `resume` was given, or raises the
    --- cancellation reason.
    park: function(self: Suspension, operation: string, subscribe: Subscribe): any

    --- Whether a suspension may happen here at all. A host with regions of its
    --- own — tecs's barriers — answers false inside them, and the run-time
    --- check backs up the static one for calls the checker could not see.
    canPark: function(self: Suspension): boolean

    --- Registers a readiness pump the host drives. A library with pending I/O
    --- retains one; the host calls it to settle waiters. Answers a handle the
    --- library releases when it has nothing outstanding.
    source: function(self: Suspension, name: string, poll: function(): integer): Source
end
```

`source` is the piece that is easy to leave out and then discover missing. A
handler that can only park has no way to *make progress*: something has to poll
the pipes. tecs's `runtime.register("processes", 20, pollAll, nil)` is exactly
this, priority included, and the priority is not decoration either — it orders
pumps within a frame.

The built-in blocking handler implements all three: `park` waits on the
registered sources until one settles, `canPark` is always true, and `source`
keeps a list.

## Resources: the rule that has to change

Nupp currently rejects suspending while an obligation is live:

> Raw coroutines may be abandoned forever, and LuaJIT has no general static
> join or cancellation guarantee. Suspending with a live owner, borrow, pin,
> retained handle, or `with` cleanup pending is therefore rejected.
> — `docs/ownership.md`, and NUPP2603

That reasoning is exactly right *about raw coroutines* and exactly wrong about
handled suspension, and the difference is the whole reason to build this.

A raw `coroutine.yield` has no one responsible for it. A handled suspension
has a handler that took the resume callback and the cancellation, and a host
that either resumes it or cancels it and unwinds. tecs relies on this: a
cancelled gate raises, `with`-style scopes unwind, and cleanup runs. That is a
guarantee the language can require of a handler rather than one it must prove
about arbitrary code.

The proposed rule:

```
 suspension form           obligation live?   verdict
 ────────────────────────  ─────────────────  ──────────────────────────
 raw coroutine.yield       yes                NUPP2603, unchanged
 raw coroutine.yield       no                 allowed, unchanged
 handled suspend           yes                allowed — new
 handled suspend           no                 allowed
```

with two conditions on the new row, both of which have to be real:

1. **A handler must guarantee termination of the park.** Every parked
   suspension is eventually resumed or cancelled. This is a contract Nupp
   states and cannot check, in the same category as a metamethod contract
   (`docs/metamethods.md`) — trusted, and named as trusted at the point it is
   relied on.
2. **Cancellation must unwind.** A cancelled park raises, so `with` cleanup and
   every other obligation discharges on the way out. A handler that completes a
   park by silently abandoning the task breaks the resource model rather than
   just its own scheduling.

This is the highest-risk decision in this document. It trades a static
guarantee for a contract, which §There is no deoptimization in
[optimizations.md](optimizations.md) warns about in a different context. The
argument for taking the trade is that the alternative is not safety but
uselessness: a suspension that may not cross a `with` cannot be used by a
library that opens a pipe, which is every library this feature exists for.

## The C boundary

The hard constraint, and the one that should shape the design rather than be
discovered by it. LuaJIT cannot yield across most C frames:

- an FFI callback invoked from C,
- a metamethod,
- a C-implemented iterator in a generic `for`,
- `table.sort` comparators, `string.gsub` function replacements, and the rest
  of the standard library's callback surface.

A `suspend` reached from inside one fails at run time with
*attempt to yield across a C-call boundary*, which is a bad error in a good
language.

Nupp can do better than the error, and this is where the effect system earns
its place rather than merely enabling the feature. Each of those contexts is
statically identifiable: the checker knows a function is an FFI callback, knows
a body is a metamethod, and knows which library functions take callbacks it
cannot see through. Treating each as an implicit `nosuspend` region turns a
run-time failure into **NUPP2702** at the call.

Coverage will not be total — a callback stored in a table and reached
dynamically escapes the analysis — so the run-time failure has to remain, with
a diagnostic that names the boundary rather than repeating LuaJIT's message.

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
  to installing a value on a stack and restoring it; `nosuspend` erases
  entirely, being a checked region with no run-time component. Neither changes
  what any other statement compiles to.

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
 runtime.register(name, pri, poll)   handler:source(name, poll)
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

## Porting `tecs.io.Process`

The port is the acceptance test for this document, and it splits cleanly.

**What ports unchanged.** The API surface, which is good and hard-won:
`Process.new{args, timeoutMs, stdin/stdout/stderr = pipe|inherit|null}`, the
`Reader`/`Writer` vocabulary shared with files and buffers, `Exit:succeeded()`
and the `killed` fields, and above all `communicate()`. That last one exists
because reading one pipe at a time deadlocks against a child that writes both,
and that lesson should be copied rather than re-learned.

**What does not port at all.** The implementation. `tecs/internal/process.tl`
is 48 `C.SDL_*` calls — `SDL_CreateProcessWithProperties`, `SDL_ReadIO`,
`SDL_KillProcess`, SDL's property and environment systems. Nupp cannot link
SDL to run `nupp check`. The platform layer is new code:

- POSIX: `posix_spawn`, `pipe2` with `CLOEXEC`, `poll`, `waitpid`, `kill`.
- Windows: `CreateProcessW`, `CreatePipe`, `PeekNamedPipe` or overlapped I/O,
  `WaitForSingleObject`, `TerminateProcess`.

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
- `NUPP2703`: `suspend` outside any handler where one is required
- `NUPP2704`: a handler installed inside a region that forbids suspension
- `NUPP2705`: a subscription that does not answer a cancellation

`NUPP2701` and `NUPP2702` carry the call chain from the region to the
suspending function as related locations. A one-line "this may yield" is not
actionable when the yield is four modules away, and the chain is already walked
by the effect analysis.

## Milestones

### S1: the effect, checked

- `nosuspend do ... end`, and `@effects(yields = false)` on a declaration.
- NUPP2701 with its call chain, from the existing inferred `yields`.
- No handler, no run-time component, nothing lowered.

Exit test: a region rejects a transitively suspending call and names the path;
a non-suspending one is silent; the generated code is byte-identical to the
same file without the region.

This milestone is worth landing alone. It converts one of tecs's run-time
errors into a checked one and needs nothing else in this document.

### S2: the handler and the operation

- `suspend(operation, subscribe)` and the built-in blocking handler.
- `handle suspension with h do ... end`, nesting, and restoration on unwind.
- The `Suspension` interface, `source` included.
- NUPP2703 and NUPP2705.

Exit test: one library, written once, blocks under no handler and parks under a
test handler; a cancelled park unwinds through `with` and runs cleanup.

### S3: the C boundary

- Implicit `nosuspend` for FFI callbacks, metamethod bodies, and the
  callback-taking standard library surface.
- NUPP2702, and a run-time failure that names the boundary for what static
  analysis cannot reach.

Exit test: a suspend inside an FFI callback is refused at compile time; one
reached dynamically fails with a diagnosable message rather than LuaJIT's.

### S4: resources

- Permit handled suspension with a live obligation; keep NUPP2603 for raw
  yields.
- State the handler contract — every park resumes or cancels, cancellation
  unwinds — where it is relied on.

Exit test: `with` holding an owner across a handled suspension runs cleanup on
resume and on cancellation; a raw yield in the same position is still refused.

### S5: `nupp.io.Process`

The platform layer and the API. Separable from S1–S4 in every respect except
that it is what proves them.

Exit test: tecs's `Process` call sites compile and pass against the Nupp
module with only the import changed.

## Test matrix

- region checking: direct, transitive, through a declared contract, through a
  function value, and the negative case at each
- handler: install, nest, restore on normal exit, restore on error, restore on
  cancellation
- blocking handler: parks that settle, parks that time out, several sources
- cancellation: unwinds `with`, runs cleanup, discharges owners, and reports
  the operation name
- C boundary: each identified context refused statically; the dynamic case
  failing with the named diagnostic
- determinism: a file's checked output, its generated Lua, and the fixpoint all
  identical with and without a handler installed in the compiling process
- comptime: `suspend` inside a block is NUPP2411 and nothing else changes
- tecs compatibility: its runtime as a handler, against its own Process tests

## Open questions

- Whether `handle` should bind a name for the handler, or only install it.
  Binding invites reaching for the handler directly, which is the coupling this
  removes.
- Whether a handler may be installed per-module rather than per-extent. Cheaper
  for a CLI; a global handler is exactly the thing that makes libraries
  unusable in other hosts.
- Whether `source` priorities belong in the language interface or in the
  handler. tecs needs them; a blocking handler does not.
- Whether a suspending call should be visible at the call site — a sigil — or
  only in the checked effect. Visible costs colouring's readability benefit
  without its cost; invisible is what makes tecs's design work.
- What a suspension inside a coroutine the program created itself means, when a
  handler is also installed. Two suspension mechanisms in one stack needs a
  stated rule.
- Whether the blocking handler should be replaceable, so a CLI can supply a
  poll loop of its own without pretending to be a scheduler.
