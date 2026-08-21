---
order: 150
---

# Workers

`nupp.workers` runs a named module in a fresh LuaJIT state on a native thread.
The states share no Lua heap, globals, loaded modules, closures, userdata, or
cdata, and communicate by copying serialized values through bounded queues.

```nupp
local workers = require("nupp.workers")

local worker = workers.spawn("jobs.hash")
local answer = worker:call({name = "level1", bytes = "payload"})
print(answer.hash)
```

::: note Workers need a compiler-owned binary
Workers run only in a `binary` target whose `stub` is `"nupp"`. That host
supplies the pinned LuaJIT, the stamped payload worker entries load from, and
the early machine-code address-space reservation later LuaJIT states need.
Builds refuse workers in module and bundle targets, and with a third-party
binary stub. See [Compiler-native
features](../guides/build.md#compiler-native-features) for the target setting.
:::

## Starting a worker

List every independently loaded worker entry in the target so the build carries
it in the binary:

```lua [nupp.lua]
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
thread, and releases the queues, and it runs on every structured exit from the
scope holding the worker:

```nupp
local workers = require("nupp.workers")

local function hash(bytes: string): string
    local worker = workers.spawn("jobs.hash")

    return worker:call({name = "level1", bytes = bytes}).hash
end

print(hash("payload"))
```

The worker is stopped as `hash` returns, and it is stopped the same way if the
call raises instead. See [Ownership](ownership.md) for what the obligation means
and how to discharge it early.

::: deepdive
Isolation is total because every ownership proof assumes single-threaded access.
A shared heap would mean either extending the capability model to describe
concurrent access, which is a much larger type system than the one Nupp has, or
keeping proofs that are silently false the moment two threads touch the same
value. Copying through a queue costs a serialization pass per message and keeps
every proof on either side true.
:::

### Serving requests

The entry obtains its own endpoints with `current` and serves request and reply
calls until its inbox closes:

```nupp [jobs/hash.nupp]
local data = require("nupp.data")
local workers = require("nupp.workers")
local self = workers.current()

self:serve(function(job: any): any
    return {name = job.name, hash = data.fnv1a64(job.bytes)}
end)
```

A handler error becomes a failed reply for that call, and the serve loop
continues.

### Exit status

An uncaught entry error is recorded by `join` instead:

```nupp
local workers = require("nupp.workers")

local worker = workers.spawn("jobs.hash")
local exit = worker:join()
if not exit.succeeded then
    io.stderr:write(exit.error or "worker failed", "\n")
end
```

Calling `join` does not close a running worker. Use `stop` for explicit cleanup,
or let ownership call it at the end of the worker's scope.

## Messages

`Worker:send` and `Self:send` carry ordinary one-way messages in either
direction. On the handle, `receive()` waits for one, `receive(timeoutMs)` waits
up to a nonnegative whole number of milliseconds, and `tryReceive()` polls
without waiting; inside the entry, `Self:receive()` waits. Nil means the channel
closed after its queued messages were drained.

```nupp
local workers = require("nupp.workers")

local worker = workers.spawn("jobs.stream")
worker:send({name = "level1"})
print(worker:receive(50))
```

The entry on the other end answers with `Self:receive` and `Self:send`, and it
is listed in the target's `entries` the same way `jobs.hash` is.

### Transferable values

Transferable values are booleans, numbers, strings, and tables recursively made
from those values with scalar keys. A top-level nil, function, thread, userdata,
cdata value, metatable, table deeper than 32 levels, cycle, or repeated table
alias is rejected before encoding, and the error names the first rejected path.
Each receiver decodes an independent copy.

A repeated table is rejected as an alias for the same reason a cycle is: the
encoding promises neither, so a message that arrived with two references to one
table would arrive as two tables and diverge on the first write.

### Queue bounds

Each direction holds at most 1024 messages and 256 MiB. Sending never waits for
capacity, and it raises when either bound is full or the channel is closed,
which keeps producer backpressure from introducing a second wait that could
deadlock against the first.

## Waiting and stopping

Ready operations return immediately. Without a suspension handler, an empty
receive sleeps on the native channel condition variable and `join` blocks the
thread. With a [suspension
handler](suspension.md#hosts-supply-scheduling-policy) installed, those same
calls register readiness sources and park cooperatively, and their ordinary call
syntax does not change.

Closing is cooperative. It is nonblocking and wakes an entry waiting in
`Self:receive` or `Self:serve`, and it cannot interrupt arbitrary worker code. A
worker that ignores its closed inbox can therefore keep `join`, `stop`, and
automatic cleanup waiting forever. Work that must be forcibly terminated, or
isolated from native crashes, belongs in an operating-system process instead.

## FAQ

### Can a worker share a table with the thread that spawned it?

No. Every value is serialized on the way out and decoded into an independent
copy on the way in, so a write on one side is invisible to the other. See
[Transferable values](#transferable-values) for what may cross at all.

### Can a stuck worker be killed?

No. Closing wakes an entry that is waiting on its inbox, and nothing interrupts
a worker that is busy in its own code, so `stop` waits for it. Use
[](nupp.io.process) for work that has to be terminated on demand.

### Should concurrent work go to a worker or to a combinator?

Use a [suspension combinator](suspension.md#combinators-interleave-waits) for
work that is waiting, since interleaved coroutines in one state cost nothing to
create and share their data directly. Use a worker for work that is computing,
because that is the only form here that runs on a second core.

::: seealso
- [suspension.md](suspension.md) for blocking and handled waits
- [ownership.md](ownership.md) for the cleanup a spawned worker owes
- [build.md](../guides/build.md#compiler-native-features) for the target a
  worker binary needs
:::
