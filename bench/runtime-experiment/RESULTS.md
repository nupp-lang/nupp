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

## The collector under compiled allocation

Date: 2026-10-11. Compiled code now allocates: `NEWRECORD`, `NEWTABLE`,
`SETSLOT`, `SETIDX`, `SETIDXF` and `CONCAT` lower to runtime helpers that
allocate through the same heap and barrier as the interpreter. Every value
register is a Cranelift stack-map variable, so at each call the live ones
are spilled to the frame and described by a map keyed by the return
address, with the frame's active span. A helper entered from compiled code
records its frame pointer; the root set then walks the frame-pointer chain,
and for each return address inside compiled code reads the live slots from
the caller's frame at frame pointer minus span plus offset. Frame pointers
are preserved in compiled code for this. Contracts 4.4 and 4.5 as written.

`hot` compiles whole now, allocation loop included, and runs as compiled
code from its first instruction.

| | stress + oracle | interleaved + oracle | `hot` |
| --- | --- | --- | ---: |
| with stack maps | pass, 476 cycles | pass | 35.5 us |
| without stack maps | the table in a compiled register is freed under it; `index of a non-table` | | |

Two mistakes on the way, both in reading the frame, neither in Cranelift:
the first walk paired a return address with the callee's frame pointer
instead of the caller's and read text addresses as roots; and a helper
that did not record its frame pointer would have hidden every frame above
it. The negative control is kept as a mode so the test stays honest.

What this leaves for the product: the walker is a linear search over
code ranges and maps, fine for a prototype, a sorted table for a runtime;
the context pointer is a global here and a parameter there; and the
interpreter does not yet poll at back-edges in compiled code, since
nothing here runs long enough to need it.

## Closures, and the untyped call path

Date: 2026-10-11. Closures: a local any nested function captures lives in a
heap cell from its declaration, closures capture cells, and reads and
writes go through them, so the enclosing scope and every closure share one
location with no open-upvalue bookkeeping. Closure and cell objects are
scanned. `emit/closures.nupp` exercises shared counters, a closure in a
table per loop iteration, and a captured parameter; it returns the expected
value under every collector mode. The prototype interpreter runs it in
48 us per call against LuaJIT's interpreter at 13 us and its trace at 1.2.

The untyped call path, the one hypothesis row outside its price, was then
worked on and first got worse. A bisect against the two earlier commits
found the interpreter 20% slower than the first prototype before any of
today's changes, and the cause was a single line: the per-instruction
trace check added for debugging, a load and a branch on every dispatch
that also kept the hot loop from holding its state in registers. It is now
a compile-time feature. Two more changes: the heavy opcode handlers are
outlined into non-inlined functions so the dispatch loop stays small, and
returns no longer clear the popped window, because the root set marks a
task's registers only up to its live top, as Lua's collector does.

| medians of three | prototype | PUC Lua 5.5 | ratio |
| --- | ---: | ---: | ---: |
| fib(30) | 42.8 ms | 19.5 ms | 2.2x |
| 5M field updates by name | 46.7 ms | 27.1 ms | 1.7x |
| binary trees | 57.4 ms | 52.4 ms | 1.1x |

fib remains outside the 2x price. What is left per call is structural to
this prototype: four register stacks grown separately, a frame record
pushed and popped, and the dispatch loop re-entered on both the call and
the return. A frame layout with the registers inline and a single stack
is the P3 design, not a tweak to this one.

## Loop-header transfer

Date: 2026-10-11. The interpreter counts back-edges per (function, loop
header). Past a threshold it asks the JIT for a header entry: the same
function compiled with a prologue that loads every value, float and
integer register from the interpreter's windows and jumps to the header's
block. The activation finishes in compiled code and returns its boxed
result; the interpreter pops the frame as if the function had returned.
There is no transfer out, as contracts 5.3 says. Callees the loop body
calls are compiled first so the entry can call them directly; a body
calling something the JIT cannot lower stays interpreted, which is what
happened to `main` because `describe` reads a string slot the JIT does not
handle yet.

In a mode where nothing is precompiled, `total` and `hot` transfer at
their first loop headers after fifty back-edges:

