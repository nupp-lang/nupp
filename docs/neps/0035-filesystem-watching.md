---
title: Filesystem watching in the standard library
status: Accepted
created: 2026-09-06
---

## Summary

Add `nupp.io.watch`, an owned filesystem watcher backed by the platform's
change-notification service, with polling as the fallback and a scheduled
reconciliation behind both. A watcher hands its consumer batches of settled
changes at the moments the consumer asks, never callbacks, and its idle cost is
independent of how many files it watches and how large they are. Hot reload
under `nupp run --watch` is the first consumer and moves off its scanning loop
in the same change; the language server and a future `build --watch` are the
next. TECS, which carried its own polling watcher, deletes it and gains nothing
to replace it with, because nothing in TECS called it.

## Goals

- One watcher, in the standard library, that every Nupp program with the
  filesystem can use: the compiler's own tools, a game engine's asset reload,
  a server reloading configuration.
- Idle cost that does not grow with the watched set. A watcher over ten
  thousand files that nobody is editing performs no stats, no directory
  listings and no content reads between scheduled reconciliations.
- A local save reaching the consumer within a second, on a laptop, with the
  benchmark watch set open.
- Delivery the consumer controls. A change is observed by the watcher on
  whatever thread the platform uses and delivered only when the consumer polls
  or waits, so a reload runs at the boundary the program declared.
- Changes that are what they claim to be. A half-written file, a save that
  produced the bytes already on disk, and a temporary that an editor renamed
  over the target are each reported as what happened, not as what a
  notification said.
- Nothing lost silently. A backend that overflowed, a subscription that
  became unusable, or a native setup that failed is reported, and the watcher
  falls back to a mode that still answers.
- Native interpreted and AOT execution on macOS, Linux and Windows, and a
  clear unavailable answer on browser backends.

## Non-goals

- Promising that a writer has finished. Settling reduces how often a partial
  save is observed; a consumer that needs a whole file still validates it.
- Delivering every intermediate state. Repeated writes to one path coalesce,
  and a change that changes back inside the settling window delivers nothing.
- Guaranteeing detection latency when the platform dropped a notification.
  Reconciliation catches what the backend missed, on its own schedule.
- Content classification. What a `.wgsl` file is for belongs to whoever
  registered it, not to the watcher.
- Watching through a network filesystem with the same guarantees as local
  storage. Forced polling is offered for filesystems that omit notifications.
- Building `build --watch` or the language server's own watching here. This
  proposal makes them possible and decides the interface they will use.

## Motivation

Nupp already had two watchers and needed a third.

The compiler's hot-reload loop under `nupp run --watch` computed a fingerprint
of every watched input on every poll, and its fingerprint was the file's whole
content. That is the correct comparison, because a save that rewrites identical
bytes must not prepare a generation, but it made an idle poll cost the sum of
every source file's size, every time the program reached a cooperative
boundary. It also never noticed a source file that was added, because the
project listing it consulted was computed once for the session.

TECS carried `tecs.watch`, a stat-polling watcher with a settling policy and a
bounded queue. Its design was sound for the hundred paths a game registers,
and its reasoning for polling over notifications was that a notification says a
write happened rather than that a writer finished, so a stat is needed either
way. That reasoning holds for the settle step and fails as a reason to poll:
polling stats every path on every interval whether or not anything happened,
while a notification names the paths that need the stat. The module also had no
caller. It dispatched to handlers keyed by content kind, which was an engine
concern wired into a generic facility, and the engine never registered one.

The language server relies on the editor to report changed files. An editor
that registers no watcher, or a client that is not an editor, leaves the server
believing whatever it last read.

Three consumers with the same need, each of which would otherwise bind a
notification service separately, is the case for one implementation beneath
the standard library. The question this proposal answers is where the
boundaries go: what runs in Rust, what the Nupp interface promises, and which
costs are paid when.

## Overview and specification

### Module and capability

