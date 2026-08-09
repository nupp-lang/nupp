# Worker threads — design record

Status: proposed. This depends on S2 of
[suspension](suspension.md): the handled `suspend` operation, its blocking
fallback, and readiness sources. The native isolation and message protocol can
be prototyped before S2, but the public waiting API should not land by
recreating the scheduler dispatch that suspension is meant to replace.

## Decision

Nupp will provide optional worker threads as `nupp.workers`. A worker is a
fresh LuaJIT state on its own operating-system thread, joined to its spawner by
two bounded byte queues. Lua values never cross directly. The sending state
validates and serializes a value; the receiving state decodes a separate copy.

The model is deliberately closer to Web Workers than to shared-memory threads:

- no shared Lua heap, globals, registry, loaded modules, closures, userdata, or
  cdata pointers;
- messages and request/reply calls are the only communication path;
- worker code runs as an independently initialized Nupp module;
- stopping closes the inbox and joins rather than killing a thread at an
  arbitrary instruction.

The implementation begins from `tecs.workers`, whose queue, isolation,
shutdown, routing, and call protocol are already exercised in a real LuaJIT
host. It does not copy tecs's scheduler integration. A Nupp wait performs
`suspend`, so the same call blocks in an ordinary command-line program and
parks under tecs or another installed scheduler.

Workers are a compiler-native feature and are included only when a target has a
resolved runtime use of `nupp.workers`. A target without that effect gets:

- no worker native library;
- no `workers` feature in the compiler-owned host;
- no worker entry dispatcher or embedded worker image;
- no machine-code arena reservation;
- no worker initialization code and no idle poll source; and
- no change to the Lua it would otherwise generate.

This follows the existing native-feature rule rather than inventing a second
manifest switch. A resolved `require("nupp.workers")` records
`native.workers`; target `nativeFeatures.workers` retains the existing
tri-state override for expert use. At `-O1` and above a use removed with
constant-dead code does not select the feature, as with the other native
facilities.

## Why this belongs in Nupp

TypeScript describes worker APIs supplied by browsers and Node, but does not
implement or unify them. The useful precedent is the execution model, not the
ownership of the API: a separate realm, messages copied through a structured
serialization boundary, and explicit termination.

LuaJIT makes that boundary more important. One `lua_State` must not be entered
from several threads, and an FFI callback invoked on a thread Lua did not enter
is unsafe. Giving each worker a state created and used only by its own thread
provides actual parallel execution without pretending Lua objects are safe to
share.

Nupp has three reasons to own the facility rather than leave every host to
write one:

1. A library can use one checked, documented worker protocol under a plain
   interpreter, the Nupp binary host, and tecs.
2. The ownership system can require a worker to be closed and joined.
3. The suspension effect makes a wait scheduler-neutral. The worker module
   should not know whether it is serving a CLI or a frame loop.

The feature is not the hardened comptime worker. A worker thread shares the
process's address space, native libraries, and fate. An abort, memory blowup,
or hostile native call can still take down the compiler and language server.
C4 in [comptime](comptime.md) therefore remains an operating-system process
with kill and resource limits, built over `nupp.io.Process` and suspension.

## Goals

1. Run CPU-bound Nupp code concurrently in isolated LuaJIT states.
2. Preserve a small message API: send, receive, request/reply call, serve, and
   orderly stop.
3. Block efficiently without a suspension handler and park without blocking
   the host thread when a handler is installed.
4. Make every payload crossing the thread boundary an owned byte copy with a
   narrow, diagnosed value vocabulary.
5. Compile and initialize worker entry modules correctly in module and
   compiler-owned binary targets.
6. Select every worker artifact and every worker-specific runtime cost only
   when the checked target uses the feature.
7. Preserve deterministic builds and the existing generated output of targets
   that do not use workers.
8. Keep the immediate send and receive paths allocation- and scheduler-free
   apart from serialization and the queue's required byte allocation.

## Non-goals

- Shared mutable Lua tables or globals.
- `SharedArrayBuffer`, atomics, locks exposed to Nupp, or arbitrary pointers
  crossing between states.
- Running a Lua closure captured in the spawning state.
- Safely terminating an uncooperative thread. There is no portable operation
  that can stop arbitrary LuaJIT execution and preserve process invariants.
