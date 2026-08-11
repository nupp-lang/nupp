# Suspension handlers

A suspension handler connects
[suspension-aware calls](suspension.md#one-call-blocks-or-parks) to a host's
event loop. A root task function installs the host's handler, then ordinary
functions beneath it can park without accepting a scheduler parameter:

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
scope. `printCompilerVersion` uses it because `application` called that
function inside the region.

## Hosts supply scheduling policy

A command-line program needs no handler. Its suspension-aware calls drive the
registered readiness sources and block the current operating-system thread.

A host supplies a handler when blocking the thread would stop unrelated work:

- A game engine parks a loading coroutine and renders the next frame.
- A server parks one request and serves other connections.
- A UI runtime parks a task and continues processing input.
- A test scheduler controls exactly when a suspended operation resumes.

Most application code consumes that handler through `handle suspension`.
Framework authors and scheduler integrations implement one. The `all`,
`gather`, `race`, and `batch` combinators also use a private handler to
interleave their branches.

## A wait parks one coroutine

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

## Scope follows the coroutine

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
        if not ok then error(problem) end
    end
end

frame.run(application)
```

`suspension.create` inherits the installation in force at creation. A stock
`coroutine.create` inherits none. A nested `handle suspension` temporarily
replaces the current handler and restores the outer one when its region ends.
Different coroutines may therefore use different handlers at the same time.

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
        if not ok then error(problem) end
    end
end

local scheduler = {
    park = function(
        _: suspension.Handler,
        waiting: suspension.Waiting,
        _: function(): nil
    ): nil
        local task = assert(coroutine.running())
        local function wake(): nil
            enqueue(task)
        end
        while not waiting:ready() do
            waiting:onResume(wake)
            if not waiting:ready() then coroutine.yield() end
        end
    end,
    canPark = function(_: suspension.Handler): boolean
        return true
    end,
    shutdown = function(_: suspension.Handler): nil
        while #runnable > 0 do runReady() end
    end,
} as suspension.Handler

local function tick(): nil
    suspension.poll()
    runReady()
end

local function run(body: function(): nil): nil
    local task = coroutine.create(body)
    local ok, problem = coroutine.resume(task)
    if not ok then error(problem) end
    while coroutine.status(task) ~= "dead" do tick() end
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

The region currently refuses a `return` or an unbound `break` that would cross
its boundary:

```nupp [wrong.nupp]
local frame = require("scheduler")

local function choose(): integer
    handle suspension with frame.handler do
        return 1
    end
    return 0
end

print(choose())
```

```text [nupp check wrong.nupp]
error: NUPP2706: control cannot leave a `handle suspension` region yet
```

Store the result outside the region and return after the previous handler has
been restored:

```nupp
local frame = require("scheduler")

local function choose(): integer
    local answer: integer = 0
    handle suspension with frame.handler do
        answer = 1
    end
    return answer
end

print(choose())
```

## Diagnostics

- **[NUPP2706](../reference.md#suspension-regions)** reports a `return` or
  unbound `break` that leaves a `handle suspension` region.

## Next

- [Suspension](suspension.md) explains blocking, parking, effects, raw
  coroutines, and concurrent combinators.
- [Ownership](ownership.md) explains the obligations cancellation unwinds.
- The [`nupp.suspension` API reference](nupp.suspension) lists the handler,
  waiting, installation, source, and subscription types.