`nupp.io.watch` is a standard-library module whose provider lives in the Rust
filesystem crate, reached through the same generational-handle ABI the file
and transfer resources use. It is its own provider feature, `watch`, which
implies `files`. It is not part of `filesystem`: that feature is what
`nupp.io.path` pulls in, and a program that only formats paths should not
carry a notification thread, an FSEvents dependency, or the framework that
dependency links. The feature is selected by requiring the module, the way
every native facility is, so no manifest key is added and the pinned
stage-zero compiler reads an unchanged manifest.

On a browser backend the module is unavailable under the same capability the
file module reports, so the diagnostic a program gets is the one it already
knows.

### The watcher value

```nupp
local watch = require("nupp.io.watch")

do
    local watcher = assert(watch.open({settleMs = 100}))
    assert(watcher:add("nupp.lua"))
    assert(watcher:addDirectory("src", {extensions = {"nupp"}}))
    while running do
        local batch = watcher:poll()
        if batch ~= nil then
            for _, change in ipairs(batch.changes) do
                reload(change.kind, change.path)
            end
            for _, notice in ipairs(batch.notices) do
                log:warn(notice)
            end
        end
        frame()
    end
end
```

A watcher is an owner. `open` answers one, or nil and a reason when the
filesystem refused, and the checker closes it at the end of its scope
whichever way the scope ends. `close` is explicit and deterministic: it
cancels outstanding work, releases every subscription, and makes the handle
stale, so a batch that a worker was assembling for it is dropped rather than
delivered to whatever the slot holds next. Path arguments are strings or path
values, a malformed argument raises at the call site, and an environmental
failure answers nil or false with a reason, which is the contract
`nupp.io.files` set.

`add` registers one file; `addDirectory` registers a tree, with options that
narrow it by extension and exclude subtrees. A file that does not exist yet is
still registered, because its creation is the event a consumer waiting for it
wants. `remove` forgets one registration; a change already delivered stays
delivered. `rescan` asks for reconciliation now, without blocking. Overlapping
registrations are one subscription underneath: a file inside a watched tree,
or two trees that share a root, count references and release when the last
registration goes.

### Delivery

`poll` answers a batch or nil, and never runs application code. A batch is a
list of changes, each a path exactly as it was registered or discovered
beneath a registered tree, with a kind of created, modified or deleted, and a
list of notices about the watcher itself: that the native backend was lost and
polling took over, that events overflowed and a reconciliation is pending, that
a reconciliation ran. The split between observing and delivering is the one
TECS drew and the one hot reload needs, because a reload replaces something
other code is reading and belongs at a point the program chose.

`next` is `poll` for a program that has nothing else to do. It suspends until
a batch is ready or a timeout elapses, registering a readiness source the way
a file transfer does, whose wait parks on the native watcher's condition rather
than sleeping a fixed interval. A watcher that only offered `poll` would make
every idle consumer choose a cadence and spin at it; the efficiency goal is
about the wake-ups as much as the work done in each.

A large result drains across batches of bounded size rather than arriving as
one, so a consumer's per-batch work stays bounded whatever a reconciliation
found.

### Settling and comparison

A notification starts a settling window for the paths it named, one hundred
milliseconds by default, and further writes to a path restart its window. When
the window closes the path is inspected: its metadata read, and by default its
content fingerprinted by streaming it through a hash off the VM thread. A
fingerprint equal to the one last delivered is not a change, which is what
keeps an editor's rewrite of identical bytes from preparing a hot generation.
Metadata-only comparison is an option for consumers that would rather be told
about every save.

An empty file is a change, and so is a deletion that stays deleted through the
window; the previous watchers treated both as saves in progress, which was a
guess that hid real states. A symbolic link is followed and its resolved target
is part of what is compared, so retargeting a link is a change to the link's
path, which is what a native artifact reached through a link needs.

Access events are never subscribed to, so the watcher's own reads cannot
notify it.

### Subscriptions, parents and identity