| `hot` per call | |
| --- | ---: |
| interpreted throughout | 538 us |
| transfer only, entered interpreted | 37.3 us |
| precompiled, entered compiled | 37.3 us |

The transferred activation allocates in compiled code with stack maps
live, and the stress and interleaved runs pass with transfers happening
inside them.

## Handlers in Nupp, and a jump-table switch

Date: 2026-10-11. The question: could the interpreter be written in Nupp
instead of Rust, would it be faster, and does having the opcode handlers in
Nupp make a JIT easier. Sources: `emit/handlers.nupp` (three handlers, an
interpreter loop, a program), `src/main.rs` `handlers_mode` and `template`,
the `Switch` opcode in `interp.rs`, `jit.rs` and `image.rs`, and `switch`,
`do` and `yield` in `emit/emit.lua`. Reference: `lua/sum.lua`.

The subject is one untyped register program, `sum(n)`: `i = 0; s = 0;
while i < n do s = s + i; i = i + 1 end`, five instructions per iteration.
It is run five ways, all agreeing on the result:

- **rust-interp**: the prototype's Rust interpreter, the subject as its
  own `Op` list.
- **nupp-interp-cranelift**: an interpreter written in Nupp (`run` in
  `handlers.nupp`: a flat code array, an `any` register array, dispatch by
  `switch`), compiled through the image pipeline to Cranelift, running the
  same program encoded as data.
- **handlers-inlined**: a template JIT. Each dynamic opcode of the subject
  becomes a typed call to its Nupp handler (`addAny`, `subAny`, `ltAny`);
  the JIT inlines the handler bodies, so the compiled function is the
  handlers stitched in program order with the subject's registers as SSA
  values.
- **direct-lowering**: the subject compiled by the JIT's own hand-written
  lowering of `Add`, `Lt` and the branches, added for this comparison.
- **nupp-interp-on-rust-interp**: the Nupp interpreter interpreted, for
  the record only.

| per iteration, medians of nine rotated rounds, n = 1,000,000 | |
| --- | ---: |
| LuaJIT trace | 1.11 ns |
| PUC Lua 5.5 | 3.09 ns |
| direct-lowering | 3.46 ns |
| handlers-inlined | 3.48 ns |
| rust-interp | 4.18 ns |
| LuaJIT interpreter | 5.02 ns |
| nupp-interp-cranelift, jump table | 26.1 ns |
| nupp-interp-cranelift, equality chain | 34.7 ns |
| nupp-interp-on-rust-interp | 230 ns |

What it says:

- **Handler inlining produces the hand-written lowering.** The template
  and the direct lowering are the same code within noise, because the
  inlined handler bodies are the same tag checks, unboxes and float ops the
  lowering emits by hand. One definition of each opcode's semantics, in
  Nupp, serves the interpreter and the JIT. That was the claim to test, and
  it holds.
- **A baseline JIT from handlers does not beat the interpreter on this
  loop.** Both compiled forms sit at the interpreter's speed because the
  loop-carried values stay boxed: each iteration moves `s` and `i` from
  integer to float registers and back, with tag checks and a NaN
  canonicalisation on each move, a chain of about ten cycles per value.
  The interpreter pays the same boxing and its five-way dispatch is
  predicted perfectly, so removing dispatch removes little. Turning off the
  stack-map spills (`NO_STACKMAPS`) and the canonicalisation (`NO_CANON`)
  moved nothing: 3.0 to 3.5 ns either way. What LuaJIT's trace does
  differently is keep `s` and `i` unboxed in float registers across the
  back-edge, which is type speculation. For typed Nupp the typed tier does
  the same without speculating; for `.lua` and `any` code nothing short of
  speculation reaches it, and that is a JIT design question independent of
  which language the handlers are written in.
- **The interpreter in Nupp is 6x slower than the one in Rust, and the
  cause is the lowering, not the language.** Its loop disassembles to 895
  instructions with 130 loads, 19 float-to-int and 18 int-to-float
  conversions: the emitter types `integer` locals as floats, so `code[pc]`
  and every register access converts the index, checks the table kind and
  the bounds, and loads through the header. A Rust interpreter reads
  `*code.add(pc)`. The typed tier that would close this (int64 registers,
  storage arrays with verified bounds) is what the kernel experiment
  already showed matching LLVM; it is not in this emitter. So the answer to
  "faster" is: not shown, and not expected to exceed Rust; the answer to
  "possible" is yes, as a program on the Rust core with its subject values
  as host values, once the typed lowering covers what an interpreter uses.
