# Suspension

A suspension-aware function waits without changing its call syntax or return
type. The same call blocks in a command-line program and parks its coroutine
where a host installed a [suspension handler](#hosts-supply-scheduling-policy):

```nupp:playground
local process = require("nupp.io.process")

local child = assert(process.new({args = {"cc", "--version"}}))
local result = assert(child:communicate())
print(result.output)
child:close()
```

::: note Only suspension-aware calls can park
An arbitrary blocking Lua or C function still blocks the operating-system
thread. A library opts into suspension through `nupp.suspension`; the runtime
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
caller's result remains `process.Result` on every path. See [Child
processes](../modules/nupp/io.md) for the operation itself.

## Hosts supply scheduling policy

A command-line program needs no handler. A host supplies one when blocking the
thread would stop unrelated work:

- A game engine parks a loading coroutine and renders the next frame.
- A server parks one request and serves other connections.
- A UI runtime parks a task and continues processing input.
- A test scheduler controls exactly when a suspended operation resumes.

A root task installs the host's handler, then ordinary functions beneath it can
park without accepting a scheduler parameter:

```nupp [main.nupp]
local frame = require("scheduler")
local process = require("nupp.io.process")

local function printCompilerVersion(): nil
    local child = assert(process.new({args = {"cc", "--version"}}))
    print(assert(child:communicate()).output)
    child:close()
end

local function application(): nil
    handle suspension with frame.handler do
        printCompilerVersion()
    end
end

frame.run(application)
```

