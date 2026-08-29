---
title: Shared immutable byte regions
status: Implemented
created: 2026-08-24
---

## Summary

Share the bytes, not the value's declared type. Large worker payloads are
expensive because their byte storage is reproduced in every Lua state. This
proposes `sharedbytes.Region`, an explicit engine-owned immutable byte
region that crosses worker boundaries by reference, slices without copying,
and is read in place through a borrowed `span.Span<uint8>`. Converting a
region to a Lua string is one explicit call. Ordinary strings and records
keep their existing meanings, a record carries a region as an ordinary
field, and nothing silently changes representation.

## Goals

- Make crossing an existing region cost the same for one kilobyte and one
  gigabyte.
- Read region content in place: no Lua-heap copy and no C call per byte.
- Keep one bulk allocation per region, however many states, slices, and
  views refer to it.
- Make production without an intermediate Lua-heap copy possible when the
  producer writes into engine storage from the beginning.
- Compose with ordinary records as a leaf field rather than a new record
  representation.
- Keep the two collectors fully decoupled, while accounting the external
  bytes a state retains so unreachable handles do not hold storage
  indefinitely.

## Non-goals

- Sharing or projecting Lua values: no `shared(T)` wrapper, no shared-record
  proxy, no shared tables.
- Implicit conversion between `string` and `Region`, in either direction.
- Shared mutable memory, in any form.
- Arbitrary object graphs. A region is bytes; structure stays in ordinary
  values that may hold regions.

## Motivation

Every transfer path copies its payload, so payload size sets the latency
floor: on an Apple M1 in August 2026, a warm round trip cost about 3 us
plus roughly 100 us per mebibyte of payload, the copy passes a value makes
between two isolated heaps. Transport tuning cannot remove that term,
because it is not transport: it is the decision to reproduce the bytes in a
second heap.

The obvious answers fail for reasons worth recording. Stock LuaJIT stores a
string's bytes inline in the garbage-collected object it interns into one
state's heap, so using engine storage behind an ordinary `string` requires a
VM fork. That fork could preserve interning with a per-state header over the
external bytes, but every string consumer and the collector would have to
understand the second representation. Aliasing the sender's heap is workable
for strings, which are immutable and never move, but the receiver still needs
a handle type to hold foreign bytes, so it saves only one construction copy
while coupling reclamation across states.
Delivering a different representation than a signature promised, chosen by
a size heuristic, was rejected on the evidence of the serializer-only
transport experiment: a value that silently arrives as something other than
its declared type fails far from the send site, in another thread.

A reference-crossing value is therefore a distinct, explicit type. What
that type must additionally provide is a way to read the bytes without
reproducing them: if the only read is "convert to `string`", a payload
fanned out to eight lanes ends as the engine copy plus eight heap copies,
and the sharing bought transport cost only. The language already has the
right reading surface: a borrowed `span.Span<uint8>`, bounds-checked,
lifetime-tied to its owner, and compiled to direct loads.

Immutability is what keeps the rest small. A block that cannot change needs
no locks, no ownership rules, and no mutation protocol between threads; its
lifetime contract is a reference count.

## Overview and specification

### Region

A `sharedbytes.Region` is a sealed, copyable handle holding a
reference-counted engine block, an offset, and a length. It lives at
`nupp.mem.sharedbytes`, beside the span it lends and the other storage
primitives, rather than under `nupp.workers`: a region is storage, useful
in one state with no worker anywhere, and workers merely consume it. The
reverse placement would make every producer of bytes depend on the
scheduler. Its core surface is deliberately small:

```nupp
region:size(): integer
region:slice(first, last): sharedbytes.Region
region:view(first: integer?, last: integer?): span.Span<uint8> borrows (region)
region:text(): string
```

- `slice` is zero-copy: a new handle with narrowed bounds and one more
  reference to the same block. It is the owning counterpart of the span
  contract's borrowed `slice`, deliberately parallel in name and shape:
  a span slice cannot outlive its anchor or cross a lane, and a region
  slice exists precisely to do both.
- `view` is zero-copy: it answers the existing `span.ByteSpan`, whose one
  runtime representation is already an anchor plus a pointer, offset, and
  count; the region is the anchor, exactly as `span.fromString` anchors a
  Lua string. The borrow keeps the storage alive, bounds are checked at
  creation, reads lower to direct pointer loads, and slicing within a view
  is the span contract's own borrowed `slice`. Both bounds are optional and
  default to the whole region.
- `text` is the explicit escape hatch: it copies and interns the selected
  bytes into the current Lua state as an ordinary `string`.

Region equality is extent identity: two regions are equal when they name the
same engine block, offset, and length. Two separately constructed blocks with
equal bytes are not equal, while slicing a region back to its exact extent is.
The byte-codec fallback assigns one attachment index to each distinct source
handle, so repeated occurrences in one copied spine decode to the same local
handle rather than losing alias identity.

A region is unconditionally sendable. The signature walk refuses userdata
carriers in general and blesses exactly this one nominal type; nothing else
rides through the exception.

### Construction

