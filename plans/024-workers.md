# Worker threads — implementation record

Status: implemented for compiler-owned binary targets. Module targets, external
LuaJIT interpreters, and third-party binary stubs remain follow-up work because
they do not yet provide the pinned interpreter, payload bootstrap, or early
machine-code reservation this implementation relies on.

## Decision

Nupp provides isolated worker threads as `nupp.workers`. Each worker is a fresh
LuaJIT state on its own operating-system thread, connected to its spawner by two
bounded byte queues. Lua values never cross directly. The sending state
validates and serializes a value; the receiving state decodes a separate copy.

The first provider belongs to the compiler-owned binary host. That host already
owns a pinned LuaJIT, the immutable stamped payload, and the point early enough
in process startup to preserve nearby machine-code address space. A worker runs
the same payload in a new state with `__nuppWorkerEntry` set to the requested
module. The payload dispatcher requires that module instead of the ordinary
entry.

This is deliberately narrower than the original two-provider proposal. A
sidecar loaded into an arbitrary interpreter cannot reliably reserve address
space before the rest of that process maps libraries, and embedding a second
LuaJIT raises symbol-interposition and native-module identity questions. Nupp
now refuses that configuration at build time instead of shipping a worker that
quietly runs interpreted or initializes a different runtime.

The model is closer to Web Workers than shared-memory threads:

- no shared Lua heap, globals, registry, loaded modules, closures, userdata, or
  cdata pointers;
- messages and request/reply calls are the only communication path;
- worker code is a named, checked module already present in the target payload;
- stopping closes the inbox and joins rather than killing a thread at an
  arbitrary instruction; and
- an uncooperative worker can keep `join` or automatic cleanup waiting forever.

## What landed

The implemented slice includes:

- automatic `native.workers` detection from `require("nupp.workers")`;
- a `workers` feature in the compiler-owned host;
- conditional worker-aware payload dispatch;
- fresh-state bootstrap with the same selected built-in C modules as the main
  state;
- two queues bounded to 1024 messages and 256 MiB per direction;
- FIFO push, blocking and nonblocking pop, close, count, and closed state;
- copied `string.buffer` messages with pathful validation;
- ordinary send/receive, request/reply call, and worker-side serve;
- protocol envelopes outside the user payload, so user table keys cannot
  collide with routing metadata;
- immediate polling plus blocking or suspension-aware waiting;
- nonblocking idempotent close, join, idempotent stop, and ownership-driven
  automatic stop;
- clean and failed exit records with worker error text; and
- an early best-effort LuaJIT machine-code arena on Unix.

The first release intentionally refuses:

- `modules` targets;
- one-file `bundle` targets;
- binary targets with a path-valued third-party stub; and
- an unstamped worker-enabled host used as a plain Lua interpreter.

The refusal is part of the feature contract, not a temporary runtime error.

## Public surface

```nupp
record nupp.workers.Exit
    succeeded: boolean
    status: integer
    error: string?
end

record nupp.workers.Worker
    send: function(self: nupp.workers.Worker, value: any)
    tryReceive: function(self: nupp.workers.Worker): any?
    receive: function(self: nupp.workers.Worker, timeoutMs: integer?): any?
    call: function(self: nupp.workers.Worker, value: any): any
    close: function(self: nupp.workers.Worker)
    join: function(self: nupp.workers.Worker): nupp.workers.Exit
    stop: function(self: nupp.workers.Worker): nupp.workers.Exit
end

record nupp.workers.Self
    receive: function(self: nupp.workers.Self): any?
    send: function(self: nupp.workers.Self, value: any)
    serve: function(self: nupp.workers.Self, handler: function(any): any)
end
```

`workers.spawn(entry)` returns an owner. `Worker:stop` is its `@drop`
operation, so a local worker is stopped on every structured exit. Collection is
not a lifecycle operation and no finalizer performs an unbounded join.

`tryReceive` is the explicit poll. `receive()` waits indefinitely; a positive
timeout waits up to that many monotonic milliseconds, and zero polls. The
worker-side `Self:receive()` waits indefinitely because an idle worker has no
other useful work and must not spin a core.

