---
order: 140
---

# Suspension

A suspension-aware function waits without changing its call syntax or return
type. The same call blocks in a command-line program and parks its coroutine
where a host installed a [suspension handler](#hosts-supply-scheduling-policy):

```nupp
local child = assert(io.popen({"cc", "--version"}))
local result = assert(child:communicate())
print(result.output)
child:close()
```

::: note Only suspension-aware calls can park
An arbitrary blocking function or C call still blocks the operating-system
thread. A library opts into suspension through `coroutine.suspend`; the runtime
does not intercept other calls.
:::

## Waits block or park

`communicate` follows one of three paths:

- A ready child returns without polling, parking, or switching coroutines.
- A pending child with no handler makes the current thread drive registered
  readiness sources until the child finishes.
- A pending child under a handler makes the handler park this coroutine while
  the host runs other work.

The library describes the wait. The handler owns scheduling policy, and the
caller's result remains `io.Process.Result` on every path. See [Child
processes](io) for the operation itself.

## Hosts supply scheduling policy

A command-line program needs no handler. A host supplies one when blocking the
thread would stop unrelated work:

- A game engine parks a loading coroutine and renders the next frame.
- A server parks one request and serves other connections.
- A UI runtime parks a task and continues processing input.
- A test scheduler controls exactly when a suspended operation resumes.

A root task installs the host's handler, then ordinary functions beneath it can
park without accepting a scheduler parameter:

```nupp:fragment [main.nupp]
local frame = require("scheduler")

local function printCompilerVersion(): nil
    local child = assert(io.popen({"cc", "--version"}))
    print(assert(child:communicate()).output)
    child:close()
end

local function application(): nil
    local installation = coroutine.sus.host.install(frame.handler)
    printCompilerVersion()
end

frame.run(application)
```

