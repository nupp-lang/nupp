# Files — design record

Status: proposed. The waiting half is built: S0 through S4 of
[suspension](suspension.md) have landed, so a library may perform `suspend`,
a host may install a handler, a `nosuspend` region is checked, and a handled
suspension may cross a live resource obligation. S5 — `nupp.io.Process` —
has not, and is not a prerequisite. This is its easier twin and should land
first.

## Decision

Nupp will provide `nupp.io.files`: a filesystem namespace implemented in the
feature-gated Rust cdylib that already backs `nupp.io.Path`, `nupp.io.URI`,
`nupp.regex` and `nupp.data`, exposed through the `Buffer`, `ByteView`,
`Reader` and `Writer` vocabulary [byte I/O](../docs/io.md) already defines, and
waiting through `suspend` rather than through an API of its own.

Concretely:

- **One API, no asynchronous variant.** `files.read(path)` blocks in a
  command-line program, parks under a scheduler, and is a compile error inside
  a `nosuspend` region. The library has no policy parameter and no `waitMode`
  check.
- **The native side is one Rust feature, not a libc binding.** `cdef` and
  `cheader` are how a program binds *its* C libraries. A standard-library
  namespace binding `stat`, `dirent`, `CreateFileW` and their platform
  variations by hand is a per-platform declaration set inside the compiler.
- **Anything that can block is a submit/poll request**, driven by a readiness
  source the suspension runtime already pumps. Metadata operations stay
  synchronous, because a request costs more than the call it would replace.
- **tecs adopts by deleting.** `tecs.io.files`,
  `tecs.internal.fileasync`, `tecs.platform.storagebackend` and the atomic-write
  worker become one import, and tecs's runtime becomes the handler.

The motivating consumers are tecs, which has a good API over an SDL
implementation Nupp cannot link, and the compiler, which shells out to `ls`.

## Why this shape

### The vocabulary was built for this