```nupp
const sharedbytes = require("nupp.mem.sharedbytes")

const corpus = sharedbytes.copy(readWholeFile("corpus.txt"))
const loaded = sharedbytes.readFile("corpus.txt")

local builder = sharedbytes.builder()
builder:append(chunk)
const built = builder:freeze()
```

`copy` makes one visible construction copy from a string. `readFile` allocates
engine storage and reads the file directly into it, without an intermediate
Lua string. A builder is an affine accumulator; `freeze(takes self)` consumes
it and transfers its allocation into a region without copying. An ordinary
affine local gives a failed append its automatic cleanup and lets a successful
freeze move the builder, where a `with` binding would expose only a borrow and
could not be consumed.

### Producer writes

A producer that holds bytes only behind a pointer, a file read or a network
receive, writes into builder storage directly instead of materializing a
chunk string, through a reserve-and-commit pair around the same affine
checked writer `nupp.mem.heap` lends over an owned allocation:

```nupp
local builder = sharedbytes.builder()
local received = 0
with writer = builder:reserve(65536) do
    received = source:readInto(writer)
end
builder:commit(received)
```

- `reserve(count)` grows the builder's storage to hold `count` more bytes
  and lends a `span.Writable<uint8>` over exactly those bytes, past what is
  already committed. All growth happens inside `reserve`, before the writer
  exists, and while the writer lives the builder is exclusively borrowed,
  so `append`, `reserve`, `commit`, and `freeze` are compile errors under
  it. No operation that could move the storage can run while the writer is
  lent, which is what keeps the lent pointer stable for the whole borrow
  rather than invalidated by growth.
- Reserved bytes are uninitialized and not yet content. After the writer
  drops, one `commit(written)` closes the reservation and extends the
  builder's content by that many bytes, at most the reservation; a short
  read commits what arrived, and the surplus returns to capacity for the
  next reservation.
- A reservation stays open until a commit closes it, with zero if nothing
  arrived. Reserving again or freezing with one open raises, because
  silently dropping bytes a producer may have written would turn a
  forgotten commit into truncated content.
- `append(chunk)` remains the one-call form of the same cycle: reserve the
  chunk's length, copy, commit.

This separates two honest guarantees: crossing an existing region is always
O(1), and creation avoids an intermediate payload copy exactly when the
producer writes into engine storage from the beginning.

### Worked example

```nupp
const sharedbytes = require("nupp.mem.sharedbytes")
const workers = require("nupp.workers")
const jobs = require("jobs")

const corpus = sharedbytes.readFile("corpus.txt")

with scope = workers.scope() do
    local counts: {workers.Task<function(sharedbytes.Region, integer, integer): integer>} = {}
    const size = corpus:size()
    for shard = 1, 8 do
        const first = math.floor(size * (shard - 1) / 8) + 1
        const last = shard == 8 and size or math.floor(size * shard / 8)
        counts[shard] = scope:spawn(corpus, first, last, jobs.countRange)
    end
    local total = 0
    for shard = 1, 8 do
        total = total + counts[shard]:await()
    end
    return total
end
```

The worker reads the engine memory without constructing a Lua string:

```nupp
module jobs

const sharedbytes = require("nupp.mem.sharedbytes")

export function countRange(
    corpus: sharedbytes.Region,
    first: integer,
    last: integer
): integer
    const bytes = corpus:view(first, last)
    local count = 0
    for index = 1, #bytes do
        const byte = bytes[index]
        if byte == 0x0A then
            count = count + 1
        end
    end

    return count
end
```

Eight lanes scan one engine allocation. The file read filled that allocation
directly, and neither crossing nor reading reproduced its bytes.

### Records compose

There is no shared record type and no proxy. A record that carries a large
payload holds a region as an ordinary field:

```nupp
export record DocumentJob
    id: integer
    body: sharedbytes.Region
    first: integer
    last: integer
end
```

The small record shell copies normally, on whichever path its shape earns;
the region field is a leaf, retained by reference, so a record carrying one
travels on the validated copy with the region as a message attachment.
Composition avoids everything a shared-record projection would have needed:
a second incompatible interface over the record, interning hidden behind
field reads, record-method and identity questions, layout reinterpretation
after hot reload, and special rules for optional fields.

### Crossing and transport

A send retains one reference for the in-flight message; a receive transfers
that reference into the receiving state's handle. Queued messages own their
references independently, so cancellation and channel destruction release
them deterministically. On the native frames, the reference rides beside
the frame's fields. On the byte-codec fallback, the encoded spine carries a
handle index where each region sat while the frame retains the
corresponding blocks in order; decoding plants local handles at those
positions. The spine of a structure containing regions is still the
ordinary validated copy, and only the regions are leaves, so this costs one
shallow rewrite of the spine on encode and nothing per region byte.

### Lifetime and memory pressure

Each state's handle is a small full userdata whose finalizer releases its
block reference; whichever state drops the last reference frees the block,
on whatever thread that happens. No collector roots into, traces, or waits
for another state.