- **The jump-table switch is worth 25% on an eight-way dispatch** against
  the equality chain in source order (26.1 against 34.7 ns), with the hot
  cases three to five compares deep in the chain. `Switch` is one opcode:
  an integer register and a table of offsets with a default; the JIT lowers
  it to `br_table` with negative and oversized indexes clamped onto the
  default. The emitter takes a switch whose cases are all small
  non-negative integer literals to it, and anything else to the chain.

Two lowering items were added on the way and stay: a comparison remembers
its i8 condition so a branch on the boxed boolean tests the comparison
directly (`cond_of`), and an array-part store of a non-object value is
inline, since no barrier is due for a number. Dynamic `Add`, `Sub`, `Mul`,
`Lt`, `Le`, `Eq` and `TagCheckNum` now lower, with the non-number path in
a cold block calling the runtime.

### Making the Nupp interpreter faster

Same day. Two changes to the emitter and the runtime, and one measurement
flag, to see how much of the 6x was the lowering.

**Integer registers.** `integer`-typed locals and integral literals now
live in the integer class: `IK`, `IAdd`, `ISub`, signed compares, `IUnbox`
from a boxed number, and `GETIDXI`/`SETIDXI`, table access by an integer
register with no float round trip. The switch selector is used directly.
The loop went from 26.1 to 18.9 ns per iteration (the register file is
also allocated at its full size now, as an interpreter's would be; the
earlier version grew it through the push path on the first write).

**Unchecked table access**, `UNCHECKED_TABLES=1`: `GETIDXI`/`SETIDXI`
lowered as a statically typed array with a proven bound would be, a load
of the array pointer and the element, no kind or bounds check. This is a
measurement of the floor, not a mode: a `{integer}` parameter cannot be
anything but a table under contracts 2, and a fixed-size storage body
gives the verifier the bound, so a typed interpreter written against
storage arrays gets this code legitimately. The prototype emitter has no
storage arrays, so the flag stands in.

| nupp-interp-cranelift, per iteration | jump table | equality chain |
| --- | ---: | ---: |
| float-typed emitter (above) | 26.1 ns | 34.7 ns |
| integer registers | 18.9 ns | 29.8 ns |
| integer registers, unchecked tables | 7.4 ns | 16.8 ns |
| the same without stack-map spills | 7.1 ns | |
| Rust interpreter | 4.3 ns | |

So the interpreter written in Nupp lands at 1.7x the Rust one once the
typed tier gives it what it has for kernels, from 6x under the float
emitter. The loop body is 259 instructions in that form, down from 895.
What remains: 19 float-to-int conversions, because `{integer}` elements
are boxed doubles and an integer storage would make them plain loads; 26
GPR-to-FPR moves from boxing handler results; the array pointer reloaded
per access, which storage, being unresizable, lets the lowering hoist. Each
is a typed-tier item already on the plan, none is interpreter-specific. The
jump table is worth 2.3x over the chain at the floor, where dispatch is a
larger share.

## Base64 from the compiler's IR

Date: 2026-10-11. The first of the P0 record's owed scalar baselines.
`nupp aot --emit ir src/nupp/codec/base64.nupp` (`evidence/base64.ir`,
the shipped word-at-a-time encoder, unmodified) is parsed, lowered to the
typed bytecode, verified, interpreted and compiled by Cranelift. Mode:
`runtime-experiment base64 evidence/base64.ir <base64.nupp>`.