`nupp.io` already has the four types a file API needs, and one of them says so
outright. From [io.md](../docs/io.md#writers):

> `flush` is a no-op for memory but is part of the common writer contract,
> allowing a later file or socket writer to implement the same interface.

So there is no abstraction to design. `files.open` answers a `File` whose
`newReader()` and `newWriter()` satisfy the interfaces a buffer already
satisfies, and every function written against `Reader` — a parser, a decoder,
a hash — works over a file without knowing one is there. tecs reached the same
arrangement independently: its `Reader`/`Writer` vocabulary is shared between
buffers, files and process pipes, and that is the part of its design worth
copying wholesale.

### The native route is already chosen

Four facilities already resolve through `runtime/native`, selected per target
by Cargo features and reached through one `ffi.load` in
[stdlib.nupp](../src/nupp/compiler/stdlib.nupp). A fifth is a feature, a set of
`nuppFs*` exports, and one more compacted installer chunk. The alternatives are
worse for specific reasons:

```
 Route                       Why not
 ──────────────────────────  ─────────────────────────────────────────────
 cdef against libc           a per-platform declaration set carried inside
                             the standard library; `struct stat` has no
                             portable layout and Windows shares none of it
 cheader("sys/stat.h")       a C toolchain becomes a requirement for
                             running `nupp check`
 Lua's `io.*` plus shelling  Lua has no directory API, which is why
 out for the rest            `fs.nupp` shells out today
 A Rust feature              chosen
```

The public surface stays free of FFI pointers, which
[stdlib.md](../docs/stdlib.md#availability-detection-and-lazy-loading) already
commits to, and a provider change stays invisible to application code.

### The waiting half is decided and shipped

A filesystem API is the first library that has to answer *who resumes me*, and
it does not have to answer it. `suspend(operation, subscribe)`, the blocking
handler, `handle suspension`, coroutine-local inheritance, ordered readiness
sources, `nosuspend`, NUPP2701, NUPP2702, and the S4 rule permitting a handled
suspension across a live obligation are all built. What remains is a library
that uses them, and the S4 rule is what makes a *file* API possible at all: a
read that cannot cross a `with` cannot be performed by anything that opened a
file.

### The compiler is a consumer, not a bystander

[`fs.nupp`](../src/nupp/compiler/fs.nupp) says what it costs to lack this:

> Directory listing shells out, because Lua has no directory API and LuaJIT's
> FFI would need one implementation per platform to get one back.

That is one process per listing, a quoting layer, and no answer at all on a
platform without a shell. F0 below deletes it, and does so before any of the
waiting work, because listing a directory never needed to wait.

## Goals

1. One namespace that covers what the compiler's build, the language server,
   tecs and an ordinary program each need from a filesystem, without a
   lowest-common-denominator API that satisfies none of them.
2. A call site that blocks under a CLI, parks under a frame, and reports
   NUPP2701 inside a barrier — written once.
3. tecs's `tecs.io.files` call sites compile against `nupp.io.files` with only
   the import changed.
4. Nothing linked, generated, or initialized for a target that does not use it,
   by the existing feature and lazy-member rules rather than a second switch.
5. The compiler stops spawning a process to read a directory.
6. No new diagnostic range. The rules this needs are already enforced.

## Non-goals

- **A virtual filesystem.** No mount table, no path rewriting, no archive
  overlay. A path names a file.
- **A storage seam.** tecs's `storagebackend` argues correctly that a console's
  content is not a directory tree, but the layer that should virtualize is
  `tecs.assets`, where content addressing already lives. `nupp.io.files` is
  concrete over the filesystem, and a platform without one does not get it.
- **File watching.** It wants the same readiness source and is listed in
  [suspension](suspension.md#what-nupp-gets) as its own consumer. It is a
  separate namespace with a separate native lane.
- **Sockets, pipes and HTTP.** The `Reader`/`Writer` contracts are the shared
  part; the rest is not this document.
- **Permissions beyond read-only.** Modes, ACLs, ownership and extended
  attributes are platform vocabulary with no common shape.
- **Memory mapping.** A mapped range is a borrow of a region whose lifetime the
  operating system owns, and the ownership model has nothing to say about it
  yet.

## The surface

```nupp
with file = nupp.io.files.open("input.txt") do
    local header = file:newReader():read(64)
    print(header)
end
```

`open` is an `@owned` function, so the checker reports NUPP2602 for a `File`
whose disposal is not recorded, and `with` discharges it across fallthrough,
errors and structured control flow. `DirectoryStream` and `TemporaryPath` are
owners for the same reason. This is where Nupp improves on the original: tecs
declares `is Closeable` and documents the obligation, and Nupp enforces it.

The namespace divides on one axis that matters, because it is the axis the
implementation divides on:

```
 Immediate                        Waiting
 ───────────────────────────────  ─────────────────────────────────────
 exists, isFile, isDirectory      read, readInto, lines
 isSymlink, info, readLink        write, writeAtomic, append
 createSymlink, setReadOnly       copy
 createDirectory, remove, rename  open, and every Reader/Writer on a File
 currentDirectory, userFolder     glob and DirectoryStream:next
 createTemporaryFile/Directory
```

An immediate operation is a metadata call that returns before a request could
have been submitted. A waiting operation *may* suspend and is therefore
inferred `yields`, which is what carries the fact to a caller and into a
`nosuspend` region.

`createTemporaryFile` is on the immediate side because creating the entry is a
metadata operation; writing through the returned path is not.

A path argument is `Path | string`, matching tecs's `PathInput`, since
[`nupp.io.Path`](../docs/path-uri.md) is the same crate and already normalizes.
Environment failures answer `nil, reason`; a malformed argument raises at the
call site, per [stdlib.md](../docs/stdlib.md#errors-and-ownership).

## The native layer

A `files` feature in `runtime/native`, following the conventions already in
`lib.rs`: a thread-local last error read by `nuppNativeError`, `NuppBytes` for
returned byte ranges, and no allocation the caller cannot destroy.

Two tiers, matching the split above.

**Immediate exports** are ordinary calls over `std::fs`: `nuppFsMetadata`,
`nuppFsReadLink`, `nuppFsCreateSymlink`, `nuppFsCreateDirectory`,
`nuppFsRemove`, `nuppFsRename`, `nuppFsList`, `nuppFsTemporary`. `userFolder`
is the one that `std` does not answer and needs the `directories` crate behind
the same feature.

**Request exports** are a bounded lane:

```
 Export                                  Answers
 ──────────────────────────────────────  ───────────────────────────────
 nuppFsSubmitRead(path) -> *Request      a handle, or null and an error
 nuppFsSubmitWrite(path, data, len, …)   a handle
 nuppFsStatus(request) -> i32            pending, ready, failed, canceled
 nuppFsData / nuppFsLength / nuppFsError the settled outcome
 nuppFsCancel(request)                   detaches a waiter
 nuppFsDestroy(request)                  releases the handle
 nuppFsPoll() -> usize                   how many settled, without blocking
 nuppFsWait(ms) -> usize                 the same, sleeping up to a deadline
```

This is `tecs`'s `tecsAsyncFile*` ABI with SDL removed. Port
`native/rust/runtime/src/fileasync.rs` onto `std::thread` and `mpsc`, keep its
bounded-lane accounting — a request cap, a total-bytes cap, a per-request byte
cap, and a fixed worker count — and drop `sdl3_sys`. That accounting is the
hard-won part and reinventing it is the predictable way to ship a queue that
grows without bound.

Two constraints on the workers, both load-bearing:

- **A worker never enters Lua.** It settles a request; the Lua side observes
  the settlement when something polls. This is what allows the pump to be
  driven from a frame, a CLI loop, or the blocking handler without three
  implementations.
- **`nuppFsWait` exists so the blocking handler does not spin.** A CLI reading
  one file should sleep in the platform, not burn a core polling a status
  integer.

Regular-file I/O is why a thread pool rather than readiness notification: on
POSIX `O_NONBLOCK` has no effect on a regular file, so there is no descriptor
to wait on and the blocking call has to happen somewhere off the calling
thread. `io_uring` and Windows overlapped I/O can replace the pool later behind
the same exports; neither is a first version.

`writeAtomic` is a request kind, not a Lua construction. The worker writes a
temporary beside the destination, syncs it, and renames over the target. tecs
currently spawns a worker thread running a Lua chunk to do this
(`ATOMIC_WRITER` in `tecs/io/files/init.tl`) because SDL's asynchronous queue
cannot express the rename; deleting that is one of the clearer wins here, and
`fs.nupp` already implements the same dance in Lua for the build.

## Waiting

A waiting operation attempts its immediate path, and only then suspends:

```nupp
local function awaitRequest(request: Request, operation: string): Outcome
    if request:settled() then
        return request:take()
    end
    return suspend(operation, |resume, context| -> do
        local source = context:source("nupp-files", FILE_PRIORITY, pump)
        local ticket = waiters:add(request, resume, source)
        return || -> waiters:cancel(ticket)
    end)
end
```

What that call does then depends on nothing the library knows:

```
 Context                        Behavior
 ─────────────────────────────  ─────────────────────────────────────────
 no handler installed           the built-in handler drives the pump and
                                sleeps in nuppFsWait between passes
 a scheduler installed          the task parks; the frame continues
 inside nosuspend or a barrier  NUPP2701, at compile time
 inside an FFI callback         NUPP2702, at compile time
 with a live obligation         allowed under `handle suspension`; a raw
                                coroutine yield is still NUPP2603
```

The early return is not an optimization.
[suspension.md](suspension.md#cost-model) measures the ready path — an await
that resumes during its own subscription — at about 414ns and 560 bytes, and
records that a real park costs only about 100ns and 45 bytes beyond it. The
apparatus, not the waiting, is most of the cost of a wait. A read whose worker
has already settled must not build a subscription, and a `Reader:read` served
from a buffered range must not reach `suspend` at all.

One readiness source covers the whole namespace, registered while the lane has
outstanding requests and released when it drains, which is what
`fileasync.tl` does today with `runtime.register`/`unregister`. The priority is
a number tecs's scheduler orders against its other sources; Nupp picks a
default and does not have an opinion beyond it.

## What tecs deletes

```
 tecs today                            After
 ────────────────────────────────────  ──────────────────────────────────
 io/files/init.tl (1652 lines)         nupp.io.files
 platform/storagebackend.tl (65 SDL)   deleted on desktop
 internal/fileasync.tl (225 lines)     one readiness source
 native/…/fileasync.rs (652 lines)     ported, SDL dropped
 the ATOMIC_WRITER worker chunk        a native request kind
 taskruntime.waitMode / checkWait      the language
 runtime.register(name, pri, poll, …)  context:source(name, pri, poll)
 Completion<T> at the files boundary   the value `suspend` answers
```

`Completion<T>` is the interesting deletion. tecs needs it because its file
operations answer a future the caller then waits on; a suspending call answers
the value, so the type disappears from this boundary. It stays wherever tecs
genuinely wants a handle to something outstanding.

What tecs keeps: the scheduler, the gates behind it, `tecs.assets`, and the
storage seam if a console port ever needs one — above `nupp.io.files` rather
than beneath it.

## Risks

- **Cancellation of a partial write.** A cancelled read discards bytes nobody
  saw. A cancelled write may have already written some. The lane must report
  the distinction rather than answering a bare "canceled", and `writeAtomic`
  is the operation that makes it tolerable — a cancelled atomic write leaves
  the destination untouched.
- **Windows.** Symbolic links carry a file/directory distinction at creation
  (tecs's `SymlinkKind` already encodes it, copy it), paths are UTF-16 and the
  namespace is byte-oriented, and `remove` on an open file behaves differently.
  Budget for this rather than discovering it.
- **Bootstrap ordering.** If the compiler uses `nupp.io.files`, the compiler's
  own build needs the `files` feature on, and `bootstrap/nupp.lua` must still
  work without it. F0 keeps `fs.nupp`'s existing fallbacks until F4 removes
  them.
- **Scope.** `glob` is the operation that invites a second implementation.
  tecs's `matchesGlob` is pure Lua and correct; port it rather than reaching
  for a Rust crate that brings a walker, a cache, and an opinion about
  `.gitignore`.

## Milestones

### F0: the immediate tier — done

- A `files` feature in `runtime/native` with the metadata, listing, directory,
  link, rename and temporary exports over `std::fs`.
- The installer chunk in `stdlib.nupp` and the lazy member registrations.

Three things landed differently than this section proposed.

**`userFolder` earns no dependency.** It reads the `XDG_*` variables where they
are set and joins the platform's conventional name under the home directory
otherwise, which is what the `directories` crate does minus the desktop
configuration file it also reads. The limit is stated on the page rather than
hidden: a desktop that records its folders somewhere else is not consulted. That
closes the open question below.

**A path goes in; a string comes out.** Answering a `Path` would make every
program that lists a directory link the `path` provider too, and the two
features are independent everywhere else. The cost is that tecs's
`readLink`/`userFolder` call sites wrap the answer in `Path.new`, which is the
one place goal 3 does not hold and is recorded here rather than discovered
during F4.

**`fs.nupp` did not adopt it.** The compiler uses no native facility today, so
switching its directory listing would make the compiler the first program that
cannot build without a Rust artifact — the bootstrap risk this document already
lists. It moves to F4, where the bootstrap question gets decided on purpose.

Exit test met: `tests/filestest.lua` builds the provider with Cargo and drives
every operation against a real filesystem, including the symbolic-link and
listing cases; a target that resolves no `files` member carries none of the
declarations.

### F1: the surface

- `File`, `DirectoryStream`, `TemporaryPath` as owners, over the existing
  `Reader`/`Writer` contracts.
`Buffer` is already backed by an FFI byte array, so a transfer through it is
linear and a native read has somewhere to write bytes into. Handing the lane a
pointer into that array, rather than copying through a Lua string, is F2's to
decide.

Exit test: a file round-trips through `Reader:transferTo(writer)`; a 256 MiB
file transfers in linear time; a `File` bound outside `with` and not disposed
reports NUPP2602; the existing `nupp.io` tests are untouched.

### F2: the request lane

- The submit/poll exports and the worker pool in Rust, with the bounded-lane
  accounting ported from tecs.
- `writeAtomic` as a request kind.
- No Nupp-side waiting yet: F2's Lua side polls to completion.

Exit test: a hundred concurrent reads settle; the request cap refuses the
hundred-and-first with a reason rather than queueing it; a cancelled request
releases its handle and its bytes; no worker touches a `lua_State`.

### F3: suspension

- The readiness source, the `suspend` call sites, and the immediate-completion
  early return.
- The blocking handler path sleeping in `nuppFsWait`.

Exit test: one program reads a file unchanged under no handler and under a test
handler; a read inside `nosuspend` reports NUPP2701 naming the chain; a read
holding a `with` obligation runs cleanup on cancellation; a settled request does
not allocate a subscription; the language server's file reads stop blocking its
loop.

### F4: adoption

- `fs.nupp`'s shell-out and `io.open` paths removed.
- tecs swaps its imports, deletes the four modules, and installs its runtime as
  the handler.

Exit test: tecs's own `files` tests pass against `nupp.io.files` with only the
import changed; tecs links no SDL asynchronous I/O; the compiler spawns no
process to read a directory.

## Test matrix

- immediate operations: each one, on each platform, plus the failure each has
  (missing path, permission, not a directory, cross-device rename)
- ownership: an undisposed `File`, `DirectoryStream` and `TemporaryPath`; each
  discharged by `with`, by transfer, and by explicit disposal
- transfers: empty file, embedded NUL bytes, a file larger than the per-request
  cap, a partial read at EOF, and a write that fills the lane
- suspension: blocked, parked, cancelled, refused in a region, refused across a
  C boundary, and settled synchronously
- cancellation: a cancelled read, a cancelled write, and a cancelled atomic
  write leaving the destination untouched
- lane accounting: request cap, byte cap, per-request cap, and a drained lane
  releasing its source
- determinism: a build's output and the fixpoint identical with the feature
  present and absent
- feature gating: no adapter, no artifact, and no initialization for a target
  that resolves no member, including after `-O1` dead-code elimination
- tecs compatibility: its `files` suite against this namespace

## Open questions

- Whether `lines` should answer an iterator that may suspend, or require the
  caller to hold the file open and read explicitly. An iterator that parks
  inside a generic `for` is allowed on this baseline — the C `ipairs` iterator
  returns before the body runs — but a suspending iterator is a surprising
  thing to hand someone.
- Whether `DirectoryStream` should read eagerly into a list or stream through
  the request lane. tecs streams, and a directory with a million entries is the
  case that justifies it; a directory with twelve is every other case.
- Whether the per-request byte cap belongs in the native lane or in the Nupp
  surface. tecs puts it in the lane, which makes a large file an error rather
  than a chunked transfer. Chunking belongs somewhere and the lane is the wrong
  place for the policy.
- Whether `nupp.io.files` should answer `Path` values once a program that uses
  both is in front of us. Doing it needs one feature to select another, which
  the effect table cannot express today.

## Diagnostics

No range is reserved. The rules this namespace needs are already enforced:

- **NUPP2602** — a `File`, `DirectoryStream` or `TemporaryPath` whose disposal
  is not recorded.
- **NUPP2603** — a raw coroutine yield while one of them is live. A handled
  suspension in the same position is allowed, which is the S4 rule.
- **NUPP2701** — a file operation inside a `nosuspend` region or a tecs
  barrier.
- **NUPP2702** — a file operation across a C-call boundary.

## Next

- [plans/suspension.md](suspension.md) — the effect, the handler, and the S5
  process library this shares a platform layer's worth of lessons with.
- [docs/io.md](../docs/io.md) — the buffer, reader and writer contracts this
  namespace implements.
- [docs/ownership.md](../docs/ownership.md) — `@owned`, `with`, and what a
  suspension may cross.