- A worker pool, work stealing, priorities, or automatic core selection. A
  pool is a library over workers once measured consumers need one.
- A scheduler. Scheduler policy remains with the installed suspension handler.
- Process isolation, crash containment, memory quotas, or the comptime worker.
- Making every target pay merely because the compiler knows how to provide
  workers. Selection still follows Nupp's existing whole-source-set effect
  rule: a compiled module containing a live `require("nupp.workers")` counts as
  a use even when an entry does not reach that module dynamically.

## Execution model

Each `Worker` owns:

- one native thread and the fresh Lua state created on it;
- one bounded spawner-to-worker queue;
- one bounded worker-to-spawner queue;
- request identifiers and reply routing held only in the spawning state; and
- the right and obligation to close and join the thread.

The native bridge sees only byte blocks and control frames. It does not inspect
Lua values, request tables, or module types. The Lua layer owns validation,
serialization, the request/reply envelope, and public errors.

The worker thread creates its Lua state, opens the same baseline libraries as
the selected host, installs the channel endpoints as private registry values,
loads the worker image, and requires the chosen entry module. It closes its
outbox on every exit path, including a load error or an uncaught error from the
entry. Closing is observable separately from an empty queue, so no waiter can
remain parked for a result that can never arrive.

The fresh state gets no copy of the spawner's `_G` or `package.loaded`. Module
initializers run again. Environment variables and process-wide native state
remain process facilities and must be documented by their owners; the worker
abstraction does not claim to isolate them.

### Worker entries

The normal spawn operation names a Nupp module, not source text:

```nupp
local workers = require("nupp.workers")

with hasher = workers.spawn("workers.hash") do
    hasher:send({name = "level1", bytes = contents})
    local answer = hasher:receive()
end
```

The entry runs only in the worker state and obtains its endpoints through
`workers.current()`:

```nupp
local workers = require("nupp.workers")
local self = workers.current()

self:serve(function(job: any): any
    return {name = job.name, hash = nupp.data.fnv1a64(job.bytes)}
end)
```

A module name may be computed at run time for a modules target, because the
filesystem remains the module registry there. A compiler-owned binary already
carries the complete compiled source set, so its worker dispatcher may require
any module present in that payload. The first version does not pretend the
caller's request type proves anything about a separately initialized entry;
messages remain `any` at the boundary and are narrowed or validated by ordinary
Nupp code on each side.

Raw source text is not public in the first API. It is useful as a native
bring-up hook and in tests, but making it the normal surface would put worker
code outside project checking, documentation, incremental dependencies, and
binary packaging—the parts Nupp is in a position to improve over the tecs API.

## Public surface

The first surface is intentionally small:

```nupp
interface nupp.workers.Worker
    pending: integer

    send: function(self: nupp.workers.Worker, value: any)
    tryReceive: function(self: nupp.workers.Worker): any?
    receive: function(self: nupp.workers.Worker, timeoutMs: number?): any?
    call: function(self: nupp.workers.Worker, value: any): any
    close: function(self: nupp.workers.Worker)
    join: function(self: nupp.workers.Worker): nupp.workers.Exit
    stop: function(self: nupp.workers.Worker): nupp.workers.Exit
end

interface nupp.workers.Self
    receive: function(self: nupp.workers.Self): any?
    send: function(self: nupp.workers.Self, value: any)
    serve: function(self: nupp.workers.Self, handler: function(any): any)
end
```

`workers.spawn(entry)` is an owned producer whose default disposal is
`Worker:stop`. `stop` is `close` followed by `join`, and a second stop returns
the recorded exit. `close` is nonblocking and idempotent. It closes the inbox,
wakes a worker blocked in `Self:receive`, and asks a conventional receive loop
to finish. `join` waits contextually through suspension and may therefore park
a task. It cannot complete while worker source ignores closure and continues
running.

`tryReceive` is the explicit poll. `receive()` waits indefinitely; a positive
timeout waits up to that many monotonic milliseconds, and zero is equivalent
to `tryReceive`. This removes tecs's surprising main-side default, which was
chosen before a general suspension operation existed. The worker-side
`Self:receive()` waits indefinitely because an idle worker has no other useful
work and must not spin a core.