An explicit file is watched through its parent directory, because an atomic
save creates a new inode and renames it over the target, and a subscription on
the old inode sees nothing. A registration whose parent does not exist yet is
held on the nearest existing ancestor and re-descended when the path comes
into being, which is also how a subscription survives its directory being
deleted and recreated.

Subscription roots are canonicalized before they reach the backend, and events
are mapped back to the registered spelling. FSEvents reports resolved paths,
so a temporary directory under `/var` comes back under `/private/var`, and
Windows may report extended-length prefixes; a consumer comparing the path it
registered against the path it was handed must find them equal.

### Backends and fallback

The native backend is the `notify` crate: FSEvents on macOS, inotify on Linux,
and directory change notifications on Windows. Its callbacks run on threads the
VM never sees and do one thing, which is record bounded dirty state and
deadlines; inspection and fingerprinting run on a worker owned by the watcher,
not on the file lane's blocking pool, because a reconciliation of ten thousand
files sharing that pool's admission would starve ordinary reads for its
duration.

FSEvents needs CoreServices, which the static application link on macOS must
name alongside the frameworks it already links. The kqueue backend would avoid
that and was rejected: it holds one descriptor per watched path, which is the
opposite of the scaling goal.

On Windows the backend holds a handle on each watched directory, which
prevents that directory from being deleted or renamed while watched. A
consumer that replaces a whole tree on Windows observes it through the parent,
and a test that removes its temporary root closes the watcher first.

When native setup fails, or a subscription becomes unusable later, the watcher
switches to polling and says so in a notice. Polling checks metadata every
five hundred milliseconds; it is also what a caller forces for a filesystem
known to omit notifications.

### Reconciliation

Every thirty seconds a reconciliation begins: it walks the subscribed trees
for membership changes the backend missed and re-reads metadata for every
registration, incrementally, so its cost is spread rather than paid in one
poll. It does not read content. A file whose size and timestamp were both
restored after an edit is the case content reconciliation would catch, and
catching it costs reading every watched byte every cycle, which makes idle
cost proportional to the watched set's size and contradicts the goal this
proposal exists for. Content reconciliation is an option with its own interval
and a byte budget per cycle, for a consumer that has decided the case is worth
the reads.

An overflow from the backend, or a rescan flag it raises, sets a sticky
requirement that the next reconciliation start immediately and complete before
the requirement clears. Nothing about overflow is quiet.

### Physical representation

The watcher is a Rust value in the filesystem provider's resource arena beside
open files and transfers, addressed by a generational handle: a stale handle
answers the stale status, never a slot reused by another watcher. Dirty state
is an indexed set of paths with deadlines in a scheduled order, so a host poll
looks at what is due rather than walking every registration. Fingerprints and
subscription membership are cached in Rust; the Nupp side holds the handle and
the registered spellings.

A batch crosses the ABI as one length-delimited buffer through the existing
bytes-handle path, decoded into records on the Nupp side. The delivery queue
holds at most 1,024 distinct paths by default; a path already queued coalesces
into its entry, and a refused path is retained as dirty for the next batch.

The Nupp record carries the handle and a `drop` that is `nosuspend`, so
cleanup runs at scope exit under the ownership rules the file record already
follows, and `close` consumes the owner and answers whether the release
succeeded.

### Hot reload as the first consumer

The compiler's watch session opens one watcher over the project's configured
source roots, with the same exclusions the project listing applies, and adds
explicit registrations for every header, provider input and native artifact
the running generation depends on, updating those whenever a committed
generation changes the dependency set. Project membership comes from the
watcher's tree subscriptions, not from the cached listing, and a created or
deleted source is reported to the incremental compiler as such, which is what
refreshes its view of the project.

A poll at the cooperative boundary drains the watcher, reports every change in
the batch to the incremental compiler, and prepares once. The observed
filesystem baseline is the watcher's; the committed generation is the
session's; a rejected candidate leaves the last good generation running, and
diagnostics, compatibility checks, restart requirements and the separation of
code and asset transactions are unchanged by where the changes came from.

