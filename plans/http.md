# HTTP client: a design record

Status: proposed. [Suspension](suspension.md), concurrent suspension drivers, buffers,
byte views, readers, writers, [files](files.md), paths and URIs have landed. One small
waitable-source extension described below, the HTTP provider and its performance
benchmarks have not.

## Decision

Nupp will provide an optional `nupp.io.http` module implemented by a feature-gated
Reqwest/Tokio provider in `runtime/native`. One pooled `Client` sends HTTP and HTTPS
requests, returns as soon as final response headers are available, and exposes the
response body as an owned progressive `Reader`.

The public call is synchronous in shape and contextual in execution:

- in a command-line program it blocks in the provider's readiness wait;
- under a suspension handler it parks the current task and lets the host continue;
- inside `nosuspend` or a host barrier it is refused before native work starts.

Small requests and sustained streams are both primary workloads. The provider will not
route a string, buffer or file through the generic reader fallback, will not allocate a
heap event for every body chunk, and will not make a handled stream wait for one host
frame per bounded queue window.

Tecs remains an SDL application. Nupp neither owns nor calls SDL. Tecs installs its task
scheduler as Nupp's suspension handler, polls Nupp readiness sources from the SDL-owned
iteration, and resumes the parked system on its Lua thread. Reqwest's worker threads
never enter LuaJIT and never call SDL. Tecs's ECS request plugin remains a Tecs facility
implemented over the Nupp client. Its HTTP transport, per-client polling registry and
private upload scheduler disappear; a thin Tecs lifecycle registry may remain to close
Teal-created clients at application shutdown.

## Why this shape

### The transport and the host have different owners

Reqwest owns HTTP semantics: connection pooling, TLS, redirects, proxies, compression,
HTTP/2, request transmission and response decoding. Nupp owns the stable typed API,
resource lifetime, bounded native boundary and suspension operation. A host owns how a
parked continuation runs again.

Tecs therefore does not need an SDL HTTP backend and Nupp does not need an SDL loop. The
join is the suspension contract already used by files and processes:

```
 Tokio / Reqwest threads       Nupp provider            Tecs SDL thread
 ────────────────────────────  ───────────────────────  ──────────────────────
 move sockets and TLS          queue readiness tokens   SDL_AppIterate
 fill bounded body queues      poll without blocking    poll Nupp sources
 drain bounded upload queues   resume one-shot waits    drain task scheduler
 never enter LuaJIT            never call SDL           resume original system
```

The same compiled `nupp.io.http` module works without Tecs because the built-in
suspension path calls the provider's sleeping readiness wait instead of a host poll.

### `Reader` is the public stream, not the provider boundary

`nupp.Reader` is the right public response type: `read`, `readInto`, `transferTo` and
`close` are the operations a consumer needs. It is not enough as the only internal
upload path. A generic reader cannot say that its bytes are already contiguous, that it
is a native file, or that its storage may be borrowed for the duration of one call.
Forcing all bodies through `Reader:read` would allocate a Lua string and copy it again
into Rust even when the caller supplied a `Buffer`.

The request body union therefore preserves concrete fast paths and has a generic reader
only as its fallback. The response body implements `Reader`, but its concrete methods
may reach Nupp's private buffer capability so `readInto` performs one copy directly
from Rust's current `Bytes` into the destination allocation.

### The original event ABI is not the performance contract

Tecs's provider proved the difficult transport behavior: bounded independent response
queues, bounded uploads, cancelable work, connection limits, stall deadlines, repeated
headers and a foreign-thread boundary that never enters Lua. Those semantics come over.

Its numeric request identifiers and allocated `TecsHttpEvent` objects do not. Looking up
a body receiver in a mutex-protected map and allocating/destroying an event for every
chunk is unnecessary once the Lua side already owns the transfer. Nupp uses opaque
client, transfer and body handles and a deduplicated readiness queue. The body handle
retains its current Rust `Bytes`, so several small reads advance an offset rather than
creating several native events.

## Goals

1. Warm pooled small requests add little overhead over the Rust provider itself.
2. String, byte-view, buffer, file and generic-reader uploads remain bounded and each
   takes its fastest valid path.
3. Response strings cost one native-to-Lua copy; response `readInto(Buffer)` costs one
   native-to-buffer copy and no intermediate Lua string.
4. One unread response applies backpressure only to that transfer and does not obstruct
   headers or another body.
5. The same call blocks under a CLI and parks under Tecs without an asynchronous twin,
   a future type or a policy argument.
6. Tecs resumes an HTTP wait in the same SDL iteration that observes its readiness,
   subject to its existing scheduler round budget.
7. A target that never requires `nupp.io.http` compiles and ships none of Reqwest, Tokio,
   Rustls or the adapter.
8. Cancellation, lexical destruction and host shutdown leave no native transfer, body,
   upload branch or readiness source alive.

## Non-goals

