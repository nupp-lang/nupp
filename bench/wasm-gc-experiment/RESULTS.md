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
cache (wasmtime serialises compiled modules), the separate browser tier,
and the bounds fragment of the verifier (Wasm validation replaces the
class checks). What it would add: a Wasm emitter from the typed bytecode
or the checked tree, a Lua object model over GC structs and arrays, and a
suspension lowering in the compiler.
