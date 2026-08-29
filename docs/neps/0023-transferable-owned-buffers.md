---
title: Transferable owned buffers
status: Implemented
created: 2026-08-24
---

## Summary

An affine, engine-backed owned buffer moves between worker lanes in constant
time: the send consumes the sender's binding, checked where it is written,
and the receiver becomes the one owner of the same writable storage. This
completes a triad with existing transfers: the validated copy carries
arbitrary shapes, a [NEP 22](0022-shared-immutable-byte-regions.md) region
shares immutable bytes with any number of readers, and a move hands
exclusive mutable storage to exactly one. Nothing is shared and nothing is
copied; ownership changes lanes.

## Goals

- Hand a mutable buffer of any size to another lane at pointer cost.
- Make a fill, move, process, move back cycle allocate nothing in steady
  state, with the same storage shuttling between lanes.
- Free the storage deterministically where the last owner consumes it, on
  whichever lane that is, rather than when a collector notices.
- Make use after transfer a compile error at the send site.
- Reuse the message-attachment transport regions established.

## Non-goals

- Shared mutable memory. Exactly one lane can touch the buffer at any
  moment; that is the entire point.
- Moving Lua-heap values. [NEP 18](0018-structured-worker-tasks.md)'s
  refusal stands: a Lua table or closure cannot change heaps by reference,
  and this proposal only moves storage that lives in neither heap.
- Implicit copies as a fallback. A value that cannot move is refused where
  it is written, not silently copied.

## Motivation

Regions solved the immutable half of large payloads; the mutable half still
copies. A worker that fills a large buffer can only return its content by
reproducing it, at roughly 100 us per mebibyte per hop on the retained
benchmark's machine, and a pipeline that touches one working set in three
lanes pays that three times over while holding several copies alive at the
peak. Fan-in patterns, frame and image pipelines, network ingest, and
double-buffered simulation all have this shape: one large mutable working
set, one lane touching it at a time.

JavaScript's transferable `ArrayBuffer` is a decade of evidence that the
move is the right primitive for this shape, and also a demonstration of the
wrong enforcement: the sender's buffer is detached at runtime, so use after
transfer explodes far from the transfer, in whichever code touches the
husk. Nupp already has the right enforcement, because the affine layer
checks consumption where it is written. What NEP 18 lacked was a value that
could legally move: it refused affine owners wholesale, correctly, because
the affine values of its day lived in a Lua heap. Engine-backed owners
changed that. A [](nupp.mem.heap) array is already affine, already lives in
malloc storage outside both heaps, and already confines its pointer behind
checked span views; moving one is handing a pointer and consuming a
binding, and every ingredient except the crossing exists.

## Overview and specification

### What moves

An affine owner whose storage is engine-backed: [](nupp.mem.heap) arrays
first, and any later type the compiler knows to have the same property,
such as a region builder. The signature walk keeps refusing affine owners
whose representation lives in a Lua heap, with its existing message; the
allowance is the storage property, not affineness itself.

### Syntax and worked example

No new syntax. A worker parameter that takes ownership says so with
`takes`, which is what makes the spawn a move; an affine result moves
ownership back.

```nupp
module jobs

const heap = require("nupp.mem.heap")

export function fill(takes frame: heap.Array<uint8>, seed: integer): heap.Array<uint8>
    local writable = frame:write()
    for index = 1, #writable do
        writable[index] = ((seed + index) % 256) as uint8
    end
    drop writable

    return frame
end
```

```nupp
local frame = heap.allocate(ffi.typeof<uint8>(), 8 * 1024 * 1024)
with scope = workers.scope() do
    for generation = 1, 60 do
        frame = scope:spawn(frame, generation, jobs.fill):await()
        present(frame:read())
    end
end
```

Sixty generations move one eight-mebibyte allocation back and forth;
nothing is copied and nothing is allocated after the first line. Using
`frame` between the spawn and the await is a compile error, because the
spawn consumed it.

### Crossing

The frame carries the transfer as an attachment, like a region's, with
moved semantics instead of retained: the message owns the allocation from
send to receipt, so a message destroyed in a closed or cancelled queue
frees it, exactly once, and a received attachment constructs the receiving
lane's owner directly. The element type crosses as a layout tag the
receiver validates before constructing its owner; a tag the receiving lane
cannot honor fails the task rather than reinterpreting memory.

### Lifetime

Exactly one owner exists at any moment: a lane's binding, or an in-flight
message. The owner's end frees the storage wherever it happens, on
whichever thread that is. A lane that dies while owning moved buffers frees
them during teardown, the same way its queues already release region
references.

### Relation to regions

A moved buffer and a region compose at the seam the builder already
defined: filling storage exclusively and then sealing it. A lane can fill a
moved buffer and freeze it into a region when the content stops changing,
moving from the exclusive world into the shared one; there is no path back,
because a region's safety rests on immutability.

## Risks and assumptions

- **Layout fidelity across lanes.** The receiver rebuilds a typed owner
  from a layout tag, so the tag vocabulary bounds what can move: element
  types both lanes derive identically, primitives first. A richer
  vocabulary is future work, and an unhonorable tag must fail loudly.
- **Exactly-once free demands exactly-once accounting.** Every path a
  message can take, including cancellation, queue destruction, and lane
  death, must release owned storage exactly once. The region attachment
  paths are the template, but moved semantics make a double free or a leak
  a memory bug rather than a refcount off-by-one.
- **The allowance must stay narrow.** Admitting engine-backed affine
  owners through a walk that exists to refuse affine owners invites the
  next narrow exception. The storage property is the whole test, and it is
  compiler-known, not user-assertable.
- **The demand evidence is another language's.** JavaScript's decade of
  transferables shapes this design; no Nupp workload has yet asked for it.
  Building it ahead of demand is a bet that the shape recurs here.

## Alternatives considered

**Writable regions.** Extending NEP 22's region with a write surface would
reuse one type, and would demolish its foundation: concurrent readers are
safe because nothing mutates, and a lifetime that is a plain reference
count works because no reader needs exclusion. One writable aliased block
reintroduces every question immutability dissolved.

**Runtime detachment, as JavaScript enforces it.** Neutering the sender's
value at transfer catches misuse only when the husk is touched, far from
the transfer that caused it. The affine layer already reports the same
mistake at the send expression, at compile time.

**Copying, the status quo.** Correct and general, and its cost scales with
the payload on every hop while the peak holds every copy alive. The
mutable working sets this proposal serves are exactly the values that
cost makes pathological.

**Shared mutable memory with atomics.** Strictly more expressive and
strictly more dangerous, and rejected on the same grounds as in NEP 22:
data races become the programmer's problem. Exclusive ownership keeps the
race impossible rather than managed.

## FAQ

**Why is this not an extension of NEP 22?** One proposal records one
decision, and NEP 22's decision is accepted: immutable storage, shared by
reference count, safe for any number of readers. This proposal's decision
is the complement: mutable storage, owned exclusively, safe because there
is never a second reader. They share transport machinery and almost no
rules; welding them into one body would rewrite an accepted decision to
describe a different one.

**Why can a region not become a moved buffer?** The region's block may
have any number of references; exclusivity cannot be reconstructed from a
shared count. The one-way door from moved to frozen is the honest shape.
