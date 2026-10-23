---
order: 150
---

# Worker tasks

`nupp.workers` runs sendable functions in parallel on a shared,
bounded scheduler whose lanes are native threads, each running its own VM.
A lane is reached through `fork` on an [application task scope](task-scopes.md),
which owns the worker children it starts. Arguments and results cross as copies,
while heaps and their globals, userdata, cdata, and mutable module state stay
isolated. Eligible closure captures cross only as independent copies.

```nupp
module jobs

export function hash(bytes: string): string
    return nupp.util.fnv1a64(bytes)
end
```

```nupp:fragment
module main

const jobs = require("jobs")
const tasks = nupp.tasks

export function hashes(left: string, right: string): (string, string)
    with scope = tasks.open() do
        const first = scope:fork(left, jobs.hash)
        const second = scope:fork(right, jobs.hash)

        return first:await(), second:await()
    end
end
```

`jobs.hash` is still an ordinary function. Calling `jobs.hash(bytes)` runs it
in the current VM; passing it to `scope:fork` runs it on the worker
scheduler. There is no worker declaration or parallel version of the function.

Workers run under `nupp run` and in a `binary` target alike: the VM runtime
carries the scheduler, so nothing has to be configured to use them.

## Structured scopes

Every worker task belongs to the task scope that forked it. Leaving the exact
`with` extent waits for all of its children, including tasks the body never
awaited and every path out by return or error.

```nupp:fragment
with scope = tasks.open() do
    scope:fork(snapshot, jobs.rebuildIndex)
end -- rebuildIndex has settled here
```

`Task:await()` returns exactly the values the function returns. The argument
list and complete result pack are inferred from that function, so wrong
arguments and wrong result uses are ordinary type errors at the call site.

