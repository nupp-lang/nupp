---
order: 145
---

# Application task scopes

`nupp.tasks` owns coroutine and worker work that belongs to one application
operation. A scope does not return until its body and every child have settled.
The first child failure cancels unfinished siblings and becomes the scope's
failure.

```nupp
const tasks = require("nupp.tasks")

export function load(): string
    return tasks.run(function(scope: tasks.Scope): string
        const atlas = scope:spawnNamed("load atlas", function(): string
            return readAtlas()
        end)
        const settings = scope:spawn(function(): string
            return readSettings()
        end)

        return atlas:await() .. settings:await()
    end)
end
```

`spawn` takes its body and returns a typed `Task<F>`. `await` returns the
body's complete result pack, including nil positions. It may be called again
after settlement. `isDone` checks settlement without waiting, and `status`
answers `queued`, `running`, `done`, `failed`, or `cancelled`.

## Cancellation

`Task:cancel(reason)` makes the first cancellation request and reports whether
this call was first. A queued coroutine child never enters its body. A parked
child is resumed far enough to unwind its cleanup. Running Lua is cooperative:
it notices cancellation when it suspends, returns, or calls
`tasks.checkpoint()`.

```nupp
const child = scope:spawn(function(): integer
    local total = 0
    for index = 1, 1000000 do
        tasks.checkpoint()
        total = total + index
    end
    return total
end)

child:cancel("scene ended")
```

Cancellation raises one nominal value. `tasks.isCancelled(problem)` recognizes
it after a `pcall`; its text includes the child operation and reason. A child
name is also the operation an installed suspension handler sees when that child
parks.

A `takes` capture moves into the child. Cancelling before the child starts
drops the uncalled closure and its captures. A borrowed affine capture is
refused because `spawn` returns before the child must settle.

## Failure ownership

The scope owns the first child failure even when nobody awaits that child. It
cancels unfinished siblings, drains them, and raises the failure. If the scope
body raises first, its error stays primary while child cleanup still runs.

An await settles against the scope before its named task. It can therefore
raise a sibling's failure: the application scope is fail-fast, rather than a
supervisor. Use [`suspension.gather`](suspension.md#combinators-interleave-waits)
when failures should remain beside individual results.

Task handles borrow the scope that created them. Returning one from the `run`
body is a type error; a task never becomes detached work.

## Deadlines

`tasks.runFor(milliseconds, body)` adds a monotonic deadline. A nested scope
uses the earlier of its requested deadline and its parent's. `tasks.deadline()`
answers the current absolute monotonic deadline, or nil outside a bounded task.

```nupp
const answer = tasks.runFor(5000, function(scope: tasks.Scope): string
    return scope:spawn(fetch):await()
end)
```

Expiry requests ordinary structured cancellation. It does not preempt running
Lua, C, or operating-system code, and the scope still waits for cleanup.

## Worker children

`Scope:workers()` lazily returns the one [worker scope](workers.md) this task
scope owns. It is borrowed from the task scope, so callers do not close it and
cannot return it. The application scope closes it through the installed
suspension handler.

```nupp
const jobs = require("image.jobs")

tasks.run(function(scope: tasks.Scope): nil
    const parallel = scope:workers()
    const thumbnail = parallel:spawn(bytes, jobs.thumbnail)
    save(thumbnail:await())
end)
```

Worker cancellation uses the same `cancel`, `status`, cancellation identity,
deadline, and `tasks.checkpoint()`:

- cancellation prevents a queued worker task from invoking its function;
- a running worker observes the request at `tasks.checkpoint()` or return;
- a checkpoint-free function is not interrupted and keeps the scope open.

Direct `workers.scope()` remains useful in blocking programs. Its affine
terminal cannot suspend, so terminal cleanup drains synchronously. The opt-in
`blocking-worker-drop` performance lint points application paths toward a
task-owned worker scope.

## Host scheduling

An installed [suspension handler](suspension.md) schedules the aggregate, not
each child. Nupp resumes children in FIFO order and consumes at most 64 child
activations in one host turn. Nested task scopes and the suspension combinators
share that token; they do not multiply the budget. Exhaustion performs one
ordinary suspension and resumes from the next host poll.

This is the SDL/Tecs integration boundary: the host keeps ownership of the main
thread, frame barriers, priorities, and poll points, while Nupp owns ordering
inside one aggregate. A handler that refuses parking remains visible through
nested task scopes and combinators. Readiness callbacks only mark work ready;
they do not resume application code inside an SDL, native, or ECS callback.

The budget is cooperative. One activation can compute until it returns or
parks, so long CPU work still belongs on a worker and should call
`tasks.checkpoint()` when cancellation latency matters.
