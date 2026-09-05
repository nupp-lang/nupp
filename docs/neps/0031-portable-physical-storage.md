---
title: Portable physical storage and ordinary I/O
status: Accepted
created: 2026-09-05
---

## Summary

Open the `cstorage` capability to a checked `representation.cstorage` backend for
Lua 5.1, with one ordinary public span family in `nupp.mem.span`. Share Nupp's I/O
algorithms over backend-lowered storage operations while preserving the rich
Reader, Writer, Buffer and lease contracts. This revises the prohibition on a
Lua 5.1 storage backend in [NEP 13](0013-dialects-and-capability-backends.md),
without opening arbitrary C interoperability or adopting its proposed `io.bytes`
whole-library substitution.

This is a decision to build that model. Target availability and supported uses
belong in the [portability documentation](../learn/projects/portability/libraries.md).

## Goals

- Let ordinary I/O and borrowed storage have one meaning across native and Wasm.
- Preserve direct native loads, bulk memory operations, and view elimination.
- Preserve zero-copy view construction and compiled/interpreted handoff.
- Make physical-storage support a complete, testable backend obligation.
- Reuse Wasm storage work without making its implementation a second public API.

## Non-goals

- Emulating arbitrary LuaJIT FFI, foreign libraries, or C function pointers.
- Providing services a browser host does not have, such as native sockets.
- Introducing a reduced Reader/Writer API, another top-level package, or changes
  to value-builder intrinsics.
- Requiring immediate physical deallocation for every borrowed-view drop.

## Motivation

A string-only portable reader makes an allocation choice part of an interface
that should also accept a caller's existing storage. Maintaining complete native
and browser I/O implementations avoids that choice locally but duplicates growth,
cursor, scalar, line, and transfer policy. Choosing storage representation below
those algorithms preserves both one interface and one policy implementation.

The decision to unify spans follows from their meaning: bounds, access permission
and an owner's lifetime are properties of a view, not of LuaJIT or Wasm. A backend
may need a different root and address representation without requiring an
application to name a different span type.

## Overview and specification

### Capability and module boundaries

`representation.cstorage` version 1 is a compile-selected representation contract.
It satisfies `cstorage` on Lua 5.1 only when the compiler and provider together
implement the complete admitted physical-storage operation set below. Native
LuaJIT retains its native capability and existing fast lowering; it does not
route ordinary native accesses through a dynamic provider.

`representation.structvalue` and storage must agree on descriptor identity,
field offsets, alignment and scalar representation. Backend resolution rejects
incompatible selections. Selecting storage does not grant `cinterop`. Foreign
symbol binding, arbitrary FFI calls, C callbacks, integer-address fabrication and
foreign pointer imports remain additional interoperation requirements.

The public names are `nupp.io` and `nupp.mem.span`. Internal storage operations
live under the existing runtime family and are inaccessible to applications.
`nupp.io.storage` retains its key/value host meaning. The representation contract
selects memory mechanisms; it does not replace the public I/O module.

### Values, arrays and bounded references

The accepted operation set includes zero-initialized dynamic and fixed arrays,
physical scalar and recursively admitted struct/fixed-array layouts, rooted
bounded references, element indexing, subranges, and bulk byte operations.
`carray(T, count)` retains its struct-type argument. Byte allocation in library
implementations uses private typed storage operations, not an expansion of the
public `carray` syntax or an untyped `any` escape.

The scalar storage set includes signed and unsigned 8-, 16-, 32- and 64-bit
integers, binary32, binary64, boolean, and the selected target's documented
`integer` layout. Exact 64-bit loads/stores exchange values through the existing
integer representation contract; converting through a Lua double is forbidden.
Narrow integer loads establish the language's fixed-width value refinements.

By-value layouts are finite and acyclic, with deterministic field order,
size/alignment and checked padding. Arrays of arrays and admitted structs use
those same descriptors. Target-specific layout is permitted; a native pointer
width or native layout fingerprint must never be reused for wasm32. Bitfields require target-layout bit extraction and masked stores, with signedness
and neighboring fields preserved. Storage references embedded in a struct require
traced owner roots and checked write barriers on Wasm, including struct copies
and fixed-array assignment. A physical offset alone cannot retain another
allocation. These are part of the complete storage obligation, even though an
AOT kernel profile may continue to admit only pointer-free layouts. Foreign
pointers, unions and foreign declarations require the separate interoperation
support that gives them meaning.

A `T*` or `T[?]` on the storage backend is a rooted bounded reference, preserving
its element representation, range and access permission. A native address is
one lowering. On Wasm, a handle retains its allocation and bounds; arithmetic
and projection cannot escape that allocation. A zero-length end reference is
valid but cannot be dereferenced. Negative, fractional, non-finite and overflowing
counts or offsets fail before allocation or mutation. Check products by division
before multiplying, and check ranges by subtraction before adding.

`unsafe` permits the documented representation boundary; it does not promise
that a Wasm handle can fabricate an arbitrary machine address. True foreign
address construction belongs to `cinterop`. The distinction permits ordinary
span signatures to retain typed references without granting a foreign ABI.

### One span contract

`nupp.mem.span` owns shared, fixed, writable and partitioned spans. Move the Wasm
implementation and its consumers to those nominal identities; remove ordinary
Span/WriteSpan/Writable identities from `nupp.wasm` when migration lands. Actual
Wasm host integration may remain in that module.

The existing operator, slice, shared-downgrade and split contracts are the common
surface. Preserve one-based inclusive slicing and the `first, first - 1` empty
range. `ref()` retains its typed pointer/count result and borrow relation. Its
Wasm lowering is an opaque bounded reference, not an `any` or a native C pointer.
Only a supported host adapter or compiled entry can project its physical address.