- **An HTTP server.** Listening sockets and request parsing are a separate facility.
- **WebSocket, WebTransport or SSE objects.** An SSE response can be read as bytes, but
  reconnection and event framing are not HTTP-client semantics.
- **A cookie jar or cache.** The client exposes repeated `set-cookie` values correctly;
  policy and persistence belong above it.
- **A Tecs ECS plugin.** Tecs may retain its request/response components, snapshots and
  per-world client. They consume this module and are not part of Nupp.
- **A callback or future API.** Suspension already gives a host a continuation without
  exposing one to application code.
- **Zero copies for arbitrary readers.** Once a caller supplies only `Reader`, its bytes
  have no transferable ownership. The generic path uses one reusable Nupp scratch
  buffer and one copy into Rust-owned queue storage. Concrete bodies avoid that path.
- **One-file native bundles.** Under the current build rules, HTTP stages the selected
  `nupp_native` sidecar. Statically absorbing it into every possible host is separate
  distribution work.

## Surface

The module is explicit because requiring it is what selects a large native feature:

```nupp
local http = require("nupp.io.http")

do
    local client = assert(http.newClient({userAgent = "example/1.0"}))
    local endpoint = assert(nupp.io.URI.new("https://example.com/manifest.json"))
    local response = assert(client:send({url = endpoint}))

    print(response.status, response:ok())
    local destination = nupp.io.newBuffer()
    assert(response.body:readInto(destination, 0, 64 * 1024))
end
```

The records below describe the intended surface. The implementation is type-checked
against these obligations rather than treating them as documentation wishes:
`newClient` produces an owned client, `send` produces an owned response, the response
owns its body, and dropping either cancels and releases what remains.

```nupp
local record http
    record Options
        userAgent: string?
        headers: {string: string}?
        timeoutMs: integer?
        connectTimeoutMs: integer?
        stallTimeoutMs: integer?
        maxRedirects: integer?
        maxPendingRequests: integer?
        maxConnections: integer?
        maxConnectionsPerHost: integer?
        maxBytes: integer?
        compressed: boolean?
        insecureHosts: {string}?
        proxy: string?
        noProxy: string?
        proxyCredentials: string?
    end

    record ReaderBody
        reader: nupp.Reader
        length: integer?
        contentType: string?
    end

    record FileBody
        path: string | nupp.Path
        contentType: string?
    end

    type RequestBody = string | nupp.ByteView | nupp.Buffer | ReaderBody | FileBody

    record Request
        url: nupp.URI
        method: string?
        headers: {string: string}?
        body: RequestBody?
        timeoutMs: integer?
        stallTimeoutMs: integer?
        maxBytes: integer?
    end

    record Body is nupp.Reader
        @drop
        release: nosuspend function(takes self: Body): nil
    end

    record Response
        status: integer
        url: nupp.URI
        body: owned<Body>

        ok: nosuspend function(self: Response): boolean
        header: nosuspend function(self: Response, name: string): string?
        getAll: nosuspend function(self: Response, name: string): {string}
        headers: nosuspend function(self: Response): {string: string}

        @drop
        close: nosuspend function(takes self: Response): (boolean, string?)
    end

    record Client
        @owned
        send: function(self: Client, request: Request): (Response?, string?)
        pending: nosuspend function(self: Client): integer

        @drop
        close: nosuspend function(takes self: Client): (boolean, string?)
    end

    reader: nosuspend function(
        reader: nupp.Reader,
        length: integer?,
        contentType: string?
    ): ReaderBody
    file: nosuspend function(
        path: string | nupp.Path,
        contentType: string?
    ): FileBody

    @owned
    newClient: function(options: Options?): (Client?, string?)
end
```

`ReaderBody` and `FileBody` make metadata explicit without widening every `Reader` with
HTTP concerns. A reader is borrowed and consumed for the duration of `send`; HTTP does
not close a caller-owned reader. The suspension cancellation that abandons the upload
unwinds any wait inside that reader. A file body is opened and closed entirely on the
Tokio side.

The response header representation is lazy. `status` and `url` are available when
`send` returns. `header`, `getAll` and `headers` decode the provider's packed block on
first use and retain the Nupp tables afterwards. A caller interested only in status and
body does not allocate a header table. Repeated `set-cookie` is never comma-joined;
`headers()` keeps its first value while `getAll` returns every value. Other repeated
fields join with `", "` in the map and remain individually available through `getAll`.

If no redirect changed the effective URL, the response reuses the request's immutable
`URI`. Only a changed URL is parsed into a new value.

Invalid options, methods, header names, header values, schemes and inconsistent content
lengths raise at the call site before work starts. DNS, connection, TLS, timeout,
compression and transfer failures answer `nil, reason` from `send`; an HTTP 404 is a
successful response whose `ok()` is false. Body failures answer through the ordinary
`Reader` result shapes.

## Fast paths

### Warm small requests

A request using an existing client and no generic reader takes this path:

