---
order: 150
---

# Worker tasks

`nupp.workers` runs ordinary exported functions in parallel on a shared,
bounded scheduler whose lanes are native threads with isolated LuaJIT states.
Arguments and results cross as copies, while Lua heaps and their globals,
closures, userdata, cdata, and mutable module state stay isolated.

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
        const first = scope:spawn(jobs.hash, left)
        const second = scope:spawn(jobs.hash, right)

        return first:await(), second:await()
    end
end
```

`jobs.hash` is still an ordinary function. Calling `jobs.hash(bytes)` runs it
in the current Lua state; passing it to `scope:spawn` runs it on the worker
scheduler. There is no worker declaration or parallel version of the function.

::: note Workers need a compiler-owned binary
Workers run only in a `binary` target whose `stub` is `"nupp"`. The host
supplies the pinned LuaJIT, stamped payload, native scheduler primitives, and
early machine-code address-space reservation. Builds refuse workers in module
and bundle targets and with third-party binary stubs. See [Compiler-native
features](../guides/build.md#compiler-native-features).
:::

## Structured scopes

Every task belongs to a `Scope`. Leaving the exact `with` extent waits for all
of its children, including tasks the body never awaited and every path out by
return or error.

```nupp
with scope = workers.scope() do
    scope:spawn(jobs.rebuildIndex, snapshot)
end -- rebuildIndex has settled here
```

`Task:await()` returns exactly the values the function returns. The argument
list and complete result pack are inferred from that function, so wrong
arguments and wrong result uses are ordinary type errors at the call site.

Awaiting a settled task is repeatable. A failure is raised by `await`. If the
body never observes a failed task, scope exit waits for every sibling and then
raises the first unobserved failure.

`Task:await()` and explicit `Scope:close()` are suspension-aware ordinary
calls. With a [suspension handler](suspension.md) they park the current
coroutine; without one they sleep on the native channel. Automatic cleanup
uses a blocking native drain because an affine terminal may not suspend while
ownership is being discharged.

## Shared scheduler

The first scope creates one scheduler for the process. Its lane count is the
host's online processor count, capped at 64. Later and concurrent scopes reuse
the same lanes rather than creating a pool or a thread per task.

Submission chooses the lane with the fewest unsettled tasks. Each lane runs
one task at a time in its own Lua state, while different lanes run in parallel.
The lanes remain alive until process exit so repeated short scopes do not pay
Lua-state startup for every task.

A worker task cannot open another worker scope. Its isolated state cannot
submit back into the parent scheduler without either exposing scheduler
internals across the heap boundary or risking that a lane waits on itself.
Compose nested parallel work in the calling state and pass each leaf operation
to the shared scheduler.

This is an executor, not an actor system. A task is a request-and-response call
whose inputs and results cross the boundary. Long-lived stateful ownership and
mailboxes would be a separate abstraction.

## Functions that can be submitted

The function must be directly exported by a loaded module:

```nupp
module image.jobs

export function resize(input: string, width: integer): string
    return resizeBytes(input, width)
end
```

```nupp
const imageJobs = require("image.jobs")
const task = scope:spawn(imageJobs.resize, bytes, 320)
```

The function reference is also the build dependency. The binary automatically
carries `image.jobs`; there is no list of worker entries in `nupp.lua`.

Private functions and closures are refused where they are written. `spawn` takes
an `addressable function`, the type of a callable a module exports, and a
closure has no name for another state to resolve: its upvalues belong to the
parent Lua heap, and re-running module initialization elsewhere would not
reproduce the values it captured. Make those values explicit arguments instead:

```nupp
-- Write this:
scope:spawn(imageJobs.resize, bytes, requestedWidth)

-- Not a closure capturing requestedWidth:
scope:spawn(|| -> imageJobs.resize(bytes, requestedWidth))
```

A callable held as a value keeps the guarantee only where the type says so, so a
dispatch table names it:

```nupp
const handlers: {[string]: addressable function(string): string} = {
    hash = jobs.hash,
    resize = jobs.resize,
}
```

`nupp reference --section addressable-callables` says where the fact comes from
and how it travels.

The worker requires the module in its own state and invokes the named export.
Top-level module initialization therefore runs once in each lane that first
uses the module. Treat mutable module state as lane-local, not shared state.

## Values crossing the boundary

Transferable values are nil, booleans, numbers, strings, and tables recursively
made from those values with scalar keys. Each receiver decodes an independent
copy. Nil positions in argument and result packs are retained.

The following are rejected before or while copying:

- functions, threads, userdata, and cdata;
- tables with metatables;
- affine owners and the nominal values that carry their metatables;
- cycles and repeated table aliases;
- tables deeper than 32 levels;
- keys outside the transferable scalar set.

A repeated table is rejected because decoding it twice would silently turn one
identity into two identities. Pass two explicit copies if that is the intended
meaning.

Each lane direction holds at most 1,024 messages and 256 MiB. Submission raises
when a bounded queue is full rather than turning producer backpressure into an
additional hidden wait.

## Failure and termination

An error raised by the submitted function becomes that task's failure and is
raised in the parent by `await` or by scope exit when it was unobserved. Other
tasks continue to settle so the structured scope never abandons live children.

A running task is not preempted. Lua and foreign code have no safe general
interruption point, so leaving a scope waits for a task that is already running.
Pending cancellation and deadlines can be added without changing the function,
scope, and task surface, but do not exist today.

The same rule applies to nontermination: an infinite worker task makes its
scope infinite. Worker tasks are for bounded CPU work. Durable work, retries
across process failure, and jobs that outlive the caller belong to a broker or
[](nupp.io.process), not this scheduler.

See [NEP 20](../neps/0020-structured-worker-tasks.md) for the design tradeoffs
behind structured worker tasks.