An ordinary receive returns only messages sent outside a call. `call(value)`
numbers the request and waits for its matching reply; replies for other calls
and ordinary messages are routed without being consumed by the wrong waiter.
`Self:serve(handler)` reads until the inbox closes. A handler error becomes a
failed reply for that call and does not end the serve loop.

`Exit` distinguishes a clean return from a load or uncaught runtime error and
carries the worker's error text. Worker failure is observable as soon as the
control frame arrives; callers do not have to wait for a later `stop` merely
to learn why a call cannot be answered.

Top-level `nil` is not a valid message. It is the receive API's absence and
closure sentinel and cannot be made distinguishable after decoding. Nested
nil has ordinary Lua table semantics. Sending nil raises before reaching the
native queue.

### Ownership and cancellation

The owning `Worker` wrapper is not copied. Borrowed method calls retain the
owner, and `stop` consumes or permanently closes it according to the ownership
surface chosen when implementation reaches this milestone. Collection is not
a substitute for joining: no finalizer calls an unbounded join from the Lua
collector.

Cancellation of a suspended `receive`, `call`, or `join` removes only that
waiter. It cannot cancel Lua code already running on the worker. A canceled call
forgets its request identifier, so a late reply is discarded rather than
delivered to a later call. If cancellation unwinds a `with` that owns the
worker, its disposer closes and joins in the same way as an explicit stop.

This interaction depends on suspension S4's ownership contract. Until a
disposer may wait through a handled suspension and cancellation reliably
unwinds it, the public owned producer does not land.

## Message boundary

The initial transferable vocabulary is:

```text
nil only below the top level
boolean
number
string
tables whose keys and values recursively use this vocabulary
```

Functions, threads, userdata, cdata, pointers, metatables, and resources do not
cross. Every send walks the value first and reports the path to the first
unsupported item. The walk has an explicit nesting limit and tracks visited
tables, both to diagnose cycles according to the selected encoding contract
and to avoid turning validation into uncontrolled recursion.

`string.buffer` supplies the first encoding because it is already part of
LuaJIT and is the proven tecs path. Its exact accepted graph shapes are pinned
by tests before Nupp documents them as a compatibility promise. If cyclic
tables or alias preservation are not guaranteed by every supported LuaJIT
build, validation rejects them rather than silently changing identity.

The queue is bounded by both message count and serialized byte count. The
tecs defaults—1024 messages and 256 MiB per direction—are the starting values,
not yet an immutable public contract. Send never blocks waiting for capacity;
it raises with the current count and byte limit. Blocking on a full producer
queue would introduce a second suspension path and a deadlock surface before a
consumer demonstrates the need for backpressure.

### Framing

User payloads are never themselves inspected for routing keys. Each native
message has a small frame kind outside the encoded value:

```text
message        ordinary user payload
request        request id plus user payload
reply          request id, success/failure, and payload or error text
worker-error   load or uncaught entry failure
```

This avoids `tecs.workers`' reserved-table-key collision, where an ordinary
message containing the numeric call-id key can be mistaken for a reply. Frame
lengths and identifiers are fixed-width and checked before allocating. The
public serializer still owns user values; the native layer owns only frame
integrity and raw error bytes from `lua_pcall`.

## Suspension integration

Every waiting operation first tries its immediate path:

- `tryReceive` performs one zero-time pop and never suspends;
- `receive` drains an already routed message before subscribing;
- `call` checks an already routed reply after sending; and
- `join` checks whether the native thread has finished.

Only an operation that is not ready performs `suspend`. Its subscription adds
a waiter to the worker module's state for that `SuspensionContext`, retains one
readiness source while that context has any worker waiter, and returns a
cancellation that removes the waiter and any abandoned call id.

One source per suspension context polls all workers with pending waits. It
does not register once per worker or once per call. A poll drains a bounded
amount of work, routes frames, resumes satisfied waiters, settles deadlines,
and reports how many continuations it resumed. The source is released when its
last waiter leaves, so imported but idle workers add no frame work.

The built-in blocking handler drives the same source. It may sleep briefly
between nonblocking polls; the native channel retains an efficient conditional
wait for a future specialized blocking context, but the public worker API has
no `waitMode` branch. The operation is written once and suspension chooses its
handler.