```
 validate Nupp values
       │
       ├─ merge small request header view
       ├─ borrow string / ByteView / Buffer for this FFI call
       ▼
 nuppHttpClientSend(client, descriptor)       one FFI submission
       │                                      one copy for an inline body
       ▼
 Tokio / Reqwest uses an existing connection
       │
       ▼
 enqueue one deduplicated HEADERS token
       │
       ▼
 readiness poll resumes the parked call       one park and wake
       │
       ├─ status directly from transfer
       ├─ reuse request URI when unchanged
       └─ retain packed headers lazily
```

There is no task or `suspension.all` allocation for bodyless, string, byte-view, buffer
or file requests. A request attempts `pollHeaders` immediately after submission and
again while subscribing, so a completion already present takes suspension's ready path.

The provider builds the secure Reqwest client once in `newClient`. The insecure client
is built only if `insecureHosts` is non-empty; an ordinary client does not pay for a
second pool. Client options and default headers are copied once. Per-request headers are
validated and packed once at submission.

### Inline byte uploads

Strings, byte views and buffers cross the synchronous submission call as borrowed
pointer/count pairs. Rust copies them once into owned `Bytes` before returning. Lua may
therefore release or mutate its source immediately after submission without racing a
worker thread.

A Nupp buffer is recognized through a private standard-library capability, not by a
public raw-pointer method. The capability validates that the object is a live canonical
buffer and supplies a rooted pointer for the synchronous call. A lookalike satisfying
the public `Buffer` interface uses its public operations rather than exposing private
storage.

Small inline bodies do not allocate the generic 512 KiB scratch buffer.

### File uploads

`http.file(path)` gives the provider a path and optional content type. Tokio opens the
file, reads it in bounded chunks and passes its stream directly to Reqwest. No payload
byte crosses Lua, and the file length supplies `Content-Length` unless the caller set a
matching value explicitly.

The provider checks file length and opens the file after the request owns a transfer, so
cancellation has one native handle to stop. Replacement between metadata and open is
handled as an ordinary open or length mismatch failure rather than trusted.

### Generic-reader uploads

A `ReaderBody` is the only request path that needs two concurrent branches:

```
 branch 1: reader -> reusable Buffer -> bounded native upload queue
 branch 2: wait for response headers or transfer failure
```

They run through Nupp's suspension driver, not through a private HTTP scheduler. If the
reader fails, branch 1 cancels the transfer before raising, which wakes branch 2. If the
server answers early or the transfer fails, branch 2 closes the native upload receiver,
which wakes branch 1. Both branches unwind before `send` returns or raises, so no helper
coroutine outlives the call.

The generic path reads at most 512 KiB into one buffer retained by the transfer. Offering
it to native storage has three answers: accepted, backpressure, or closed. Accepted
bytes are copied once into Rust-owned `Bytes`; backpressure parks without reading or
allocating another chunk; closed abandons the reader branch. An explicit length is
checked against both a caller-supplied `Content-Length` and the total actually read.

### Response headers

Rust retains headers in one packed block:

```
 header count
 [name offset, name length, value offset, value length]...
 concatenated name and value bytes
```

Names are already lowercase. Bounds and UTF-8 validity are checked once when Nupp first
decodes the block. The maximum encoded header bytes remain bounded, initially at 256
KiB. The provider never converts the block to CRLF text and Nupp never reparses HTTP
wire syntax Reqwest already parsed.

### Response bodies

Each transfer owns a bounded body receiver independent of the client's header-ready
queue and every other transfer. The initial window remains one MiB until benchmarks
justify another value. Backpressure therefore bounds a forgotten response without
blocking a second request's headers.

Reqwest chunks have no fixed size. The producer splits a large `Bytes` value into
at-most-64-KiB `Bytes` views before queueing it, without copying the allocation, so the
one-MiB window is a byte bound rather than sixteen arbitrarily large network chunks.

The native body handle retains one current `Bytes` value and an offset:

```
 nuppHttpBodyPeek(body, &pointer, &count, &state)
 nuppHttpBodyConsume(body, count)
```

`Body:read(count)` converts the borrowed range directly to one Lua string, consumes it,
and returns. `Body:readInto(buffer, offset, count)` asks the private buffer capability
for writable capacity, copies directly from the borrowed range, commits the resulting
length, and consumes it. Neither path allocates a native event. Several caller reads may
consume one Rust chunk.

Both methods drain every already-buffered chunk before suspending. A read registers one
waiter; a second simultaneous read of the same one-shot body raises. Closing the body
cancels a live transfer, releases the current chunk and wakes any waiter with a closed
reason. Reaching EOF releases the client's connection permit before the caller performs
another operation.

`transferTo` specializes canonical Nupp buffer and file writers internally. A buffer
destination uses the same direct copy as `readInto`. A file destination may use a
provider-owned native file sink so response bytes do not become Lua strings. An unknown
writer retains the ordinary `Reader` contract and receives bounded strings.

## Native model

### Cargo feature