An ordinary receive returns only `message` frames. `call(value)` numbers a
`request` and waits for its matching `reply`; replies observed by another
waiter are routed to their request id rather than consumed. `Self:serve` handles
requests until the inbox closes. A handler error becomes a failed reply and the
serve loop continues.

`close` is nonblocking and idempotent. It closes the inbox and wakes a worker
blocked in `Self:receive`. `join` waits for the native thread, and `stop` closes,
joins, then destroys both queues. Repeated joins and stops return the recorded
exit.

## Worker entries and payloads

The normal spawn operation names a module:

```nupp
local workers = require("nupp.workers")

do
    local hasher = workers.spawn("workers.hash")
    local answer = hasher:call({name = "level1", bytes = contents})
end -- automatic stop
```

The entry obtains its endpoints in its own state:

```nupp
local workers = require("nupp.workers")
local self = workers.current()

self:serve(function(job: any): any
    return {name = job.name, hash = nupp.data.fnv1a64(job.bytes)}
end)
```

The entry must be one of the modules compiled into the target. Listing a worker
entry in `target.entries` is the direct way to include a module not otherwise
reachable from the ordinary entry.

Worker-aware packaging preloads the ordinary entry as a module too, then emits
one final dispatcher:

```lua
local entry = rawget(_G, "__nuppWorkerEntry")
return require(entry or ordinaryEntry)
```

Worker-free payload generation keeps its existing shape and bytes.

## Message boundary

The transferable vocabulary is:

```text
boolean
number
string
tables whose scalar keys and values recursively use this vocabulary
```

Top-level nil is rejected because it is the absence and closure sentinel.
Functions, threads, userdata, cdata, metatables, resources, table keys that are
not scalar, nesting past 32 tables, cycles, and repeated table aliases are
rejected before encoding. The diagnostic names the path to the first rejected
value.

Repeated aliases are rejected along with cycles because the compatibility
contract does not promise graph identity. A later encoder may widen the
contract only with conformance tests across every supported LuaJIT build.

Every serialized value is wrapped in a private envelope:

```text
message  { kind = "message", payload = value }
request  { kind = "request", id = n, payload = value }
reply    { kind = "reply", id = n, ok = true, payload = value }
reply    { kind = "reply", id = n, ok = false, error = text }
```

The user's value is always below `payload`. Unlike tecs's original reserved-key
protocol, a user table can contain any of these field names without becoming a
control frame.

Send never waits for queue capacity. It raises when the channel is closed or
when either fixed bound is full. Blocking on a full producer queue would add a
second suspension path and a deadlock surface; it remains out until a measured
consumer needs backpressure.

## Suspension integration

Every wait tries its immediate path first. No ready operation calls
`suspension.suspend`.

Without an installed handler, receive waits on the native channel condition
variable and join blocks in the native thread join. Timed receive uses the
host's monotonic clock.

With a handler, a wait registers a readiness source through its
`SuspensionContext`. The source polls native state without blocking and resumes
the caller when its message, reply, deadline, closure, or thread exit is ready.
Cancellation releases the source. No native worker thread calls a Lua callback.

This implementation uses one short-lived source per suspended operation. A
future optimization may coalesce waits into one source per suspension context,
but it must preserve cancellation, request routing, and the zero-source idle
state before replacing the simpler correct path.

## Native host

The `workers` Cargo feature preloads a private `nupp.workers.native` C module in
every state. Its ABI exposes opaque handles and byte strings only:

- channel create, destroy, close, push, pop, count, and closed state;
- worker spawn, finished state, and consuming join;
- the current worker endpoints; and
- monotonic milliseconds.

Rust owns `Mutex<ChannelState>`, `Condvar`, `VecDeque<Box<[u8]>>`, and
`JoinHandle`. Lua owns value validation, `string.buffer` encoding, framing,
routing, errors, and public records. The worker closes its outbox on every exit
path so no receive or call waits for a result that can no longer arrive.

The host retains one immutable copy of the verified payload for the process
lifetime. Worker states borrow its bytes only while loading them; each state
gets its own Lua objects and `package.loaded` table. A worker closes both queues
when its entry returns, so later sends fail and no receive waits on a producer
that no longer exists.

## Machine-code arena

The arena follows the implementation and measurements in tecs.