### Testing seam

The settling, coalescing, overflow and reconciliation state machine is a Rust
type driven by an injected event source and clock, tested there. The Nupp
tests drive real watchers over real temporary directories through the real
provider, interpreted and AOT, and cover what only a real backend shows:
atomic saves, empty files, deletion and recreation, symlink retargeting,
directory replacement, path spelling, forced polling, and close during pending
work. Efficiency is gated by operation counts: zero stats, listings and reads
across idle polls between reconciliations; an isolated edit inspecting only its
own candidates; a burst coalescing; queue memory bounded. Reconciliation cost
is reported separately from idle cost, with the hardware and storage recorded.

### Migration

Nupp lands first. TECS then moves its pinned compiler revision, deletes
`tecs.watch`, its manifest entry and its tests, and rewrites the README
paragraph that argued for polling. No alias is left, because no caller
existed to keep working. The generic cases of its test suite move into Nupp
against the watcher's interface, and the settle and queue cases move into the
Rust tests, since that is where the state machine now lives.

## Risks and assumptions

- **The bet is that notifications plus scheduled reconciliation detect what a
  developer does.** A dropped notification delays detection until the next
  reconciliation, up to thirty seconds. That is accepted; a consumer that
  cannot wait calls `rescan`.
- **Content fingerprinting by default reads every changed file in full.** For
  a game saving a large asset this is one read per save, which is the read the
  reload does anyway. It is not paid at idle.
- **A same-size edit with a restored timestamp is invisible without content
  reconciliation.** Tools that do this exist; a consumer facing one turns the
  option on and pays for it.
- **Backend behavior differs in ways a portable test cannot flatten.** Windows
  holding directory handles, FSEvents coalescing and resolving paths, inotify's
  per-directory watch limit. The design names each and the suite runs on all
  three, but a fourth difference will appear.
- **`notify` is a dependency with its own release cadence**, a third
  `windows-sys` in the lock, and platform crates beneath it. The offline vendor
  set grows accordingly.
- **The interface is decided before the second and third consumers exist.**
  If the language server needs something `poll` and `next` cannot express, the
  interface changes while it has one consumer, which is the cheap time.

## Alternatives considered

**Keep TECS's polling watcher and improve Nupp's loop separately.** Rejected:
two watchers with different settle policies, one of them in an engine with no
caller, and a third to come. The reasoning TECS recorded for polling was a
reason to stat after a notification, not a reason to stat without one.

**Callbacks from the notification thread into Lua.** Rejected. A callback
arrives on a thread the VM did not create, inside whatever the program was
doing, and a reload that replaces a resource mid-frame is the bug the
poll/dispatch split exists to prevent.

**`notify`'s own polling watcher with content comparison for everything.**
Rejected for the same reason as content reconciliation: it reads every file on
every interval, which is the cost being removed.

**Content reconciliation every thirty seconds by default.** Considered and
rejected in review. It catches one rare case at a cost proportional to the
watched set's size, which is the one property this proposal promises to hold.

**Attaching the provider to the `filesystem` feature.** Rejected: every path
formatter would carry the notification backend and, on macOS, its framework.

**The kqueue backend on macOS.** Rejected: one descriptor per path, which fails
at the ten-thousand-file benchmark, to avoid naming one framework in a link
line.

**Fingerprinting on the file lane's blocking pool.** Rejected: a reconciliation
would consume the lane's admission and stall unrelated reads.

**A thread per watched file.** Rejected without much discussion; it is the
scaling failure in its purest form.

**Settling in Nupp with an injected clock, as TECS did.** Rejected as the
production design, because the deadlines and dirty set have to live where the
notifications arrive. The injected clock survives as the Rust test seam.

**Leaving the language server to the editor's watcher.** Rejected as the only
option; it stays the preferred one when an editor offers it, and the native
watcher serves clients that do not.