Worker-source shutdown cancels its waiters and releases registrations. It does
not silently destroy worker owners. Cancellation unwinds their scopes; owned
workers then close and join through their normal cleanup. The suspension
handler's invariant—that shutdown returns with no live parks or sources—is
therefore preserved without giving a global source authority over unrelated
worker lifetimes.

## Native implementation

The proven tecs core ports with deliberately fewer dependencies:

- Rust `Mutex<ChannelState>` and `Condvar` protect a `VecDeque` of owned byte
  frames;
- `std::thread::Builder` starts a named worker thread;
- one fresh `lua_State` is created, opened, run, and closed on that thread;
- close wakes every blocked pop;
- `JoinHandle::is_finished` supports nonblocking join polling; and
- no native function ever calls a Lua callback on the worker thread.

SDL logging, tecs's FFI registry, tecs's Lua-module installer, trace watcher,
task runtime, and frame-source registry do not port. Worker errors travel over
the control frame and Nupp's own state bootstrap installs selected native Lua
modules.

### Two provider forms

The same Rust core has two link forms:

1. A `nupp_workers` sidecar for module targets running under an external
   LuaJIT. It contains or resolves a LuaJIT runtime usable exclusively by its
   worker states and exports only the byte-channel/worker ABI.
2. The `workers` feature of the compiler-owned Nupp host. It reuses the host's
   pinned LuaJIT and its module-registration path, and exposes the same ABI to
   generated Lua through `ffi.C`.

Generated bootstrap tries the host ABI first and loads the sidecar otherwise,
the same distinction other compiler-native facilities already make. Both
forms must run the same conformance suite.

W0 decides the sidecar's LuaJIT linkage after a spike. A private statically
linked LuaJIT is acceptable only if its symbols are hidden on ELF, Mach-O, and
PE and a process already running LuaJIT cannot interpose them. Resolving the
embedding interpreter is acceptable only if all supported deployments expose
the required symbols and module openers. The spike tests both rather than
turning platform-loader folklore into the ABI.

### Machine-code address space

Several LuaJIT states can exhaust nearby machine-code address space while
`jit.status()` continues to report the JIT enabled. The tecs host reserves a
small inaccessible arena near LuaJIT before later states start, giving their
machine code somewhere branch-reachable to land after the reservation is
released.

Nupp ports or replaces that mechanism only with the `workers` host feature.
The ordinary host performs no reservation. The sidecar measures its own
private interpreter image and applies the equivalent reservation within that
provider. Tests run hot worker loops and inspect trace aborts so a worker that
quietly runs interpreted fails the feature's performance gate.

## Build and packaging

`nupp.workers` is registered in the compiler-native feature table with:

```text
effect          native.workers
module          nupp.workers
feature name    workers
sidecar         nupp_workers
host feature    workers
```

The existing effect collection, target override, provider grouping, cache key,
and staging flow do the selection. No unconditional dependency is added to
`runtime/native`, the host's default feature set, or every generated module.

### Modules targets

A modules target stages `lib/nupp_workers` only when `native.workers` survives
resolution. `spawn(entry)` gives the fresh state the target's generated module
path and corresponding rock paths, then requires the compiled entry normally.
Selected native sidecars remain discoverable through the worker's `package.cpath`.

The worker artifact is part of the target's output set and cache fingerprint.
Removing the last use removes it on the next successful build through the
existing stale-output cleanup.

### Compiler-owned binaries

A compiler-owned binary selected with `stub = "nupp"` builds the host with its
`workers` feature only when the resolved effect is present. Its worker states
must see the same compiled module registry and selected statically linked Lua
modules as the main state.

When workers are selected, bundle generation emits a worker-aware dispatcher:
all compiled modules, including the ordinary entry, are installable through
`package.preload`; the host runs the configured main entry, while a worker
state runs the module name supplied to `spawn`. The host retains the verified
payload bytes for its lifetime so a worker can load the same image rather than
embedding a second copy.

When workers are not selected, packaging keeps its current shape. The
dispatcher, retained payload, and alternate entry path are not generalized
into every binary merely for implementation convenience.

