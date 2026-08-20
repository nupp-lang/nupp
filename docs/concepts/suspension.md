# Suspension

A suspension-aware function waits without changing its call syntax or return
type. The same call blocks in a command-line program and parks its coroutine
when a host installs a [suspension handler](#hosts-supply-scheduling-policy):

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

::: rationale
This is one effect with handlers rather than general algebraic effects, which
would be a much larger language than anything here needs. Suspending with a live
obligation is permitted for a handled suspension and refused for a raw
coroutine yield, and that permission rests on a trusted handler contract rather
than a proof: the checker cannot prove anything about an arbitrary scheduler's
cancellation behaviour.

[NEP 6](../neps/0006-suspension.md) has the full record.
:::

## One call blocks or parks

`communicate` follows one of three paths:

- A ready child returns without polling, parking, or switching coroutines.
- A pending child with no handler makes the current thread drive registered
  readiness sources until the child finishes.
- A pending child under a handler makes the handler park this coroutine while
  the host runs other work.

The library describes the wait. The handler owns scheduling policy, and the
caller's result remains `process.Result` on every path.

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
scope. Most application code only consumes a handler this way. Framework
authors and scheduler integrations implement one. The `all`, `gather`, `race`,
and `batch` combinators use a private handler to interleave their branches.

### Waits park one coroutine

When `child:communicate()` cannot finish immediately, control moves through
seven steps:

1. The process library registers its readiness source and cancellation
   function.
2. The suspension runtime calls `frame.handler.park` with the pending wait.
3. The handler records the current coroutine and yields it to the event loop.
4. The event loop runs another coroutine, request, or frame.
5. `suspension.poll()` discovers that the child process has completed.
6. The library resumes the wait, and the handler queues its coroutine again.
7. The coroutine runs, and `communicate()` returns its `process.Result`.

The handler never supplies the result. The library's guarded `resume` function
does that. The handler decides when the coroutine runs again.

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

The compiler infers that `compilerVersion` and `printVersion` may suspend. That
fact travels separately from their parameter and result types.

## Suspension propagates through calls

A direct `coroutine.yield` marks its function as suspending. The effect
propagates through resolved calls and across module boundaries, so a caller can
require uninterrupted control without annotating every function on the path.

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
unresolved call is refused because the checker cannot prove the guarantee.

This call path reaches `coroutine.yield`:

```nupp [pause.nupp]
local function pause(): nil
    coroutine.yield()
end

nosuspend do
    pause()
end
```

```text [nupp check pause.nupp]
error: NUPP2701: `pause` may suspend
```

### Function types carry the guarantee

`nosuspend function(...)` describes a callback or host declaration whose body
is not visible:

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

The guarantee covers suspension only. The function may allocate, mutate,
perform external I/O, or raise.

### Effect contracts publish the complete boundary

An [effect contract](effects.md) includes suspension in its `yields` member:

```nupp [transport.d.nupp]
@effects(yields = true, raises = true)
const receive: function(): string
```

Use `@effects` when an API needs a reviewed complete effect summary.
`@effects()` means that every modeled effect is absent, so it promises much
more than a `nosuspend function` type.

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
restores the outer one when its region ends. Different coroutines may therefore
use different handlers at the same time.

### Raw coroutine yields keep explicit control

`coroutine.yield` yields directly to the code that resumes the coroutine. It
does not register cancellation or give a handler responsibility for the
suspended stack.

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

Each body runs in a coroutine. One body parking lets another run. When every
body is parked, the driver parks on the surrounding handler or drives the
readiness sources itself.

- `all` returns values in input order and raises the first branch error after
  every branch settles.
- `gather` returns parallel value and error arrays for a caller that handles
  every failure.
- `race` returns the first settled value and its one-based index, then cancels
  and unwinds the other branches.
- `batch` has the behavior of `all` with at most `limit` branches in flight.

These helpers provide concurrency, not CPU parallelism. Their coroutines share
one LuaJIT state and run one at a time between suspensions. Nupp workers run CPU
work on native threads with isolated heaps.

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

A poll function returns how many operations it settled. Lower priorities run
first, with names breaking ties. A source returning zero means that nothing
completed during that pass. A wait with no handler and no source reports that
it cannot make progress instead of hanging.

## Writing a frame handler

This scheduler keeps a queue of runnable coroutines. Its event loop calls
`tick` once per frame to poll readiness sources and resume the tasks they woke:

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

The `as suspension.Handler` cast accepts a trusted runtime contract. The
checker verifies the function bodies and their annotations, but only the
scheduler author can guarantee that `park` eventually resumes or cancels every
wait.

The three members divide the work:

- `park` registers a waker that enqueues the current coroutine, then yields
  until the wait is ready.
- `canPark` returns false inside a host barrier where yielding would violate a
  runtime invariant.
- `shutdown` drains work queued while the handled extent is ending.

`waiting:onResume(wake)` is a notification, not value delivery. The readiness
source supplies the value through `resume`; the waker makes the coroutine
runnable after that value exists. `run` creates the root task used in the
opening application. Its first resume reaches `park` and yields. Each `tick`
polls completion sources and resumes tasks placed on `runnable`. A game host
calls the same `tick` function once per frame instead of using this standalone
loop.

## Cancellation unwinds the parked stack

`handle suspension` lowers to an owned handler installation. When its extent
ends, the runtime restores the previous handler, cancels outstanding
subscriptions, wakes their coroutines, and invokes `shutdown`. A cancelled
`suspend` raises inside its parked coroutine, so lexical resource drops run as
the stack unwinds.

Structured exits leave the region only after its installation has been
released. `return` preserves all values, `break` and `continue` reach the loop
that owns them, and `goto` may reach a label outside:

```nupp
local frame = require("scheduler")

local function choose(): integer
    handle suspension with frame.handler do
        return 1
    end
end

print(choose())
```

The lowering uses the same completion protocol as automatic resource cleanup.
That preserves the body failure as primary when releasing the handler also
fails, while still reporting the release failure.

Control cannot jump *into* a handled region. Such a jump would bypass handler
installation and the lexical state before the label:

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
positions. The checker follows their callback bodies and reports a suspension
that reaches the C boundary. The runtime names the operation when an unknown C
API hides the boundary from static analysis.

## FAQ

### Can Nupp suspend any blocking function?

Nupp does not turn an arbitrary blocking Lua or C call into a park. A library
registers readiness through the [suspension
protocol](#libraries-register-readiness), and only that suspension-aware path
can yield control to its host. The checker rejects a yield through a
[non-yieldable C boundary](#c-call-boundaries).

### Does a suspending call return a future?

A suspension-aware call returns its declared result after the wait, so callers
do not unwrap a future or acquire a second function type. The compiler tracks
the possibility of suspension separately through [call
propagation](#suspension-propagates-through-calls), while `nosuspend` function
types express the stronger callback guarantee.

### Does cancellation run affine cleanup?

A handler cancels a parked operation by unwinding its coroutine stack. That
unwind performs [automatic lexical
destruction](../type-system/ownership.md#consumption-and-lexical-destruction),
so affine files, locks, and native allocations do not become stranded. The
handler contract specifies how [cancellation unwinds a parked
stack](#cancellation-unwinds-the-parked-stack).