What the IR needed that the kernel slice did not: byte buffers as an
object body (`Bytes`, the builder's scratch), checked byte and
little-endian word loads and stores on strings and buffers, shifts, or,
byte swap, equality, a value-class return, `elseif`, store statements, a
builder that finishes into a string, constant-pool strings bound to the
IR's `konst_N` names, and the `nupp.math.u32` helpers the IR lists
without bodies, lowered by name. The lowering also had to reclaim scalar
temporaries per statement: the encoder's expression trees ran the
prototype's 8-bit operands past 255 and wrapped silently.

Checked against a reference over every length 0 to 200 and at 1 KiB, 64
KiB and 1 MiB, on both tiers; then under collector stress with the oracle
and interleaved, since the compiled encoder allocates its scratch and its
result with value registers live: 420 checks.

**Bounds checks were the cost, and one proof removed it.** With every
byte access checked the compiled encoder ran at 0.852, 0.546 and 0.520 ns
per input byte at the three sizes. The sixteen alphabet lookups per
twelve input bytes index a constant-pool string of length 64 by a value
masked with 63. The lowering now emits those unchecked and the verifier
re-derives the proof from the bytecode (constant-pool object, mask
constant below the constant's length, neither register redefined;
contracts 3.4b; a tampered mask of 64 is rejected). With that, the
remaining fourteen checked word reads and stores per iteration cost
nothing measurable (`UNCHECKED_BYTES=1` moves nothing), and neither does
allocating the scratch per call (`REUSE_SCRATCH=1`).

| ns per input byte | 1 KiB | 64 KiB | 1 MiB |
| --- | ---: | ---: | ---: |
| Cranelift, every access checked | 0.852 | 0.546 | 0.520 |
| Cranelift, alphabet lookups proven | 0.521 | 0.392 | 0.387 |
| LLVM, the same source, repository harness today (`const`) | 0.828 | 0.473 | 0.485 |
| LLVM, the same source, as recorded in `bench/base64/results` | 0.742 | 0.352 | 0.353 |
| C scalar, as recorded there | 0.592 | 0.260 | 0.251 |
| interpreter | 18.0 | 12.9 | |

Against the harness run today, on the same loaded machine
(`evidence/base64-harness-2026-10-11.txt`), the Cranelift encoder is at
0.63x, 0.83x and 0.80x of the LLVM entry's time; against the quieter
recorded figures it is 0.70x, 1.11x and 1.10x. The two harnesses differ
(thread CPU time and rotated rounds here, `os.clock` around the LuaJIT
call there, which includes the FFI boundary and the Lua string build), so
the honest statement is: inside the 1.3x price either way, and the
difference between the two LLVM columns is the machine, not the code. What
is left in the loop is the `u32` masking after each add and shift, which
32-bit integer registers would remove, and the per-iteration reload of
the two buffers' pointers and lengths at the loop header.

## Path normalisation from the compiler's IR

Date: 2026-10-11. The second owed scalar baseline, and the first kernel
whose cost is the runtime rather than the loop. `nupp aot --emit ir
src/nupp/io/path/pathtext.nupp` (`evidence/pathtext.ir`, the shipped
normaliser, unmodified) lowers, verifies and runs on both tiers. Mode:
`runtime-experiment paths evidence/pathtext.ir evidence/paths-corpus.tsv`.
The corpus is 777 paths, POSIX and Windows, generated by
`paths/corpus.lua` with the shipped implementation's answers beside them,
verbatim `\\?\` paths excluded because the wrapper answers those before
the kernel runs. 1,596 checks on both tiers, then under stress and
interleaved collection.

What the IR needed beyond Base64: a numeric `for`, `break`, string
buffers with append and finish, substrings (an appended substring copies
straight from the source), table index reads and stores by a float index,
bare string literals, boolean uniforms, and Lua's `and`/`or`. That last one
was a correctness bug: the lowering evaluated both operands, and `"./a"`
read byte 4 of a 3-byte string inside a conjunction whose left side was
already false. Operands that can trap or touch memory now short-circuit;
pure operands stay eager so the loop facts the verifier reads remain single
instructions. Comparisons also now land in integer registers whichever
class they compare; a float compare's result had been numbered as a float
register and overflowed the integer table.

| per call, 10.6 input bytes on average | |
| --- | ---: |
| LuaJIT, the Lua source traced (`luajit`) | 0.092 us |
| LLVM, the `@aot` entry through the builder (`llvm-aot`) | 0.149 us |
| Cranelift from the IR | 0.243 us |
| LuaJIT interpreter | 0.751 us |
| prototype interpreter | 0.806 us |

Harness runs: `paths/run.sh` (`evidence/paths-harness-2026-10-11.txt`),
same machine, same hour.

**The gap is allocation, not code.** A call allocates a component table,
a string buffer and the result string; on the prototype heap those three
cost 89 ns on their own (`alloc probe`), a third of the call, before the
table's growth or any of the work. Each object is a `Box` plus a push onto
the heap's object list, about 30 ns; LuaJIT's whole call, allocations
included, is 92 ns. LLVM's entry is slower than LuaJIT here too, at 1.6x,
for the same reason in a different place: the builder and the FFI
boundary. The design item this adds to P3 is the allocator: a size-class
or bump allocator with the sweep walking segments rather than a vector of
boxes, at the 5 to 10 ns per object that would put this call at LLVM's
level. Pre-sizing the buffer and moving its bytes into the result string
without a copy, both done, moved nothing measurable against that.

Against the hypothesis row this is a miss as measured: 1.6x LLVM and 2.6x
LuaJIT's trace on a workload the row did not foresee as allocation-bound.
It stands as a decision on the allocator rather than a decision against
the plan: the loop itself is the same code as the other two kernels'.

## Chunked object allocation

Date: 2026-10-11, following the path finding. Objects were a `Box` each
plus a push onto a heap-wide vector the sweep walked and compacted. They
are now slots in 1,024-object chunks that never move: allocation pops a
free list or bumps into the newest chunk, the sweep walks slots in order,
and a freed slot's body is dropped in place and the slot goes on the free
list. Two collector rules followed from it, both caught by the oracle on
the first run. A slot reused behind the sweep's position is not whitened
this cycle, so an object allocated there is white, while one ahead of the
sweep or allocated during marking is black (the old vector appended every
new object ahead of the sweep, so the question never arose). And a
quarantine tombstone leaves the heap's accounting when it is made,
rather than being freed again on every later sweep, which had wrapped the
live-byte count and stopped collection from ever starting.

Old and new binaries interleaved, three rounds each, on a loaded machine:

| | old | new |
| --- | ---: | ---: |
| table + buffer + string allocation probe | 125-174 ns | 62-80 ns |
| path normalisation per call | 0.35-0.41 us | 0.24-0.29 us |
| binary trees, depth 15 x10 | 77-88 ms | 58-70 ms |

Every mode passes as before: the collector check, the image kernels,
Base64 and the paths corpus under stress and interleaved collection, the
sample and closure images. What remains per object is the body's own
allocation, a `Vec` for a table or a `Box<str>` for a string, and the
write of the fixed header; inline string storage and tables that start
with a sized array part are the next two steps, both P3.

## One stack, inline frames: the P3 layout, measured

Date: 2026-10-11. The plan's answer to the untyped call row (fib 2.2x
PUC) was the frame layout: one stack per task, each frame a four-word
header followed by its value, integer, float and vector windows, a call
placing the callee's frame after the caller's whole frame and copying the
arguments. It is implemented (`Task { stack, cur }`, `push_frame`,
`pop_frame`, `HDR`), with one capacity check per call instead of four and
no frame-record vector. The root walk follows the caller chain through
the headers and scans each frame's value window.

Two things fell out. Clearing the callee's value window on every push
(so the root walk never reads a stale word of another class left by an
earlier frame on the same region) cost 5% in `memset`; it is gone, and
instead the root walk filters candidates through `Heap::is_live_slot`,
which the chunked allocator makes cheap: a word that decodes as a pointer
is a root only if it addresses a used slot. A stale integer that happens
to equal a live object's address keeps that object one cycle longer,
nothing worse. And the caller's frame size lives in its own header, so a
push looks up only the callee.

| medians of three | before | after | PUC 5.5 |
| --- | ---: | ---: | ---: |
| fib(30) | 44 ms | 40-42 ms | 19.5 ms |
| binary trees | 47 ms | 45 ms | 54 ms |
| field updates | 50 ms | 50 ms | 31 ms |
| 1000 tasks x 1000 parks | 9.6 ms | 8.3 ms | |

The layout was worth 5-10% on calls, not the 2x the plan assumed. The
sampler puts 75% of fib in the dispatch loop itself and 25% in the push,
before and after; what a call costs is leaving the inner loop and
re-entering it with everything re-derived, twice per call, plus the
decode and `match` per instruction, and that is the shape of a Rust
`match` interpreter rather than of the frame. fib stands at 2.05x PUC,
on the price line. The row is not closed by layout; it is closed, if at
all, by the dispatch design P3 chooses, which this prototype's loop is
not (its handlers are to be Nupp, its loop language open).

## Parking from compiled code, as a lowering

Date: 2026-10-11. Contract 6.2 said a task with compiled frames parks by
spilling live typed registers and switching native stacks, which needs a
native stack per task and has no browser form. The Wasm gate found the
other shape fast: a park is a spill and a return, a resume is a re-entry
at the park's pc. The prototype already had the re-entry: the
loop-header transfer entry takes the frame record's windows and loads
every register before jumping to a pc. So `PARK` in a function compiled
as a frame-record entry stores the registers the function names back
into the windows, writes the pc after the park into the header word, and
returns the `PARKED` sentinel; the interpreter marks the task parked on
the key it reads from the spilled window, and a resume calls the entry
for the saved pc. Mode `park-compiled`: the worker runs entirely
compiled this way, from pc 0, under the same scheduler as `park`.

| 1,000 tasks x 1,000 parks, per park and resume, medians of five interleaved | ns |
| --- | ---: |
| interpreter frames (`park`) | 9.0 |
| compiled frames, spill and re-enter (`park-compiled`) | 12.5 |
| state machines on Wasm GC, scheduler in Wasm | 4.2 |

Three million compiled parks, every one resumed at its pc with its
registers, under the loop-transfer tests still passing. The first cut
was 24.5 ns: a hash lookup per resume for the entry, and a prologue and
spill touching every register the function had. Entries are now indexed
by pc per function, and only registers the function names are loaded or
stored (an over-approximation of liveness that a verifier liveness pass
would tighten). What remains over the interpreter's 9 ns is the entry
call and the five registers the worker names.

What this changes: 6.2 no longer needs native stacks. A compiled
function that can park is compiled with its frame record, calls to
functions the checker marks `suspends` go through a frame record rather
than a direct typed call, and the browser's compiled tier, if it ever
exists, parks the same way. No stack switching anywhere in the runtime.

## The compiler's lexer on the runtime

Date: 2026-10-11. The first real compiler module run end to end on the
prototype: `nupp.compiler.syntax.lexer`, unmodified, with its trivia-arena
dependency and the table arena provider, emitted as a module graph by
`emit/emitmod.lua` and driven by `src/nupp/bench/lexbench.nupp` (in the
tree, because the checker judges package membership by path). Mode:
`runtime-experiment lexer evidence/lexer.image <source> tokens,errors,sum`.
The subject is the lexer's own source: 41,192 bytes, 4,903 tokens. The
prototype agrees with LuaJIT on the token count, the error count and a
checksum over every token's text, line and column.

What the module graph needed, all new to the emitter and runtime: a chunk
function per module with its top-level locals as cells when captured,
every function a closure and every call dynamic, `require` by constant
and by value with a module registry, multiple results (`RetN`, results
delivered into the caller's window), the generic `for` protocol over
iterator objects (`pairs`, `ipairs`, `gmatch`), `repeat`, `break`, tuple
locals and assignments, function statements on tables and as record
methods (with the implicit `self`), interfaces as shapeless, `%` and `/`,
string comparison, sized table constructors, `error` values through
`pcall`, and a library: `string.byte`, `sub`, `find`, `char`, `rep`,
`format`, `gsub`, `gmatch`, `table.concat`, `math.*`, `pairs`, `type`,
`tostring`, `tonumber`, with a Lua pattern matcher for the three
pattern users. Bugs found by the run, each a lesson for P3: method values
are closures now and the shape table rooted only their names, so the
collector freed them; `string.byte` copied the whole source per call;
the first capture analysis made a cell of every local that shared a name
with anything a nested function used, 26,521 cells per lex.

| the lexer's own source, per lex | ms | ns per byte |
| --- | ---: | ---: |
| LuaJIT trace, ffi arena (the toolchain's selection) | 0.43 | 10.6 |
| LuaJIT interpreter, ffi arena | 2.70 | 65.6 |
| prototype, table arena, first run | 32.3 | 784 |
| prototype, after the source-copy fix | 11.7 | 285 |
| prototype, after sized tables and allocation-free builtin calls | 9.1 | 220 |
| prototype, after free-variable capture analysis | 8.6 | 210 |

Allocation per lex, after the fixes: 7,239 objects, of which 4,907 are
the token tables, 1,354 cells, 970 closures, 6 strings (every token text
is an interned hit). Cutting the cells from 26,521 to 1,354 moved the
time by 2%. The sampler puts 62% of the run in the interpreter's dispatch
loop and 20% in malloc and free, the latter mostly the token tables' hash
parts and the closures. This is the first compiler-shaped evidence and
it says the same thing the call path said: the untyped tier is
dispatch-bound, at 3.2x LuaJIT's interpreter here, and allocation is
second. The strings-as-views item added to the plan would not move this
workload: its substrings are interned hits. Where it would move is code
whose substrings are distinct, which the path normaliser is.

What is still not measured: the lexer compiled by the typed tier. Every
function here is a closure called dynamically and carries `any`-shaped
locals, so the JIT refuses all of them; the typed tier's number for the
lexer needs the emitter to keep the checker's types for locals and
parameters (it discards them for dynamic calls) and the JIT to take
closures and upvalues. That is the next step for this slice.

## Threaded dispatch: the call row closed

Date: 2026-10-11. The frame layout left fib at 2.05x PUC with 75% of the
time in the dispatch loop, so the dispatch design was the open gate. The
test is `csrc/threaded.c`: the nine opcodes fib uses, on the same one-stack
frame layout, each handler ending in a `musttail` call to the next
instruction's handler through a table, with the pc, the window, the
context and the frame in the argument registers throughout. No frame
record push beyond the header words, no re-entry of an outer loop on call
or return. Built by `build.rs` with clang at -O3; mode `fib-threaded`
translates the interpreter's fib bytecode into the C core's instruction
form at startup.

| fib(30), three interleaved runs | ms |
| --- | ---: |
| Rust `match` loop, inline frames | 43-44 |
| tail-call-threaded C, same frames | 24.8-25.4 |
| PUC Lua 5.5 | 20-22 |

Threaded dispatch takes the call row from 2.05x to 1.2x PUC, inside the
2x price with room. Each instruction is now one indirect branch with its
own predictor slot, and a call is twelve stores and a jump. What this
decides for P3: the interpreter's dispatch is tail-call threaded. The
handlers are the bodies, already decided to be Nupp; the skeleton needs
guaranteed tail calls, which clang gives C through `musttail` and which
Cranelift gives any function compiled with its `tail` calling convention
and `return_call_indirect`. So the loop can be produced by the runtime's
own JIT from the Nupp handlers, each handler a Cranelift function that
ends by tail-calling the next handler through the opcode table, with no C
in the path and no second dispatch mechanism for the browser to port.
That is the P3 design; this measurement is its gate.

### The threaded loop produced by the JIT

Same day. The decision above claimed Cranelift can produce the threaded
loop itself. `src/threaded_jit.rs` does it: the nine handlers as Cranelift
functions under the `tail` calling convention, each loading the next
instruction's opcode, indexing the dispatch table and ending in
`return_call_indirect` with the pc, the window, the context and the frame
as arguments; a plain entry function calls the first handler. Same
instruction form and frames as the C core.

| fib(30), three interleaved runs | ms |
| --- | ---: |
| C, `musttail` | 24.4-25.0 |
| Cranelift, `tail` calling convention, `return_call_indirect` | 25.6-26.1 |
| Rust `match` loop | 41.8-42.3 |
| PUC Lua 5.5 | 20-22 |

Within 5% of clang. So the runtime's interpreter can be built by its own
JIT from the Nupp handlers, which settles the loop's language question
the plan left open: there is no loop to write in any language, only
handlers, and the skeleton that threads them is generated. The browser
builds the same thing from the same handlers.