`runtime/native/Cargo.toml` gains an `http` feature whose dependencies are optional:

- `bytes`;
- `reqwest`, without its default TLS provider and with gzip, deflate, streaming, SOCKS
  and the chosen Rustls backend;
- `rustls` with an explicitly installed crypto provider;
- `tokio` with the multithreaded runtime, filesystem, I/O, network, synchronization and
  time support;
- `tokio-stream` and `tokio-util` for bounded upload and file streams.

Requiring `nupp.io.http` records `native.http`. It requires `runtime.suspension` and
`native.uri`, builds `nupp_native` once with the union of selected features, stages the
public Nupp module and its private binding, and remains absent otherwise.

### Runtime

One process-wide Tokio runtime starts on first HTTP client creation. Its worker count is
not hard-coded to two: it defaults from available parallelism with a conservative floor
and ceiling, and an expert build-time or environment override can tune a host whose
network workload is known. The benchmark records the chosen count. TLS provider
installation is process-wide and idempotent.

Each `NuppHttpClient` owns:

- secure and optionally insecure Reqwest clients;
- connection and per-host concurrency semaphores;
- a preallocated ready ring with one slot per admitted transfer;
- a condvar/activity generation for the blocking waiter;
- the native references needed to cancel all transfers on close.

Each `NuppHttpTransfer` owns:

- request cancellation and the Tokio abort handle;
- final status, effective URL and packed headers;
- an optional upload sender and its backpressure notification state;
- a body receiver and its current `Bytes`/offset;
- one atomic readiness bit per token kind and one queued bit, preventing a full body
  queue from enqueuing sixteen identical wakeups;
- terminal failure and completion state.

Handles are reference-counted internally but cross FFI as owning opaque pointers. Every
destroy is idempotent from Nupp's wrapper, and the raw ABI requires one matching destroy
per returned owner. Cancellation removes producers first, then wakes consumers. A Tokio
panic settles the transfer with a failure before its guard drops.

### Readiness tokens

The client queue carries transfer handles, not body data. Each queued record snapshots
a bitmask of these token kinds:

```
 HEADERS       final status, URL and header block are ready
 BODY          at least one chunk or a terminal body state can be observed
 UPLOAD_SPACE  an offered generic-reader chunk may now fit
 FAILED        the transfer failed before headers
```

Native progress sets the token-kind bit and atomically sets the transfer's queued bit.
Only the transition of the queued bit from clear to set appends the transfer to the
ring. Polling takes the accumulated token-kind bits and clears the queued bit; progress
that races with that clear either joins the record or queues the transfer again. There
is therefore at most one queued record per admitted transfer and no full-queue drop:
the ring is sized from `maxPendingRequests` and submission cannot admit more live
transfers than it has slots. Lua maps the opaque transfer pointer to its live wrapper
only when draining a record. Body reads address their handle directly and perform no
client-map lookup.

The nonblocking poll drains a bounded batch, initially 256 records, into one reusable FFI
array owned by the Nupp client. It reports whether more remain, allowing a blocking
driver or host scheduler to call it again without allowing one client to monopolize an
SDL iteration. Body-copy loops carry their own 16 MiB per-resumption budget, so a direct
`transferTo` cannot walk around the token budget by consuming an unlimited ready body in
one task turn. Reaching that byte budget re-arms the body and performs a deferred
fairness suspension: it never completes inline, so a handled task yields once and is
made runnable by the next nonblocking source poll. The built-in driver immediately
pumps that ready source, without sleeping. This makes the byte budget real without
putting an asynchronous operation in the public API.

### ABI sketch

Names and exact C integer widths are fixed with the implementation and checked on every
platform. The ownership and work division are the important part:

```
NuppHttpClient *nuppHttpClientCreate(const NuppHttpClientOptions *);
void nuppHttpClientDestroy(NuppHttpClient *);

NuppHttpTransfer *nuppHttpClientSend(
    NuppHttpClient *, const NuppHttpRequest *
);
void nuppHttpTransferCancel(NuppHttpTransfer *);
void nuppHttpTransferDestroy(NuppHttpTransfer *);

int nuppHttpTransferOffer(
    NuppHttpTransfer *, const uint8_t *, size_t, bool finished
);
int nuppHttpTransferHeaders(
    NuppHttpTransfer *, NuppHttpResponseHead *
);

NuppHttpBody *nuppHttpTransferTakeBody(NuppHttpTransfer *);
int nuppHttpBodyPeek(NuppHttpBody *, const uint8_t **, size_t *);
bool nuppHttpBodyConsume(NuppHttpBody *, size_t);
void nuppHttpBodyDestroy(NuppHttpBody *);

size_t nuppHttpClientPoll(
    NuppHttpClient *, NuppHttpReady *, size_t capacity, bool *more
);
size_t nuppHttpClientWait(
    NuppHttpClient *, uint64_t ms,
    NuppHttpReady *, size_t capacity, bool *more
);
void nuppHttpReadyRelease(const NuppHttpTransfer *);
```

