# Wasm GC as the runtime

Date: 2026-10-11. The question: with the GC proposal in wasmtime (which
compiles through Cranelift) should the Nupp VM be Wasm, native through an
embedded wasmtime and the browser through the same bytes, deleting the
collector and the JIT from the plan? The workloads are the plan's untyped
proxies (fib, binary trees), their typed forms, an allocation-rate loop,
the host boundary, and suspension through the stack-switching proposal.
Hand-written `wat/` modules, harness in `src/main.rs`, wasmtime 48.0.5,
arm64 macOS, same loaded machine and hour as the prototype numbers beside
them. `wasm-gc-experiment [copying|drc|null]` selects the collector.

Three encodings: `untyped-boxed` is what an `any` costs with no tricks:
every value an `anyref`, every number a boxed `f64` struct, records
structs of `anyref`, a cast per operation. `untyped-i31` uses `i31ref`
for integers, which allocates nothing. `typed` is unboxed `f64` and typed
struct references, the typed tier.

| fib(30) | ms |
| --- | ---: |
| Wasm GC typed | 3.8 |
| LuaJIT trace | 3.1 |
| Wasm GC untyped, i31 | 8.3 |
| LuaJIT interpreter | 13.5 |
| Wasm GC untyped, boxed f64 | 15.4 |
| PUC Lua 5.5 | 19.6 |
| prototype interpreter | 44 |

| binary trees, depth 15, per tree of 65,535 nodes (200 trees) | ms |
| --- | ---: |
| Wasm GC typed | 0.25 |
| Wasm GC untyped, i31 | 0.36 |
| Wasm GC untyped, boxed f64 | 1.10 |
| LuaJIT trace | 2.0 |
| LuaJIT interpreter | 2.8 |
| prototype interpreter | 4.7 |
| PUC Lua 5.5 | 5.4 |

The untyped row's price in the plan is 2x PUC. Boxed-everything on Wasm GC
is inside it on both workloads, and on trees it is faster than LuaJIT's
trace. The reason is the collector: wasmtime's default is a copying
collector with bump allocation, and a short-lived object costs 1.7 ns
allocated and reclaimed (`alloc-drop`, fifty million objects, 1.2 GB
through the heap). The prototype's non-moving heap is 30 ns per object
after today's chunking, and that gap, not code quality, is the whole of
the trees result: both sides are Cranelift. wasmtime's other collectors
do not give this: deferred reference counting is 23 ns per object and
cannot collect cycles (trees 30 ms per tree), and the null collector does
not collect.

The host boundary is cheap: 2.5 ns for Wasm calling an imported Rust
function, 11.6 ns for Rust calling into Wasm. Module compile time is 1 to
4 ms for these modules.

What it does not give, as measured today:

