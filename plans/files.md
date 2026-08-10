# Files: a design record

Status: proposed. The waiting half is built: S0 through S4 of
[suspension](suspension.md) have landed, so a library may perform `suspend`,
a host may install a handler, a `nosuspend` region is checked, and a handled
suspension may cross a live resource obligation. S5, `nupp.io.Process`, has
not, and is not a prerequisite. This is its easier twin and should land
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
satisfies, and every function written against `Reader` works over a file
without knowing one is there: a parser, a decoder, a hash. tecs reached the same
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
read that cannot cross a live cleanup obligation cannot be performed by
anything that opened a file.

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
   NUPP2701 inside a barrier, written once.
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
do
    local file = assert(nupp.io.files.open("input.txt"))
    print(file:newReader():read(64))
end
```

`open` is an `@owned` function, so a `File` nobody binds reports NUPP2605 and
one that goes out of scope is closed across fallthrough, early return and
errors. `TemporaryPath` is an owner for the same reason. This is where Nupp
improves on the original: tecs declares `is Closeable` and documents the
obligation, and Nupp enforces it.

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
bounded-lane accounting, and drop `sdl3_sys`. That accounting is a request cap,
a total-bytes cap, a per-request byte cap, and a fixed worker count. It is the
hard-won part, and reinventing it is the predictable way to ship a queue that
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
[suspension.md](suspension.md#cost-model) measures the ready path, an await
that resumes during its own subscription, at about 414ns and 560 bytes, and
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
storage seam if a console port ever needs one, which would sit above
`nupp.io.files` rather than beneath it.

## Risks

- **Cancellation of a partial write.** A cancelled read discards bytes nobody
  saw. A cancelled write may have already written some. The lane must report
  the distinction rather than answering a bare "canceled", and `writeAtomic`
  is the operation that makes it tolerable, since a cancelled atomic write
  leaves the destination untouched.
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

### F0: the immediate tier (done)

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
cannot build without a Rust artifact, which is the bootstrap risk this document
already lists. It moves to F4, where the bootstrap question gets decided on
purpose.

Exit test met: `tests/filestest.lua` builds the provider with Cargo and drives
every operation against a real filesystem, including the symbolic-link and
listing cases; a target that resolves no `files` member carries none of the
declarations.

### F1: the surface (done)

- `File` and `TemporaryPath` as owners, over the existing `Reader`/`Writer`
  contracts.
- Whole-file `read`, `write`, `append`, `writeAtomic`, `copy` and `lines`.
- `docs/files.md`, and `nupp.io.files` listed in `stdlib.md`.

The reader and writer are declared as `nupp.Reader` and `nupp.Writer`, which
are interfaces, so conformance is structural and a parser written against a
buffer takes a file with no adapter. `readInto` and `writeFrom` reach into the
destination buffer's FFI storage directly, which is the payoff for backing
`Buffer` with an array: a native read lands where the bytes belong rather than
in a Lua string on the way there.

Transfers are synchronous here. F2 replaces the mechanism and F3 adds the
`suspend`; the surface above does not move.

`with` had been removed from the language by the time this landed, so the
ownership story is the lexical one: a `File` nobody binds reports NUPP2605, and
one that goes out of scope is closed on fallthrough, early return and error.

`DirectoryStream` did not land. `list` answers a table, which is the whole of
what a caller needs until a directory is too large to hold, and streaming it
belongs with the request lane rather than ahead of it.

Exit test met: a file round-trips through `Reader:transferTo(writer)`; a 300 KiB
payload streams through a fixed window; the generated Lua for an unbound `File`
carries its `close`; the existing `nupp.io` tests are untouched.

### F2: the request lane (done)

- The submit/poll exports and the worker pool in Rust, with the bounded-lane
  accounting ported from tecs.
- `writeAtomic` and `copy` as request kinds.
- No Nupp-side waiting yet: F2's Lua side waits on `nuppFsWait` to completion.

Whole-file `read`, `write`, `append`, `writeAtomic` and `copy` submit to the
lane; the four synchronous exports they used to call are gone rather than left
beside it. The cursor operations on an open `File` stay direct, because
scheduling a transfer costs more than a cursor read costs to run.

The lane prices a read by sizing the file **on the submitting thread**, since a
lane that cannot price a transfer cannot bound itself, and SDL leaves the same
lookup synchronous for the same reason.

The budget is returned when the **caller's handle** is destroyed. The first
attempt tied it to the shared state instead, so that a cancelled transfer whose
worker was still reading had not yet given its bytes back. That is a nicer
sentence and an unobservable rule: a worker publishes `READY` from inside the
state both sides share, so a caller releasing the instant it sees the result is
still counted until the worker gets around to dropping its own reference. It
shipped, and the suite caught it one run later. Intermittently, because
whether the worker had let go by then was a race. What the cap is for is
bounding what a program can keep accumulating, and the caller's handle is
exactly what measures that.

`nuppFsWait` reads the arrival count under the same lock a worker raises it
under. Without that, a settlement landing between the status check and the
sleep is slept through, which is a 25ms stall per transfer and invisible to a
test that only checks the answer.

The Rust unit tests this needs cannot run from the Lua suite, so `nupp task
native-test` runs them.

Exit test met: 24 concurrent transfers settle and return their slots; the
request cap refuses rather than queueing; a cancelled transfer reaches
`STATUS_CANCELED` and is refunded on destroy; no worker touches a `lua_State`.

### F3: suspension (done)

- The readiness source, the `suspend` call sites, and the immediate-completion
  early return.
- The blocking path sleeping in `nuppFsWait`.
- The immediate operations declared `nosuspend`, so a region that forbids
  waiting still permits asking what a path is.

**A target has to carry the suspension runtime, and nothing shipped it.** The
generated installer calls `require("nupp.suspension")`, and that module resolved
only inside this repository. An outside project got `unknown` for it. The same
was already true of `handle suspension`, so a library performing `suspend` could
not ship at all; F3 is only where it stopped being avoidable.

The fix is one edge in the feature table. `native.files` declares
`requires = {"runtime.suspension"}`, `native.resolve` closes over `requires`
transitively, and the native stage copies a feature's `runtimeModule` out of the
compiler's own build into the target. `handle suspension` records the same
effect from the checker, so user code gets the module by the same route. That
feature is deliberately not `binary`, so no manifest can force it on or off:
nothing selects it, it is implied by what waits.

The pump is chosen per wait rather than once. Under a handler it is
`nuppFsPoll`, which must not block a frame; with no handler it is `nuppFsWait`,
because the built-in blocking path drives sources in a loop and would otherwise
spin. `suspension.handled()` distinguishes them, which answers the deadline-hint
open question in [suspension.md](suspension.md#open-questions) with "not yet".

Exit test met: one program reads a file unchanged under no handler and under a
test handler that drives the pump and is told `file transfer`; a read inside
`nosuspend` reports NUPP2701 while `isDirectory`, `list` and `rename` in the
same region do not; a settled transfer never reaches a handler; an outside
project that uses `nupp.io.files` builds, stages `nupp/suspension.lua`, and
runs.

Not covered: the language-server claim in the original exit test, which is F4's
rather than this milestone's.

### F4: adoption (blocked, and on more than it looked)

Both halves were attempted and neither is a swap. Recorded here because
"adoption" as one milestone hid two separate projects.

**The compiler cannot adopt this without a Rust toolchain.** Rewriting
`fs.listFiles` over `files.list` is ten lines, and it does not build:

```
src/nupp/compiler/fs.nupp:125: error: NUPP2004: no field "files" in
  {Path: Library, URI: Library, newBuffer: ..., newStringReader: ...}
