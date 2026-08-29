---
title: Structured worker tasks
status: Implemented
created: 2026-08-21
---

## Summary

CPU-parallel work is a sendable function submitted to a structured scope. The
scope owns every child task, the process owns one bounded scheduler, and each
scheduler lane owns an isolated LuaJIT state. A module function names its
authored member; an eligible function literal names a compiler-outlined hidden
member and carries a copied capture snapshot. The submitted function supplies
the static argument and result contract, and signatures that cannot cross the
isolation boundary are refused where the task is written.

There is no worker declaration, designated entry module, protocol, dispatcher,
serving loop, per-entry pool, or per-call thread.

## Goals

- Let one function be called directly or submitted for parallel execution.
- Make ordinary function literals concise worker tasks without sharing their
  creating activation.
- Infer task arguments and results from the function instead of restating a
  protocol.
- Refuse intrinsically uncopyable captures, parameters, and results at compile
  time, with a path to the offending type.
- Make a lexical scope responsible for all of its children on every exit.
- Reuse a bounded number of native threads across unrelated scopes.
- Keep the share-nothing ownership boundary intact.

## Non-goals

- Sharing Lua values or mutable state between threads.
- Moving affine values between Lua states.
- Serializing arbitrary pre-existing closures discovered through `any`.
- Proving from types that every possible value is copyable.
- Deriving the transfer codec from a function signature.
- Durable, distributed, or process-independent job queues.
- Preempting a task that is already executing native or Lua code.

## Motivation

An ordinary function already contains the complete static contract for a unit
of work: its module is a build dependency, its parameter and result packs
already exist, and direct invocation already has the desired local meaning.
Making parallel execution require an entry name, operations shape, generated
handle, dispatcher, and serving loop would duplicate that contract with
transport infrastructure, and make pools part of an entry's identity even though
native threads are a bounded process resource.

Restricting tasks to exported functions would avoid that ceremony but force
every closed-over value into an explicit parameter, a restriction following from
representation rather than semantics. A Lua closure cannot cross into a second
state, but compiler-owned code and an immutable environment can be represented
and copied separately, and the compiler knows a literal's body, lexical
bindings, and declared module.

The same boundary should reject what types can already prove impossible. A
function-typed field can never be reproduced in another Lua state, and waiting
until a particular value is copied turns a static mistake into a runtime one,
while other failures such as cycles and repeated table aliases are properties of
values rather than types and must remain dynamic.

Finally, parallel work needs an owner and a bounded executor, because a detached
task has ambient failure and cleanup policy and a native thread and Lua state
per call make submission an unbounded resource operation. A lexical scope and
one process scheduler supply those two missing pieces.

## Overview and specification

### Syntax and task contract

No new syntax is introduced. `scope:spawn` is generic over its final callable
and derives the preceding arguments and the task's result pack from that exact
function type:

```nupp
module jobs

export function hash(bytes: string): string
    return nupp.data.fnv1a64(bytes)
end
```

```nupp
module main

const jobs = require("jobs")
const workers = require("nupp.workers")

export function hashes(left: string, right: string): (string, string)
    with scope = workers.scope() do
        const first = scope:spawn(left, jobs.hash)
        const second = scope:spawn(
            right,
            |bytes: string| -> jobs.hash(bytes)
        )

        return first:await(), second:await()
    end
end
```

`jobs.hash` remains an ordinary function when called directly, and passing it to
`spawn` selects the worker scheduler for that invocation, so execution policy is
not part of the declaration's identity.

The callable is last so a multiline literal reads as the operation rather than
as punctuation before its inputs. A task with no explicit arguments is
`scope:spawn(callable)`, and expressions are still evaluated once in source
order.

### Sendable callable types

`sendable` qualifies a function type in the same syntactic position as
`nosuspend`:

```nupp
sendable function(string, integer): string
```