- **Suspension.** The stack-switching proposal is in wasmtime 48 behind a
  feature but refused on this platform ("not supported on this compiler
  configuration", arm64). Without it a parked task has no stack to keep.
  The alternatives are the compiler lowering suspendable functions to
  state machines over heap frames (what Kotlin/Wasm does for coroutines),
  or an interpreter in Wasm for suspendable code, which is the browser
  row of the existing plan. Either way the 10 ns park of the prototype is
  not available by construction.
- **Tables, strings and metatables.** Not measured here. A Lua table is a
  struct over GC arrays with a hash the program computes itself; Wasm GC
  references have no identity hash, so every object that can be a key
  carries one. Strings are byte arrays with interning done in Wasm. The
  field-update proxy (`churn`) is the next thing to write.
- **Pointers into managed objects.** FFI passes copies through host
  functions; `@layout record` and `carray` live in linear memory, where
  bounds are guard pages and free, while GC arrays check every access
  with nothing to cite.

What it would delete from the plan if the rest holds: the collector and
its four modes, the allocator, the JIT and its stack maps, the compiled
cache (wasmtime serializes compiled modules), the separate browser tier,
and the bounds fragment of the verifier (Wasm validation replaces the
class checks). What it would add: a Wasm emitter from the typed bytecode
or the checked tree, a Lua object model over GC structs and arrays, and a
suspension lowering in the compiler.

## Second half: tables, strings, suspension

Same day. `wat/tables.wat` is a Lua table on Wasm GC: open addressing
over two GC arrays (keys as `eqref`, values as `anyref`), string keys
interned through a second open-addressed table so equality is `ref.eq`,
the hash carried in the string struct, growth at half load. Numbers stay
boxed `f64` structs. `wat/statemachine.wat` is suspension the way a
compiler would lower it without stack switching: a suspendable function
is a state machine over a heap frame, a park is a return, a resume a call;
one level, and three nested suspendable frames per park.

| 5M field updates by name (`churn`) | ms |
| --- | ---: |
| LuaJIT trace | 2.6 |
| PUC Lua 5.5 | 31 |
| LuaJIT interpreter | 31 |
| Wasm GC, copying collector, 256 MB initial heap | 49 |
| prototype interpreter | 51 |
| Wasm GC, copying collector, default heap | 84 |
| Wasm GC, null collector (no collection) | 42 |

The table itself is fine: the same loop with `i31` values and no
allocation is 5.2 ns per iteration against PUC's 6 for the whole
operation. What the default configuration pays is the collector, and the
isolation is clean: allocating a box and storing it into an existing
array costs 64 ns per store under the copying collector with the default
heap, 2.8 ns with a 256 MB initial heap, 3.3 ns under the null collector.
wasmtime's copying collector is a semispace without generations: every
collection copies the live set, so cost per allocation is the live set
divided by the space between collections, and the default heap is small.
The same shows in interning: finding an existing string among 100,000
costs 108 ns at the default size and 22 ns at 256 MB (LuaJIT's trace 39
to 46, PUC 120). Making new strings: 26 to 61 ns against PUC's 155 and
LuaJIT's 105.

| suspension, per park and resume | ns |
| --- | ---: |
| state machine, one frame | 0.9 |
| state machine, three nested frames | 3.9 |
| prototype runtime, heap frame stack switch | 10 |
| stack-switching proposal | refused on arm64 |

Where that leaves the gate:

- **Calls and records**: inside the price with margin (first half).
- **Tables**: inside the price only with the heap tuned (1.6x PUC at
  256 MB), outside it at the default (2.7x). The dependence is on
  wasmtime's collector policy, which its documentation says may change,
  and a non-generational semispace will always charge mutation-heavy code
  with a large live set. The compiler's own heap is that case.
- **Strings**: fine.
- **Suspension**: faster than the prototype's primitive, but only as a
  compiler lowering: every function that can park compiles to a state
  machine, so the checker has to know which can (an effect on the
  signature), or every function is compiled twice. Nothing on the native
  stack can be kept, which is the same constraint the plan already has
  for its own runtime, met a different way.
- **Not measured**: metatables and dynamic dispatch, `pcall` through the
  exceptions proposal, the vector family, the typed kernels (expected to
  tie), the browser.

## Third round: the scheduler, and a large live heap

Same day, after review. Two measurements the second half did not make:
suspension with a scheduler and many tasks resuming at their own frames,
rather than one generator yielding to a loop in the same call; and an
allocation-heavy workload beside a live heap of the size the compiler
keeps. Modes `sched` and `live`; the prototype gained `trees-live`.

**Scheduler.** `wat/sched.wat` is the prototype's park benchmark: 1,000
tasks, each parking 1,000 times from the innermost of three suspendable
frames, scheduled round-robin until all finish, each task resuming at its
own frame state. With the scheduler loop in Wasm it is 4.2 ns per park
and resume; with the host driving one `step` call per task it is 17.7,
of which the host-to-Wasm call is 11.6. The prototype's figure for the
same workload is 10 ns with its scheduler in Rust. So the state-machine
lowering stands at 4.2 against 10 when both schedulers are in their own
code, and loses when the scheduler sits across the boundary.

**Live heap.** `wat/liveheap.wat` builds two million records, each
holding two boxed numbers and an eight-byte array, about 250 MB of
objects, keeps them reachable, then runs the boxed untyped trees. The
prototype does the same with two million records holding a number and a
string. Each configuration in its own process so peak memory is its own.

| boxed trees, depth 15 x10, beside 2M live records | time | full collection | peak RSS |
| --- | ---: | ---: | ---: |
| Wasm GC, default heap, no live records | 11.2 ms | | 17 MB |
| Wasm GC, default heap, live | 292 ms | 53 ms | 521 MB |
| Wasm GC, 256 MB heap, live | 293 ms | 55 ms | 521 MB |
| Wasm GC, 1 GB heap, live | 9.4 ms | 81 ms | 799 MB |
| prototype, no live records | 43.6 ms | 2 ms | 53 MB |
| prototype, live | 42.9 ms | 37 ms | 838 MB |

This is the result that matters. wasmtime's copying collector copies the
whole live set at every collection, and sizes its heap by its own policy,
so an allocation-heavy loop beside a large live set runs 26x slower than
the same loop alone, until the heap is told to be four times the live set,
at which point the workload is fast again and the process holds 800 MB
for 250 MB of objects. The prototype's incremental mark-sweep is paced by
the live size and is unaffected: 43 ms either way, at the cost of fatter
objects (its records are 130-byte slots plus a boxed string). The
compiler is exactly the live-heap case, hundreds of megabytes of checked
trees and types kept across a run while every expression allocates.

What this does to the gate: the untyped row's pass in the first half was
a property of a small live set. On a runtime that does not control its
collector, the row is a function of wasmtime's heap policy, which its
documentation says may change. A generational collector in wasmtime would
change this; none is offered today. The suspension row is settled in
Wasm's favor as a lowering, provided the scheduler is in Wasm; the
checker's existing `suspends` inference supplies the fact the lowering
needs.
