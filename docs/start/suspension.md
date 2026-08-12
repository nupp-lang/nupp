# Suspension

A suspension-aware function waits without changing its call syntax or return
type. The same call blocks in a command-line program and parks its coroutine
when a host installs a [suspension handler](suspension-handlers.md):

```nupp
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

## One call blocks or parks

`communicate` follows one of three paths:

- A ready child returns without polling, parking, or switching coroutines.
- A pending child with no handler makes the current thread drive registered
  readiness sources until the child finishes.
- A pending child under a handler makes the handler park this coroutine while
  the host runs other work.

The library describes the wait. The handler owns scheduling policy, and the
caller's result remains `process.Result` on every path.

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

An [effect contract](../effects.md) includes suspension in its `yields` member:

```nupp [transport.d.nupp]
@effects(yields = true, raises = true)
const receive: function(): string
```

Use `@effects` when an API needs a reviewed complete effect summary.
`@effects()` means that every modeled effect is absent, so it promises much
more than a `nosuspend function` type.

## Raw coroutines keep explicit control

`coroutine.yield` yields directly to the code that resumes the coroutine. It
does not register cancellation or give a handler responsibility for the
suspended stack.

`suspension.create` creates an ordinary coroutine and makes it inherit the
handler installed where it was created:

```nupp
local suspension = require("nupp.suspension")

local thread = suspension.create(function(): nil
    print("running")
end)

local ok, problem = coroutine.resume(thread)
if not ok then
    error(problem)
end
```

Inheritance is fixed at creation. Continue to use `coroutine.resume`; no
resume wrapper is required. A coroutine made with `coroutine.create` inherits
no handler.

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

## C-call boundaries

LuaJIT cannot yield through every C frame. A comparator called by `table.sort`,
a replacement called by `string.gsub`, and an FFI callback are non-yieldable
positions. The checker follows their callback bodies and reports a suspension
that reaches the C boundary. The runtime names the operation when an unknown C
API hides the boundary from static analysis.

## Diagnostics

- **[NUPP2701](../reference.md#suspension-regions)** reports a call in a
  `nosuspend` region or cleanup contract that may suspend.
- **[NUPP2702](../reference.md#suspension-regions)** reports a suspending
  callback invoked through a non-yieldable C boundary.
- **[NUPP2603](../reference.md#owned-resources)** reports a raw coroutine yield
  that would strand a live ownership or borrowing obligation.

## Next

- [Suspension handlers](suspension-handlers.md) explains who supplies a handler,
  how it parks one coroutine, and how its scope ends.
- [Effect contracts](../effects.md) defines the complete `@effects` surface and
  its inference limits.
- [Ownership](ownership.md) defines the obligations that handled cancellation
  unwinds.
