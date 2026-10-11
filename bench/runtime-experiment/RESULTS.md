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

## The image pipeline: compiler IR to verified bytecode to both tiers

Date: 2026-10-10, same branch. The milestone after P2: take real Nupp source
through the existing compiler, verify the result, and run it on both tiers.
Sources: `src/ir.rs` (parser for `nupp aot --emit ir` text, 150 lines),
`src/lower_ir.rs` (lowering to the typed bytecode and the verifier, 450
lines), `src/jit.rs` (Cranelift lowering of the bytecode, 200 lines). Input:
`bench/codegen-experiment/nupp/kernels.ir`, the compiler's `native-ir 45`
listing for the integrated map and dot kernels, produced by `nupp aot --emit
ir` on the unmodified compiler.

What happened, in order:

- **The compiler's IR was consumed unchanged.** `lower.nupp`'s textual
  output has params with regions and ownership, entry relations, structured
  `while`/`if`/`let`/`set` statements, and call-shaped expressions over the
  species API. The parser is a page; the lowering maps each node to the
  bytecode's typed opcodes. For the kernel slice the open question is
  answered: port, not rewrite. The IR has no heap-value nodes beyond the
  builder bridge family, so the whole-language question stays open as the
  plan says.
- **The verifier rejected a real image for a real reason.** The map loop's
  condition proves `cursor + 4 <= #input`, but the body also stores to
  `output`. The only thing that makes that store safe is the entry check that
  the counts are equal, which the IR lists under `relations`. The bytecode
  had no instruction for it, so the verifier refused the store. The fix is
  the contract's: relations become `GUARDLENLE` instructions in the prologue
  that the interpreter and JIT enforce by trapping, and a fact on one span
  carries to another only through a guard chain the verifier can follow.
  Contracts 3.4 and 3.5 are amended accordingly.
- **The verifier rejects tampered images.** An overstated fact (`+8` where
  the condition proves `+4`) and an unchecked access with its fact removed
  are both refused, with the pc and the reason.
- **Both tiers agree with LLVM.** 67,817 checks at thirteen sizes, including
  0, 1, odd tails and 65,539, against a Rust reference and the LLVM NEON
  artifact: interpreter, Cranelift, and LLVM all within 1e-9 relative.
- **Lowering peepholes are where the compiled-code quality lives.** The
  first lowering compiled to 2.0x LLVM. The IR writes a span index as
  `int_to_f64(u32_add(cursor, 1))`, which round-trips through two float
  conversions per access; recognising it as the cursor register took map to
  1.6x. Assignments emitted as add-with-zero put an extra vector add on the
  accumulator chain; real moves took dot from 2.1x to 1.3x. Splats of
  uniforms inside the loop are hoisted to the prologue by the lowering,
  though Cranelift rematerialises them anyway. Fused multiply-add is
  emitted for add-of-mul, as the LLVM artifact does.

Nine processes, medians of nine rotated rounds each, this machine under
other sessions' load:

| Elements | compiled from IR / LLVM | interpreted / LLVM |
| ---: | ---: | ---: |
| 65,539 map | 1.57x | 40x |
| 65,539 dot | 1.40x | 32x |
| 1,024 map | 1.92x | 50x |
| 1,024 dot | 1.39x | 36x |
| 63 map | 2.87x | 61x |
| 63 dot | 2.03x | 60x |

Compile time 0.4-1.8 ms per function here, against 0.1-0.3 ms in the first
experiment, because this lowering emits every subexpression into its own
register and the Cranelift front end does the cleanup.

What the remaining gap is: the hand lowering of the same kernels reached
1.04x and 0.74x on the same backend. The compiled loop body here is 17
instructions where the hand one was 12; the extra five are two phi moves of
the span pointers at the loop header, the rematerialised splat, and the
32-bit mask of the cursor. None is the pipeline; all are the shape of what
the lowering hands Cranelift, and the second experiment showed what the
shape should be. Dot additionally has one accumulator because the source
has one; the reduction-unrolling rule is the generator's, not the
lowering's.

What this does not cover: SHA-256, whose IR is the builder-bridge entry
mode and needs the string and scratch nodes lowered; records, `any`, and
anything outside the admitted subset; the GC in the compiled tier (no stack
maps yet); loop-header transfer; x86-64.

## The whole-language slice: checked tree to image to runtime

