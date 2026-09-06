# Typed events benchmark

`nupp.events` against the Teal router it replaces, on the same work. Run from
the repository root:

```sh
bench/events/run.sh           # a table on standard output
bench/events/run.sh --json    # the same, followed by one JSON array
```

`run.sh` builds `bench/events/candidate.nupp` at `-O2`, the deliverable level,
into `build/bench/events`, and runs `bench/events/run.lua` with the pinned
LuaJIT from `scripts/toolchain luajit`. Nothing else has to be installed.

## What is measured

Each scenario is built twice, from the compiled Nupp candidate and from the
reference under `reference/`, and both sides do the same work: the same number
of observers at the same addresses, reading the same payload fields into a
checksum and counting their calls. The harness asserts the checksum and the
callback count equal between the two sides before it reports a row, so a
speedup from doing less is refused rather than reported.

| scenario | one operation is |
| --- | --- |
| `no-observers` | emit a one-field record at an address nothing observes, while one observer exists elsewhere, so the emission pays for both lookups rather than the registration-count short circuit |
| `observers-1`, `-4`, `-32` | emit a one-field record by type to that many observers at one address |
| `addresses-10000` | emit a one-field record by type, round-robin over ten thousand addresses with one observer each |
| `record-pool` | emit a five-field record by type with two defaulted fields and named arguments, to one observer reading every field |
| `struct-arena` | emit a three-field struct by type, to one observer |
| `deliver` | deliver an instance the caller built and mutates each time, to one observer |
| `nested` | emit a record by type whose observer emits a second record type at another address, to one observer each |
| `once` | register a once observer, then emit to it |
| `churn` | register a named observer at a fresh address and remove it again, without emitting: the entity spawn and despawn case, where the per-address map and list are made and returned |

Per row the report gives throughput over the timed operations, per-operation
latency at the 50th and 95th percentile, and KiB allocated over ten thousand
operations with the collector stopped. Latency is sampled in batches of a
thousand operations, because `os.clock` resolves to a microsecond and a single
emission is tens of nanoseconds; a percentile is over the per-batch means.

Following `bench/soa.md` and `bench/portable-storage-io`: every side is warmed
with twenty thousand operations before it is timed, the five runs of the two
sides are interleaved with the side that goes first alternating, and every
column is the median of the five. Allocation is measured on a separate pass
with the collector stopped, since `collectgarbage("count")` reports the heap
rather than a cumulative total and a delta with the collector running measures
what survived a collection. The pass runs the body once before reading its
baseline: a full collection shrinks the Lua stack, and the first delivery
afterwards grows it back through the protected call and the observer frames,
which the collector accounts as a kilobyte or two on the first operation and
never again.

`BENCH_EVENTS_OPERATIONS`, `BENCH_EVENTS_BATCH`, `BENCH_EVENTS_WARMUP` and
`BENCH_EVENTS_RUNS` change the sizes; the defaults are 200000, 1000, 20000 and
5.

## The reference

