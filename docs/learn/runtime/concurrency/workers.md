---
order: 150
---

# Worker tasks

`nupp.workers` runs sendable functions in parallel on a shared,
bounded scheduler whose lanes are native threads with isolated LuaJIT states.
Arguments and results cross as copies, while Lua heaps and their globals,
userdata, cdata, and mutable module state stay isolated. Eligible closure
captures cross only as independent copies.

```nupp
module jobs

export function hash(bytes: string): string
    return nupp.data.fnv1a64(bytes)
end
```

```nupp
module main

const jobs = require("jobs")
const workers = nupp.workers

export function hashes(left: string, right: string): (string, string)
    with scope = workers.scope() do
        const first = scope:spawn(left, jobs.hash)
        const second = scope:spawn(right, jobs.hash)

        return first:await(), second:await()
    end
end
```

`jobs.hash` is still an ordinary function. Calling `jobs.hash(bytes)` runs it
in the current Lua state; passing it to `scope:spawn` runs it on the worker
scheduler. There is no worker declaration or parallel version of the function.

::: note Workers need a compiler-owned binary, or a browser package
Natively, workers run only in a `binary` target whose `stub` is `"nupp"`. The
host supplies the pinned LuaJIT, stamped payload, native scheduler primitives,
and early machine-code address-space reservation. Builds refuse workers in
module and bundle targets and with third-party binary stubs. See
[Compiler-native features](../../projects/build.md#compiler-native-features).

```lua
-- nupp.lua
return {
   include = { "src" },
   build = {
      kind = "binary",
      stub = "nupp",
      entries = { "main" }
   }
}
```

A `lua51` bundle whose backend supplies the `host.workers` seam runs them too.
That is [the browser backend](#browser-lanes) today, where a lane is a Web
Worker rather than a thread.
:::

## Structured scopes

Every task belongs to a `Scope`. Leaving the exact `with` extent waits for all
of its children, including tasks the body never awaited and every path out by
return or error.

```nupp
with scope = workers.scope() do
    scope:spawn(snapshot, jobs.rebuildIndex)
end -- rebuildIndex has settled here
```

`Task:await()` returns exactly the values the function returns. The argument
list and complete result pack are inferred from that function, so wrong
arguments and wrong result uses are ordinary type errors at the call site.

Awaiting a settled task is repeatable. A failure is raised by `await`. If the
body never observes a failed task, scope exit waits for every sibling and then
raises the first unobserved failure.

`Task:isDone()` answers whether a reply has arrived without waiting for one. It
is a progress question, not a scheduling one: a task is settled or it is not,
and the way to have its values is still `await`.

`Task:status()` answers `queued`, `running`, `done`, `failed`, or `cancelled`.
`Task:cancel(reason)` idempotently requests cancellation and reports whether
this call made the first request. A queued cancellation settles immediately and
the lane discards its work frame without loading or invoking the function. A
running task is cooperative as described under [Failure and
termination](#failure-and-termination).

`Task:await()` and explicit `Scope:close()` are suspension-aware ordinary
calls. With a [suspension handler](suspension.md) they park the current
coroutine; without one they sleep on the native channel. Automatic cleanup uses
the worker scope's blocking native terminal, so it has the same behavior even
when no suspension handler is installed.

## Fanning out over a list

Two spawns are two lines; a list is a loop. A scope is never told in advance
how many children it will have.

```nupp
export function hashEach(inputs: {string}): {string}
    with scope = workers.scope() do
        local tasks: {workers.Task<function(string): string>} = {}
        for index, bytes in ipairs(inputs) do
            tasks[index] = scope:spawn(bytes, jobs.hash)
        end

        local hashed: {string} = {}
        for index, task in ipairs(tasks) do
            hashed[index] = task:await()
        end

        return hashed
    end
end
```

Submit the whole list before awaiting any of it. Awaiting inside the first loop
would spawn one task, wait for it, and spawn the next: still correct, and
exactly as parallel as calling the function. A single task rarely needs a type
annotation, because `const task = scope:spawn(bytes, jobs.hash)` infers one;
a table of them names the submitted function's type as `workers.Task<F>`. The
handle is derived from the signature alone, so it is spelled
`workers.Task<function(string): string>` even though [`spawn` took an
sendable one](#functions-that-can-be-submitted).

### Work in the caller

The calling thread has nothing to do while lanes run. Give it a share when the
work divides:

```nupp
export function bothHashes(left: string, right: string): (string, string)
    with scope = workers.scope() do
        const task = scope:spawn(right, jobs.hash)
        const mine = jobs.hash(left)

        return mine, task:await()
    end
end
```

### Batches instead of items

Arguments and results are copied, so a task whose work is smaller than its
message spends longer being sent than being run. Submit chunks of a list rather
than its elements when the work per element is small:

```nupp
export function hashChunks(inputs: {string}, size: integer): {string}
    with scope = workers.scope() do
        local tasks: {workers.Task<function({string}): {string}>} = {}
        for first = 1, #inputs, size do
            local chunk: {string} = {}
            for offset = first, math.min(first + size - 1, #inputs) do
                chunk[#chunk + 1] = inputs[offset]
            end
            tasks[#tasks + 1] = scope:spawn(chunk, jobs.hashAll)
        end

        local hashed: {string} = {}
        for _, task in ipairs(tasks) do
            for _, one in ipairs(task:await()) do
                hashed[#hashed + 1] = one
            end
        end

        return hashed
    end
end
```

`jobs.hashAll` is the ordinary loop over `jobs.hash`, exported like anything
else. Lanes are bounded by the host's processor count, so a chunk count near
that number is the useful knob; ten thousand one-element tasks queue behind the
same lanes and pay ten thousand copies to do it.

## Shared scheduler

The first scope creates one scheduler for the process. Its lane count is the
host's online processor count, capped at 64. Later and concurrent scopes reuse
the same lanes rather than creating a pool or a thread per task.

Submission chooses the lane with the fewest unsettled tasks. Each lane runs
one task at a time in its own Lua state, while different lanes run in parallel.
The lanes remain alive until process exit so repeated short scopes do not pay
Lua-state startup for every task.

The scheduler also owns one suspension readiness source. A poll pass drains
available replies from every lane and wakes the tasks that settled. Awaiting
many tasks therefore does not register one source or lock every lane again for
each awaiter.

A worker task cannot open another worker scope. Its isolated state cannot
submit back into the parent scheduler without either exposing scheduler
internals across the heap boundary or risking that a lane waits on itself.

```nupp
module jobs.index

const workers = nupp.workers

-- Submitting this raises where it runs: a worker task cannot open another
-- worker scope.
export function countAll(shards: {{string}}): integer
    with scope = workers.scope() do
        return #shards
    end
end

-- One shard of the same work, which a lane can run.
export function count(paths: {string}): integer
    return #paths
end
```

Compose nested parallel work in the calling state instead, and pass each leaf
operation to the shared scheduler. A tree of work becomes a flat submission of
its leaves:

```nupp
const indexJobs = jobs.index

export function countAll(shards: {{string}}): number
    with scope = workers.scope() do
        local tasks: {workers.Task<function({string}): integer>} = {}
        for at, paths in ipairs(shards) do
            tasks[at] = scope:spawn(paths, indexJobs.count)
        end

        local total: number = 0
        for _, task in ipairs(tasks) do
            total = total + task:await()
        end

        return total
    end
end
```

This is an executor, not an actor system. A task is a request-and-response call
whose inputs and results cross the boundary. Long-lived stateful ownership and
mailboxes would be a separate abstraction.

## Functions that can be submitted

The final argument to `spawn` must be a `sendable function`. A function read
from a loaded module is sendable with no captures:

```nupp
module image.jobs

export function resize(input: string, width: integer): string
    return resizeBytes(input, width)
end
```

```nupp
const imageJobs = image.jobs
const task = scope:spawn(bytes, 320, imageJobs.resize)
```

The function reference is also the build dependency. The binary automatically
carries `image.jobs`; there is no list of worker entries in `nupp.lua`.

An eligible function literal is sendable too. Its activation-local captures are
snapshotted when the literal is created and copied with the explicit arguments:

```nupp
scope:spawn(bytes, |input: string| -> imageJobs.resize(input, requestedWidth))
```

The binding `requestedWidth` must be initialized and never reassigned. Its value
must be copyable, just like an explicit argument. The source file must declare a
module so a worker state has a stable place to load the outlined body. The local
value is still an ordinary closure when called directly; outlining is additional
worker metadata, not a different local calling convention.

Module locals are reconstructed independently when that module loads in a lane.
Activation locals are copied as captures. In neither case does a Lua upvalue or
heap identity cross between states.

A callable held as a value keeps the guarantee only where the type says so, so a
dispatch table names it:

```nupp
const handlers: {[string]: sendable function(string): string} = {
    hash = jobs.hash,
    resize = jobs.resize,
}
```

`nupp reference --section sendable-callables` describes contextual literals,
effective finality, and how the guarantee travels through types.

The worker requires the module in its own state and invokes the authored export
or compiler-registered outline. Top-level module initialization therefore runs
once in each lane that first uses the module. Treat mutable module state as
lane-local, not shared state.

## Values crossing the boundary

Transferable values are nil, booleans, numbers, strings, and tables recursively
made from those values with scalar keys. An instance built by an exported Nupp
record declaration is transferable too. Each receiver decodes an independent
copy, and a record receives that state's declaration table as its metatable.
Nil positions in argument and result packs are retained.

A submitted signature is held to this where it is written. A parameter or a
result no copy could reproduce is refused at the call site, and the message
names the path to it rather than the argument:

```
main.nupp:9:9: error: NUPP2006: argument 1.hook is a function, which cannot
  cross into another Lua state
```

Refused this way: functions, threads, userdata, cdata, C pointers, and any
parameter carrying an ownership mode, wherever one of them sits inside an
array, a tuple, a union, or a shape. The one exception is the owned-buffer
move described [below](#moving-owned-buffers), which is a transfer of
storage rather than a copy of a value.

A type that says nothing definite is left to the copy. `any`, a bare `table`,
and a record all describe values that may or may not be copyable. A record built
with `new` carries its declaration table and crosses with that identity; a plain
table cast to the same record type remains plain. The type alone cannot decide
which value arrives.

The following are therefore still rejected while copying:

- an unsendable value that arrived through `any`, `table`, or a record;
- tables with metatables other than an exported Nupp record declaration;
- cycles and repeated table aliases;
- tables deeper than 32 levels;
- keys outside the transferable scalar set.

A rejection names the position it found, so the message says which argument and
which field stopped the copy rather than that the message was untransferable:

```nupp
with scope = workers.scope() do
    const row = new jobs.Row(name = "a")

    -- The lane receives its own jobs.Row metatable, so its methods work there.
    scope:spawn(row, jobs.displayRow)

    const plain = {name = "a"}

    -- nupp: cannot copy task arguments: arguments[1][2] repeats a table
    -- already present in the message
    scope:spawn({plain, plain}, jobs.count)

    -- Two tables, and a lane that reads two rows:
    scope:spawn({{name = "a"}, {name = "a"}}, jobs.count)
end
```

All fields present on a record table cross, including dynamic fields not named
by the declaration. Only the canonical declaration metatable stamped by `new`
is reproducible. A prototype-style instance carrying a private metatable whose
`__index` points at a record is still rejected rather than silently losing that
private behavior.

Identity is a property of values rather than of types, which is why these stay
here whatever a signature said. A repeated table is rejected because decoding it
twice would silently turn one identity into two identities. Pass two explicit
copies if that is the intended meaning.

Each lane direction holds at most 1,024 messages and 256 MiB. Submission raises
when a bounded queue is full rather than turning producer backpressure into an
additional hidden wait.

## Moving owned buffers

One exception to the ownership refusal is deliberate. A worker parameter may
take a [](nupp.mem.heap) array of a fixed-width element, and an affine result
may return one; neither is a copy. The array's storage lives in neither Lua
heap, so the message hands its pointer across and the receiving lane becomes
the one owner. The spawn consumes the sender's binding, so touching it
afterwards is a compile error at the send site, and an affine result moves
ownership back to whichever lane awaits the task.

```nupp
module jobs

const heap = nupp.mem.heap

export function fill(takes frame: heap.Array<uint8>, seed: integer): affine(heap.Array<uint8>, heap.destroyArray)
    local writable = frame:write()
    for index = 1, #writable do
        writable[index] = (seed + index) % 256
    end
    drop writable

    return frame
end
```

```nupp
local frame = heap.allocate(ffi.typeof<uint8>(), 8 * 1048576)
with scope = workers.scope() do
    for generation = 1, 60 do
        frame = scope:spawn(frame, generation, jobs.fill):await()
    end
end
drop frame
```

Sixty generations shuttle one allocation between lanes with nothing copied
and nothing allocated after the first line. On the retained benchmark's
machine an 8 MiB buffer moves there and back in about 7 us where copying the
same working set as a string costs about 900, and the move's cost does not
grow with the payload; below tens of kilobytes the string copy's fast path
is still quicker, the same guidance regions carry.

Exactly one owner exists at any moment: a lane's binding, or the in-flight
message, which frees the allocation if it is destroyed unread by a cancelled
task, a closing queue, or a dying lane. A lane that keeps a received buffer
instead of returning it consumes it like any affine owner, with
`values:close()`. The element layout crosses as a tag the receiver validates
before rebuilding its owner, and primitive elements move; every other
ownership mode and element shape keeps the refusal above.

A move complements a region rather than replacing it: a
`sharedbytes.Region` shares immutable bytes with any number of readers,
while a move hands exclusive mutable storage to exactly one. Filling a
moved buffer and freezing the content into a region when it stops changing
is the intended composition, and there is no path back.

## Failure and termination

An error raised by the submitted function becomes that task's failure and is
raised in the parent by `await` or by scope exit when it was unobserved. Other
tasks continue to settle so the structured scope never abandons live children.

```nupp
export function observed(): string
    with scope = workers.scope() do
        const good = scope:spawn("alpha", jobs.hash)
        const bad = scope:spawn("beta", jobs.refuse)

        -- false, "nupp: worker task failed: ...: cannot hash beta"
        print(pcall(function(): nil
            bad:await()
        end))

        return good:await() -- the sibling ran anyway
    end
end

export function unobserved(): string
    with scope = workers.scope() do
        scope:spawn("beta", jobs.refuse)

        return jobs.hash("alpha") -- the failure is raised leaving the scope
    end
end
```

`observed` returns a hash and `unobserved` raises, from the same pair of
children. Handling a failure means observing it, and the way to observe one is
to await the task that carries it.

A running task is not preempted. Lua and foreign code have no safe general
interruption point, so leaving a scope waits for a task that is already running.
A bounded function can cooperate by calling `tasks.checkpoint()`:

```nupp
const tasks = nupp.tasks

export function search(limit: integer): integer
    for index = 1, limit do
        tasks.checkpoint()
        if matches(index) then return index end
    end
    return 0
end
```

The checkpoint raises the same nominal cancellation value that coroutine tasks
use. A task submitted through an [application task scope](task-scopes.md) inherits
that scope's absolute deadline; expiry becomes a cancellation request in the
native task registry. A normal result or application failure that wins the race
remains that result or failure.

`workers.scope()` itself has no deadline and cancelling one child does not
cancel its siblings. `scope:fork` on an application task scope is the fail-fast
form: the task scope requests cancellation for every unfinished worker child when
a sibling fails, then awaits running cleanup through the installed suspension
handler. The task scope owns that worker scope privately; `fork` is the only way
in.

The same rule applies to nontermination: an infinite worker task makes its
scope infinite. Worker tasks are for bounded CPU work. Durable work, retries
across process failure, and jobs that outlive the caller belong to a broker or
[](nupp.io.process), not this scheduler.

## Browser lanes

A browser application selects
[`nupp.runtime.backend.browser`](../../performance/ahead-of-time/wasm.md#browser-platform-backend),
which supplies `host.workers`, so everything above is written the same way there.
A lane is a module Web Worker holding its own Lua 5.1 Wasm state, booted from the
same verified application package the page loaded; the packaging step ships the
lane entry point beside the content-addressed runtime. Nothing is shared between
lanes, so no Wasm threads, no `SharedArrayBuffer`, and no cross-origin isolation
headers are involved.

The page's pool is bounded by `navigator.hardwareConcurrency`, and lanes boot as
work arrives rather than when the first scope opens.

Three things a program can observe differ, because a browser gives two Workers no
synchronous channel:

- a reply reaches the calling state when it next waits, so `Task:isDone` answers
  as of that point rather than the moment a lane produced the value;
- `Task:cancel` still reports whether it made the first request, but a queued
  task settles at the next wait rather than inside the call;
- reading a cancellation request costs one turn of the lane's event loop, so
  `tasks.checkpoint()` belongs at a granularity the loop chooses rather than on
  every iteration of a tight one.

One thing the native scheduler offers is not there. A [moved owned
buffer](#moving-owned-buffers) needs [](nupp.mem.heap), which the `lua51` dialect
has no storage capability for, so every ownership mode keeps the copy refusal.

Everything else is the same, [application task scopes](task-scopes.md) included:
`scope:fork` gives a browser page the fail-fast form, a scope deadline reaches a
lane, and `nupp.tasks.checkpoint()` is where a running lane observes that its
cancellation was requested.

See [NEP 18](../../../neps/0018-structured-worker-tasks.md) for the design tradeoffs
behind structured worker tasks.
