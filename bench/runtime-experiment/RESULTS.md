# Runtime prototype: collector, interpreter, tasks

Date: 2026-10-10. Nupp baseline `843af410a`. A throwaway Rust prototype of the
runtime pieces the code-generation experiment left out, built to answer: does
a precise incremental collector with an insertion barrier survive a mutator
that moves old objects around, do shaped records with enforced untyped writes
hold up under aliasing, does an interpreter with heap frame stacks park and
resume through nested calls, and roughly what does the untyped tier cost
against PUC Lua and LuaJIT's interpreter. Sources in `src/`, bars in `lua/`,
raw runs in `evidence/runs.tsv`.

## What was built

- NaN-boxed values with tags for nil, booleans, function ids and heap objects.
- Objects: interned strings, tables with array and hash parts, records with a
  shape whose slots carry declared types, numeric storage that spans borrow.
- A precise, incremental, non-moving tri-colour mark-sweep collector driven
  by allocation debt at safepoints (allocations and every 256th back-edge),
  with an insertion barrier on every heap store; objects allocated during a
  cycle are black; roots are rescanned once when the grey set empties. Three
  verification modes: stress, a whole cycle at every allocation; interleaved,
  one small marking step at every allocation with the oracle at every cycle
  end; quarantine, where freed objects are retained as tombstones so a
  use-after-free is an error instead of undefined behaviour. The oracle
  recomputes reachability from the roots and asserts every reachable object
  survived, and after an atomic cycle that nothing unreachable did.
- A register interpreter: untyped ops over values, typed ops over unboxed
  integer, float and two-lane vector registers, frames as heap records on a
  per-task frame stack, tasks that park on a key and resume where they
  stopped, `GETFIELD`/`SETFIELD` by name as the untyped path with the enforced
  write, `GETSLOT`/`SETSLOT` by offset as the typed path with no check.

## What it established

- **The collector is correct on what was thrown at it.** Binary trees and a
  string-keyed table under full stress with the oracle: 1,023 cycles, 7,162
  frees, no discrepancy. A mutator swapping 200 records between two
  root-reachable tables while hanging the old ones off fresh records, with
  one collector step per allocation: the barrier greyed 6,820 objects across
  50 rounds, every cycle end passed the safety oracle and every following
  atomic cycle the exact oracle, and the records' contents were intact
  afterwards. Two bugs were found by the oracle and fixed, both of the kind
  the plan said the oracle was for: objects allocated during a sweep in
  progress were white and got swept, and a sweep slice read past a shrinking
  object list.
- **Enforced writes work and cost only the untyped side.** A number written
  through an untyped alias into a `Num` slot is read back by the typed
  `GETSLOT`; a string written the same way is refused before it lands. The
  typed read carries no check.
- **Parking is a frame-stack switch.** A worker parks inside its loop three
  frames deep, the scheduler runs the others, and each resumes at its own pc;
  a million park-and-resume cycles across a thousand tasks take 9.9 ms, about
  10 ns each including the scheduler loop. No native stack is involved, which
  is the property the browser port relies on.
- **Allocation during interleaved marking is sound** by construction, and the
  cost of floating garbage is one cycle, as expected.

## Untyped tier cost, medians of five runs, thread CPU time

| Workload | prototype | PUC Lua 5.5 | LuaJIT interpreter | LuaJIT JIT |
| --- | ---: | ---: | ---: | ---: |
| fib(30), call-bound | 47.6 ms | 20.9 ms (0.44x) | 13.6 ms (0.29x) | 3.1 ms |
| binary trees, depth 15 x10, allocation and collection | 60.1 ms | 56.5 ms (0.94x) | 28.0 ms (0.47x) | 17.4 ms |
| 5M field updates by name on one table | 47.7 ms | 29.3 ms (0.61x) | 32.5 ms (0.68x) | 2.6 ms |

Against the plan's price of 2x PUC for the untyped corpus: trees and field
access are inside it, calls are not, at 2.3x. The call path pushes a frame
record and grows four register stacks per call; a frame layout with the
registers inline and a single stack would remove most of it. That is tuning
the plan expected, not a design finding. LuaJIT's interpreter remains 2-3x
ahead on everything, which the plan accepts for `.lua` files.

## Typed tier interpreted

map and dot over 65,539 elements, lane-wise vector ops in the interpreter:
178 us and 176 us per call, about 2.7 ns per element, against 6.3 us and
8.2 us compiled by Cranelift in the sibling experiment. The cold tier is
some 25x slower than the hot tier on vector loops, which is the ratio a
loop-header transfer has to hide; it is also faster than the LuaJIT trace
with the adapter was (12.1 us per call at best, interpreted at 10 ms).

## What it does not establish

No JIT frames or stack maps; no generational nursery; no strings beyond
interning; no closures or upvalues; no `any`-to-typed boundary beyond the
enforced write; one thread; one arm64 machine under other sessions' load.
The interpreter is a `match` over an enum with no threading of dispatch.