A path-valued third-party stub does not automatically gain worker-state
bootstrap. The first version refuses a binary using workers unless its stub
declares the worker ABI or the target uses `stub = "nupp"`; it does not emit a
binary that starts successfully and fails on its first spawn. The declaration
mechanism is designed with the first third-party host that needs it rather than
guessed here.

### Bundles

A one-file Lua bundle cannot carry a native worker provider. It follows the
existing native-feature rule and is refused when workers are selected. There
is no silent subprocess fallback and no base64-encoded shared library hidden
inside generated Lua.

## Failures and lifecycle

The following are distinct and remain distinct in the API:

- spawn failure: the native thread or Lua state could not be created;
- entry load failure: the worker image or selected module did not load;
- entry runtime failure: uncaught code ended the worker;
- call failure: `serve` caught one handler error and continued;
- closed: the worker returned cleanly or its inbox was closed and drained;
- queue full: send exceeded a configured bound; and
- canceled wait: the caller stopped waiting, without implying the worker
  stopped computing.

`call` raises the remote handler's reason with a worker-entry frame in the
traceback context. An entry failure settles every outstanding receive with
closure and every call with the entry error. A clean worker return settles
calls with "worker ended before replying" rather than waiting forever.

`stop` can wait forever when source never receives again or ignores a closed
inbox. That is a property of cooperative thread shutdown and is documented as
such. Process workers are the answer for untrusted or forcibly bounded work;
unsafe thread cancellation is not.

## Determinism and cost

Worker selection is a checked build fact. It cannot affect comptime evaluation
or another module's meaning. The effect and provider set participate in the
ordinary configuration and interface fingerprints.

A worker-enabled payload remains deterministic:

- module installation order is sorted;
- no worker id, timestamp, machine path, or build counter enters output;
- alternate entry dispatch is selected at run time by the host, not baked from
  a run; and
- the same source and configuration produce byte-identical worker-aware
  payloads.

The zero-use cost is zero by construction. For a selected feature with no live
worker waits, there is no registered readiness source and no per-frame poll.
For a live worker, send pays validation, encoding, one byte copy into the
bounded queue, and a condition-variable notification. A ready receive pays a
queue pop, one byte copy into a Lua string, and decoding. The scheduler path is
reached only when an operation is not ready.

## Relationship to tecs

The following concepts port directly:

```text
tecs.workers                         nupp.workers
----------------------------------   ----------------------------------
fresh lua_State per native thread    unchanged
two bounded byte channels            unchanged
string.buffer encoding               unchanged initially
close wakes a blocked worker         unchanged
call id and reply routing            retained with external framing
Self:serve                            unchanged in behavior
taskruntime.checkWait                 removed
taskruntime.awaitCallback             suspend
runtime.register("workers", ...)     SuspensionContext:source(...)
SDL_Log worker failure                worker-error control frame
raw source spawn                      internal bring-up hook only
```

Tecs can continue using its implementation until it is itself ported to Nupp.
Once Nupp suspension is installed in tecs, adopting `nupp.workers` should
change the import and worker entry packaging, not the semantics of its call
sites. Tecs's scheduler, gates, source ordering, and frame policy remain tecs's.

## Milestones

### W0: native and packaging spike

- Run two fresh LuaJIT states concurrently through the shared Rust core.
- Prove the sidecar link strategy on macOS, Linux, and Windows without symbol
  interposition or a dependency on a development-only LuaJIT installation.
- Run the same worker entry in a modules target and a compiler-owned binary.
- Install the exact native Lua modules selected for the target in every state.
- Prove worker-free builds are byte-identical and build no new artifact.
- Measure machine-code allocation and select the conditional arena strategy.

Exit test: a hot pure-Nupp worker runs JIT-compiled in both provider forms;
adding and then removing the only `nupp.workers` use adds and removes every
worker artifact, host feature, dispatcher, and reservation.

### W1: channels and lifecycle

- Bounded native frames, push, zero-time pop, conditional wait, close, count,
  closed state, and destruction.
- Worker spawn, state bootstrap, entry selection, clean exit, error control
  frame, `is_finished`, and join.
- Owned `Worker`, nonblocking `close`, suspending `join`, and `stop`.
- Validation and `string.buffer` encode/decode with pathful errors.

Exit test: messages round-trip in order; full queues refuse without blocking;
close drains queued frames and wakes blocked receivers; every native allocation
and thread is released after clean and failed entries.