It is a positive guarantee that another isolated state can reproduce the
callable: a sendable function fits an ordinary function slot, and an ordinary
function does not fit a sendable slot. The qualifier composes with `nosuspend`
in either order and can be preserved by a binding, parameter, result, field, or
container:

```nupp
const handlers: {[string]: sendable function(string): string} = {
    hash = jobs.hash,
    normalize = |value| -> normalize(value, currentRules),
}
```

Sendability is minted for a function read from a module member with an empty
capture environment, and for a function literal checked where a sendable
callable is expected; `Scope:spawn` supplies that expected type to its final
argument, so the common literal needs no annotation.

### Captures and callable identity

An activation-local capture must be initialized before the literal is created,
must be final or effectively final, and must have a type the worker copy can
reproduce. Reassignment anywhere in the binding's scope removes eligibility,
including reassignment after the literal. Gradual types retain the runtime
value check.

The capture is a snapshot taken when the literal is evaluated: tables are
serialized like explicit worker arguments and the lane receives an independent
copy, while module locals are not capture payload and each lane initializes them
independently when it loads the module.

The containing file must declare a module, and generated module code registers a
stable hidden member containing the literal body with capture parameters
prepended. The local value remains an ordinary Lua closure in its creating state
and is associated with that hidden member plus its packed capture snapshot, and
hidden members do not enter the authored export table.

An ordinary module function uses the same identity with an empty capture pack
and names the authored member directly. In neither case does a Lua closure or
upvalue cross the channel.

### Static transfer check

Submission checks the callable's parameter and result types. A type is refused
when no value of it could ever be copied: a function, thread, userdata, cdata,
C pointer or array, or a parameter carrying an ownership mode. The walk
descends arrays, tuples, unions, intersections, and shapes, so a diagnostic can
name `argument 1.hook` rather than only `argument 1`.

Ownership modes are checked before their types, since a mode other than `plain`
cannot be rebuilt by the type blueprint, so `takes value: File` reports that
argument 1 is an owner rather than exposing an internal reconstruction failure.

The check occurs at submission, not when a `workers.Task<F>` type is named: a
task handle is derived from a signature and describes no crossing, where the
arguments before `spawn`'s final callable do.

`any`, a bare `table`, and records remain dynamic because each can contain a
copyable value. A record is the sharpest case, since the same declared type is a
plain table when built from a table literal and carries a metatable when built
with `new`, so refusing the type would reject values that can cross.

Cycles, repeated table aliases, metatables, excessive depth, and unsupported
keys are likewise decided while copying. The static rule is necessary, never
sufficient: identity is a property of values, and a recursive shape is a valid
type that can build a cyclic value.

### Structured lifetime and failures

`workers.scope()` returns an affine scope. Leaving its exact `with` extent
drains every child through a non-suspending native wait, including unawaited
tasks and every exit by return or error. Explicit `Scope:close` and
`Task:await` are ordinary suspension-aware calls, so they park when a handler
is installed and block efficiently otherwise.

Awaiting is repeatable after settlement and returns the complete Lua result
pack, including nil positions. A task failure is returned as a failed reply and
raised by `await`, and scope exit waits for every child before raising the first
failure the body did not already observe.

A running task cannot be preempted safely, and structured exit still waits for
it, so a nonterminating task remains a nonterminating child.

### Scheduler and values

The first scope starts one process-wide scheduler, bounded by the host's online
processor count and a defensive maximum. A lane is one native thread and one
isolated LuaJIT state; lanes persist and execute submitted tasks sequentially,
submission chooses the lane with the fewest unsettled tasks, and different
scopes share the same lanes.

A task running in a lane cannot open another worker scope, because nested
submission from an isolated state could create a second scheduler or wait on its
own lane; the calling state owns composition of parallel leaves.

Arguments, captures, and complete result packs are serialized through bounded
byte queues, and unsupported values and queue overflow are rejected. Copying
keeps Lua heaps, mutable module state, and ownership isolated even when the
static signature admits the value.

### Lowering