`reference/tecs/` is the Teal router at the revision before Tecs deleted it,
commit `3d14e7ab` (the parent of `d2b7664`, "Delete the Teal engine, its
specs, examples and benchmarks"): `src/tecs/events.tl`,
`src/tecs/internal/events.tl`, `src/tecs/utils/pool.tl`,
`src/tecs/internal/ffi/EpochArena.tl`, `src/tecs/internal/ffi/FFIEvents.tl`
and their dependency `src/tecs/internal/ffi/schema.tl`, each compiled to Lua by
the Teal compiler, `tl gen` 0.24.8, and committed as it came out. The logic is
the compiler's output, not a port.

Two adapters sit beside it. `reference/tecs/types.lua` stands in for
`src/tecs/types.tl`, which the router requires for its type aliases only and
which `tl gen` reduces to an empty table with two namespaces. `reference/router.lua`
defines the scenarios over the reference and carries one thing the router
itself did not have: emission by type. The Teal `MessageBus` delivers an
instance the caller holds; construction into a pooled table or an FFI arena row
lived in the Teal world, as `WorldImpl:emit` in `src/tecs/internal/world/init.tl`
at the same revision, so `router.lua` carries that method's body with the
world's event pool and FFI slice as its state. It leaves out the entity-id slot
unpacking, which is id layout rather than routing, and it clears the FFI slice
after every emission rather than once per frame, so the reference arena
rewinds where the candidate's does and the allocation column measures rows
rather than pages.

## Results

Apple M5 Pro, macOS 26.6, LuaJIT 2.1.1785763465 (the pinned toolchain build),
2026-09-06, default sizes, machine otherwise idle.

| scenario | side | ops/s | p50 ns | p95 ns | KiB/10k | candidate / reference |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| no-observers | candidate | 961,538,462 | 1.0 | 2.0 | 0.00 | 1.04x |
| | reference | 921,658,986 | 1.0 | 2.0 | 0.00 | |
| observers-1 | candidate | 8,034,387 | 127.0 | 134.0 | 0.00 | 0.19x |
| | reference | 41,675,349 | 23.0 | 25.0 | 0.00 | |
| observers-4 | candidate | 7,338,103 | 136.0 | 141.0 | 0.00 | 0.24x |
| | reference | 30,637,255 | 32.0 | 33.0 | 0.00 | |
| observers-32 | candidate | 4,883,409 | 186.0 | 247.0 | 0.00 | 0.44x |
| | reference | 10,983,580 | 64.0 | 146.0 | 0.00 | |
| addresses-10000 | candidate | 22,872,827 | 43.0 | 44.0 | 0.00 | 0.79x |
| | reference | 28,989,709 | 34.0 | 35.0 | 0.00 | |
| record-pool | candidate | 18,446,781 | 54.0 | 55.0 | 0.00 | 0.99x |
| | reference | 18,575,276 | 54.0 | 56.0 | 0.00 | |
| struct-arena | candidate | 6,960,395 | 142.0 | 148.0 | 0.00 | 0.16x |
| | reference | 43,544,524 | 22.0 | 24.0 | 0.00 | |
| deliver | candidate | 122,174,710 | 8.0 | 9.0 | 0.00 | 1.32x |
| | reference | 92,506,938 | 10.0 | 11.0 | 0.00 | |
| nested | candidate | 2,740,552 | 365.0 | 375.0 | 0.00 | 0.13x |
| | reference | 21,753,317 | 45.0 | 47.0 | 0.00 | |
| once | candidate | 3,869,595 | 243.0 | 327.0 | 1562.50 | 0.90x |
| | reference | 4,277,434 | 201.0 | 330.0 | 3125.00 | |
| churn | candidate | 31,012,560 | 32.0 | 33.0 | 0.00 | 0.87x |
| | reference | 35,542,918 | 28.0 | 29.0 | 0.00 | |

The `no-observers` row is a nanosecond on both sides because nothing in that
loop changes: LuaJIT hoists both lookups out of it. It says an unobserved
emission is invisible inside a traced loop, not what one costs from cold.

## Reading the numbers

`deliver`, which constructs nothing, is a third faster than the reference.
The rows that construct a one-field record or a struct by type and deliver it
at one address, `observers-1` through `observers-32`, `struct-arena` and
`nested`, are four to eight times slower than it; `addresses-10000` and
`record-pool`, which construct by type too, are within a quarter of the
reference only because the reference spends more per emission there itself.
`deliver` and `emit` differ in one thing: `emit` runs its initializer and
delivery under `pcall(construct, ...)`, where `construct` is a vararg function
forwarding the constructor arguments, and `deliver` runs
`pcall(deliverTo, ...)` with a fixed arity. LuaJIT cannot return from a vararg
frame into a `pcall` frame inside a trace, so `jit.v` reports every loop that
emits by type as `NYI: return to lower frame` at the end of `construct`, the
loop is never compiled as a root trace, and the emission runs interpreted,
with only what sits beneath it compiled: the observer loop when it has enough
observers to be hot, the callbacks, and a few return-traces. A loop that
protects a fixed-arity function traces; the same loop over a vararg one does
not, which a five-line probe reproduces without the bus.

The `once` row allocates 160 bytes per operation on the candidate: consuming a
once registration during delivery records the list for compaction in a fresh
`{list, address, eventId}` entry. The reference allocates twice that, a wrapper
closure per `observeOnce` and a deferred-unsubscribe record. Every other
candidate row allocates nothing per operation.
