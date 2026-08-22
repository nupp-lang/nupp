---
title: Structured worker tasks
status: Implemented
created: 2026-08-22
---

## Summary

CPU-parallel work is an ordinary exported function submitted to a structured
scope. The scope owns every child task, the process owns one bounded scheduler,
and each scheduler lane owns an isolated LuaJIT state. Arguments and results are
copied. There is no worker declaration, entry module, protocol, dispatcher, or
per-call thread.

## Goals

- Let one function be called directly or submitted for parallel execution.
- Infer task arguments and results from the function instead of restating a
  protocol.
- Make a lexical scope responsible for all of its children on every exit.
- Reuse a bounded number of native threads across unrelated scopes.
- Keep the existing share-nothing ownership boundary intact.

## Non-goals

- Sharing Lua values or mutable state between threads.
- Moving affine values between Lua states.
- Treating arbitrary closures as portable code.
- Durable, distributed, or process-independent job queues.
- Preempting a task that is already executing native or Lua code.

## Motivation

The protocol design made a parallel call look typed, but only after the author
declared an entry module, an operations shape, a generated handle, a dispatcher,
and a serving loop. That ceremony described transport rather than the program's
operation. It also created a pool per entry, even though native threads are a
bounded process resource rather than part of a function's identity.

An ordinary function already contains the complete static contract. Its module
is already a build dependency, its parameter and result packs already exist,
and direct invocation already has the desired local meaning. The missing piece
is not another declaration form; it is a structured way to choose a different
executor for that call.

## Overview and specification

### Syntax

No new syntax is introduced. `scope:spawn` is generic over the submitted
function and derives its remaining arguments and task results from that exact
function type.

```nupp
with scope = workers.scope() do
    const task = scope:spawn(jobs.hash, bytes)
    const digest = task:await()
end
```

`workers.scope()` returns an affine scope. Its terminal drains every child
through a non-suspending native wait. Explicit `Scope:close` and `Task:await`
are ordinary suspension-aware calls, so they park when a handler is installed
and block efficiently otherwise.

### Callable identity

The submitted value must be a function directly exported by a loaded module.
The parent resolves the function value back to that module member and sends the
stable pair to a scheduler lane. The lane requires the same module from the
stamped payload and calls that export. The explicit reference makes the module
an ordinary build dependency; targets no longer list dynamic worker entries.

This excludes closures and private functions. A closure's upvalues belong to
one Lua heap, and silently reconstructing module state in another heap would not
copy the captured value the author saw. Values that should vary per task are
therefore explicit arguments.

### Scheduler

The first scope starts one process-wide scheduler, bounded by the host's online
processor count and a defensive maximum. A lane is one native thread and one
LuaJIT state. Lanes persist and execute submitted tasks sequentially; submission
chooses the lane with the fewest unsettled tasks. Different scopes share these
same lanes. A task running in a lane cannot open another worker scope: nested
submission from an isolated state could otherwise create a second scheduler or
wait on its own lane. The calling state owns composition of parallel leaves.

### Values and failures

Arguments and complete Lua result packs are serialized through bounded byte
queues. Nil positions are retained by an explicit pack length. Unsupported
values, aliases, cycles, metatables, excessive depth, and queue overflow are
rejected. A task failure is returned as a failed reply and raised by `await`.

Awaiting is repeatable after settlement. Leaving a scope waits for every child,
including unawaited ones, and raises the first failure the body did not already
observe after all children have settled.

### Lowering

The typed surface erases to ordinary method calls. The function value is used in
the parent only to resolve an exported address; no Lua closure crosses the
channel. A worker receives the module, member, argument values, and argument
count, then performs the equivalent of:

```lua
local callable = require(module)[member]
return pack(callable(unpack(arguments, 1, count)))
```

## Risks and assumptions

- Export lookup is intentionally narrower than arbitrary closure outlining. If
  real programs repeatedly need immutable closure captures, the compiler can
  later outline them without changing the scope and task model.
- A task already running cannot be preempted safely. Structured exit still
  waits for it, so a nonterminating task remains a nonterminating child.
- The shared scheduler remains alive until process exit. This trades bounded
  resident threads for avoiding repeated Lua-state startup and teardown.
- One task at a time runs in each lane. Suspension inside worker code therefore
  blocks that lane; coroutine multiplexing within a lane is a compatible later
  optimization, not part of this decision.

## Alternatives considered

**A `worker` declaration modifier.** It makes execution policy part of a
function's identity and prevents the same function from being called normally.
The isolation constraints still require a scheduler and copying, so the keyword
removes no machinery.

**Lua coroutine syntax and handles.** Coroutines provide the right ordinary-call
feel for suspension, but run one at a time in one Lua state. Exposing
`resume`/`yield` would describe control transfer rather than structured
parallelism and would let child lifetimes escape their parent.

**One native thread per task.** This resembles classic Java threads, but LuaJIT
state startup is substantial and unbounded submission becomes unbounded native
resource creation. A shared executor gives the useful Java structured-
concurrency property without making thread count part of program shape.

**Typed entry protocols.** This was NEP 19. It checked messages but duplicated
the function signature and made transport infrastructure user-authored. It also
made pools explicit objects rather than one bounded process resource.

**A global `spawn(function() ... end)`.** Concise, but it has no lexical owner.
Detached work makes failure, cleanup, and program exit ambient policy. The scope
is the minimum structure that makes every child somebody's responsibility.