Date: 2026-10-10, same branch. The chunk after the image milestone: a
bytecode emitter that walks the compiler's checked tree rather than the
kernel IR, for a bounded program, and the runtime pieces to run it.
Sources: `emit/emit.lua` (339 lines, run by `nupp run`, consuming
`compile.check`'s annotated tree), `emit/sample.nupp` (the program),
`src/image.rs` (the loader, 94 lines), and the untyped opcodes added to
`interp.rs`: string concatenation, length, negation, tag checks, dynamic
method dispatch through the shape's method table, and `pcall`.

The program: a `local record Point` with three typed fields and a method; a
function building a hundred points with `new` and named arguments and
string concatenation into a typed array; a loop summing a method call per
element; a function casting `any` to `Point` and reading a field; `pcall`
around it with a well-typed and an ill-typed value; a string-keyed table
written and read back; an `and`/`not` chain deciding the result.

What happened:

- **The checked tree carried everything the emitter needed.** Every
  expression node has `inferredType`: primitives by tag, arrays with their
  element, maps with key and value, records as `nominal` with a name and a
  `byname` field map, literals with a base, `any` as itself. Record
  declarations carry `resolvedType`. Slot order comes from the declaration's
  entries. The emitter did its own lexical scoping and resolved method calls
  statically when the receiver's type was a known record, dynamically
  through the shape's method table otherwise. Nothing had to be added to the
  checker.
- **`lower.nupp` is not where the whole-language lowering lives.** Its IR
  starts from admission and has no node for a record, a table, a string
  value, a closure, `any` or an error path. The slice's emitter is a sibling
  walking the checked tree; the kernel pipeline consumed `lower.nupp`'s
  output for the admitted subset. That is the second of the plan's two
  options, and it is now the answer: the whole-language lowering reads the
  checked tree, and calls into the kernel lowering for bodies the kernel
  admission accepts.
- **The oracle found a collector bug the earlier corpus could not.** Under
  interleaved marking, iteration eleven of the second run interned `"p11"`,
  hit the intern table, and received the previous run's `"p11"`: white,
  unreachable, and about to be swept. Registers carry no barrier, so the
  sweep freed a string a register held. The intern table is a weak table,
  and a weak table that hands out references needs a read barrier: while
  marking, a white hit is greyed; while sweeping, a white hit is already
  dead and is treated as a miss. Contracts 4.12. Stress mode could not see
  this because its cycles are atomic; the interleaved mode exists for it.
- **Enforced writes and the `any` boundary behave.** `value as Point` on a
  table raises inside `pcall`, which reports false; on a real point it
  passes and the typed slot read follows with no check.
- **Result and cost.** The expected 1,691,750 from every run, including
  under stress and interleaved collection with the oracle. The prototype
  interpreter runs `main` in 27.7 us; LuaJIT's interpreter runs the same
  program, compiled by the ordinary generator, in 8.6 us, and its JIT in
  5.2 us. The gap is the cold tier the plan accepts plus the emitter's naive
  register use, one move per operand, and `pcall` on a scratch task.

What this does not cover: closures and upvalues, varargs, multiple
returns, `for in`, string methods, metamethods, workers, and the typed tier
for anything in this program: `Point.length` runs on the untyped
interpreter although every operand is typed. Routing typed method bodies to
the typed register classes and Cranelift is the next emitter step, and the
first one where the two experiments meet.

## The tiers meet: typed bodies compiled, called from the interpreter

Date: 2026-10-11, same branch. The emitter now has register classes:
expressions of numeric type live in float registers, boxing only where a
value is required (a call argument, a table store, a return through the
value convention), unboxing where a number arrives as a value (a parameter,
a call result, an element read). Record slots declared numeric are read
and written unboxed (`GETSLOTF`/`SETSLOTF`). Numeric `for` loops run on
float registers with the compare flag driving the branch. `Point.length` is
now a pure float body; `total` mixes value registers for the array and the
receiver with float registers for the sum and the index.

The JIT lowers the value-class opcodes these bodies use through runtime
helpers, record slots by pointer, table reads and lengths by call, direct
calls between compiled functions, and the interpreter hands calls to
compiled entries through per-arity trampolines, the handoff in contracts
section 5. Compilation is attempted per function, callees first, and a
function with an unsupported opcode stays interpreted; the sample compiles
`Point.length` and `total` and interprets the rest.

| `hot`: 200 sums over 100 points | per call |
| --- | ---: |
| prototype, all interpreted | 954 us |
| prototype, `total` and `Point.length` compiled | 129 us, then 87 us with the slots pointer hoisted per receiver |
| LuaJIT interpreter, same source through the Lua generator | 358 us |
| LuaJIT trace compiler | 47 us |

Both collector verification modes pass with compiled frames in the call
chain, because nothing in these compiled bodies allocates; stack maps are
still absent and remain a P5 item.

Two findings on the way:

- **`as` is checked here and erased there.** With `bad = {x = "no"}`, the
  Lua backend's erased cast lets `p.x` return a string and `pcall` reports
  success; the new runtime's `TAGCHECK` refuses the cast. That is the
  intended semantics of contracts 1.2 and a real behavioural difference a
  migration will surface. The sample now uses a number, which both refuse.
- **Two whites.** The intern table's read barrier treated any white hit
  during sweeping as dead, but a sweep whitens survivors as it passes, so a
  live interned string looked dead, was re-interned as a second object, and
  a string-keyed table lookup then missed by identity. Objects now carry
  the epoch that last whitened them; a white object from an earlier cycle
  is dead, one from this cycle is a survivor. This is LuaJIT's two-white
  scheme, and contracts 4.12 is amended to require it.

The remaining gap to LuaJIT's trace on this path is lowering quality: an
array read is a helper call on a boxed index, the method call is a real
call, and nothing is inlined. Each is a known lowering item, not a design
limit.

## Closing the hot path: fixed headers, inline access, inlining

Date: 2026-10-11, same branch. The three shortcuts named above were taken
back in order, with the hot path re-timed after each (three runs, spread
under 5%):

| step | `hot` per call |
| --- | ---: |
| two typed functions compiled, helper call per slot and per element | 129 us |
| slots pointer hoisted per receiver within a block | 87 us |
| fixed object header: kind, payload pointer and length at known offsets; slot reads and array reads inline (kind check, integrality, bounds, load; helper on the slow path) | 62 us |
| Cranelift's inliner fed the callee's CLIF: `Point.length` inlined into `total` | 52 us |
| LuaJIT trace compiler, same source | 47 us |
| LuaJIT interpreter | 358 us |

The fixed header is the one change that touches the object model: every
object now begins with its kind, a mirrored pointer to its payload and the
payload's length, refreshed whenever the payload moves. Records and
storage never move theirs; a table's array part is refreshed on each push.
Compiled code masks the value's payload bits to the object pointer and
loads from there; the general case, a hash key or a non-table, falls to the
runtime helper. This is the shape the contracts assume for the real
runtime and the prototype had been faking with calls.

Cranelift 0.135's inliner takes a per-call decision and the callee's CLIF;
the JIT keeps the CLIF of every function it compiles and offers it for
direct calls. No typed calling convention exists yet: an inlined callee
still boxes its return and the caller unboxes it, which Cranelift's
optimiser folds only partly. That, the value-index box in the array read,
and the move chains the emitter leaves are what remains between 52 and the
roughly 10 us of actual work in this loop.

What this does and does not show. A two-tier runtime whose typed tier is
a non-speculative Cranelift lowering now matches a mature trace compiler
on a record-array loop, to within 10%, with three lowering items still
open. It does not show anything about collection under compiled
allocation (no stack maps), about closures, or about the untyped tier,
which is unchanged at 3x LuaJIT's interpreter.

## The typed calling convention

Date: 2026-10-11, same branch. Signatures are now part of the image: the
emitter reads the checker's signature type and classes each parameter as
float or value and the return as float when numeric. Float parameters are
the callee's first float registers and value parameters its first value
registers, in declaration order within each class; a float result returns
in the caller's float window. `CALLT` carries both windows. The
interpreter copies the float window on a call and delivers a float result
unboxed; compiled callers pass f64 in registers; the interpreter reaches a
compiled function through a generated boxed wrapper that unboxes on the
way in and boxes on the way out, so the handoff stays per-arity. Nothing
boxes between typed code any more.

The first run with it was slower, 52 to 59 us, and the compiled loop said
why: the JIT had computed storage pointer and length for every value
parameter in every prologue, and inlining `Point.length` put those two
helper calls into the loop per element. They are now emitted only in
functions that touch storage.

| `hot` per call | |
| --- | ---: |
| before the convention | 52 us |
| typed convention, prologue fixed (three runs) | 41, 42, 46 us |
| LuaJIT trace compiler | 47 us |

The compiled loop is 25 instructions per element: the inline array read
with its kind, integrality and bounds checks, two unboxed slot loads, three
float operations, and spills of the accumulator and the index across the
loop header, which Cranelift's variable-based SSA construction leaves in
when values cross many small blocks. The index is still boxed before the
array read because the emitter chose the value-index form; that and the
spills are what remain.

## The last two lowering items on the hot path

Date: 2026-10-11. The emitter now keeps a numeric index in a float
register through `GETIDXF`/`SETIDXF` instead of boxing it for the value
form, and the JIT marks the array read's slow path, the only call in the
loop, as a cold block.

| `hot` per call | |
| --- | ---: |
| typed convention | 41-46 us |
| unboxed index, cold slow path (three runs) | 38, 39, 45 us |
| LuaJIT trace compiler | 47 us |

The loop is now the inline array read, two unboxed slot loads, three float
operations, and two spills: the accumulator and the index are stored and
reloaded across the loop header because the slow path's call clobbers
every float register under AAPCS64, and the allocator keeps values that
are live across any call in the loop on the stack even when the call is
cold. That is the same tax LuaJIT pays around calls on this ABI, and the
way out is a slow path that does not look like a C call to the register
allocator, which is a later refinement, not a contract.