### W2: suspension waits

- `tryReceive`, indefinite and timed `receive`, and suspending `join`.
- One readiness source per `SuspensionContext`, retained only while waiters
  exist.
- Cancellation, deadlines from a monotonic clock, worker exit, and handler
  shutdown settlement.
- Blocking-handler and cooperative-handler conformance tests.

Exit test: one call site blocks without a handler and parks with one; a ready
operation never calls `suspend`; canceling the last waiter removes the source
and leaves no idle polling.

### W3: calls and serving

- External request/reply frames and monotonically increasing identifiers.
- Concurrent calls, out-of-order replies, ordinary message routing, late-reply
  discard, and id exhaustion handling.
- `Self:serve`, per-call error replies, and continued service after failure.

Exit test: calls return to their issuing waiters regardless of reply order;
ordinary messages are never consumed as replies; user tables cannot collide
with protocol metadata.

### W4: build and distribution completion

- Automatic `native.workers` detection and `nativeFeatures.workers` override.
- Conditional sidecar staging and conditional compiler-host feature.
- Worker entry dispatch for compiler-owned binaries and explicit refusal for
  unsupported stubs and one-file bundles.
- Cache, stale-output, clean, package, and binary fixpoint coverage.

Exit test: modules and binary targets run the same entries; a worker-enabled
binary rebuilds byte-identically; a worker-free compiler binary remains
byte-identical to its pre-feature output.

### W5: tecs adoption and performance

- Port representative tecs worker entries and the existing worker spec suite.
- Install tecs's suspension handler and exercise receive, call, cancellation,
  stop, and shutdown inside a frame.
- Benchmark spawn, send, ready receive, parked receive, call throughput, frame
  polling, and several workers computing concurrently.

Exit test: behavior matches the tecs suite, ready paths do not regress beyond
the cost of Nupp's validation contract, and four CPU-bound workers demonstrate
parallel progress.

## Test matrix

- selection: direct require, aliased module use, constant-dead use at `-O1`,
  forced include, forced removal, no use
- targets: modules, compiler-owned binary, unsupported prebuilt stub, refused
  one-file bundle
- values: every scalar, nested tables, mixed allowed keys, top-level nil,
  function, thread, userdata, cdata, excessive depth, cycles, oversized payload
- queue: FIFO order, message limit, byte limit, close with queued messages,
  close while blocked, send after close, repeated close and destruction
- worker: missing entry, syntax/load failure, runtime failure, clean return,
  blocked receive, compute before receive, repeated stop, join while running
- routing: ordinary messages among replies, concurrent calls, reversed replies,
  canceled call, late reply, handler failure, unserializable handler result
- suspension: immediate readiness, blocking wait, cooperative wait, timeout,
  synchronous resume, cancellation, source retention and release, shutdown
- ownership: explicit stop, `with` fallthrough, error unwind, cancellation
  unwind, no GC join, uncooperative worker documented as non-terminating
- native modules: pure standard library, each selected Lua C module, each
  sidecar native facility supported in workers, absent facility diagnostics
- performance: JIT compilation in every worker state, no idle source, bounded
  poll work, parallel CPU progress, repeated spawn/stop memory stability
- determinism: module output, worker-aware payload, binary fixpoint, cache hits,
  and byte identity for worker-free targets

## Open questions

- Whether the sidecar embeds a symbol-hidden pinned LuaJIT or receives a
  verified runtime function table from the embedding interpreter. W0 owns the
  answer.
- Whether timed receive belongs in W2 or should wait for the first common
  monotonic time facility. Indefinite receive and explicit polling are enough
  for the first useful worker.
- Whether queue bounds become spawn options. Fixed bounds make the first
  ownership and denial-of-service contract easier to audit.
- Whether a later `Worker<Request, Reply>` protocol type can be checked against
  an entry module without introducing a false guarantee across `any`, dynamic
  module names, or independently built packages.
- Whether worker entry metadata should eventually be inspectable by `nupp
  tasks`. It is unnecessary while any compiled module may be selected and
  should not become manifest ceremony without a packaging need.
- Whether a pool belongs in `nupp.workers.pool` after the compiler or tecs has
  two measured consumers with compatible scheduling requirements.