Because bulk allocations live outside the Lua heaps, a state can retain
gigabytes through handles its collector considers a few dozen bytes. The
engine therefore charges external bytes to each state, and the unit of
account is the block, once per state: a state is charged a block's full
size when it takes its first handle over that block and discharged when
its last one is finalized, however many handles and slices name the block
in between. Per handle would charge a gigabyte block once per slice; per
extent would understate, because the smallest slice pins its whole block.
Each state keeps a private live-handle count per block, touched only when
a handle is created or finalized, the two moments the engine already has
the block in hand.

The trigger is the charge itself, never a reachability guess about live
handles, which only a collection could answer. Charged bytes accrue as
collection debt the state pays with ordinary collector steps at its safe
points, exactly as its own heap allocation already paces its collector,
and a discharge credits the account. A state accumulating handles collects
sooner, its cycle finalizes the unreachable ones, and their discharges are
what settle the debt. The unit and the trigger are fixed here; only the
ratio of debt to collector work is tuning.

## Risks and assumptions

- **The savings begin above tens of kilobytes.** At 4 KiB, measured, the
  copies a region avoids cost less than its handle bookkeeping. Guidance
  has to say plainly that regions are for large payloads.
- **A small slice pins its whole block.** A slice holds a reference to the
  block it was cut from, so keeping one line of a gigabyte corpus keeps the
  gigabyte. Detaching costs an explicit copy, and nothing warns when it is
  needed.
- **Span borrows must not escape.** `view` leans entirely on the borrow
  checker to keep a span from outliving its region. That machinery exists
  and is load-bearing elsewhere; this adds a user-visible place where its
  failure would be memory-unsafe rather than merely wrong.
- **The checker blesses one nominal type.** The signature walk refuses
  userdata for good reasons, and `Region` asks for exactly one exception.
  The narrowness is the defense; a general mechanism here would weaken the
  boundary the walk exists to defend.
- **Pressure heuristics can misjudge.** Prompting a collector on external
  retention is a heuristic; too eager wastes cycles, too lazy strands
  memory. The contract is right, the tuning is a bet.
- **One author, one platform measured.** Every number behind this proposal
  is one Apple M1; the atomics, finalizer, and mapping paths are portable
  in design but unproven elsewhere.

## Alternatives considered

**A `shared(T)` modality with shared-record proxies**, the previous draft
of this proposal. Sharing was typed as a wrapper over the content type,
with records projected through a proxy answering fields from the block,
strings interned on first touch, and layout fingerprints deciding type
tests after reload. It measured well, but every difficulty was
self-inflicted by projecting an engine object as a second interface over a
Lua type: hidden interning behind field reads, `is` and method questions
with no good answers, reload rules to keep stale proxies from lying, and
special treatment of optional fields. Composition delivers the same
crossing costs with none of that surface, and the one thing the proxy had
that composition lacks, reading content without a heap copy, is provided
better by `view`.

**An intersection with the content type**, `string & shared`. An
intersection asserts the value truthfully offers both interfaces, so it
flows anywhere a `string` flows; but every string operation on it either
fails or hides a whole-payload copy. A coercive relationship priced at a
copy is not an intersection, and modeling it as one moves the cost cliff to
the least visible sites in the program.

**Transparent sharing above a size threshold.** The received representation
would depend on the payload's runtime size, so a function's behavior forks
at an invisible boundary, and the serializer-only transport experiment
already demonstrated what silently delivering a different shape does: the
failure surfaces in another thread, far from the cause.

**Aliasing the sender's heap.** Implementable for strings, because LuaJIT
strings are immutable and do not move: anchor the value in the sender's
state, pass the pointer, unanchor when the receiver's handle is collected
and its release message is pumped. The receiver still needs a handle type,
so all this saves over an engine-owned block is the one construction copy;
in exchange the sender's heap retains every aliased payload until it
happens to pump a release, an idle sender reclaims nothing, and closing a
state with outstanding aliases must either wait on every receiver or
invalidate them into use-after-free. The related direct-handoff experiment
retained with [NEP 18](0018-structured-worker-tasks.md)'s transport work
tested a narrower thing, a destination-side copy under short source
parking, and its single-digit gains against deadlock surface bound that
design, not this one.

**Forking LuaJIT for external strings.** Each state could intern a small
string header that references engine-owned bytes, preserving pointer equality
and ordinary table-key behavior while making the shared storage transparent
to source. That is a real advantage over `Region`, but it requires invasive
changes to the collector, string table, string library, C API paths, interpreter
and JIT, plus permanent maintenance of the fork. The explicit region keeps
stock LuaJIT and pays for that choice with an honest distinct type.

**A common `Bytes` interface** over both `string` and `Region`, for
read-only polymorphic code. Honest, since everything it could offer is
cheap on both, and deferred rather than rejected: the region's own surface
covers the known uses, and the interface can be added when duplication
appears without changing anything decided here.

## FAQ

**Why is there no way to get a `string` implicitly?** Because the copy is
the one cost sharing exists to make visible. `text` is short to type and
impossible to mistake for free.

**Why not let a region nest inside another region?** A block never
references a block, which keeps lifetime a plain count with no cycles.
Slices already provide nested extents over one block, and independent
payloads are independent regions.