```

`bootstrap/nupp.lua` is a pre-generated compiler carrying the prelude it was
generated from, and that prelude predates `nupp.io.files`. So the bootstrap has
to be regenerated first, and then a fresh clone's bootstrap reaches
`nupp.io.files` while listing the sources it is about to compile, which means
`nupp_native` has to be built and loadable *before* the compiler runs at all.
Building it needs Cargo:

```
 Step                              Needs
 ────────────────────────────────  ──────────────────────────────────
 regenerate bootstrap/nupp.lua     a compiler that knows the member
 fresh clone runs ./bin/nupp       nupp_native, with the files feature
 build nupp_native                 Cargo
```

Today Cargo is needed only by a target that selects a native facility. Adopting
here makes it a prerequisite for building Nupp at all, and `bin/nupp` grows a
Cargo invocation and a `NUPP_NATIVE_LIBRARY` export, since the staged
`build/lib/nupp_native` is on neither path the generated loader tries. That is a
decision about what the project depends on rather than a cleanup, and it is what
F0 declined to take on its own authority.

The shell-out is still worth deleting and the reason has not changed.

**And under that sits a defect in how `ffi.C` is typed.** With the Cargo
prerequisite accepted, the launcher wired to build and name the provider, and
the bootstrap primed, the compiler still does not check itself:

```
src/nupp/compiler/ansi.nupp:131: error: NUPP2004: no field "_isatty" in
  {nuppBytesData: ..., nuppFilesList: ..., nuppFsSubmitRead: ..., ...}