`frame.handler` is an ordinary value. It is not a keyword, a global scheduler,
or a handler built into Nupp. The `application` function defines its dynamic
scope. Most application code only consumes a handler this way. Framework authors
and scheduler integrations implement one, as [Writing a frame
handler](#writing-a-frame-handler) shows.

Installing is `coroutine.sus.host`, and parking is
`coroutine.suspend`. The two jobs belong to different people: a library makes
itself waitable and never installs a handler, while a host decides what runs
meanwhile and never subscribes to a readiness source. Keeping them apart means
neither reads past the other's operations to find its own.

### Waits park one coroutine

When `child:communicate()` cannot finish immediately, control makes a round
trip:

1. The process library registers its readiness source and cancellation
   function.
2. The suspension runtime calls `frame.handler.park` with the pending wait.
3. The handler records the current coroutine and yields it to the event loop,
   which runs another coroutine, request, or frame.
4. `suspension.poll()` discovers that the child has completed, the library
   resumes the wait, and the handler queues its coroutine again.
5. The coroutine runs, and `communicate()` returns its `io.Process.Result`.

The handler decides when the coroutine runs again. It never supplies the result;
the library's guarded `resume` function does that.

## Function signatures stay synchronous

Waiting does not introduce `async function`, `await`, or a future return type.
An ordinary wrapper returns the value produced after the wait:

```nupp
local function compilerVersion(): string
    local child = assert(io.popen({"cc", "--version"}))
    local result = assert(child:communicate())
    child:close()
    return result.output
end

local function printVersion(): nil
    print(compilerVersion())
end

printVersion()
```

The compiler infers that `compilerVersion` and `printVersion` may suspend, and
that fact travels separately from their parameter and result types.

## Suspension propagates through calls

A direct `coroutine.yield` is what marks a function as suspending. The fact
propagates through resolved calls and across module boundaries, so a caller that
needs uninterrupted control gets it without annotating every function on the
path.

### Non-suspending regions

`@nosuspend do` requires every call inside the region to prove that it cannot
suspend:

```nupp
local function commit(write: @nosuspend function(): nil): nil
    @nosuspend do
        write()
    end
end

print(commit)
```

The region is lexical, static, and erased. It adds no runtime lock. An
unresolved call is refused too, because the checker cannot prove the guarantee
for a callee it cannot follow.

The annotation also attaches to a loop. It covers the header, implicit
iterator calls, body, and cleanup inside the loop:

```nupp
local total = 0
@nosuspend for index = 1, 3 do
    total = total + index
end
print(total)
```

This call path reaches `coroutine.yield`, so the region is reported, and the
report names the path from the call to the suspension:

```nupp:refused [pause.nupp]
local function pause(): nil
    coroutine.yield()
end

@nosuspend do
    pause()
end
```

```text [nupp check pause.nupp]
error: NUPP2701: `pause` may suspend, and this region forbids suspending
```

A cleanup running at a scope boundary is held to the same rule, because an
obligation is being discharged there and the discharge cannot be left half done.

### Function types carry the guarantee

`@nosuspend function(...)` describes a callback or host declaration whose body is
not visible:

```nupp
local type Reporter = @nosuspend function(message: string): nil

local function publish(report: Reporter): nil
    @nosuspend do
        report("committed")
    end
end

print(publish)
```

A non-suspending function fits an ordinary function slot. An ordinary function
does not fit an `@nosuspend` slot. The qualifier survives aliases, generics,
imports, and exports.

The guarantee covers suspension only. The function may allocate, mutate, perform
external I/O, or raise.

### Effect contracts publish the complete boundary

An [effect contract](../../language/effects.md) includes suspension in its `suspends` member:

```nupp [transport.d.nupp]
@effects(suspends = true, raises = true)
const receive: function(): string
```

Use `@effects` where an API needs a reviewed complete effect summary.
`@effects()` says that every modeled effect is absent, so it promises much more
than a `@nosuspend function` type does.

## Handler scope follows the coroutine

A handler is dynamically scoped per coroutine, not process-wide. A host often
wraps its root application task, which makes that handler application-wide in
practice:

```nupp:fragment
local frame = require("scheduler")
local suspension = coroutine.sus

local function childWork(): nil
    assert(suspension.handled())
end

local function application(): nil
    local installation = coroutine.sus.host.install(frame.handler)
    local task = suspension.create(childWork)
    local ok, problem = coroutine.resume(task)
    if not ok then
        error(problem)
    end
end

frame.run(application)
```

`suspension.create` creates an ordinary coroutine and makes it inherit the
handler installed where it was created. Inheritance is fixed at creation.
Continue to use `coroutine.resume`; no resume wrapper is required. A coroutine
made with `coroutine.create` inherits no handler. Natively a wait there drives
the readiness sources on the current thread; in a browser application, whose
only wait is a return to the page from its root coroutine, it raises "cannot
suspend here" and `suspension.cansuspend()` returns false.

A nested handler installation temporarily replaces the current handler and
restores the outer one when its region ends, so different coroutines may use
different handlers at the same time.

### Raw coroutine yields keep explicit control

`coroutine.yield` yields directly to the code that resumes the coroutine. It
does not register cancellation or give a handler responsibility for the
suspended stack.

## Running several waits together

Waiting on more than one thing at a time is a
[task scope](task-scopes.md), which owns the coroutines it starts and settles
them before it returns. This module supplies the effect those coroutines wait
through, and nothing that starts one.

## Libraries register readiness

A suspension-aware library calls `coroutine.suspend` with a subscription. This
example completes after its readiness source has been polled twice:

```nupp
local suspension = coroutine.sus

local function after(polls: integer, value: string): string
    return coroutine.suspend("counter", function(resume: function(string), context: suspension.Context): function()
        local left = polls
        context:source("counter", 10, function(): integer
            left = left - 1
            if left > 0 then
                return 0
            end
            resume(value)

            return 1
        end)

        return function(): nil
            left = 0
        end
    end)
end

print(after(2, "ready"))
```

The protocol has three rules:

1. `resume(value)` supplies the result exactly once.
2. A subscription that does not resume during the call returns a cancellation
   function, so every real park can be abandoned.
3. A source registered through the context belongs to that wait. The runtime
   drops it when the wait returns, raises, or is cancelled.

A poll function returns how many operations it settled, and zero means that
nothing completed during that pass. Lower priorities run first, with names
breaking ties. A wait with no handler and no source reports that it cannot make
progress instead of hanging.

## Writing a frame handler

This scheduler keeps a queue of runnable coroutines. Its event loop calls `tick`
once per frame to poll readiness sources and resume the tasks they woke.

```nupp [scheduler.nupp]
local suspension = coroutine.sus
local host = coroutine.sus.host

local runnable: {thread} = {}

local function enqueue(task: thread): nil
    runnable[#runnable + 1] = task
end

local function runReady(): nil
    local pass = runnable
    runnable = {}
    for _, task in ipairs(pass) do
        if coroutine.status(task) == "suspended" then
            local ok, problem = coroutine.resume(task)
            if not ok then
                error(problem)
            end
        end
    end
end
```

A waker may run before the park that registered it has yielded, when the wait
completes during the registration itself, so a task can be queued and have moved
on by the time its turn comes; the status check is what makes that harmless.

The handler itself is three members. `park` registers a waker that enqueues the
current coroutine, then yields until the wait is ready. `canpark` returns false
inside a host barrier where yielding would violate a runtime invariant.
`shutdown` drains work queued while the handled extent is ending.

```nupp:fragment [scheduler.nupp]
local scheduler = host.Handler(
    park = function(_: host.Handler, waiting: host.Waiting, _: function(): nil): nil
        local task = assert(coroutine.running())
        waiting:onresume(function(): nil
            enqueue(task)
        end)
        while not waiting:ready() do
            coroutine.yield()
        end
    end,
    canpark = function(_: host.Handler): boolean
        return true
    end,
    shutdown = function(_: host.Handler): nil
        while #runnable > 0 do
            runReady()
        end
    end
)
```

`waiting:onresume(wake)` is a notification, not value delivery. The readiness
source supplies the value through `resume`, and the waker makes the coroutine
runnable after that value exists. Arming once above the loop is enough because
`onresume` is settle-safe: a wait that completed during the subscription itself
runs the waker before `onresume` returns, so there is no window between arming
and the first `ready` check to guard against. The loop remains because a
scheduler may resume a coroutine for its own reasons, and a park ends only when
its wait is ready.

A handler is a record, so `host.Handler(...)` constructs it and the
checker holds each member to its declared signature. There is nothing to cast.

```nupp:fragment [scheduler.nupp]
local function tick(): nil
    suspension.poll()
    runReady()
end

local function run(body: function(): nil): nil
    local task = coroutine.create(body)
    local ok, problem = coroutine.resume(task)
    if not ok then
        error(problem)
    end
    while coroutine.status(task) ~= "dead" do
        tick()
    end
end

return {handler = scheduler, tick = tick, run = run}
```

`run` creates the root task used in the opening application, and its first
resume reaches `park` and yields. Each `tick` polls completion sources and
resumes tasks placed on `runnable`. A game host calls the same `tick` function
once per frame instead of using this standalone loop.

## Cancellation unwinds the parked stack

`host.install(handler)` returns an owned handler installation, a
`own.Closeable`. When its extent ends and it is closed, the runtime restores the previous handler, cancels outstanding
subscriptions, wakes their coroutines, and invokes `shutdown`. A cancelled
`suspend` raises inside its parked coroutine, so lexical resource drops run as
the stack unwinds.

Structured exits leave the region only after its installation has been closed.
`return` preserves all values, `break` and `continue` reach the loop that owns
them, and `goto` may reach a label outside:

```nupp:fragment
local frame = require("scheduler")

local function choose(): integer
    local installation = coroutine.sus.host.install(frame.handler)
    return 1
end

print(choose())
```

The lowering uses the same completion protocol as automatic resource cleanup,
which preserves a body failure as the primary error when closing the
installation fails too, while still reporting the close failure.

## C-call boundaries

A suspension cannot cross a native frame. A comparator called by `table.sort`,
a replacement called by `string.gsub`, and a C callback are non-yieldable
positions. The checker follows those callback bodies and reports a call inside
one that reaches a suspension:

```nupp:refused [compare.nupp]
local function pause(): nil
    coroutine.yield()
end

table.sort({2, 1}, function(a: integer, b: integer): boolean
    pause()

    return a < b
end)
```

```text [nupp check compare.nupp]
error: NUPP2702: `pause` may suspend, and `table.sort` cannot yield across the C call that reaches it
```

The same function is free to suspend anywhere else; the boundary belongs to the
invocation. Where an unknown C API hides the boundary from static analysis, the
runtime names the operation instead.

::: seealso
- [workers.md](workers.md) for CPU parallelism on native threads
- [](io) for the library these examples wait on
- [ownership.md](../ownership/index.md) for the cleanup a cancelled park unwinds
:::