Awaiting a settled task is repeatable. A failure is raised by `await`, and it is
the scope's from the moment it happens, whether or not anything awaits it: the
scope cancels its unfinished children, waits for them, and raises the failure
where the block is left. [Failure and termination](#failure-and-termination)
says more.

`Task:isDone()` returns whether a reply has arrived without waiting for one. It
is a progress question, not a scheduling one: a task is settled or it is not,
and the way to have its values is still `await`.

`Task:status()` returns `queued`, `running`, `done`, `failed`, or `cancelled`.
`Task:cancel(reason)` idempotently requests cancellation and reports whether
this call made the first request. A queued cancellation settles immediately and
the lane discards its work frame without loading or invoking the function. A
running task is cooperative as described under [Failure and
termination](#failure-and-termination).

`Task:await()` and leaving the block are suspension-aware. With a [suspension
handler](suspension.md) they park the current coroutine; without one they sleep
on the native channel.

## Fanning out over a list

Two forks are two lines; a list is a loop. A scope is never told in advance
how many children it will have.

A handle borrows the scope that made it, so it lives in a local rather than a
table. A list therefore fans out through children: each one forks its item and
waits for it, and the children wait together, so every item is on a lane at
once.

```nupp:fragment
export function hashEach(inputs: {string}): {string}
    local hashed: {string} = {}

    local function hashInto(index: integer, bytes: string): nil
        with lane = tasks.open() do
            hashed[index] = lane:fork(bytes, jobs.hash):await()
        end
    end

    with scope = tasks.open() do
        for index, bytes in ipairs(inputs) do
            scope:spawn(index, bytes, hashInto)
        end
    end

    return hashed
end
```

Waiting inside the loop that forks would fork one task, wait for it, and fork the
next: still correct, and exactly as parallel as calling the function. A handle
rarely needs a type annotation, because `const task = scope:fork(bytes,
jobs.hash)` infers one. Where one is written, it is `nupp.tasks.Task<F>`, named
by the submitted function's type: the handle is derived from the signature
alone, so it is `nupp.tasks.Task<function(string): string>` even though [`fork`
requires an `@sendable` function](#functions-that-can-be-submitted).

### Work in the caller

The calling thread has nothing to do while lanes run. Give it a share when the
work divides:

```nupp:fragment
export function bothHashes(left: string, right: string): (string, string)
    with scope = tasks.open() do
        const task = scope:fork(right, jobs.hash)
        const mine = jobs.hash(left)

        return mine, task:await()
    end
end
```

### Batches instead of items

Arguments and results are copied, so a task whose work is smaller than its
message spends longer being sent than being run. Submit chunks of a list rather
than its elements when the work per element is small:

```nupp:fragment
export function hashChunks(inputs: {string}, size: integer): {string}
    local chunks: {{string}} = {}

    local function hashChunk(at: integer, chunk: {string}): nil
        with lane = tasks.open() do
            chunks[at] = lane:fork(chunk, jobs.hashAll):await()
        end
    end

    with scope = tasks.open() do
        local count = 0
        for first = 1, #inputs, size do
            local chunk: {string} = {}
            for offset = first, math.min(first + size - 1, #inputs) do
                chunk[#chunk + 1] = inputs[offset]
            end
            count = count + 1
            scope:spawn(count, chunk, hashChunk)
        end
    end

    local hashed: {string} = {}
    for _, chunk in ipairs(chunks) do
        for _, one in ipairs(chunk) do
            hashed[#hashed + 1] = one
        end
    end

    return hashed
end
```

`jobs.hashAll` is the ordinary loop over `jobs.hash`, exported like anything
else. Lanes are bounded by the host's processor count, so a chunk count near
that number is the useful knob; ten thousand one-element tasks queue behind the
same lanes and pay ten thousand copies to do it.

## Shared scheduler

The first fork creates one scheduler for the process. Its lane count is the
host's online processor count, capped at 64, and
`nupp.system.availableParallelism()` returns that count without opening
anything. Later and concurrent scopes reuse the same lanes rather than creating
a pool or a thread per task.

Submission chooses the lane with the fewest unsettled tasks. Each lane runs
one task at a time in its own VM, while different lanes run in parallel.
The lanes remain alive until process exit so repeated short scopes do not pay
VM startup for every task.

The scheduler also owns one suspension readiness source. A poll pass drains
available replies from every lane and wakes the tasks that settled. Awaiting
many tasks therefore does not register one source or lock every lane again for
each awaiter.

A worker task cannot fork. Its isolated state cannot submit back into the
parent scheduler without either exposing scheduler internals across the heap
boundary or risking that a lane waits on itself.

```nupp
module jobs.index

const tasks = nupp.tasks

-- Submitting this raises where it forks: a worker task cannot open another
-- worker scope.
export function countAll(shards: {{string}}): integer
    local total: integer = 0
    with scope = tasks.open() do
        for _, paths in ipairs(shards) do
            total = total + scope:fork(|| -> #paths):await()
        end
    end

    return total
end

-- One shard of the same work, which a lane can run.
export function count(paths: {string}): integer
    return #paths
end
```

Compose nested parallel work in the calling state instead, and pass each leaf
operation to the shared scheduler. A tree of work becomes a flat submission of
its leaves:

```nupp:fragment
const indexJobs = jobs.index

export function countAll(shards: {{string}}): number
    local total: number = 0

    local function countShard(paths: {string}): nil
        with lane = tasks.open() do
            total = total + lane:fork(paths, indexJobs.count):await()
        end
    end

    with scope = tasks.open() do
        for _, paths in ipairs(shards) do
            scope:spawn(paths, countShard)
        end
    end

    return total
end
```

This is an executor, not an actor system. A task is a request-and-response call
whose inputs and results cross the boundary. Long-lived stateful ownership and
mailboxes would be a separate abstraction.

## Functions that can be submitted

The final argument to `fork` must be a `@sendable function`. A function read
from a loaded module is sendable with no captures:

```nupp:fragment
module image.jobs

export function resize(input: string, width: integer): string
    return resizeBytes(input, width)
end
```

```nupp:fragment
const imageJobs = image.jobs
const task = scope:fork(bytes, 320, imageJobs.resize)
```

The function reference is also the build dependency. The binary automatically
carries `image.jobs`; there is no list of worker entries in `nupp.lua`.

An eligible function literal is sendable too. Its activation-local captures are
snapshotted when the literal is created and copied with the explicit arguments:

```nupp:fragment
scope:fork(bytes, |input: string| -> imageJobs.resize(input, requestedWidth))
```

The binding `requestedWidth` must be initialized and never reassigned. Its value
must be copyable, just like an explicit argument. The source file must declare a
module so a worker VM has a stable place to load the outlined body. The local
value is still an ordinary closure when called directly; outlining is additional
worker metadata, not a different local calling convention.

Module locals are reconstructed independently when that module loads in a lane.
Activation locals are copied as captures. In neither case does an upvalue or
heap identity cross between VMs.

A callable held as a value keeps the guarantee only where the type says so, so a
dispatch table names it:

```nupp:fragment
const handlers: {[string]: @sendable function(string): string} = {
    hash = jobs.hash,
    resize = jobs.resize,
}
```

`nupp reference --section sendable-callables` describes contextual literals,
effective finality, and how the guarantee travels through types.

The worker requires the module in its own VM and invokes the authored export
or compiler-registered outline. Top-level module initialization therefore runs
once in each lane that first uses the module. Treat mutable module state as
lane-local, not shared state.

A module that raises while loading in a lane fails the task that needed it, and
so does a record value whose declaring module cannot load there. Neither ends
the lane: later tasks sent to it run normally.

## Values crossing the boundary

Transferable values are nil, booleans, numbers, strings, and tables recursively
made from those values with scalar keys. An instance built by an exported Nupp
record declaration is transferable too. Each receiver decodes an independent
copy, and a record receives that VM's declaration table as its metatable.
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
which value arrives. The checker's guarantee is therefore one level deep -- each
capture and argument is held to its declared type -- and the transport walks the
values themselves when the message is built, at `fork`.

The following are therefore still rejected while copying:

- an unsendable value that arrived through `any`, `table`, or a record;
- tables with metatables other than an exported Nupp record declaration;
- cycles and repeated table aliases;
- tables deeper than 32 levels;
- keys outside the transferable scalar set.

A rejection names the position it found, so the message says which argument and
which field stopped the copy rather than that the message was untransferable:

```nupp:fragment
with scope = tasks.open() do
    const row = new jobs.Row(name = "a")

    -- The lane receives its own jobs.Row metatable, so its methods work there.
    scope:fork(row, jobs.displayRow)

    const plain = {name = "a"}

    -- nupp: cannot copy task arguments: arguments[1][2] repeats a table
    -- already present in the message
    scope:fork({plain, plain}, jobs.count)

    -- Two tables, and a lane that reads two rows:
    scope:fork({{name = "a"}, {name = "a"}}, jobs.count)
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
`nupp: a worker queue is full` when a lane's task queue is full rather than
turning producer backpressure into an additional hidden wait; awaiting what is
already submitted makes room. A lane that has closed for good refuses with
`nupp: a worker lane is closed` instead, which no retry reaches. A lane whose reply queue is full waits instead, until
the parent awaits or polls and takes replies off it, because a refused reply
would be a task its parent never hears of.

Each lane direction also names at most 256 distinct record types. A task or a
result that would carry a 257th fails with a message saying so; the lane keeps
running, and so do tasks whose values use records it already carries.

## Moving owned buffers

One exception to the ownership refusal is deliberate. A worker parameter may
take a [](nupp.mem.heap) array of a fixed-width element, and an affine result
may return one; neither is a copy. The array's storage lives in neither VM's
heap, so the message hands its pointer across and the receiving lane becomes
the one owner. The fork consumes the sender's binding, so touching it
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
    nupp.drop(writable)

    return frame
end
```

```nupp:fragment
local frame = heap.allocate(ffi.typeof<uint8>(), 8 * 1048576)
with scope = tasks.open() do
    for generation = 1, 60 do
        frame = scope:fork(frame, generation, jobs.fill):await()
    end
end
nupp.drop(frame)
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

An error raised by the submitted function becomes that task's failure, worded
`nupp: worker task failed: ...`, and the scope's from the moment it happens. The
scope cancels its unfinished children, waits for every one of them so it never
abandons a live child, and raises the failure where the block is left. `await`
raises it too, and so does any later task operation in the scope.

```nupp:fragment
export function observed(): string
    local digest = ""
    with scope = tasks.open() do
        const bad = scope:fork("beta", jobs.refuse)

        -- false, "nupp: worker task failed: ...: cannot hash beta"
        print(pcall(function(): nil
            bad:await()
        end))

        digest = jobs.hash("alpha") -- the block goes on, but the scope has failed
    end

    return digest -- not reached: leaving the scope raised the failure
end

export function unobserved(): string
    with scope = tasks.open() do
        scope:fork("beta", jobs.refuse)

        return jobs.hash("alpha") -- the failure is raised leaving the scope
    end
end
```

A worker failure carries its message and the worker's traceback back to the
caller. The stack is captured before the worker call unwinds, so it identifies
where the worker failed. Cancellation keeps its separate identity and does not
become a failure with a traceback. A bytecode payload stripped of debug
information retains stack frames but cannot recover stripped names or lines.

Both raise. A scope is fail-fast rather than a supervisor, so a failure is
handled where the scope is left, not by awaiting the task that carries it. Where
each item should keep its own outcome, give each one a scope of its own, as the
[fan-out](#fanning-out-over-a-list) children do, and catch there.

A running task is not preempted. Running code and foreign calls have no safe
general interruption point, so leaving a scope waits for a task that is already running.
A bounded function can cooperate by calling `tasks.checkpoint()`:

```nupp:fragment
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

Cancelling one child with `Task:cancel` does not cancel its siblings, and
`scope:cancel` cancels every one. When a sibling fails, the task scope requests
cancellation for every unfinished worker child, then awaits running cleanup
through the installed suspension handler. The task scope owns its family of
lanes privately; `fork` is the only way in.

The same rule applies to nontermination: an infinite worker task makes its
scope infinite. Worker tasks are for bounded CPU work. Durable work, retries
across process failure, and jobs that outlive the caller belong to a broker or
[](nupp.io.process), not this scheduler.