```

`ffi.C`'s type comes from `cNamespaceType`, which calls
`cheader.declaredFunctions`, which walks **the running process's ctype table**
rather than the declarations the checked program made. The set therefore depends
on what has been `cdef`'d in the compiler's own process, and when. Loading the
file provider while listing sources moves it. Here the compiler's own
`_isatty`, which `ansi.nupp` declares and calls, was not in what came back.

The window is not the cause: `MAX_CTYPE_ID` is 8192 and the provider adds about
fifty symbols. What was *not* established is why the program's own declarations
dropped out, only that the set the checker believes in moved when the load order
did. That is the part to understand before changing anything.

The fix is to type `ffi.C` from what the program declared, which is what the
comment above `cNamespaceType` already claims it does. Until then a program that
declares its own C functions cannot also use an FFI-backed standard facility.
That is a limit worth knowing independently of this milestone.

So the first half is blocked on three things, and only the first was a decision:
the Cargo prerequisite (taken), the bootstrap regeneration (mechanical), and
this (a defect, and not one this milestone should fix on the way past).

**tecs is Teal, which this milestone did not account for.** "Swaps its imports"
assumed a Nupp consumer. `tecs.io.files` is `.tl`, and `nupp.io.files` is an
ambient global installed by a generated chunk rather than a module anything can
`require`. Reaching it from Teal needs at least:

- the `nupp` bootstrap chunk installed in tecs's runtime, so the global exists;
- a `.d.tl` describing the surface, since Teal cannot read a `.d.nupp`;
- `nupp_native` built with the `files` feature and loadable from tecs;
- `nupp/suspension.lua` staged, which for a Teal consumer nothing does; and
- tecs's `taskruntime` adapted to the `Suspension` handler interface.

The last is the interesting one and the rest is plumbing. None of it is an
import swap, and the `readLink`/`userFolder` string-versus-`Path` divergence
recorded under F0 sits on top of it.

Exit test, unchanged and unmet: tecs's own `files` tests pass against
`nupp.io.files`; tecs links no SDL asynchronous I/O; the compiler spawns no
process to read a directory.

## Test matrix

- immediate operations: each one, on each platform, plus the failure each has
  (missing path, permission, not a directory, cross-device rename)
- ownership: an undropped `File`, `DirectoryStream` and `TemporaryPath`; each
  discharged at scope exit, by transfer, and by explicit drop
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
  inside a generic `for` is allowed on this baseline, since the C `ipairs`
  iterator returns before the body runs. A suspending iterator is still a
  surprising thing to hand someone.
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

- **NUPP2602**: a `File`, `DirectoryStream` or `TemporaryPath` whose drop
  is not recorded.
- **NUPP2603**: a raw coroutine yield while one of them is live. A handled
  suspension in the same position is allowed, which is the S4 rule.
- **NUPP2701**: a file operation inside a `nosuspend` region or a tecs
  barrier.
- **NUPP2702**: a file operation across a C-call boundary.

## Next

- [plans/suspension.md](suspension.md): the effect, the handler, and the S5
  process library this shares a platform layer's worth of lessons with.
- [docs/io.md](../docs/io.md): the buffer, reader and writer contracts this
  namespace implements.
- [docs/ownership.md](../docs/ownership.md): `@owned`, lexical cleanup, and
  what a suspension may cross.