`Poll` never sleeps. `Wait` uses the activity generation and condvar so a CLI consumes no
CPU while the network is quiet. Neither function enters Lua. Nupp reads settled state
from the returned ready records. Each ready record carries a bitmask and one retained
reference to the transfer; the reusable Lua array allocates nothing per ready record, and
`nuppHttpReadyRelease` drops that reference after the wrapper handles or ignores it. A
transfer canceled and removed from Lua before a late record is drained therefore yields
a missing wrapper rather than a dangling pointer.

## Suspension and cancellation

HTTP needs one general suspension extension. A readiness source carries two operations:

```
 poll()             always nonblocking; hosts call this
 wait(timeoutMs)    optional; only the built-in blocking driver calls this
```

`Context:source` and the process-wide `suspension.source` accept the optional `wait`
alongside `poll`. The built-in driver polls all sources, and when a pass makes no
progress it round-robins across waitable sources with a bounded deadline before polling
all of them again. `suspension.poll`, which is what Tecs calls, invokes only `poll`.
There is no route from a handler-owned source pass to `wait`.

Keeping the two operations on one source also fixes the nested concurrency case. A
generic upload branch sees the suspension driver's internal handler, but the driver may
itself be using the built-in blocking path. Choosing a sleeping or nonblocking callback
from `suspension.handled()` inside the branch would misclassify that case and spin. With
both operations registered, the outer driver makes the choice. Files and processes can
adopt the same shape after HTTP proves it.

Every unresolved send, upload-backpressure wait and response-body read performs
`suspension.suspend`. Its subscription:

1. installs the one-shot resume callback on the transfer;
2. retains the client's shared poll/wait source, registering it if this is the first
   waiter;
3. probes the native state again, closing the subscribe-before-ready race;
4. returns a cancellation that removes the waiter and cancels the transfer when this
   operation is its sole consumer.

The ready path probes before constructing a park. A client with several waits has one
ref-counted readiness source while it has any Lua waiter, not one native poll per
waiter. The first subscription registers it through `suspension.source`; settlement or
cancellation decrements the count, and the last releases it. It is deliberately shared
rather than owned by the first subscription's context, whose automatic release would
otherwise stop the pump while a second wait still needed it. Host shutdown closes
clients before releasing its handler, so no shared source escapes the handled extent.
An unread body with no waiter needs no Lua pump: Tokio fills its bounded queue and stops
on backpressure.

Cancellation has one direction:

```
 host cancels task
   -> suspension calls subscription cancellation
      -> Nupp removes the Lua waiter
         -> native transfer aborts and closes upload/body producers
            -> helper upload branch wakes and unwinds
               -> lexical response/client cleanup runs
```

A late ready record may still be present in the client queue, but it retains only its
native transfer reference. Polling recognizes the canceled terminal state and drops it
without finding or resuming a Lua consumer.

`Client:close` stops accepting requests, cancels every transfer, wakes every wait and
releases the client's ownership of its Reqwest pools. It is non-suspending: helper
branches scheduled in other tasks unwind when their host next drains runnable work,
while their retained transfer state keeps the cancellation reason valid. The enclosing
task scope or suspension installation proves those branches have unwound before host
shutdown continues. Repeated close is safe.

## Tecs and the SDL loop

### Adapter

Tecs's task runtime implements `suspension.Handler` with its existing gate:

```nupp
local handler = new suspension.Handler {
    park = function(_, waiting, cancel)
        local task = currentTask()
        checkCanSuspend(task, waiting.operation)
        local gate = newGate(cancel)
        waiting:onResume(function() gate:complete(true) end)
        gate:wait()
    end,
    canPark = function()
        local task = currentTaskOrNil()
        return task ~= nil and task.scope.barrier == nil
    end,
    shutdown = function() end,
}
```

The handler is installed for the dynamic extent of each Tecs task body, including every
cycle of a reusable world-update root. Installation is not global around
`Application:_iterate`: a task owns its continuation, and one task's nested handler or
barrier must not leak into another.

The gate's cancellation calls the subscription cancellation before the task unwinds.
World shutdown and request-entity despawn therefore cancel native HTTP work through the
same route as any other task cancellation. `canPark` preserves Tecs's deterministic
barriers as the run-time counterpart of Nupp's `nosuspend` checking.

Tecs may load the adapter dynamically so a build without Nupp remains valid. Absence is
optional; a present but broken Nupp module is an initialization failure and is not
silently ignored.

### One SDL iteration

The ordering is:

```
 SDL_AppIterate
   1. seal the SDL event batch for this logical update
   2. poll process-wide Tecs sources
   3. poll Nupp suspension sources, without sleeping
   4. step the world scheduler
      a. readiness-completed gates become runnable
      b. resume each system at its original HTTP call
      c. poll Nupp again between runnable rounds while progress is reported
   5. render and finish the host iteration
```