The typed surface lowers the callable-last source form while retaining source
evaluation order. A worker receives a module, member, copied capture values,
explicit argument values, and their counts, then performs the equivalent of:

```lua
local callable = resolve(require(module), member)
return pack(callable(unpack(capturesAndArguments, 1, count)))
```

The explicit module path is an ordinary build dependency, so targets do not list
dynamic worker entries. For an outlined literal, `member` resolves the hidden
compiler registration and the capture prefix supplies its environment.

## Risks and assumptions

- Outlining duplicates a literal body in generated source: one copy closes over
  the local activation and one accepts a copied environment.
- Outlining is contextual, so a closure discovered only through `any` has no
  compiler-owned body or capture contract and is refused.
- Module locals may differ between lanes because every Lua state initializes a
  module independently, so per-task state belongs in arguments or captures.
- Gradual surfaces can hide an uncopyable value, leaving the runtime encoder as
  the final assertion at the isolation boundary.
- Leaving records dynamic means construction decides whether one crosses. The
  receiving lane could later reattach a metatable by nominal name; until then
  the type cannot honestly refuse or accept records.
- The static transfer rule is a comptime function rather than a `Sendable`
  bound. A generic wrapper around `spawn` therefore reports inside the wrapper
  rather than at its caller.
- The shared scheduler remains alive until process exit, trading bounded
  resident threads for avoiding repeated Lua-state startup and teardown.
- One task at a time runs in each lane, so suspension inside worker code blocks
  that lane; coroutine multiplexing within a lane is a compatible later
  optimization.

## Alternatives considered

**Typed entry protocols and generated handles.** An entry-name literal and an
operations shape can produce a typed structural handle, but they duplicate the
function signature and require a designated entry, dispatcher, and serving loop,
and deriving the protocol from a module name would require a new type-level
module projection. Passing the qualified function uses resolution the compiler
already has, makes the module an ordinary dependency, and makes the same body
useful locally.

**A `worker` declaration modifier.** It makes execution policy part of a
function's identity even though the same body has a valid direct meaning, and
the isolation constraints still require a scheduler and copying, so the keyword
removes no machinery.

**A global `spawn(function() ... end)`.** This has no lexical owner, so detached
work makes failure, cleanup, and program exit ambient policy. The scope is the
minimum structure that makes every child somebody's responsibility.

**Lua coroutine syntax and handles.** Coroutines provide an ordinary-call feel
for suspension, but run one at a time in one Lua state, and `resume` and `yield`
describe control transfer rather than CPU parallelism while letting child
lifetimes escape their parent.

**One native thread per task.** LuaJIT state startup is substantial and
unbounded submission becomes unbounded native resource creation, where a shared
executor retains structured concurrency without making thread count part of
program shape.

**Require explicit arguments instead of captures.** Mechanically sufficient,
but it makes the worker API dictate source structure and prevents helpers from
naturally closing over configuration.

**Serialize Lua bytecode and upvalues.** Bytecode is tied to the VM and build,
upvalues can contain arbitrary heap identity, and deserializing either bypasses
the module dependency graph, where compiler-owned outlining has a stable source
and load path.

**Require `const` captures or a `sendable` declaration modifier.** Requiring
`const` needlessly rejects a local initialized once and never reassigned, and
module functions already have a stable load path and empty environment, so a
declaration annotation would restate what the compiler knows. Contextual
effective finality expresses both cases without new declaration syntax.

**Put the callable first.** This reads well for a bare export but poorly for a
multiline closure, where callable-last keeps the operation at the end and
matches other APIs whose final argument is a callback.

**Refuse every record type.** That would mirror the current copy's treatment of
constructed records but also reject a plain `{x = 1, y = 2} as Point` that
crosses correctly, and an implementation limit is not proof that a type can
never work.

**Check transferability in `Task<F>` or only in a derived codec.** Checking the
handle makes naming a type fail when no value is submitted. Deriving a codec
from the function type could compute the same answer and improve transfer
performance, but it is a separate design and the useful diagnostic should not
wait for it.
