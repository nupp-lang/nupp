---
order: 145
---

# Application task scopes

`nupp.tasks` owns the coroutine and worker work that belongs to one application
operation. A scope is opened with `open` and held by a `with`: the block is the
scope's body, and leaving it settles the scope, so every child has run, been
cancelled, or unwound before the block is left. The first child failure cancels
unfinished siblings and becomes the scope's failure.

```nupp
export function load(): string
    local loaded = ""
    with scope = nupp.tasks.open() do
        const atlas = scope:spawnNamed("load atlas", function(): string
            return readAtlas()
        end)
        const settings = scope:spawn(function(): string
            return readSettings()
        end)
        loaded = atlas:await() .. settings:await()
    end

    return loaded
end
```

The standard library is reached by nesting; nothing here is required.

## Children

`spawn` starts a child on the scope's coroutine driver and `fork` starts one on a
worker lane. Both have one shape: arguments first, callable last, and both answer
a `Task<F>`.

```nupp
const page = scope:spawn(function(): string return fetchPage() end)
const size = scope:spawn(url, measure)                 -- measure(url: string): integer
const thumbnail = scope:fork(bytes, jobs.thumbnail)    -- on a worker lane
```

A module function with arguments builds nothing per call, which is what a loop
that spawns many children wants; the `jit-loop-closure` lint says so where a
per-iteration closure is written instead. A bare body is the zero-argument case.
Arguments to `spawn` are plain values: an owner or a borrow cannot be tracked
through the table the child unpacks them from. Arguments to `fork` are copied
into another Lua state, and the callable must be sendable, a module function or a
literal whose effectively-final captures can be copied. The selected worker
provider says which values may cross: the native provider moves an engine-backed
`nupp.mem.heap` buffer, the browser provider refuses every ownership mode.

`await` returns the body's complete result pack, including nil positions, and
may be called again after settlement. `isDone` checks settlement without
waiting, and `status` answers `queued`, `running`, `done`, `failed`, or
`cancelled`. Handles borrow the scope that created them: one cannot be returned
from the block or stored past it, so a task never becomes detached work.


## Bounded fan-out

`open(limit = n)` parks `spawn` and `fork` while `n` children are live. The loop
that spawns is the source, and a settlement is what lets it continue, so nothing
is pulled from the source before there is room to run it. A worker child holds a
slot until its lane answers.

```nupp
const sizes: {integer} = {}
with scope = nupp.tasks.open(limit = 8) do
    for index, url in ipairs(urls) do
        scope:spawn(sizes, index, url, storeSize)
    end
end
```

Iteration is whatever the loop says: an array, `pairs`, a generator, a paginated
cursor. A child holds its own result when it finishes, so it processes it there,
in completion order by construction. A worker result comes back through the
child that awaits it, which is the child that occupies the slot:

```nupp
with scope = nupp.tasks.open(limit = nupp.workers.__parallelism()) do
    for name, path in pairs(paths) do
        scope:spawn(function(): nil
            total = total + scope:fork(name, path, jobs.compress):await()
        end)
    end
end
```

## Cancellation

`Task:cancel(reason)` makes the first cancellation request and reports whether
this call was first. A queued coroutine child never enters its body. A parked
child is resumed far enough to unwind its cleanup. Running Lua is cooperative:
it notices cancellation when it suspends, returns, or calls
`nupp.tasks.checkpoint()`.

```nupp
const child = scope:spawn(function(): integer
    local total = 0
    for index = 1, 1000000 do
        nupp.tasks.checkpoint()
        total = total + index
    end
    return total
end)

child:cancel("scene ended")
```

`scope:cancel(reason)` requests cancellation of every child as the scope's own
decision. Queued children settle without running, running ones observe the
request at their next checkpoint or wait, worker tasks are cancelled on their
lanes, and a child spawned afterwards settles as cancelled without running.
Because the scope asked for it, leaving the block afterwards does not raise. This
is how the first result wins:

```nupp
local winner: string? = nil
with scope = nupp.tasks.open(limit = 4) do
    for _, mirror in ipairs(mirrors) do
        if winner ~= nil then break end
        scope:spawn(function(): nil
            const answer = scope:fork(mirror, jobs.probe):await()
            if answer ~= nil and winner == nil then
                winner = answer
                scope:cancel("a mirror answered")
            end
        end)
    end
end
```

Cancellation raises one nominal value. `nupp.tasks.isCancelled(problem)`
recognizes it after a `pcall`; its text includes the child operation and reason.
A child name is also the operation an installed suspension handler sees when
that child parks.

A `takes` capture moves into the child. Cancelling before the child starts
drops the uncalled closure and its captures. A borrowed affine capture is
refused because `spawn` returns before the child must settle.