The first Nupp poll precedes the scheduler, so a response observed in this iteration
resumes its task in this iteration. Polling again between scheduler rounds matters for
streaming: a task may consume a full body window, let Tokio refill it, and become ready
again without waiting for the next rendered frame. Both the readiness batch and Tecs's
existing maximum scheduler rounds bound the work. A zero-progress poll ends the extra
drain immediately; the SDL thread never spins waiting for network activity.

The world-update latch remains unchanged. If a system parks in `Client:send` or
`Body:readInto`, later systems do not overtake it, events arriving from SDL remain in the
next event batch, and simulated time does not advance on continuation iterations. HTTP
completion changes only which gate becomes runnable.

No provider call made from this path sleeps. `nuppHttpClientWait` is used only when no
handler is installed. Under Tecs every source calls `nuppHttpClientPoll`, and an empty
poll returns immediately.

### Frame cadence and waking SDL

The baseline contract assumes the continuously iterated SDL application Tecs already
runs: every host iteration polls readiness. HTTP does not call `SDL_PushEvent` and does
not link SDL, which keeps the provider usable in every Nupp host.

If Tecs later adopts an event-driven mode that lets `SDL_AppIterate` sleep indefinitely,
the host must arrange its own wakeup. The native HTTP provider exposes readiness through
its activity generation; a host-specific adapter may wait for that generation on a
host worker and request an SDL wake without entering Lua. That is a Tecs host feature,
not an alternate Nupp HTTP backend, and it must coalesce wakeups by the same readiness
bit so one packet does not become one SDL event.

### Tecs public API and plugin

`tecs.io.http.newClient` becomes a typed facade over `nupp.io.http.newClient` so its
current defaults, log naming and Teal surface remain stable. Nupp code may use the Nupp
module directly and receive lexical ownership checking.

The existing Tecs client registry loses its transport role: active Nupp waits register
their own readiness source, and unread bodies move independently on Tokio until their
bounded queue fills. If Tecs keeps `getOpenClientCount` and its promise to close a
forgotten Teal client during application shutdown, the facade retains a thin lifecycle
registry. It holds facade owners, unregisters them on `close` and closes them during
runtime shutdown, but it never polls a native HTTP queue. This is the same adaptation
needed whenever an owned Nupp value crosses into plain Lua or Teal, where Nupp's lexical
drop checking no longer runs.

The facade preserves Tecs's current surface deliberately:

```
 Tecs value or behavior            Facade mapping
 ────────────────────────────────  ─────────────────────────────────────────────
 Options and defaults              copied into Nupp options
 transport failure raises         turn Nupp's nil/reason into the Tecs error
 Response.headers field            materialize Nupp's lazy map for the facade only
 Response:getAll                   delegate to the retained Nupp response
 string body                       Nupp inline-string path
 known Tecs file stream            Nupp native-file path
 generic ReadableStream            borrowed Nupp Reader adapter
 response Stream                   owning adapter over the Nupp Body
```

The response adapter delegates reads and close rather than buffering, and its discard
path drains with the same bounded body operations. A known file stream exposes its path
privately to this facade; no application-visible downcast is added. Snapshot policy
stays in the ECS plugin.

Direct buffer streaming needs one shared implementation boundary. H3 either ports
`tecs.io.Buffer` and its byte views to the Nupp buffer implementation or teaches both
facades the same checked private borrow/write/commit capability from H0. Shipping a
Tecs adapter that turns every `readInto` into a Lua string is not acceptable: it may be
useful for functional bring-up, but it cannot pass the Tecs streaming gate and is not a
completed adoption.

The ECS plugin remains in Tecs because entities, snapshots and per-world clients are ECS
policy. Its system starts `Client:send` in the world's existing task scope, replaces the
request component after settlement, and closes an unread response when the entity is
despawned. Loading a snapshot cancels the old task scope and reissues the declarative
request just as it does today.

At shutdown Tecs orders work as follows:

1. world shutdown runs while application resources remain live;
2. per-world and application HTTP clients close, canceling transfers and bodies;
3. task scopes drain cancellation and lexical drops;
4. the Nupp suspension installation releases and proves it owns no parks or sources;
5. Tecs's runtime registry proves no source remains;
6. SDL resources and SDL itself shut down.

The Tokio runtime is process-global and may remain allocated until process exit, but it
has no client, socket, transfer or callback capable of reaching the torn-down
application.

## Backpressure, fairness and limits

The initial bounds retain Tecs's proven order of magnitude and become benchmark inputs,
not accidental constants:

```
 Resource                         Initial bound
 ───────────────────────────────  ─────────────────────────────
 admitted transfers               256 per client by default
 control/readiness ring           one slot/admitted transfer, one queued record each
 response chunks                  16 x 64 KiB = 1 MiB per body
 generic upload chunks            2 x 512 KiB = 1 MiB per upload
 response headers                 256 KiB per response
 nonblocking poll batch           256 records / 16 MiB visible progress
 Tecs same-iteration drain        existing scheduler round ceiling
```