A caller writes the same source for either representation:

```nupp
local span = require("nupp.mem.span")
local indexed = require("nupp.mem.indexed")
local sample = {}

local struct Cell
    value: int32
end

function sample.sum(borrows source: span.Span<Cell>): number
    const values = source
    const rows = indexed.range(1, #values, values)
    local total = 0
    for index = rows.first, rows.last do
        total = total + values[index].value
    end
    return total
end

function sample.zeroed(): number
    const storage = carray(Cell, 4)
    const values = span.fromCarray(storage, 4)
    return sample.sum(values)
end

return sample
```

The example's proposed Wasm support depends on the new capability. It illustrates
the shared contract rather than introducing new syntax.

### Lowering and cost

A native admitted loop keeps its current rooted pointer, offset and extent and
emits direct physical field loads after the range proof. An admitted Wasm AOT
loop lowers the same proof to linear-memory loads with its wasm32 layout. Its
entry validates the region and roots it across the compiled call.

Interpreted Wasm operations use checked runtime memory operations and bulk paths.
Bulk movement is one operation, not a loop of Lua/JavaScript byte exchanges. View
metadata may materialize when it escapes; a nonescaping view can stay as compiler
values. Escape and optimization-level controls must preserve the checked answer.
Compiler view elimination and LuaJIT allocation sinking require separate evidence.

String borrowing roots immutable runtime string bytes and grants no write access.
If a representation cannot borrow a string, that operation is unsupported until
implemented: silently copying would violate `fromString`'s purpose. Explicit
materialization makes a Lua string and accounts for its bytes separately.

### Ownership, growth and leases

A view retains an owner; dropping the view ends access, not ownership of the
payload. A shared downgrade temporarily blocks conflicting writes. A writable
child blocks its parent; the audited split operation alone produces simultaneous
disjoint child permissions. These constraints survive generic, module and
compiled/interpreted boundaries, exceptions and suspension.

An allocation owns capacity, and a buffer separately tracks initialized logical
extent. Growth allocates compatible storage, preserves live bytes and initializes
newly exposed bytes before publishing them. Failure leaves the original buffer
usable. No invalidating resize or close may proceed while conflicting borrows or
foreign leases are live. Metadata-only slicing and ownership transfer do not copy
payloads. Byte copying is nonoverlapping or overlap-safe as explicitly specified
by the operation; existing overlap-safe memory movement must remain so.

Logical close and lease revocation are deterministic. GC-backed payloads can be
reclaimed later; explicitly allocated owners can release/reuse their capacity at
their terminal. A borrow does not acquire a new physical-deallocation obligation.
This respects the distinction between rooted views and the owning containers in
[NEP 22](0022-shared-immutable-byte-regions.md) and
[NEP 23](0023-transferable-owned-buffers.md).

A host lease retains the issuing VM/thread and the complete allocation root,
bounded byte extent and permission until completion, cancellation or teardown.
Revoked IDs cannot still yield addresses. Teardown releases roots before closing
the VM. An ID must not collide with another live lease after counter wraparound.
Writable and shared host access must be distinguished in the final storage
contract; a raw historical lease alone is not proof of write permission.

A Wasm linear-memory address remains associated with its rooted allocation.
JavaScript typed-array views over that memory have a separate lifetime: after
memory growth, resolve a fresh view from the live lease before use, including
after an asynchronous wait. Validate current memory extent before projection.
Memory-growth handling must preserve bytes and permissions, without staging a
second payload merely to preserve a stale JavaScript view.

### Ordinary I/O and ecosystem scope

Keep growth, cursor management, scalar encoding, lines and transfer policy in
shared Nupp modules. Reader/Writer retain their rich Buffer/span operations.
Native files, sockets, TLS, processes and HTTP retain specialized host paths.
Supported browser response bodies implement ordinary readers once their storage
requirements are available.

`http.Reader` remains the structural read/close upload-source subset. A lightweight
producer need not implement unrelated methods. A full ordinary reader should
satisfy that subset with the same close/affine obligation; migration must verify
that assignment rather than introducing a wrapper by default. Structural
ByteQueues likewise remain valid, with `string.buffer` providers selected through
`text.buffer` where used.

Every language operation admitted by cstorage is part of its conformance gate.
Heap/SoA allocators and cross-worker shared/transferred storage may need additional
host services. Their native contracts and optimizations remain intact, and the
checker must express any genuinely missing service before advertising those
modules on Wasm. A bytes-only provider cannot claim cstorage by relabeling its
missing language operations as interop.

## Risks and assumptions

- Full cstorage includes far more than bytes. Exact scalars, layouts, pointers,
  ownership and compilation must agree before the capability can be enabled.
- An abstraction can obscure alias information and regress native hot loops.
  Equivalent-boundary measurements, generated-code checks and copy accounting
  are required; aggregate speedups cannot hide an individual regression.
- A host transfer can require copying even when the language view does not.
  Claims of zero-copy must name the measured boundary.
- Existing Wasm representation support is useful reuse, not evidence of complete
  conformance. Identity migration must include compiled fixtures and carried
  resources, not only the library source.

## Alternatives considered

**A reduced portable reader and a richer native reader.** Rejected because the
storage allocation choice would become a permanent application-facing API split.

**Whole-library `io.bytes` substitution.** Rejected because it would preserve two
copies of ordinary I/O policy and hide the shared physical-storage problem.

**Permanent `nupp.wasm` spans.** Rejected because applications and compiler passes
would continue naming the backend in a concept whose meaning is portable.

**A complete portable FFI implementation.** Rejected because physical storage and
foreign ABI interoperability are different obligations; ordinary I/O needs the
former without granting the latter.