## Failure ownership

The scope owns the first child failure even when nobody awaits that child. It
cancels unfinished siblings, drains them, and raises the failure where the block
is left. The block learns of it sooner where it is waiting: a child failure
cancels the block's own wait, so a `spawn`, an `await`, or a sleep in the block
raises it rather than the scope waiting for the block's next task operation.

An await settles against the scope before its named task. It can therefore
raise a sibling's failure: the application scope is fail-fast, rather than a
supervisor. Use [`gather`](#whole-family-calls) when failures should remain
beside individual results.

The block is not a child of the scope, so a failure the block itself raises does
not cancel the children: they run to completion before the failure propagates.
Call `scope:cancel()` first where that is not wanted.

## Whole-family calls

A family that is complete at the call does not need a block to hold it.
`nupp.tasks.gather` and `nupp.tasks.race` take the bodies, run each in a
coroutine of its own, and settle every one before returning, so neither answers
a scope a caller has to discharge.

`gather` returns parallel value and error arrays, indexed as the bodies were,
for a caller who has to see every outcome:

```nupp
const values, errors = nupp.tasks.gather({
    function(): string return fetch(primary) end,
    function(): string return fetch(mirror) end,
})
```

Its branches are fail-soft, which is the one thing a scope will not do: a
branch that raises reports its error beside its siblings' values rather than
cancelling them.

`race` returns the first settled value and its one-based index, then cancels
and unwinds the rest:

```nupp
const answer, which = nupp.tasks.race({
    function(): Head return upload(transfer) end,
    function(): Head return head(transfer) end,
})
```

A loser is resumed once so its park cancels and its branch unwinds through
whatever cleanup it had, and one that had not started never starts. Because the
call does not return until every body it entered has settled, a body may be
moved into it: an owner captured by a `race` branch is consumed or dropped
exactly once, which is what `spawn` cannot promise for a handle that outlives
it.

A family opened inside a bounded scope inherits that scope's deadline, and
raises its cancellation rather than its branch outcomes where it passes.

## Deadlines

`open(deadline = milliseconds)` bounds the scope on the monotonic clock. A
scope opened inside another takes the earlier of its own deadline and the
enclosing scope's, so a child may bound itself more tightly than its parent did
and may not extend what its parent already promised. `nupp.tasks.deadline()`
answers the current absolute deadline, or nil outside a bounded scope.

```nupp
with scope = nupp.tasks.open(deadline = 5000) do
    index(scope:spawn(url, fetch):await())
end
```

Expiry requests ordinary structured cancellation, and it reaches the block's own
wait as it reaches a child's. It does not preempt running Lua, C, or
operating-system code, and the scope still waits for cleanup. A deadline's
cancellation is the scope's promise broken, so unlike `scope:cancel()` it is
raised where the block is left.

Both arguments are named: `open()`, `open(limit = 8)`, `open(deadline = 500)`,
or `open(limit = 8, deadline = 500)`.

## Settlement

`nupp.tasks.settle` is the terminal `open` carries, and what leaving the `with`
calls. It is a settling terminal: it parks until every child has settled and the
owned worker scope has been closed through the suspension-aware path, and so it
is refused inside a `nosuspend` region. A scope may be settled by hand before its
block ends; it settles once. Operations on a settled scope raise.

Direct `workers.scope()` remains useful in blocking programs. Its terminal
settles the scope the same way: under a suspension handler it parks until every
child has settled, and without one it drains synchronously.

## Host scheduling

An installed [suspension handler](suspension.md) schedules the aggregate, not
each child. Nupp resumes children in FIFO order and consumes at most 64 child
activations in one host turn. Nested task scopes and the suspension combinators
share that token; they do not multiply the budget. Exhaustion performs one
ordinary suspension and resumes from the next host poll.

The block that opened a scope is not a coroutine child, so while it waits on
anything at all, `open` installs a driver in front of the host that runs the
children meanwhile and hands outward what it cannot satisfy. The driver is
transparent to the turn budget: where no host is beneath it, as at the root of
an ordinary program, the turn is unbounded exactly as it is where nothing is
installed.

This is the native application integration boundary: a host such as SDL or
Tecs keeps ownership of the main thread, frame barriers, priorities, and poll
points, while Nupp owns ordering inside one aggregate. A handler that refuses
parking remains visible through nested task scopes and combinators. Readiness
callbacks only mark work ready; they do not resume application code inside a
native, UI, or ECS callback.

The budget is cooperative. One activation can compute until it returns or
parks, so long CPU work still belongs on a worker and should call
`nupp.tasks.checkpoint()` when cancellation latency matters.