`maxPendingRequests` counts transfers waiting for a connection, using one, or retaining
an unread body. `send` takes that admission permit before creating the native handle;
when none is free it suspends without native work, and cancellation simply removes the
waiter. The request deadline starts before this wait. Releasing a body or failed
transfer hands the permit to the next waiter. This bounds the ring and native transfer
state independently of how many Tecs tasks happen to call `send`.

One client uses round-robin ready records. A body that remains ready does not append an
unbounded sequence of records; after its consumer drains a bounded turn, it is eligible
behind other ready transfers. Connection limits are request-lifetime limits: a request
holds its total and host permit until its body ends or closes, because that is how long
its socket may remain occupied.

HTTP/2 multiplexes requests over fewer sockets, so the public names are concurrency
limits rather than promises about physical socket count. Benchmarks include HTTP/1.1
and HTTP/2; defaults must not cap a multiplexed client at six active streams merely
because six was a reasonable HTTP/1.1 per-host socket count. The implementation may
separate maximum in-flight requests from Reqwest's idle-per-host pool setting while
preserving compatibility aliases for Tecs.

Timeout is one deadline measured from submission through permit acquisition and body
completion. Connect timeout covers establishment. Stall timeout covers a response body
that makes no progress. Waiting behind a connection permit consumes the request
deadline rather than receiving a new duration once admitted.

## Performance contract

Performance is a landing gate, not a later optimization milestone. Benchmarks run on a
quiet machine against loopback servers, discard warmups, validate every byte and report
p50 and p95 latency, throughput distribution and retained/allocation counts. Cold client
and first-TLS setup are reported separately from the warm pool.

Three implementations are measured from the same Rust workspace and server:

1. the native Reqwest provider called directly from Rust;
2. the existing Tecs HTTP client;
3. the Nupp public API, blocking and under the Tecs handler adapter, plus the Tecs
   compatibility facade once H3 begins.

### Small-request matrix

- HTTP/1.1 keep-alive and HTTP/2;
- empty, 1 KiB and 4 KiB response bodies;
- GET and same-sized string POST;
- headers ignored, one header read, and full header map read;
- serial latency and concurrent throughput at 1, 8, 32 and 128 in flight;
- plain loopback and local TLS with session reuse.

After warmup, the full Nupp path must:

- meet or beat Tecs p50 and p95 in every equivalent case;
- stay within 1.15x of the direct Rust p50 and 1.25x of its p95 for empty and 1 KiB
  serial keep-alive requests;
- perform no generic-upload scratch allocation for bodyless or inline requests;
- allocate no native body event per chunk and no eager header table when headers are
  ignored.

If the direct baseline includes unavoidable server or kernel noise large enough to hide
adapter cost, a second benchmark uses an already-settled synthetic native transfer and
reports submission, ready suspension and body-consumption overhead in nanoseconds and
bytes per operation.

### Streaming matrix

Uploads:

- string;
- `ByteView`;
- `Buffer`;
- native file;
- generic memory reader;
- generic file reader;
- a composed reader that itself suspends.

Downloads:

- `read` to strings;
- `readInto(Buffer)`;
- transfer to canonical buffer writer;
- transfer to native file writer;
- generic writer;
- discard;
- one unread body beside an actively consumed body.

Payloads are 64 KiB, 4 MiB and 256 MiB. The 256 MiB run proves boundedness and sustained
behavior rather than fitting a whole transfer in caches. Each result reports MiB/s,
p50/p05 throughput, p50/p95 completion latency, maximum resident growth and bytes held
per active transfer.

Canonical buffer and file paths must reach at least 90% of the direct Rust provider's
sustained throughput and meet or beat Tecs. Generic reader/writer paths must reach at
least 80% while retaining the public fallback semantics. No path may retain the complete
256 MiB payload, and one stalled body may not reduce an independent small request to the
stalled body's cadence.

### SDL-host matrix

- response readiness immediately before an SDL iteration resumes in that iteration;
- a response body larger than one queue window drains through repeated nonblocking
  scheduler rounds rather than one window per frame;
- a zero-progress source poll returns control without another scheduler round;
- frame work remains bounded by token, byte and scheduler-round limits;
- cancellation during send, upload backpressure and body read unwinds in the same task;
- an active barrier refuses the call before native pending count changes;
- shutdown with pending requests, unread bodies and suspended composed uploads leaves no
  Nupp source or Tecs runtime entry.

Performance gates are recorded with machine, toolchain, provider versions and runtime
worker count. A change to chunk sizes, queue windows, polling budgets, header layout or
worker count reruns the whole affected matrix; throughput alone cannot approve a p95 or
frame-time regression.

## Tests

Rust unit and loopback tests cover:

- option, method, URL and header validation at the ABI;
- connection and per-host permits;
- proxy modes and TLS provider installation;
- redirect and effective-URL behavior;
- timeout, stall timeout and body limits;
- upload backpressure and wake deduplication;
- response queue independence;
- token fairness and poll budgets;
- handle destruction, cancellation and panic settlement;
- packed repeated headers;
- partial body peek/consume;
- runtime behavior on Windows, macOS and Linux.

Nupp tests use an injected private backend, following the process state-machine tests,
to cover API validation, lazy headers, ownership, cancellation, ready-path suspension,
generic-reader concurrency and direct-buffer operations deterministically. Native smoke
tests build the actual `http` feature and use a local server for one end-to-end request,
streaming upload and streaming download on every supported host.

Feature tests prove that literal `require("nupp.io.http")` selects `native.http`, brings
`native.uri` and `runtime.suspension`, stages the module and sidecar, and that a project
without the require contains none of them. Documentation examples compile. The standard
suite remains network-independent; no test contacts an external service.

Tecs acceptance tests run the Nupp client under its actual scheduler and SDL callback
host. They preserve the logical-update latch, barrier and shutdown assertions in
addition to the SDL-host performance matrix above. The existing Tecs HTTP suite runs
unchanged against the facade, including raised transport failures, eager `headers`,
repeated values, file-stream recognition, open-client count and shutdown. An allocation
assertion proves facade `readInto` does not create an intermediate Lua string for a
canonical Tecs buffer.

## Delivery

The design lands in measured slices, but every slice preserves the final boundary:

### H0: baselines and private buffer capability

- Port the Tecs loopback benchmark into a host-independent Nupp benchmark.
- Add the small-request and SDL-host matrices before the provider changes.
- Capture direct Rust and Tecs baselines.
- Add optional blocking `wait` to readiness sources; prove host `poll` never invokes it
  and nested concurrent operations block rather than spin outside a host.
- Give compiler-owned providers a checked private borrow/write/commit capability for
  canonical buffers; file and HTTP use the same mechanism.

### H1: handles, readiness and small requests

- Add the Cargo feature and Reqwest/Tokio provider.
- Implement opaque client/transfer/body handles, ready-token deduplication and packed
  headers.
- Implement bodyless and inline string/byte-view/buffer requests, lazy response headers
  and streaming response reads.
- Pass the small-request gates before adding another body source.

### H2: complete streaming paths

- Add native file uploads, generic-reader upload branches and native file downloads.
- Add direct canonical buffer/file writer specializations.
- Prove bounded queues, fairness, cancellation and the full streaming gates.

### H3: Tecs adoption

- Keep Tecs's suspension-handler adapter and make its poll/drain ordering explicit.
- Converge the Tecs and Nupp buffer fast paths before measuring hosted streaming.
- Replace `tecs.io.http.client` transport with the Nupp client.
- Delete the Tecs registry's transport pump and the private upload scheduler; retain
  only its close/count role if API compatibility requires it.
- Retain the ECS plugin as a consumer and run the SDL acceptance matrix.

### H4: distribution and documentation

- Document the API, ownership, limits, proxy/TLS behavior and sidecar requirement.
- Add native feature detection, staging, platform CI and package smoke tests.
- Record benchmark gates and provider versions beside the implementation.

Each slice is independently releasable only if it does not expose a slower fallback as
the permanent public path. In particular, H1's request union and native handles already
reserve buffer, file and generic-reader cases even before H2 implements every one.

## Rejected alternatives

### Port the Tecs adapter unchanged

It preserves behavior but also preserves numeric lookup, per-chunk event allocation,
eager CRLF header parsing, the private upload scheduler and the client registry's
transport pump. Those are Tecs integration artifacts, not HTTP requirements. A thin
facade-owner registry for Teal shutdown compatibility is a separate lifetime concern.

### Put HTTP directly in the Tecs host

That keeps SDL working by making every other Nupp host unable to use the client. The
suspension adapter already gives Tecs control of continuation scheduling without owning
the transport.

### Poll only once per SDL frame

A one MiB response window at 60 frames per second caps an otherwise local transfer near
60 MiB/s and makes the queue size an accidental bandwidth setting. Repeated nonblocking
poll/drain rounds use readiness already present while Tecs's existing round budget
preserves frame fairness.

### Give every completion an SDL event

It couples the provider to SDL, makes headless Nupp need a second backend and turns
packet activity into host event pressure. Tecs may add one coalesced host wake only if it
later stops iterating continuously.

### Materialize small responses in `send`

It saves one public read but destroys the invariant that `send` returns at headers and
requires a threshold where the provider guesses whether the caller wanted streaming.
Buffered chunks already make the following read synchronous when bytes arrived early.

### One generic `Reader` request type

It erases the information required for one-copy buffers and native files. Convenience is
kept through `http.reader`; performance is kept by preserving concrete variants.

### Expose native pointers publicly

It would make the provider ABI part of the standard-library API and let a caller retain
a pointer after consuming or closing its body. Private checked capabilities give
compiler-owned modules the fast path without transferring that hazard to applications.