`frame.handler` is an ordinary value. It is not a keyword, a global scheduler,
or a handler built into Nupp. The `application` function defines its dynamic
scope. Most application code only consumes a handler this way. Framework authors
and scheduler integrations implement one, as [Writing a frame
handler](#writing-a-frame-handler) shows.

::: deepdive
Suspension is one effect with handlers rather than general algebraic effects,
which would be a much larger language than anything here needs. One effect buys
the property a host wants, which is that a wait deep inside a library reaches
the handler installed around the task, and it costs one construct in the grammar
and one fact in the checker rather than an effect system every signature has to
carry.

See [NEP 5](../neps/0005-suspension.md) for more information.
:::

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
5. The coroutine runs, and `communicate()` returns its `process.Result`.

The handler decides when the coroutine runs again. It never supplies the result;
the library's guarded `resume` function does that.

## Function signatures stay synchronous

Waiting does not introduce `async function`, `await`, or a future return type.
An ordinary wrapper returns the value produced after the wait:

```nupp
local process = require("nupp.io.process")

local function compilerVersion(): string
    local child = assert(process.new({args = {"cc", "--version"}}))
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

`nosuspend do` requires every call inside the region to prove that it cannot
suspend:

```nupp
local function commit(write: nosuspend function(): nil): nil
    nosuspend do
        write()
    end
end

print(commit)
```

The region is lexical, static, and erased. It adds no runtime lock. An
unresolved call is refused too, because the checker cannot prove the guarantee
for a callee it cannot follow.

This call path reaches `coroutine.yield`, so the region reports
[NUPP2701](../reference/diagnostics.md#diagnostic-index) and names the path from
the call to the suspension:

```nupp [pause.nupp]
local function pause(): nil
    coroutine.yield()
end

nosuspend do
    pause()
end
```

```text [nupp check pause.nupp]
error: NUPP2701: `pause` may suspend, and this region forbids suspending
```

A cleanup running at a scope boundary is held to the same rule, because an
obligation is being discharged there and the discharge cannot be left half done.

### Function types carry the guarantee

`nosuspend function(...)` describes a callback or host declaration whose body is
not visible:

```nupp
local type Reporter = nosuspend function(message: string): nil

local function publish(report: Reporter): nil
    nosuspend do
        report("committed")
    end
end

print(publish)
```

A non-suspending function fits an ordinary function slot. An ordinary function
does not fit a `nosuspend` slot. The qualifier survives aliases, generics,
imports, and exports.

The guarantee covers suspension only. The function may allocate, mutate, perform
external I/O, or raise.

### Effect contracts publish the complete boundary

An [effect contract](effects.md) includes suspension in its `yields` member:

```nupp [transport.d.nupp]
@effects(yields = true, raises = true)
const receive: function(): string
```

Use `@effects` where an API needs a reviewed complete effect summary.
`@effects()` says that every modeled effect is absent, so it promises much more
than a `nosuspend function` type does.

## Handler scope follows the coroutine

A handler is dynamically scoped per coroutine, not process-wide. A host often
wraps its root application task, which makes that handler application-wide in
practice:

```nupp
local frame = require("scheduler")
local suspension = require("nupp.suspension")

local function childWork(): nil
    assert(suspension.handled())
end

local function application(): nil
    handle suspension with frame.handler do
        local task = suspension.create(childWork)
        local ok, problem = coroutine.resume(task)
        if not ok then
            error(problem)
        end
    end
end

frame.run(application)
```

`suspension.create` creates an ordinary coroutine and makes it inherit the
handler installed where it was created. Inheritance is fixed at creation.
Continue to use `coroutine.resume`; no resume wrapper is required. A coroutine
made with `coroutine.create` inherits no handler.

A nested `handle suspension` temporarily replaces the current handler and
restores the outer one when its region ends, so different coroutines may use
different handlers at the same time.

### Raw coroutine yields keep explicit control

`coroutine.yield` yields directly to the code that resumes the coroutine. It
does not register cancellation or give a handler responsibility for the
suspended stack.

::: deepdive
The two forms are judged differently where an [affine
obligation](ownership.md) is live. A raw yield with an obligation outstanding is
rejected, because nobody is responsible for the abandoned continuation. A
handled suspension with one outstanding is allowed, because responsibility
transfers to a handler that owns the continuation and its cancellation until the
park returns or unwinds.

That permission rests on a trusted handler contract rather than on a proof. The
checker cannot prove anything about an arbitrary scheduler's cancellation
behavior, and the invariant being trusted is not that a wait completes, which it
may legitimately never do, but that the continuation is never abandoned without
being woken far enough to run its cleanup.

See [NEP 5](../neps/0005-suspension.md#handled-suspension-is-not-a-raw-coroutine-yield)
for more information.
:::

## Combinators interleave waits

The suspension module runs several zero-argument functions concurrently:

```nupp
local process = require("nupp.io.process")
local suspension = require("nupp.suspension")

local function version(program: string): string
    local child = assert(process.new({args = {program, "--version"}}))
    local result = assert(child:communicate())
    child:close()
    return result.output
end

local outputs = suspension.all({function(): string
    return version("cc")
end, function(): string
    return version("lua")
end,})

print(outputs[1], outputs[2])
```

Each body runs in a coroutine. One body parking lets another run, and when every
body is parked the driver parks on the surrounding handler or drives the
readiness sources itself.

- `all` returns values in input order and raises the first branch error after
  every branch settles.
- `gather` returns parallel value and error arrays for a caller that handles
  every failure.
- `race` returns the first settled value and its one-based index, then cancels
  and unwinds the other branches.
- `batch` has the behavior of `all` with at most `limit` branches in flight.

These helpers provide concurrency, not CPU parallelism. Their coroutines share
one LuaJIT state and run one at a time between suspensions. See
[Workers](workers.md) for running CPU work on native threads with isolated
heaps.

## Libraries register readiness

A suspension-aware library calls `suspension.suspend` with a subscription. This
example completes after its readiness source has been polled twice:

```nupp
local suspension = require("nupp.suspension")

local function after(polls: integer, value: string): string
    return suspension.suspend("counter", function(resume: function(string), context: suspension.Context): function()
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
local suspension = require("nupp.suspension")

local runnable: {thread} = {}

local function enqueue(task: thread): nil
    runnable[#runnable + 1] = task
end

local function runReady(): nil
    local pass = runnable
    runnable = {}
    for _, task in ipairs(pass) do
        local ok, problem = coroutine.resume(task)
        if not ok then
            error(problem)
        end
    end
end
```

The handler itself is three members. `park` registers a waker that enqueues the
current coroutine, then yields until the wait is ready. `canPark` returns false
inside a host barrier where yielding would violate a runtime invariant.
`shutdown` drains work queued while the handled extent is ending.

```nupp [scheduler.nupp]
local scheduler = {park = function(_: suspension.Handler, waiting: suspension.Waiting, _: function(): nil): nil
    local task = assert(coroutine.running())
    local function wake(): nil
        enqueue(task)
    end

    while not waiting:ready() do
        waiting:onResume(wake)
        if not waiting:ready() then
            coroutine.yield()
        end
    end
end, canPark = function(_: suspension.Handler): boolean
    return true
end, shutdown = function(_: suspension.Handler): nil
    while #runnable > 0 do
        runReady()
    end
end,} as suspension.Handler
```

`waiting:onResume(wake)` is a notification, not value delivery. The readiness
source supplies the value through `resume`, and the waker makes the coroutine
runnable after that value exists. The `as suspension.Handler` cast accepts a
trusted runtime contract: the checker verifies the function bodies and their
annotations, and only the scheduler author can guarantee that `park` eventually
resumes or cancels every wait.

```nupp [scheduler.nupp]
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

`handle suspension` lowers to an owned handler installation. When its extent
ends, the runtime restores the previous handler, cancels outstanding
subscriptions, wakes their coroutines, and invokes `shutdown`. A cancelled
`suspend` raises inside its parked coroutine, so lexical resource drops run as
the stack unwinds.

Structured exits leave the region only after its installation has been released.
`return` preserves all values, `break` and `continue` reach the loop that owns
them, and `goto` may reach a label outside:

```nupp
local frame = require("scheduler")

local function choose(): integer
    handle suspension with frame.handler do
        return 1
    end
end

print(choose())
```

The lowering uses the same completion protocol as automatic resource cleanup,
which preserves a body failure as the primary error when releasing the handler
fails too, while still reporting the release failure.

Control cannot jump *into* a handled region, because such a jump would bypass
handler installation and the lexical state before the label:

```nupp [wrong.nupp]
local frame = require("scheduler")

goto inside
handle suspension with frame.handler do
    ::inside::
end
```

```text [nupp check wrong.nupp]
error: NUPP2706: control cannot enter a `handle suspension` region
```

## C-call boundaries

LuaJIT cannot yield through every C frame. A comparator called by `table.sort`,
a replacement called by `string.gsub`, and an FFI callback are non-yieldable
positions. The checker follows those callback bodies and reports **NUPP2702**
for a call inside one that reaches a suspension:

```nupp [compare.nupp]
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

## FAQ

### Does a suspending call return a future?

No. A suspension-aware call returns its declared result after the wait, so
callers do not unwrap a future or acquire a second function type. The compiler
tracks the possibility of suspension separately through [call
propagation](#suspension-propagates-through-calls).

### Should a callback be a `nosuspend` type or an `@effects` contract?

Use `nosuspend function(...)` when suspension is the only thing that matters,
which is the common case for a callback invoked inside a region or across a C
boundary. Use [`@effects`](effects.md) when the API owes a reviewed summary of
allocation, raising, and yielding together.

### Does cancellation run affine cleanup?

Yes. A handler cancels a parked operation by unwinding its coroutine stack, and
that unwind performs [automatic lexical
destruction](../type-system/ownership.md#consumption-and-lexical-destruction),
so affine files, locks, and native allocations do not become stranded.

::: seealso
- [workers.md](workers.md) for CPU parallelism on native threads
- [io.md](../modules/nupp/io.md) for the library these examples
  wait on
- [ownership.md](ownership.md) for the cleanup a cancelled park unwinds
- [NEP 5](../neps/0005-suspension.md) for the record of the design
:::
