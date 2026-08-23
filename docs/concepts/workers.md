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

`Task:isDone()` answers whether a reply has arrived without waiting for one. It
is a progress question, not a scheduling one: a task is settled or it is not,
and the way to have its values is still `await`.

`Task:await()` and explicit `Scope:close()` are suspension-aware ordinary
calls. With a [suspension handler](suspension.md) they park the current
coroutine; without one they sleep on the native channel. Automatic cleanup
uses a blocking native drain because an affine terminal may not suspend while
ownership is being discharged.

## Fanning out over a list

Two spawns are two lines; a list is a loop. A scope is never told in advance
how many children it will have.

```nupp
export function hashEach(inputs: {string}): {string}
    with scope = workers.scope() do
        local tasks: {workers.Task<function(string): string>} = {}
        for index, bytes in ipairs(inputs) do
            tasks[index] = scope:spawn(jobs.hash, bytes)
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
annotation, because `const task = scope:spawn(jobs.hash, bytes)` infers one;
a table of them names the submitted function's type as `workers.Task<F>`. The
handle is derived from the signature alone, so it is spelled
`workers.Task<function(string): string>` even though [`spawn` took an
addressable one](#functions-that-can-be-submitted).

### Work in the caller

The calling thread has nothing to do while lanes run. Give it a share when the
work divides:

```nupp
export function bothHashes(left: string, right: string): (string, string)
    with scope = workers.scope() do
        const task = scope:spawn(jobs.hash, right)
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
            tasks[#tasks + 1] = scope:spawn(jobs.hashAll, chunk)
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

A worker task cannot open another worker scope. Its isolated state cannot
submit back into the parent scheduler without either exposing scheduler
internals across the heap boundary or risking that a lane waits on itself.

```nupp
module jobs.index

const workers = require("nupp.workers")

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
const indexJobs = require("jobs.index")

export function countAll(shards: {{string}}): number
    with scope = workers.scope() do
        local tasks: {workers.Task<function({string}): integer>} = {}
        for at, paths in ipairs(shards) do
            tasks[at] = scope:spawn(indexJobs.count, paths)
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

A submitted signature is held to this where it is written. A parameter or a
result no copy could reproduce is refused at the call site, and the message
names the path to it rather than the argument:

```
main.nupp:9:9: error: NUPP2006: argument 1.hook is a function, which cannot
  cross into another Lua state
```

Refused this way: functions, threads, userdata, cdata, C pointers, and any
parameter carrying an ownership mode, wherever one of them sits inside an
array, a tuple, a union, or a shape.

A type that says nothing definite is left to the copy. `any`, a bare `table`,
and a record all describe values that may or may not be copyable -- a record
built from a table literal is a plain table, while one built with `new` carries
its metatable -- so the type alone cannot refuse them.

The following are therefore still rejected while copying:

- an unsendable value that arrived through `any`, `table`, or a record;
- tables with metatables;
- cycles and repeated table aliases;
- tables deeper than 32 levels;
- keys outside the transferable scalar set.

A rejection names the position it found, so the message says which argument and
which field stopped the copy rather than that the message was untransferable:

```nupp
local record Row
    name: string
end

with scope = workers.scope() do
    const row = new Row(name = "a")

    -- nupp: cannot copy task arguments: arguments[1][1] has a metatable
    scope:spawn(jobs.count, {row as {name: string}})

    const plain = {name = "a"}

    -- nupp: cannot copy task arguments: arguments[1][2] repeats a table
    -- already present in the message
    scope:spawn(jobs.count, {plain, plain})

    -- Two tables, and a lane that reads two rows:
    scope:spawn(jobs.count, {{name = "a"}, {name = "a"}})
end
```

A record is a nominal value carrying a metatable, so widening it to its
structural shape does not make it transferable: build the plain table the lane
should receive.

Identity is a property of values rather than of types, which is why these stay
here whatever a signature said. A repeated table is rejected because decoding it
twice would silently turn one identity into two identities. Pass two explicit
copies if that is the intended meaning.

Each lane direction holds at most 1,024 messages and 256 MiB. Submission raises
when a bounded queue is full rather than turning producer backpressure into an
additional hidden wait.

## Failure and termination

An error raised by the submitted function becomes that task's failure and is
raised in the parent by `await` or by scope exit when it was unobserved. Other
tasks continue to settle so the structured scope never abandons live children.

```nupp
export function observed(): string
    with scope = workers.scope() do
        const good = scope:spawn(jobs.hash, "alpha")
        const bad = scope:spawn(jobs.refuse, "beta")

        -- false, "nupp: worker task failed: ...: cannot hash beta"
        print(pcall(function(): nil
            bad:await()
        end))

        return good:await() -- the sibling ran anyway
    end
end

export function unobserved(): string
    with scope = workers.scope() do
        scope:spawn(jobs.refuse, "beta")

        return jobs.hash("alpha") -- the failure is raised leaving the scope
    end
end
```

`observed` returns a hash and `unobserved` raises, from the same pair of
children. Handling a failure means observing it, and the way to observe one is
to await the task that carries it.

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
