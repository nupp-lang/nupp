# Workers

`nupp.workers` runs a named module in a fresh LuaJIT state on a native thread.
The states share no Lua heap, globals, loaded modules, closures, userdata, or
cdata. They communicate by copying serialized values through bounded queues.

Isolation is total because every ownership proof assumes single-threaded access:
sharing a heap would mean either extending the capability model or holding
proofs that are silently false under concurrency.

Workers are currently available only in a `binary` target whose `stub` is
`"nupp"`. The compiler-owned host supplies the pinned LuaJIT, the stamped
payload from which worker entries load, and the early machine-code address-space
reservation needed by later LuaJIT states. Builds refuse workers in module and
bundle targets or with a third-party binary stub.

```nupp
local workers = require("nupp.workers")

local worker = workers.spawn("jobs.hash")
local answer = worker:call({name = "level1"})
print(answer)
```

## Start and call a worker

List every independently loaded worker entry in the target so it is carried in
the binary:

```lua
return {
   include = { "src" },
   build = {
      default = "app",
      targets = {
         app = {
            kind = "binary",
            stub = "nupp",
            entries = { "main", "jobs.hash" },
         },
      },
   },
}
```

`spawn` returns an owned worker. Its drop operation closes the inbox, joins the
thread, and releases the queues on every structured exit:

```nupp
local workers = require("nupp.workers")

do
    local worker = workers.spawn("jobs.hash")
    local answer = worker:call({name = "level1", bytes = contents})
    print(answer.hash)
end -- worker:stop() runs here
```

The entry obtains its own endpoints with `current` and can serve request/reply
calls until its inbox closes:

```nupp
local data = require("nupp.data")
local workers = require("nupp.workers")
local self = workers.current()

self:serve(function(job: any): any
    return {name = job.name, hash = data.fnv1a64(job.bytes)}
end)
```

A handler error becomes a failed reply for that call; the serve loop continues.
An uncaught entry error is instead recorded by `join`:

```nupp
local exit = worker:join()
if not exit.succeeded then
    io.stderr:write(exit.error or "worker failed", "\n")
end
```

Calling `join` does not close a running worker. Use `stop` for explicit cleanup,
or let ownership call it at the end of the worker's scope.

## Messages

`send` and `Self:send` carry ordinary one-way messages. `receive()` waits for
one, `receive(timeoutMs)` waits up to a nonnegative number of milliseconds, and
`tryReceive()` only polls. Nil means the channel closed after its queued
messages were drained.

Transferable values are booleans, numbers, strings, and tables recursively made
from those values with scalar keys. A top-level nil, function, thread, userdata,
cdata value, metatable, table deeper than 32 levels, cycle, or repeated table
alias is rejected before encoding. The error identifies the first rejected
path. Each receiver decodes an independent copy.

Each direction holds at most 1024 messages and 256 MiB. Sending never waits for
capacity: it raises if either bound is full or the channel is closed. This keeps
producer backpressure from introducing a second, potentially deadlocking wait.

## Waiting and stopping

Ready operations return immediately. Without a suspension handler, an empty
receive sleeps on the native channel condition variable and `join` blocks on the
thread. With a handler installed, those same calls register readiness sources
and park cooperatively; their ordinary call syntax does not change.

Closing is cooperative. It is nonblocking and wakes an entry waiting in
`Self:receive` or `Self:serve`, but it cannot interrupt arbitrary worker code. A
worker that ignores its closed inbox can therefore keep `join`, `stop`, and
automatic cleanup waiting forever. Work that must be forcibly terminated or
isolated from native crashes belongs in an operating-system process instead.

See [Suspension](suspension.md) for blocking and handled waits, and
[Ownership](ownership.md) for automatic cleanup.