LuaJIT arm64 traces reach the interpreter with an immediate branch. LuaJIT
therefore needs to map machine code within roughly 62 MiB on either side of its
own image. A process may fill that window before a later worker calls
`luaL_newstate`; the worker then runs interpreted even though `jit.status()`
still returns true.

Tecs tried a per-state workaround first: warm one trace, set `sizemcode` and
`maxmcode` to the one 64 KiB area that still fit, and reuse it. That was not a
cache worth porting. A trace flush released the area, the state could not take
another, and the load-bearing size depended on process layout.

The successful tecs design reserves unreadable address space near the pinned
LuaJIT image before ordinary initialization. Nupp ports that design:

- try 24 MiB first and halve down to 4 MiB;
- search within LuaJIT's branch-reachable window;
- use `PROT_NONE`, so reservation consumes address space but no physical memory;
- make failure best-effort rather than a launch failure; and
- release once, immediately before the first worker state is created.

The reservation is compiled only into a worker-enabled host. Windows currently
uses the no-op platform branch pending an equivalent measured implementation.

A permanent performance gate still needs a trace-abort probe comparable to
tecs's `TECS_TRACEPROF`. `jit.status()` alone is explicitly not an adequate
test.

## Build selection

The feature registry entry is:

```text
effect          native.workers
module          nupp.workers
feature name    workers
host feature    workers
runtime module  nupp.workers
requires        runtime.suspension
```

Resolved use selects the host feature, both compiler-provided runtime modules,
and the worker dispatcher. Removing the last use removes those outputs on the
next successful build through ordinary stale-output cleanup.

`nativeFeatures.workers = true` may force the feature into a compatible binary
target; `false` removes it. A forced removal from code that still calls the
module produces a target without its provider by explicit expert request, the
same contract as other native-feature overrides.

## Failures and lifecycle

The following remain distinct:

- spawn failure: the native thread could not be started;
- entry load or runtime failure: `join` returns a failed exit with error text;
- call failure: `serve` catches one handler error, replies with it, and
  continues;
- closed and drained: receive returns nil;
- queue full: send raises without blocking; and
- canceled wait: the caller stops waiting without canceling worker code.

A call whose worker exits before replying joins the already-ending thread and
raises its entry error when available. A clean early return raises that the
worker ended before replying.

Thread cancellation is not provided. Code that must be killed, memory-limited,
or isolated from a crash belongs in an operating-system process, as the
comptime worker already does.

## Verification

Required regression coverage for the landed slice:

- host unit tests for FIFO delivery, close-and-drain, send-after-close, and the
  message-count bound;
- compiler tests for `native.workers` detection and suspension expansion;
- packaging tests for conditional dispatch and compiler runtime modules;
- an end-to-end stamped binary that starts a named worker, exchanges a call,
  stops through ownership, and observes a failed entry through `join`;
- build refusal tests for modules, bundles, and third-party stubs; and
- ordinary compiler tests plus self-host fixpoint.

The platform matrix must add Windows before the feature is advertised there.
The performance matrix must add a worker trace-abort probe and parallel hot-loop
benchmark before modules-sidecar work begins.

## Follow-up milestones

### W6: harden the shipped host provider

- Add trace-abort instrumentation and fail when a hot worker remains
  interpreted.
- Add bounded parallel-progress and repeated spawn/stop memory tests.
- Exercise cancellation and handler shutdown with a cooperative test handler.
- Implement and measure the Windows arena strategy.

### W7: external interpreter spike

- Decide between a verified embedding function table and a symbol-hidden
  private LuaJIT.
- Prove no symbol interposition on Mach-O, ELF, or PE.
- Prove early reservation is possible before arbitrary host mappings, or state
  and enforce the narrower deployment contract that makes it possible.
- Run the same conformance suite as the compiler-owned host.

Only after W7 passes should `modules` targets stage a `nupp_workers` sidecar.

### W8: source and scheduler optimization

- Measure whether one readiness source per suspension context improves real
  hosts over one source per wait.
- Preserve late-reply discard and cancellation while coalescing.
- Consider typed `Worker<Request, Reply>` protocols only with a checked entry
  relation that does not make dynamic module names falsely safe.
- Add a pool only after two measured consumers need compatible policy.
