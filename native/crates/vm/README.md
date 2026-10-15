# nupp-vm

The Nupp runtime of the runtime plan (`~/projects/nupp-plans/todo/nupp-runtime.md`,
contracts in `nupp-runtime-contracts.md`), started 2026-10-11 as the real P3
build after the prototype in `bench/runtime-experiment` had answered its design
questions. It now includes the P5 typed tier. What is here is the object model, the heap
and collector, the interpreter with one-stack frames and parking, the library,
the image loader and verifier, and the host services on the parking surface.

## Layout

| module | what it owns |
| --- | --- |
| `value` | the NaN-boxed word: tags for nil, false, true, function handle (image id and index), object |
| `numeric` | exact signed and unsigned 64-bit values, boxing, arithmetic, comparison and kind checks |
| `heap` | the fixed 32-byte header, inline payloads, size-classed chunks, large objects, the incremental tri-colour collector with stress, interleaved, quarantine and oracle modes, shapes, the weak intern table |
| `interp` | tasks, frames inline on one stack of words, the opcode set and dispatch loop, calls and returns, varargs in the frame, host calls that park |
| `builtins` | the library the compiler's modules use (strings with Lua patterns, tables, math, iteration, errors) |
| `verify` | operand classes, branch and callee checks, fact re-derivation, def/use and liveness |
| `image` | the loader for the emitter's text image |
| `host` | a pool of host threads serving file, process and directory requests as plain data; legacy unscheduled sleep |
| `scheduler` | runnable queues, task generations, logical timers, cancellation, deadlines and host completion batches |
| `persist` | versioned binary value graphs, shape policies, resource hooks and VM checkpoints |
| `threaded` and `csrc/dispatch.c` | the tail-call-threaded core and its helpers |
| `jit` | the typed tier: shared Cranelift lowering for JIT and object emission |
| `compiled` | runtime helpers, runtime address table and stack-map root walk, without Cranelift |
| `src/nupp/compiler/vm/lower.nupp` | checked-tree lowering and image writing, with project resolution/checking supplied as callbacks |
| `emit/emitmod.lua` | the stage-zero project-loading driver for the Nupp emitter |

## Decisions the layout fixes

- **Header.** `kind, color, class, flags, epoch, size, aux, aux_ptr, aux_len`:
  32 bytes, payload inline after it. Compiled code will read a string's
  bytes, a record's slots or a table's array part from `aux_ptr`/`aux_len`
  with no call. `aux` holds a record's shape and a closure's function id.
- **Allocation.** Thirty size classes from 32 bytes to 32 KiB, 256 KiB chunks
  aligned to themselves so an address finds its chunk by masking; larger
  objects on their own. `is_live_slot` is a chunk-set lookup and a slot
  boundary check, which the root walk uses to accept a register word.
- **Growable payloads** (a table's parts, storage, byte buffers, a record's
  ordered children) are Rust vectors inline in the object; the header
  re-mirrors their pointer after a change.
- **Records** are slots inline, then the ordered children a record type
  declares (`{cst.Node | lexer.Token}` inside the record), then an overflow
  map a structural shape may grow (an optional field of the declared type
  written after a closed constructor). Nominal shapes refuse unknown fields
  on write (contracts 2.5); an untyped read of an absent field is nil on
  any record, because the compiler's own `x.trivia ~= nil` tests on `any`
  need it (2.4 amended).
- **Strings** are interned when at most 40 bytes (1.3); a longer string or a
  slice used as a table key is looked up and stored by content through the
  intern table. Equality past the word compare is by content for string-like
  objects.
- **Varargs** stay in the frame: a vararg function's surplus arguments lie
  just below its header, their count in header word 3, and a trailing `...`
  in a call copies them straight into the callee. No object is allocated.
- **Roots** are every task's value windows down the caller chain, each
  frame's closure and vararg words, results, constant pools, handle scopes
  and registered handles; the heap walks shape names and methods itself.
- **Binary graphs and VM checkpoints are implemented.** `persist` shares
  `Heap::each_child` with the collector, preserves graph identity, and relocates
  parked frames into a fresh VM. The persistence section below records the
  tested scope and the remaining Tecs/worker integration gates.

## Running

```sh
cargo build -p nupp-vm --release
cd native/crates/vm/emit && ../../../../bin/nupp run emitmod.lua ../../../.. nupp.bench.parsebench > ../parser.image
cd .. && ../../../build/rust/target/release/nupp-vm run parser.image nupp.bench.parsebench parse @../../../src/nupp/compiler/syntax/parser.nupp --setup setup --repeat 5
```

`GC_STRESS=1`, `GC_INTERLEAVE=1`, `GC_ORACLE=1` and `GC_QUARANTINE=1` select
the collector's verification modes. `TRACE_CALLS=1` prints every call.

## Where it stands (2026-10-11)

The compiler's lexer and parser run unmodified on it, as module graphs
emitted from the checked tree, and agree with LuaJIT node for node:

| source | nodes | Rust loop | threaded core | typed tier | LuaJIT interpreter | LuaJIT JIT |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| lexer.nupp (41 KB), lex only | 4,903 tokens | 8.0 ms | 5.3 ms | 1.54 ms | 2.7 ms | 0.43 ms |
| lexer.nupp, parse | 8,523 | 15.6 ms | 9.6 ms | 3.4 ms | 5.9 ms | 4.3 ms |
| cst.nupp (94 KB), parse | 12,197 | 23.7 ms | 14.3 ms | 4.9 ms | 8.7 ms | 3.9 ms |
| parser.nupp (156 KB), parse | 40,179 | 67 ms | 42.1 ms | 15.6 ms | 26.8 ms | 16.9 ms |

(The Rust-loop column is from before the emitter's opcode work; the
threaded column after it. The typed tier compiles every function of the
parser's image, 151 of them, in about 290 ms before the first call, which is
reported apart from the run time.)

**The typed tier** (`src/jit.rs`, feature `jit`, on by default) is the
prototype's Cranelift lowering ported onto this heap: value registers as
stack-map variables, typed registers as machine registers, inline fast
paths for arithmetic, comparison, array and slot access, byte reads and
field reads through a per-site shape cache, guarded direct calls to known
callees, and helpers for the rest. The threaded core calls a compiled
function wherever it would push a frame, and compiled code calls back into
the runtime for what it does not lower. Parsing parser.nupp runs at
LuaJIT's trace speed with no inlining and every local still boxed, and the
collector's stress and interleaved modes pass under compiled code through
the stack maps.

**Raises do not unwind native frames.** cranelift-jit 0.135 no longer
registers unwind information with the system unwinder, and the threaded
core's C frames cannot be unwound either, which contracts 6.4 and 6.5
anticipated: a raise unwinds VM frames. `error` still raises as a Rust
panic between catch points, but at every boundary into compiled code or
the core a guard turns it into `Value::ERROR` with the value parked in
`pending_error`; compiled code checks each helper and callee result and
returns the sentinel, the core returns an error status, and the Rust frame
that entered them re-raises it as a panic up to the nearest `pcall`. A
small module with a captured counter, recursion and `error` under `pcall`
(`nupp.bench.jitbench`) agrees across all four tier combinations.

Two bugs the parser found in the port: a compiled entry was called with
the argument count the caller supplied rather than the callee's parameter
count, so a missing optional parameter read a stale register (the same
family as the interpreter's bug earlier); and the panic hook was taken and
reinstalled around every helper call, which doubled the run time until it
moved to the runner.

Under stress with the oracle the lexer-source parse runs 19,000-odd full
cycles and the parser-source parse survives interleaved marking with the
oracle and quarantine, on both dispatch loops.

**Dispatch.** The Rust `match` loop spent 60% of the parse in dispatch at
2.4 ns per opcode (27.9M opcodes for parser.nupp). The tail-call-threaded
core in `csrc/dispatch.c` (contracts 5.2) handles the hot opcodes and the
call and return path in C, with specialised helpers for field reads,
indexed stores, builtin calls and allocation and a generic one-opcode
fallback into the Rust interpreter for the rest (0.7% of opcodes). It
takes the interpreter from 2.6x to 1.7x LuaJIT's interpreter. The profile
on it is flat across handlers.

**Opcode count.** The emitter then learned to land results where they are
needed (the destination is passed down to kinds that write it last, and a
call's window starts at the destination when nothing is live above it), to
keep arithmetic and comparison on value-register operands in the value
domain instead of unboxing into the typed files and boxing back, to branch
on a typed compare's integer register without boxing a boolean, to load a
number literal as a value constant, and to load a closure's captures once
at entry. Opcodes for the parser-source parse went from 27.9M to 23.4M
(`Move` from 5.0M to 3.1M, the box and unbox pairs halved) and the time
from 44.6 to 42.3 ms: a 16% opcode cut bought 5%, because the remaining
opcodes are the ones the parser's structure demands. Its state lives in
captured locals read through small closures (`cur()`, `advance()`), so a
call, two cell reads and an index make up most of the stream, and a cell
read can only be hoisted where a semantic fact proves nothing writes the
cell across the loop, which the emitter does not have. The Rust loop and
the threaded core agree on every checksum; the collector modes pass on
both. A value-key `GetIdx` fast path in the core came after (42.3 to 42.1
ms). The comparison that counts is end to end, since the two VMs execute
different instruction streams: parser.nupp parses in 42.1 ms against
LuaJIT's interpreter at 26.8 ms, 1.57x, from 2.5x on the Rust loop. The
next step that changes that ratio is the typed tier, not the emitter.

Bugs the parser found: a dynamic call to a closure copied `sig.len()`
registers from the caller's window, so a parameter the call did not supply
held a stale word instead of nil, and the parser took a type path on it; a
`return f()` returned eight registers rather than what `f` returned; image
string constants with bytes outside ASCII were written raw; a field named
`method` collided with the image's method entries.

**Coverage (2026-10-11).** The next gate is the compiler and the library,
then self-hosting, so the emitter was run over the checker's whole module
graph (`EMIT_SURVEY=1`, which emits every function under `pcall` and
tallies what refused): 2,473 functions across the modules `nupp.compiler.check`
reaches, and every one emits. What it took, in the order the survey turned
them up:

- The capture analysis walked every named key of a node, and the checker
  hangs `definition` links there: a name's declaration, possibly in another
  module. The walk followed those into other functions' bodies first, so
  the shared `seen` set skipped them when their own function was analysed,
  and a method's use of a module local was never recorded. The CST keeps
  every syntax child in a node's array part, so the walks now read only that.
- `self` is a parameter only in the colon form; elsewhere it is whatever
  local the name reaches (`local self = {}` with `function self.fix()`).
- Exports follow the Lua backend's model: a declared module's value is an
  exports table, `export = v` replaces it, `export <decl>` adds the names,
  and an exported bare `function f` is a local of the chunk from its first
  instruction. Not yet done: registering the table before the body runs,
  which the Lua backend does for require cycles.
- Ownership intrinsics (`borrow`, `borrowFrom`, `adopt`, `release`,
  `region`, `drop`, `partition`) are identities at run time, as in the Lua
  backend; there is no cleanup runtime here yet.
- `x is T` as the backend decides it: settled statically, a nil test, a
  `type()` comparison, or a record shape test (`IsRec`, a boolean form of
  `TagCheckRec`; a union of records tests each in order).
- `..` chains fold left into one accumulator rather than nesting right with
  a register per operand; compound assignment; captured `for` variables get
  a cell per iteration; `do ... yield v end` expressions.
- Varargs outside a call's last argument: `VarargN` copies the frame's
  surplus into registers (`local a, b = ...`, `f(..., x)`), `VarargTable`
  builds `{...}`. The typed tier refuses vararg functions, which have no
  window onto the interpreter frame; the parser image has one.
- Register pressure: `checkMod.check` declares 242 locals and
  `gen.generate` 200. A function with more declarations than the budget
  (120) keeps a spill table in one register, and locals declared past the
  budget live there under a per-declaration key, cells included; reads and
  writes are field accesses. Only `local`, `local function` and record
  values spill; parameters and loop variables stay in registers.

The parser's three inputs and `jitbench` agree with LuaJIT on every tier
and collector mode after all of it, at the same times as above. The survey
proves emission, not execution: running the checker on the VM is the next
step, and needs the host services it reads files and environment through.

**The checker runs (2026-10-11).** `nupp.bench.checkbench` parses a source
and checks it in a memory-only environment (`envMod.new` builds the prelude
from `decls/*.d.nupp`, through comptime), answering the diagnostic count, the
typed node count and a checksum over inferred type tags and diagnostic codes.
The image is emitted with the modules `compilerPrivate` loads dynamically
named on the command line and the two `nupp.io` modules stubbed
(`EMIT_STUBS=nupp.io.files,nupp.io.path`); the runtime provides those two
natively (below). Every tier agrees with LuaJIT:

| source | result (diagnostics, typed nodes, checksum) | typed tier | threaded core | Rust loop | LuaJIT |
| --- | --- | ---: | ---: | ---: | ---: |
| small sample (20 lines) | 0, 77, 758055804 | 153 ms | 293 ms | 462 ms | 76 ms |
| lexer.nupp (41 KB) | 4, 3643, 467446496 | 305 ms | 585 ms | 915 ms | 232 ms |

(Medians of seven on a machine with a stray process at 100% of one core;
LuaJIT's includes its own warm-up across the repeats. The typed tier compiles
the image's 3,063 functions in about 6.1 s before the first call, 2 ms each,
reported apart from the run time; 16 are refused: 13 vararg, 3 with more than
eight parameters.) The interleaved collector with the oracle and quarantine
passes under compiled code (65 cycles on the small sample). The lexer-source
result differs from LuaJIT's `6, 3641, 379691941` only in the diagnostics the
project index contributes: the repository's `nupp.lua` manifest is a 700-line
Lua program, and this runtime evaluates no Lua, so there is no project index
and `require` of an internal stdlib module is not reported. That is the
self-hosting question the plan has to answer: the compiler evaluates Lua in
exactly two places, manifests and the Lua it generates, and both need a
decision (a manifest subset the compiler itself reads, and the backend
emitting images rather than Lua source).

What it took to get the checker running, each a runtime decision:

- **Casts to records are erased**, as the Lua backend erases them, because
  the compiler builds its own records as `setmetatable({...}, R) as R`: a
  struct-shaped table where a nominal one was declared. So every slot access
  by offset is **guarded by the shape the emitter assumed** (`GetSlot d o
  slot shape` and the three others), inline in the core and the typed tier,
  with a by-name slow path; and a nominal record keeps unknown fields in its
  overflow part rather than refusing them. The checker's own types decide
  slot offsets, the guard decides whether they apply.
- **Constructor-inferred shapes have untyped slots**: the checker types
  `x and y or nil` without the nil, and a numeric slot would refuse the nil
  the program stores. Declared record fields keep typed slots.
- **A trailing call argument spreads its results** (`f(a, g())`,
  `pcall(f, g())`): the argument count carries flag 64 and the callee's
  results follow the fixed arguments in registers, at most eight; every call
  path normalises the count from `last_nres`. `PadResults` after a call that
  wanted several results nils the ones it did not return, since a single
  `Ret` writes one register. Every compiled return now records its count.
- **`t[#t] = nil` shrinks the array part** (Lua's border rule) on every store
  path; `tonumber` of a non-string is nil; `require` of a missing module
  raises Lua's message, which `nupp.spi` probes for.
- **Metatables on tables**: `__index` (function or table), `__newindex`,
  `__call`, stored by `setmetatable` and walked by the collector; records
  have none. A method call that finds no shape method calls the field of
  that name, which is how the compiler's class idiom dispatches.
- **`loadstring`** evaluates `return <literal>` (numbers, strings with Lua's
  escapes, booleans, nil), which is what every compiler use decodes, as a
  closure over the value; anything else loads and raises when called, since
  the generator loads its output only to validate it.
- **Host surface**: `io.open` for reading (a file object whose methods are
  fields), `io.stderr`/`io.stdout` objects, `os.*` and `io.read` stubs that
  answer as failed calls, `debug.getinfo(1, "S").source` from the calling
  function's module path (the image records each module's source path, and
  compiled code passes its function id through dynamic calls), `package.loaded`
  as a live mirror, `table.sort` with a comparator, the `bit`/`math`/`string`
  extras, the fixed-width scalar intrinsics (`nupp.math.u32.*` and the i32
  and f32 families) as builtins the checker's intrinsic marks select, and
  `nupp.io.files`/`nupp.io.path` natively since `nupp.io` is FFI-backed and
  cannot load here.
- **Diagnostics**: an uncaught error prints every task's backtrace, innermost
  first, and the core records the pc before any helper that can raise.
- **Emitter**: inherited record fields are slots; shapes are keyed by nominal
  type identity rather than bare name (two modules each declare an `Error`);
  a `for` with a negative step tests `limit <= var`; `..` chains fold left;
  spilled locals; upvalue registers come from the analysis's exact free names
  (a nested local of the same name declared later no longer hides a capture).

Bugs the checker found in the runtime: the closure word of a vararg entry
frame was written at a fixed offset rather than after the surplus arguments
(the frame corrupted on return); a compiled function with more than eight
parameters lost the rest; the compiled multi-value return read its values
from the wrong slots; `install_globals` held an interned key across an
allocation.

**Slot guards, measured (2026-10-11).** `SLOT_STATS=1` on the Rust loop
counts every slot access by whether the object had the shape the emitter
assumed, and whether a verifier could have proved it exact (the register was
written by `NewRecord` of that shape in the same function, in straight-line
code, with no redefinition since). `NO_SLOT_GUARD=1` drops the typed tier's
shape compare, for measuring what it costs where shapes are known exact.

| workload | slot accesses | assumed shape held | provable exact | guard cost (typed tier) |
| --- | ---: | ---: | ---: | ---: |
| parser.nupp parse | 353,068 | 100% | 19% (158 of 262 sites) | within noise (27.4–28.5 ms both ways, minima equal) |
| checker on lexer.nupp | 780,236 | 83% | 14% (2,849 of 5,674 sites) | — |

The checker's 135,442 misses were 99.9% one object: the `Checker` built as
`setmetatable({...}, R) as R`, read at 1,220 sites. The emitter now lowers
that idiom, and `{...} as R`, to a `NewRecord` of the cast target with the
fields in their slots (records carry no metatable, and nothing in the
compiler reads one back), which leaves 56 misses at 4 sites: erased casts
across union members (`TypeVar` read as a `Prim`, `Call` as a `MethodCall`),
a separate semantic decision. With the misses gone the checker's own A/B
is meaningful: five interleaved pairs on lexer.nupp, guard 297–312 ms
against no guard 299–315 ms, minima 292–296 both ways, so within noise
there too. Local provenance would let the verifier drop the guard on a
fifth of accesses at most; the other four fifths read parameters, fields
and call results, where the only shape evidence is the checker's declared
type. The guard stays the general rule and the direct load is the
verifier's optimisation for the proven fifth.

**Profiling the checker's typed tier (2026-10-11).** With slot guards ruled
out, `sample` on the checker found the time in the runtime's helpers rather
than in compiled code: field reads by name, dynamic calls, builtins, the
collector and malloc. Each item below is one step on lexer.nupp (medians of
seven on the loaded machine; LuaJIT 232 ms):

| step | typed tier | helper traffic per check it removed |
| --- | ---: | --- |
| start of the pass | 297 ms | — |
| shapes answer a name through an open-addressed slot table (Rust, C, typed tier) instead of a linear scan | 267 ms | — |
| a dynamic call to a closure or bare function with a compiled entry calls it straight, eight nil-padded register arguments; builtins straight to their table; `ipairs` steps inline | 249 ms | 3.3M compiled-callee and 3.7M builtin calls through `j_call_dyn`; 1.2M iterator steps |
| the fixed-width scalar intrinsics as a `Scalar` opcode lowered inline (the digest's `u32.wrap`, `i32.add`, …) | 206 ms | 3.0M builtin calls |
| an inline shape-table probe behind the per-site cache; module exports as records | 207 ms | 1.4M polymorphic cache misses (273 megamorphic sites) |
| the table hash part as the same open-addressed table (`ValueTable`), probed inline by the typed tier and the core | 202 ms | 1.4M table reads |
| absent record fields answered inline, the overflow part the same table | 171 ms | 1.2M absent-field reads |

The small sample went from 153 to 90 ms. What the profile shows now, in
order: the collector (scan, child walk, sweep: a fifth of samples), malloc
and free (the `Vec` behind every table's array part and every record's
children, a sixth), then dynamic calls that still take the helper (1.1M
per check: trailing-call spread sites through `CallK`, callees with typed
signatures), `get_index` by value key, and the builtins left
(`string.byte` on untyped subjects, `tonumber`, `pairs`). The collector and
the allocator are the plan's P5 items (a nursery, inline small arrays); the
rest are emitter and tier work of the kind above.

Found on the way: a nil key read of the new table matched its empty marker
(nil's bits), answering the slot's filler; the compiled dynamic path cannot
pass more than eight register arguments, so a callee with more parameters
stays interpreted; the field-cache helper never filled its cache for an
absent field, so every such read paid the call.

**Startup: compile time and lazy compilation (2026-10-11).** A one-shot
check pays the typed tier's compile before its first call, so the compile
is the product problem once steady state is ahead. What this pass found:

- **The inline probes tripled compile time.** The parser's 150 functions
  went from 290 ms to 798 ms and the checker's 3,063 from 6.1 s to 17.5 s
  as the field-read, dynamic-call and iterator sites grew; Cranelift's time
  follows IR size. Those sequences are now three stubs compiled once per
  JIT (`stub.probe`, `stub.dispatch`, `stub.iter`) that each site calls,
  which brought the checker to 9.6 s at the same steady state (176 ms).
- **The optimiser and the IR verifier bought nothing here.** `opt_level=none`
  measured 170 ms against 176 at steady state and compiled 18% faster; the
  verifier was a tenth of the compile. Both are off by default now
  (`JIT_OPT=speed`, `JIT_VERIFY=1` restore them): 6.2 s for the checker's
  image, 317 ms for the parser's. The compile-phase profile is then
  register allocation (30%), instruction selection and lowering (35%),
  the frontend (4%) and allocation; the rest is per-function cost of the
  tier itself, not of any one lowering.
- **Lazy compilation does not solve the one-shot.** `JIT_THRESHOLD=n`
  compiles a function at its nth call (counted in the core and the
  interpreter). A check of lexer.nupp touches about 960 functions and
  compiling them costs 4.7 s, 5 ms each, because the hot checker functions
  are its largest; a threshold of 1 or 2 gives a 4.5–4.9 s first call, 5
  gives 3.6 s, and from 10 on the steady state suffers because warm
  functions stay interpreted (lazy 50: 2.8 s first call, 230 ms median).
  The interpreter alone checks lexer.nupp in 440 ms, so a one-shot is best
  served by the interpreter today, and by compiling the bundled compiler
  ahead of time tomorrow.

**AOT object gate (2026-10-11).** The JIT and object emitter use the same
Cranelift lowering. Object code reads the current closure, result buffers,
entry/call/shape tables, and image constants through the bound
`nupp_vm_runtime` table. Field caches are writable object data. The closure
is read into a local at each activation, so closures of one function can
have different captures. The build links helper symbols and the generated
stack maps into the executable; the loader checks the image's SHA-256 digest.

```sh
build/rust/target/release/nupp-vm aot native/crates/vm/check.image /private/tmp/nupp-check.o
NUPP_AOT_OBJECT=/private/tmp/nupp-check.o cargo build --release -p nupp-vm --features aot
build/rust/target/release/nupp-vm run native/crates/vm/check.image nupp.bench.checkbench check @src/nupp/compiler/syntax/lexer.nupp --setup setup
```

The checker object contains 3,063 compiled functions; the existing 16
vararg/wide-parameter functions remain interpreted. Object generation on a
release build host takes 8.08 s; the object is 32 MB and its uncompressed
stack-map sidecar is 13 MB. With the linked release executable and a warm
filesystem cache, completed-check process wall time is 0.26–0.27 s,
against 0.50 s interpreted (`NO_AOT=1 NO_JIT=1`) and 5.93 s with eager
JIT compilation (`NO_AOT=1`). The check result is 4 diagnostics, 3,643
typed nodes, checksum 467446496 on each. An initial run immediately after
linking took 1.26 s wall while its measured load and first call totaled
0.26 s; cold filesystem startup is not yet characterized. The linked AOT
checker also passes the interleaved collector with oracle and quarantine.

**No-code-generator build (2026-10-12).** The runtime helpers, root walk and
address table now live in `compiled`, independent of the Cranelift module.
The build host uses `aot`; the deployed executable uses `aot-linked` with
default features disabled:

```sh
cargo build --release -p nupp-vm --features aot
build/rust/target/release/nupp-vm aot native/crates/vm/check.image /private/tmp/nupp-check.o
NUPP_AOT_OBJECT=/private/tmp/nupp-check.o cargo build --release -p nupp-vm --no-default-features --features aot-linked
build/rust/target/release/nupp-vm run native/crates/vm/check.image nupp.bench.checkbench check @src/nupp/compiler/syntax/lexer.nupp --setup setup
```

| features | interpreter | compiled runtime | Cranelift |
| --- | --- | --- | --- |
| `--no-default-features` | yes | no | no |
| default (`jit`) | yes | yes | JIT |
| `--features aot` | yes | yes | JIT and object emitter |
| `--no-default-features --features aot-linked` | yes | yes | no |

The linked checker executable is 43,761,176 bytes (41.7 MiB, unstripped).
Its dependency tree and symbol table contain no Cranelift. With the macOS
executable-memory denial harness active, three warm-filesystem process runs
took 401, 286 and 294 ms, against 513, 523 and 523 ms interpreted in the same
binary. Five repeated checks gave a 176 ms median. These are startup and
packaging results, not an improvement to the generated machine code.
The result remains `4 / 3643 / 467446496`; interleaved GC with oracle and
quarantine passes (77 cycles).

`tests/no-jit-smoke.sh` builds both ends, checks the dependency and symbol
tables, compares linked code with the interpreter, exercises recursive
closures and `pcall` under stress GC, and rejects an image digest mismatch.
On macOS, `tests/deny-exec.c` rejects executable `mmap`, `MAP_JIT` and
executable `mprotect` requests; negative probes verify both allocation and
protection-change rejection before running the VM. This is a host API
interposition test, not an OS sandbox or console certification.

The interpreter is linked explicitly and handles module chunks and the 16
functions refused by the current lowering. The image still ships beside
the executable on initial load. A checkpoint embeds its code recipe and can
restore without that image file. Compiled suspension, SIMD and plugin refusal
have since been covered (`tests/no-jit-smoke.sh` with `FRAME_AOT=1`,
`tests/simd-aot-smoke.sh`); actual console SDK validation remains the open
gate for the full no-JIT target.

## Compiler emitting images on the VM (2026-10-12)

Lowering and image writing now live in the checked Nupp module
`nupp.compiler.vm.lower`. `lower.emit(entry, extras, resolve, check)` takes
project-loading callbacks and returns image text. Shapes, function IDs,
capture analysis and output buffers belong to one call. The old Lua script
is a 44-line stage-zero driver, with no copy of the lowering.

`nupp.bench.emitbench` runs parser, checker and lowering on the VM for a
closed input module. A fresh VM verifies and executes the resulting image.
The integration fixture exercises captured mutation, descending loops,
`pcall`, metatable methods (table and function `__index`), and builtin and
method calls with more than eight arguments. It returns 40 on the Rust
loop, threaded core and typed tier, under collector verification. Invalid
source is rejected before an image is returned; repeated emission has no
state carried over from the previous call.

The emitter also lowers its own source: **223,060 bytes, byte-identical
between LuaJIT, the VM interpreter and the typed tier**. The generated image
passes the VM verifier. Loading that emitted module in place of the original
lowerer and running it reproduces the same image byte-for-byte. The smoke
script runs this additional gate through `tests/self_lowering.rs`.
Interpreted parse/check/lower of that source took
1.07 s, plus 63 ms loading the compiler image, in the measured run.

Two runtime bugs were exposed and fixed: colon calls bypassed `__index`,
and builtin calls silently truncated arguments at eight. Builtin argument
windows now retain an inline fast path and allocate only for wider calls,
including vararg spreading. The lowerer's growing function descriptors
are explicitly open tables so their method table survives lowering.

Generate the compiler image with the stage-zero driver, then run the gate:

```sh
EMIT_STUBS=nupp.io.files,nupp.io.path ./bin/nupp run native/crates/vm/emit/emitmod.lua . nupp.bench.emitbench nupp.compiler.fs nupp.compiler.project.projectconfig nupp.compiler.project.store nupp.compiler.project.fingerprint nupp.compiler.hash nupp.compiler.hostservices nupp.compiler.compilerpacks nupp.compiler.project.preludecache > /private/tmp/nupp-emitbench.image
cargo build --release -p nupp-vm
python3 native/crates/vm/tests/lowering-smoke.py /private/tmp/nupp-emitbench.image
```

`nupp-vm verify IMAGE` loads and runs the existing verifier without executing
module initialization or compiling native code. This first gate verifies
closed-input lowering and the emitter fixpoint. The project gate below
extends it to the complete compiler core.


## Project loading, manifests, and compiler-image fixpoint

`nupp.tools.vm.project` reads projects through the existing compiler module
resolver, checks each source, and emits the reachable image. The compiler core
includes its computed project dependencies; a Rust runner calls `emit`, `manifest`,
or `rebuild`. The four-line `emit/project.lua` only seeds it with the existing host.

Lua manifests execute on the VM. `nupp.compiler.vm.chunks` parses source when it
is loaded and lowers it when the returned function is first called. This also
validates generated Lua that the compiler loads only to check syntax. A manifest
can compute its include roots; it is not restricted to a literal configuration
object. Syntax errors fail before project emission.

The host supplies filesystem/path operations, process identity, and SHA-256.
Their target declarations live in `decls/`; the compiler still checks their call
sites. The LuaJIT host retains its process-ID implementation behind the same
module. Project configuration gets its current directory from the filesystem
service. Diagnostic severity policy is separate from terminal rendering, so the
compiler core does not acquire the CLI's native terminal dependencies.

The measured compiler image has **2,522 functions and 6,905,030 bytes**.
Stages two and three are byte-identical. Interpreter rebuilds took 53.4–54.5 s
of CPU time in this run; this is a correctness gate, not a startup-performance result.

The project gate rebuilds the complete compiler core three times without a host
compiler after the seed, verifies every image, compares stages two and three
byte-for-byte, then uses stage three to compile a separate project. That project
uses a computed Lua manifest and a transitive import. Its image must agree
between both interpreters and under collector verification, and execute on the
Rust loop, threaded core, and typed tier. It also tests mixed vararg constructors,
`pcall` result counts, nil holes, and numeric constant precision.

```sh
./bin/nupp run native/crates/vm/emit/project.lua "$PWD" > /private/tmp/nupp-project.image
cargo build --release -p nupp-vm
python3 native/crates/vm/tests/project-smoke.py /private/tmp/nupp-project.image
```

This workload exposed and fixed:

- filesystem builtins incorrectly entering the scalar dispatch range;
- trailing varargs in mixed table constructors being truncated to one value;
- interpreted `pcall` counts omitting the success flag and retaining stale counts
  on failure;
- black allocations missing barriers for initial closure, cell, slice, and iterator
  references during incremental marking;
- decimal constant output and constant-pool keys rounding distinct numbers together.
  The image writer now uses 17 significant digits, including opcode immediates.

Dynamic image loading refreshes interpreter dispatch tables after callbacks. It
currently requires interpreter execution; loading into an active JIT/AOT VM is
rejected. `--load IMAGE` adds an image before startup for development. Neither is
a versioned plugin ABI or an untrusted-image security boundary. The compiler gate
still needs a source checkout and does not include the full CLI, native C-header
services, or release packaging. P4's repository-wide CLI check remains a separate
gate.

Validation also passed the existing LuaJIT bootstrap fixpoint, six focused
project tests, and 2,172 shared-suite cases across the initial run and recovery
of a failed shard. The shared suite was not fully green: its worker-startup test
requires the unavailable standalone worker host, and the unchanged
`spiinterfacetest/runtimeImplementationInterfacesArePublic` fixture declares
`application` while being checked as `typed-interface.nupp`. Native VM tests
pass with and without the JIT feature.

## Binary graphs and VM checkpoints (2026-10-12)

`persist::save_graph` writes VM objects directly. Object IDs preserve cycles,
shared references and object keys. Numeric storage and byte buffers use raw
little-endian spans. Strings are byte strings, including interned non-UTF-8 keys;
slices retain their source/range. Tables, metatables, record slots/children/overflow,
closures, cells and iterator positions are covered. Loading allocates objects,
relocates references and rebuilds hash tables using their new keys. It does not
copy native pointers or require per-type generated codecs.

The experimental Nupp module is `require("nupp.vm.persist")`:

```lua
local persist = require("nupp.vm.persist")
local bytes = persist.save(value)          -- binary string
local restored = persist.load(bytes)      -- same graph, new identities
-- Optional nominal root check: persist.load(bytes, "module.Shape")
```

Use `saveData` and `loadData` for data that must survive changes to the program's
record declarations:

```lua
local persist = require("nupp.vm.persist")
local bytes = persist.saveData({version = 1, score = 42})
local restored = persist.loadData(bytes)
assert(restored.score == 42)
```

These operations preserve aliases, cycles and object keys. Structural records
restore as ordinary tables without attaching destination record methods or
hooks. Nominal records, metatables, callable values and resources are rejected.
Applications supply their own format version, schema migration and validation.

Nupp callers can supply explicit policies for durable shape names, transient
fields and before-save/after-load hooks:

```lua
local policies: {persist.Policy} = {{
    shape = player, -- record exemplar; an exact runtime shape name also works
    name = "game.Player.v1",
    transient = {"cache"},
    afterLoad = function(value: any): nil
        value.cache = rebuildCache(value)
    end,
}}
local bytes = persist.save(player, policies)
local restored = persist.load(bytes, nil, policies)
persist.loadInto(bytes, player, policies) -- preserves player's identity
```

Hooks cannot suspend, run once per reachable record, and see all graph references
relocated on restore. Transient values are excluded from traversal. Unknown fields,
unknown/duplicate shape policies, and nonfunction hooks are rejected. Failure is a
normal catchable error; scratch tasks and roots are cleaned up. Policies are scoped
to the operation, not registered globally. Rust callers have the same mechanism
through `Policies` and native function callbacks. Nupp closure callbacks belong to
the current VM and are refused for cross-VM checkpoints; checkpoint resource and
shape hooks are supplied by the embedding host. `load_into` preserves an existing record's identity.
Shape fields/types must match; typed fields are checked throughout the graph.
Transient typed fields require an after-load initializer. Hooks run after all
references are resolved; hook errors can leave an in-place target modified.
Selecting/excluding roots is the caller's responsibility. The licensed Tecs
integration now uses runtime storage and data persistence for world save/load,
including its existing selection and lifecycle hooks. See
[tecs-storage-coverage.json](tests/tecs-storage-coverage.json) for the original
world tests and 10,000-entity benchmark acceptance. Whole-game replacement,
provider restoration and the complete snapshot-policy API remain separate.

`save_vm` takes an embedding safepoint, outside active VM/native calls. It saves
module globals, constant pools, shape methods, registered/scoped roots, every
task and its value/integer/float/vector windows, varargs, return locations, park
keys, result counts and idle host-pool configuration. `load_vm` creates a fresh
VM without rerunning module initializers. Native entries/caches are dropped;
execution initially resumes in the interpreter. The embedding host can attach
its compilation policy again. The image loading recipe travels with the file,
so the compiler source checkout is not needed to reconstruct code (application
operations may still read source files). Code/closure identity is conservatively
bound to a SHA-256 of the complete code context, including module/function names.

External objects must be explicitly registered in `Interp::resources`. Ordinary
value saves refuse them. Checkpoints require a named `ResourceCodec` to save and
reconstruct each one in place. All resource restore callbacks finish before
record after-load hooks run, and all hooks finish before tasks resume. Missing codecs identify the
resource kind; pending host requests block checkpointing until completions are
drained. Codecs own their external resource lifetime and failure cleanup. Tests
exit the saving process, restore in a new process, reopen a real Rust-owned
file at its saved offset, and resume a task holding that same resource identity.
A separate test restores Rust-owned mutable counter state. The current buffered
`io.open` implementation already holds file contents as VM data.

This covers the current VM, including its host request pool. Nupp worker VMs and
channels do not exist here yet; their coordinated checkpoint gate remains open.
Compiled `Park` is still refused by the real typed tier, so parked-frame proof is
for both interpreter loops; a separate test drops actual JIT entries on restore.
The format has versioned framing, CRC32 corruption detection, bounded lengths,
reference/schema validation and a 256 MiB limit. It is not an authenticated or
untrusted-bytecode security boundary, nor a stable released file format.

### Measurements

macOS arm64, release build without Cranelift, median of nine measured iterations
after three warmups. GC cleanup is outside the graph timing. VM save time is the
pause time; these are memory operations, excluding disk I/O and resource hooks.

| fixture | graph bytes | graph save / load | VM save / restore | harness peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 10,000 two-field records | 400,136 | 1.30 / 1.48 ms | 1.34 / 1.48 ms | 11.3 MiB |
| three numeric column groups, 10,000 entities | 320,193 | 0.02 / 0.02 ms | 0.04 / 0.04 ms | 5.5 MiB |
| 16 MiB byte buffer | 16,777,315 | 1.00 / 0.84 ms | 1.99 / 1.33 ms | 99.3 MiB |

Peak RSS includes the live source VM, retained encoded graph/checkpoint buffers,
temporary save output and restored VM in the benchmark process. The fixtures
measure the runtime mechanism; they are **not** the actual Tecs snapshot benchmark
or evidence of meeting its acceptance target. That integration remains open.
The live compiler also checkpoints after compiling a project: a 23,815,485-byte
snapshot saved in 102 ms and restored in 183 ms, then emitted an identical program.
These timings are directional on the shared machine.

This work also fixed UTF-8 assumptions in binary string interning and incorrect
allocation/free accounting for growable native payloads. Repeated restore/GC now
returns retained bytes to zero; collector debt includes payload growth.

```sh
cargo test -p nupp-vm --lib --tests
cargo test -p nupp-vm --no-default-features --lib --tests
cargo build --release -p nupp-vm
python3 native/crates/vm/tests/persistence-smoke.py /private/tmp/nupp-project.image
cargo run --release -p nupp-vm --no-default-features --example persistence_bench
cargo run --release -p nupp-vm --no-default-features --example checkpoint_compiler -- /private/tmp/nupp-project.image
```

The tests cover cycles/aliases, every object kind, typed schema rejection, durable
names and in-place load, corruption/truncation, GC stress/oracle/quarantine,
nested/vararg/typed parked frames, globals, JIT cache dropping, host-pool restart,
resource refusal/restoration, and fresh-process continuation. The Nupp fixture
is compiled by the VM compiler and runs on all three execution tiers.

### Restore into a no-JIT executable (2026-10-12)

The runner now supports saving after a completed call and restoring initialized
module state in a fresh process:

```sh
nupp-vm run game.image game update --checkpoint game.save
nupp-vm restore game.save game update --checkpoint next.save
```

Restore loads the checkpoint's code recipe without rerunning module initializers.
An AOT-linked runner checks the primary image SHA-256 before binding any entry,
then rebuilds the runtime address table from the restored constants, shapes,
call metadata and entry array. It attaches the executable's stack maps and native
functions; no serialized address is reused. A mismatched checkpoint is rejected
before application execution. `NO_AOT=1` keeps restored calls interpreted.
The CLI uses default host policies; custom resource codecs remain embedding API
parameters. It calls the named initialized export; it does not automatically wake
parked tasks or override a saved host with `--host`.

`tests/no-jit-smoke.sh` now checks checkpoint restore as well as initial loading.
With `tests/checkpoint.image checkpoint step` arguments, separate save/restore
processes advance a captured counter from 1 to 2 to 3, with native and interpreted
restore agreeing under GC stress. With the Nupp persistence fixture, the same
harness exercises hook callbacks, failed-hook recovery and restored closures.
Reproduce both fixtures with:

```sh
sh native/crates/vm/tests/no-jit-smoke.sh native/crates/vm/tests/checkpoint.image checkpoint step
python3 native/crates/vm/tests/persistence-smoke.py /private/tmp/nupp-project.image /private/tmp/hooks.image
sh native/crates/vm/tests/no-jit-smoke.sh /private/tmp/hooks.image main run
```

Both dependency and binary-symbol checks exclude Cranelift. The macOS executable
memory interposer rejects allocation/protection requests during all runtime steps.
Compiled suspension and console SDK validation remain separate gates.

Hook failure testing also fixed native helper cleanup: the saved GC frame pointer
is now restored by a drop guard when a callback raises, so the next allocation
cannot walk an expired native frame.

## Embedding scheduler and saved timers (2026-10-12)

`Interp::enable_scheduler` enables the cooperative scheduler at an idle boundary.
`Interp::schedule` creates a task and returns a `TaskId { index, generation }`.
`run_ready(max_turns)` dispatches FIFO until each task parks or completes, drains
ready host completions once per batch, and returns terminal events. A failing task
becomes `Failed(message)` without aborting its siblings. Results remain rooted in
the task until `release_task`. Releasing reuses the slot with a fresh generation;
stale task IDs and cancellation tokens cannot affect the replacement. Frame
stacks return to the bounded existing stack pool (at most 64), and released
results stop being roots. A 5,000-task churn test retains one slot and one stack.

The clock is explicit monotonic **milliseconds**, driven by `advance_to(now)`.
`Scheduler::next_wakeup` tells the embedding event loop its next timer/deadline.
A scheduled `host.sleep` parks on a scheduler timer without using a host thread;
zero milliseconds yields to the next batch. It returns the same `true` completion
as the existing host sleep. Manual `wake_task` is idempotent for event parks and
refuses to bypass a timer or native I/O wait. At a matching timestamp, a deadline
cancels before a sleep can resume application code. Ordinary native requests still
run on the host pool. Late completions of cancelled tasks are drained without
resurrecting them; releasing such a task waits for that completion to drain.

A cloneable `Cancellation` token can be requested from another host thread without
touching the heap. The VM observes it at scheduled entry/exit, `CHECKPOINT`, `PARK`
and host-call boundaries. Scheduling is cooperative, not instruction-preemptive;
a function with no poll point cannot be interrupted before it returns. Deadlines
use the host-driven logical clock, not an independently advancing wall clock.
At this milestone affine regions and the Nupp facade were still open; the
following section records the first source-level path. Coroutine generators,
workers and channels remain open.

VM checkpoints now include the queue order, clock, timers, deadlines, requested
cancellations, terminal status, task-local result counts, free slots and generation
sequence. Restore rebuilds cancellation tokens and timer indexes. A 20 ms sleep
saved at time 5 still has 15 ms left after restart; time spent with the process
absent does not consume it. The optional versioned scheduler extension accepts
older checkpoints with no scheduler; older readers reject the new extension.
Pending OS requests retain the existing drain-before-save rule; scheduler timers
have no OS state and can be saved while pending. Native-code attachment after
restore remains the embedding host's responsibility as before.

`tests/scheduler.rs` covers both interpreter loops under GC stress/oracle/quarantine:
FIFO and batch limits, nested-frame sleeps, zero/invalid durations, equal-time
deadlines, cross-thread cancellation of a checkpoint loop, sibling isolation,
late OS completions, fresh-process timer/object restore, malformed metadata, and
bounded task churn with stale handles. `examples/scheduler_bench.rs` runs 1,000
three-frame tasks through a million parks. Release build without Cranelift, median
of five after two warmups on the shared macOS arm64 host:

| per park/resume | raw task driver | scheduler with cancellation and queues |
| --- | ---: | ---: |
| Rust loop | 13.3 ns | 46.8 ns |
| threaded loop | 18.3 ns | 48.5 ns |

These measurements predate compiled heap-frame entries and do not measure their
cost. The ordinary native calling convention still refuses `Park`. No timer
elapses or native request completes in that benchmark. Reproduce with:

```sh
cargo test -p nupp-vm --test scheduler
cargo run --release -p nupp-vm --no-default-features --example scheduler_bench
```

## Nupp scopes, affine regions and compiled suspension (2026-10-12)

The first source path is connected to the scheduler: `nupp.tasks.open`, scope
`spawn/cancel/close`, handle `await/isDone/status/cancel`, and
`checkpoint/deadline/isCancelled`. The VM declarations describe this supported
subset. `run ... --tasks` drives the queue and clock; embeddings use the existing
scheduler methods. Await and a spawn blocked by `limit` park and retry their
instruction. Closing a scope waits for children. Completed handles retain their
values while scheduler slots are released and reused with fresh generations;
the scope prunes settled handles on spawn/close. Wait edges carry full task IDs,
are checked for cycles, and survive checkpoints.

The emitter reads the checker's cleanup terminals for `with`, automatic local
owners and explicit `drop`. `Defer`/`DeferMethod` register rooted receiver/callback
pairs, `Unwind` closes lexical regions, and `DisarmAt` identifies a transferred
owner by its frame-local slot. Equal values do not identify ownership. Return,
break, errors and cancellation run the registered callbacks in reverse region
order; an exceptional scope exit cancels and drains its children. The original
error remains primary. General callbacks are synchronous: parking host requests
and task operations are rejected before submission. Native scope close itself
can park. Affine closure captures, conditional field cleanup and aggregation of
secondary cleanup failures remain open.

Scheduled functions can use a separate Cranelift ABI `(frame, pc) -> boundary_pc`.
It loads the frame windows, runs ordinary lowered instructions, spills at calls,
returns and parks, and returns to the VM driver. Every suspending call therefore
uses heap frames, including dynamic calls and functions with varargs or wide
signatures. `pcall` handlers are heap-frame records and can span suspension.
The initial implementation spilled all windows and routed storage operations
through the driver. The live-register transfer follow-up below replaces that path.
The CLI selects frame entries for images with cleanup regions as well as for
`--tasks`. Ordinary native entries remain available for synchronous images
without those regions.
The AOT follow-up below adds linked frame entries for no-JIT builds.

Checkpoints include cleanup callbacks/receivers, protected-call frames, original
error values and scheduler wait edges. They contain no native continuations.
The extended VM payload uses kind 2 only when those extra task records are needed;
kind 1 remains readable. Scheduler extension 2 adds wait targets and accepts
extension 1. Compiled parked tasks restore into an interpreter-only VM.

Validation lives in `tests/scheduler.rs` and `tests/tasks-smoke.py`. The latter
compiles a Nupp fixture and exercises bounded spawning, resource cleanup,
cancellation through `pcall`, ownership transfers without double close, original
error identity (including nil), repeated awaits and handle churn with GC
stress/oracle/quarantine, both interpreted and through actual compiled entries.
Both compiler fixpoints pass: the legacy compiler rebuilds byte-identically,
and VM compiler generations two and three are identical at 6,918,539 bytes.
The repository check, default/no-JIT Rust suites, linked no-executable-memory
checkpoint gate and three-tier persistence-hook smoke also pass.

This is an initial P5 slice. `tasks.run/gather/race`, named-spawn overload routing,
worker `fork`, channels and coroutine/generator APIs are not yet migrated.
Cancellation identity is VM-local; operation/reason metadata still needs the
full public cancellation representation. No performance claim is made for the
new frame tier.

```sh
cargo test --offline -p nupp-vm --lib --tests
cargo test --offline -p nupp-vm --no-default-features --lib --tests
python3 native/crates/vm/tests/tasks-smoke.py /path/to/project-compiler.image
```

## Task coverage follow-through (2026-10-12)

This supersedes the open task items above. The native facade now includes
`run/gather/race`, named spawn, and cancellation values carrying operation/reason.
Gather preserves independent failures; race selects the first completed branch
and drains canceled losers. The emitter uses the checker's trailing-callable
argument order and selected member, preserving source evaluation order.

Affine closures transfer the checker's explicit `takes` captures. Their body or
uncalled drop closure consumes them once; queued cancellation drops them too.
Conditional field transfers test the exact cleanup slot before disarming it.
Scheduled cleanup callbacks run as saved child continuations and may park.
Errors retain `primary` and reverse-order `suppressed` failures. Cleanup state,
including an in-progress callback, is part of the checkpoint graph. Cancellation
requests made during a scheduler batch are noticed before the next activation.

`scope:fork(arguments..., body)` creates an isolated interpreter VM on an OS
thread. Code recipes are replayed and captured graphs/arguments/results are
copied through the binary serializer. No ordinary heap address crosses threads.
The host drives worker turns, cancellation and clocks. The implementation caps
concurrent worker threads at 64. Workers now compile heap-frame entries on their
own threads, or attach the parent's verified linked AOT entries. Pooling remains
performance work. Native capabilities without transfer codecs are refused. Failed result transfer
fails the task once; it never restarts an old worker snapshot.
Compiled helper context, closure roots and helper frame pointers are thread-local.

`tasks.channel<T>(capacity)` is a shared, bounded channel. `send(value)` parks
when full; `receive()` returns `(value, true)`, including a nil value, or
`(nil, false)` once closed and drained. `close()` wakes waiters and rejects future
sends. Messages are serialized copies. `channel()` returns an affine owner: scope
exit closes it, including error unwinding. `share()` returns a send/receive endpoint
that can cross worker boundaries; the owner controls the queue's lifetime. Closing
still permits draining queued messages. Closing and draining releases registration. Worker transfer shares
only the queue, through a VM-owned registry and codec. Checkpointing pauses worker
turns, saves each worker VM and the channel queues, and restores shared queue
identity. Pending external OS requests still require the existing drain gate.

`coroutine.create/resume/yield/wrap/status/running/isyieldable/close` use scheduler
frames. Nested resume and host parking preserve result positions and resumer
relationships across restore. Standalone value serde refuses coroutine
continuations; they require a whole-VM checkpoint. Nupp's VM declarations make
`coroutine.create` and `coroutine.wrap` affine owners, so leaving their scope closes
suspended continuations and drains resources. A wrapped coroutine is a reusable
owning callable. The typed
`nupp.generator.create<T>(body)` facade returns an
owner with `next(): (T?, boolean)` and `close`; its `with` scope closes a partially
consumed body and drains its affine resources automatically.

`aot IMAGE OBJECT --frames` emits the heap-frame ABI into ordinary object files.
The no-JIT host binds these entries after image verification and uses the same
park/resume driver. `FRAME_AOT=1 tests/no-jit-smoke.sh IMAGE MODULE FUNCTION`
checks compiled frame execution, GC, fresh-process restore and interpreted
agreement while executable-memory allocation is denied. Native entries and
helper pointers are rebound, never serialized.

Acceptance coverage: source-level task/ownership/channel/coroutine/generator
fixtures on interpreter and frame JIT with GC stress, oracle and quarantine;
Rust scheduler/worker tests for secondary errors, cleanup sleeping through
restore, isolated cyclic graphs, channel backpressure and restoring a worker
waiting on a channel; nested coroutine yield and timer parking through restore.
These are correctness gates, not new throughput or startup performance claims.

The final source fixtures pass on both task tiers, including a channel shared
with a worker and early generator close. Persistence hooks pass on the Rust,
threaded and typed tiers. VM compiler generations two and three are byte-identical
at 6,927,267 bytes. The generator fixture also passes linked frame AOT execution
and fresh-process checkpoint restore with executable memory denied.
Formatting, a cold repository check, default/no-JIT Rust suites, and the legacy
compiler's byte-identical fixpoint also pass.


## Compiled workers and uniform ownership (2026-10-12)

Worker JITs are created and retained on their worker thread. A loop backedge polls
the bounded-turn budget, including loops without calls or explicit checkpoints;
a save or cancellation never requires interrupting a native activation. Restored
workers compile again on demand. Worker teardown frees generated code and removes
its stack maps. Linked frame AOT works in workers too: object
code obtains VM addresses through `nupp_vm_runtime_v3` on the executing thread.
The previous process-global address table is gone. Older objects must be re-emitted.

Ordinary Nupp locals returned by `tasks.channel`, `coroutine.create`, or
`coroutine.wrap` now close at lexical scope exit, just like generators. Explicit
close consumes the owner; subsequent use is rejected. Channel endpoints from
`share()` are shareable capabilities with no cleanup ownership. After owner close,
receivers can drain queued messages and then see end-of-stream; sends fail. Native
queue references follow managed endpoint reachability, so a closed unread queue
does not stay alive through a registry root.
The private coroutine provider remains the unowned mechanism used internally by
the generator facade, whose public result already carries its cleanup obligation.

The checker retains ownership when refining a coroutine's typed protocol. The VM
target declares that it drains owned continuations, permitting resources to remain
live across yield; the Lua target's existing suspension rule is unchanged. Tests
cover early scope exit, repeated wrapped calls, error unwinding, and rejection of
use after explicit close, under interpreted/compiled execution and GC stress.

### Measured costs

Release build on the same loaded machine as the preceding experiments. Three
alternating interpreter/compiled process pairs, each with one first call and five
repeats; the table is the median of the three process medians. Reproduce with
`python3 native/crates/vm/tests/concurrency-perf.py COMPILER_IMAGE`.

| workload | interpreter | compiled frame tier |
| --- | ---: | ---: |
| sum 1..2,000,000 on main VM | 32.43 ms | 9.10 ms |
| same sum in a fresh worker | 40.58 ms | 12.65 ms |
| 10,000 cancellation checkpoints | 0.282 ms | 0.480 ms |
| 10,000 numeric channel send/receive pairs, same VM | 4.84 ms | 6.11 ms |
| 10,000 coroutine resume/yield pairs | 7.83 ms | 9.09 ms |

Each worker sample includes thread/VM creation, graph transfer, scheduling, and
fresh worker compilation. Worker compilation itself was 0.50 ms; the compiled
first invocation including parent compilation was 13.74 ms. CPU-heavy workers
improve about 3.2x. Tiny control/message loops still favor the interpreter: the
frame tier's runtime transfers and full-window loads/spills outweigh their little
arithmetic. Cancellation checkpoints do not park; coroutine handoffs do. These
results do not establish compiler throughput or worker scaling across core counts.
The runner now wakes promptly on worker replies instead of imposing a 1 ms sleep.

Validation on the final revision: cold repository check and both byte-identical
compiler fixpoints (VM image: 6,930,222 bytes); default/no-JIT Rust suites; source
ownership/task tests with GC stress/oracle/quarantine; persistence hooks on all
three tiers; linked AOT worker and automatic-close fixtures with fresh-process
restore and executable memory denied. The unread-channel test confirms collection
releases queued native storage after all managed endpoints are dropped.


## Live-register suspension transfers (2026-10-12)

Native task suspension requires no reusable Lua coroutine. Each task owns its
heap frame stack and continuation PC. Parking returns control to the scheduler;
resumption enters that continuation. Coroutines and generators use this machinery
as APIs, and released stack storage can be pooled without reusing a coroutine's
logical identity. The legacy Lua/browser suspension providers remain separate.

The frame compiler now loads only live-in registers at each continuation and
spills only live-in registers at runtime boundaries. A guarded frame helper
executes the operation against that saved frame. If it completes immediately,
native execution continues; if it changes frames, parks, or finishes, the native
activation returns a transfer status to the driver. An immediate call reloads
only its live result registers, retaining other native values. Errors propagate
through the existing sentinel path. Bounded worker turns still stop at native
backedges and runtime operations, with no native activation retained when parked.

The liveness pass now conservatively handles partial result writes, padding,
trailing-call spreads, varargs, and typed call windows. Added regression tests
carry boxed objects, multiple results, integers, floats, and vectors across calls
and parks; the object/result test also saves and restores the parked VM.

### Performance after the transfer change

Same release harness and alternating-pair protocol as above, with positive native
entry counts required for every compiled workload. Warm medians on the loaded
machine; no other validation jobs were running during this measurement:

| workload | interpreter | compiled frame tier | compiled first call |
| --- | ---: | ---: | ---: |
| sum 1..2,000,000 on main VM | 32.50 ms | 7.05 ms | 7.52 ms |
| same sum in a fresh worker | 39.74 ms | 9.93 ms | 10.96 ms |
| 10,000 cancellation checkpoints | 0.277 ms | 0.186 ms | 0.491 ms |
| 10,000 channel send/receive pairs, same VM | 4.95 ms | 4.48 ms | 5.14 ms |
| 10,000 coroutine resume/yield pairs | 7.59 ms | 7.30 ms | 8.30 ms |

All five warmed workloads now favor compiled execution. Fresh worker compilation
costs 0.208 ms and is included in every worker sample. First-use JIT compilation
still outweighs the savings on tiny control workloads; linked AOT avoids that
compilation cost. These results establish neither general program speedups nor
multicore scaling. The coroutine row measures real handoffs; checkpoints only
check cancellation. Compiled control-path regressions remain a release gate.

Validation: default and no-JIT Rust suites; source task/ownership fixtures under
GC stress, oracle, quarantine, and JIT verification; persistence hooks and restore
on all three tiers; frame AOT cleanup and worker restore with executable memory
denied. No Nupp compiler sources or bytecode format changed.

## Check image dependencies (2026-10-12)

The project builder loads AOT code generation, packaging, hot-reload support,
and the documentation builder when a target requests them. GPU declaration
detection stays in the lightweight checking policy. Dynamic dependency markers preserve
the existing cache fingerprints, and AOT builds restore their cached inputs
through a factory in the backend. Stub catalogs read the host ABI version from
platform metadata without loading the LuaJIT packager.

The compiler loads the native process provider when it starts an isolated
child. Its typed loader retains the affine process result and automatic
cleanup, while ordinary checking can emit without that provider's source.
The filesystem host creates directories and removes files, links, and directory
trees. Recursive removal leaves symlink targets intact.

The VM emitter excludes imports the checker marked as type-only. Runtime
library tables expose the existing string, table, and math builtins, including
numeric `math.huge` and `math.pi`. Concatenation assignments use a temporary
accumulator so later operands can still read the destination's previous value.
Capture analysis includes named cleanup functions from affine metadata, even
when no source expression refers to them. Assignments to global names write
the VM's shared global table, including `_` in a multiple assignment.
Project loading registers the VM library root for module names and type
resolution. Qualified module references use the checker's resolved projection;
the repository manifest cannot become the global `nupp` namespace.
The intrinsic namespace is a runtime table. Labels and jumps resolve within
their lexical block and unwind affine cleanups when leaving a scope.

```sh
python3 native/crates/vm/tests/cli-image-smoke.py /path/to/project-compiler.image
python3 native/crates/vm/tests/project-smoke.py /path/to/project-compiler.image
```

The CLI image test asks the VM compiler to emit the real `check` command,
verifies its bytecode, and rejects legacy AOT lowering, LLVM code generation,
LuaJIT packaging, hot-reload, native processes, and documentation backends in
its module list. The emission list includes the dynamically selected compiler
host services and the VM's C-declaration adapter.
Static target descriptions remain available for manifest checking. The project
fixture exercises erased imports, library tables, concatenation and global
assignments, and named affine cleanup on both interpreters and the JIT, followed
by the compiler-image fixpoint.

This gate covers image construction. The execution test below runs the same
image through the compiler host services and derived metadata.

## Check command execution (2026-10-12)

`nupp.tools.vm.cli` runs the existing derived `check` command on the VM.
The executable entry accepts raw arguments and returns the command's exit status:

```sh
NO_JIT=1 NUPP_COMPILER_ROOT="$PWD" \
  build/rust/target/release/nupp-vm exec check.image nupp.tools.vm.cli --json
python3 native/crates/vm/tests/cli-execution-smoke.py check.image --repository
```

Build `check.image` with `nupp.tools.vm.project.emit`, using
`nupp.tools.vm.cli` as its entry and these extra modules:
`nupp.compiler.hostservices`, `nupp.compiler.fs`,
`nupp.compiler.project.projectconfig`, `nupp.compiler.project.store`,
`nupp.compiler.project.fingerprint`, `nupp.compiler.hash`, and
`nupp.compiler.project.preludecache`. Decode the emitter's JSON string into the
image file, as in the project test. The current executable image has 191 modules
and 9,570,956 bytes. Legacy AOT/LLVM code generation remains outside its graph.

Checked derive recipes and reflection descriptors become ordinary VM syntax.
Record defaults, positional construction, declared constructors, short functions,
qualified methods, and managed cleanup use semantic checker facts. Switches
preserve ordered arms, guards, captured bindings, and one selector evaluation;
yielding from a value block runs its pending cleanup. Optimized
tables preserve metatables across interpreter/JIT access, GC, and persistence.
Dynamic Lua bindings can change numeric kind, absent globals are nil, and fixed
result assignments pad missing values. Generic iterators stop only on nil and
pad missing results; trailing calls retain their result pack through casts
without overwriting the outer callee. Named fields use canonical string keys
at every length. JSON escaping honors replacement-table metatables and roots
captures across callbacks.

The compiler host provides filesystem operations, writable file handles, cache
hashing, and C declarations. The optional `c-headers` Cargo feature uses an
in-process libclang library, selected with `NUPP_LIBCLANG` or platform defaults;
it launches no compiler process. Builds without the feature retain the runtime
and report that C-header checking is unavailable. Open writable files and the
C declaration registry are external resources that require explicit snapshot
policies. Release packaging for libclang remains open.

The command acceptance test runs with an empty `PATH` and covers files, projects,
C declarations, invalid input, control bytes in JSON, help, schema, usage errors,
and exit status. Repository checking has passed interpreted for all 545 modules
with zero errors. The final cold run took 563.0 seconds on a loaded machine.
The compiler-image test reaches byte identity at 7,374,387
bytes and exercises its source fixtures on both interpreters and the JIT under
collector verification. The root CLI and launcher follow below; release
bootstrap packaging remains separate migration work.

`corpus-classification.json` preserves the P0 classifications. `corpus-smoke.py`
emits unchanged Lua suites and their checked Nupp dependencies on the VM, then
runs each suite in a fresh VM process and records every result. It rejects image
construction failures, failed cases, unavailable capabilities, and incomplete
results. The initial 2026-10-12 run covered all 100 portable test suites:
45 passed, 54 failed, and one timed out. It reported 742 passing case or hook
results, 297 failures, and one unavailable capability. The baseline also
contains three portable helper modules, 117 suites requiring ports, 32 retired
entries, and three harness entries. The current
[coverage inventory](tests/corpus-coverage.json) supersedes those execution results.

Run the corpus with the compiler and root CLI images:

```sh
python3 native/crates/vm/tests/corpus-smoke.py compiler.image \
  --cli-image root.image --gc-interleave --output /tmp/vm-corpus \
  --unavailable-module nupp.runtime.provider.nativetls
```

The remaining flag leaves TLS unresolved, so affected suites fail. The math,
checksum, CLI, and fixture ports below remove dependencies from the initial
run. The complete gate requires resolving TLS, porting surviving tests, and
passing the corpus under collector verification. Runtime workers and compiled
suspension already exist; remaining failures include library routing, source
lowering, test assumptions, documentation dependencies, and compilation timeouts.

## Public time, suspension, and tasks (2026-10-13)

The VM uses the public task-scope implementation and shares suspension and
timer logic with the native provider. VM adapters supply monotonic and wall
clocks, coroutine storage, captured-resource cleanup, and worker completion.

```sh
python3 native/crates/vm/tests/corpus-smoke.py compiler.image \
  --suite timetest --suite taskstest --suite taskfailuretest --suite suspensiontest \
  --engine jit --gc-interleave --jobs 1 --output /tmp/vm-concurrency
python3 native/crates/vm/tests/tasks-smoke.py compiler.image
```

The corpus driver accepts `rust`, `threaded`, and `jit` engines. `--image`
reuses the emitted corpus for another engine. All 118 cases in these four suites
pass on all three engines; `tests/concurrency-coverage.json` records the image
hashes and results. Their gate is separate from the full corpus inventory above.
The JIT corpus run compiles frames before entering the timed tests. Cold JIT
compilation and full collection on every allocation can consume the suites'
5 ms deadlines before a child starts. Incremental collection runs at every
allocation with the root oracle and quarantine enabled. The task smoke test
separately exercises on-demand JIT with full collection at every allocation.

The VM links `src/nupp/tasks.nupp` under a private module name, preserving its
public nominal identity for the checker's call and ownership rules. Scoped
`fork` polls existing VM workers through a suspension source. Completed workers
leave the live registry, and failures and cancellation settle through the public
scope's existing rules. The broader `nupp.workers` facade still needs migration.

Suspension state belongs to VM coroutine objects, so it persists with them and
does not depend on weak-table support. Checkpoints store the monotonic reading
and restore its remaining intervals; offline time does not consume a deadline.
Wall time continues to report Unix milliseconds. The task smoke test restores
a parked scope, child timer, and installed handler after an offline interval
longer than the scope's timeout, then completes under JIT and collector stress.

Corpus coverage exposed return-pack lowering and numeric equality gaps. Trailing
calls expand inside table constructors, protected calls forward trailing
varargs, and `return ...` forwards the result pack. Both interpreters and the
compiled path compare NaN and signed zero numerically. Table maximum-index
queries and `__tostring` support preserve the existing test and failure formats.
Open-ended trailing call spreads still use an eight-value window.

The task smoke test also checks worker failures and deadlines, channels,
coroutines, generators, affine cleanup, and cancellation before a captured
closure starts. Full CLI migration, remaining host services, and the broader
corpus gate remain open.

## Exact integers and shared math (2026-10-13)

The VM preserves signed and unsigned 64-bit integers across dynamic values,
table keys, collection, workers, binary graphs, and checkpoints. Public
`nupp.math` operations and function aliases use the shared math implementation.

```sh
python3 native/crates/vm/tests/numeric-smoke.py compiler.image --output /tmp/vm-numeric
NUPP_VM_BUILD_PROFILE=release sh native/crates/vm/tests/no-jit-smoke.sh \
  /tmp/vm-numeric/numeric.image demo.numeric run
cargo build -p nupp-vm --release
python3 native/crates/vm/tests/corpus-smoke.py compiler.image \
  --suite quaterniontest --engine jit --jit-compilation on-demand \
  --gc-interleave --output /tmp/vm-quaternion
```

An integer a double represents exactly remains immediate. Other values use a
weakly interned box carrying the complete bits and signedness. `IBox` preserves
signed integer registers; wide constants and operations preserve unsigned
values. Runtime kind tests inspect the boxed kind, and numeric comparisons and
table keys use the exact magnitude. `as` assertions erase; they preserve the
operand, including nil type witnesses. Explicit conversion to `number` through
`tonumber` can round. The collector drops unused boxes, and persistence preserves
live ones.

The lowerer consumes the checker's resolved numeric types, fixed-width
arithmetic annotations, type-test targets, and namespace identities. Ordinary
`int32` and `uint32` arithmetic wraps. Direct and indirect calls agree for
64-bit bit operations, deterministic `f32.exp`, and half-precision conversions;
local bindings named `nupp` retain their own meaning. The shared math module
supplies the remaining library operations, including quaternion functions.

All 23 unchanged quaternion cases pass on both interpreters and on-demand JIT
with incremental collection, the root oracle, and quarantine. Its nine-value
basis result exposed truncation: fixed tuples now retain up to 127 explicit
results, including protected calls. Tests cover larger builtin result packs,
parked tuples, and checkpoint restore. Open-ended trailing call spreads still
reserve eight result slots, and leaf compilation still refuses functions with
more than eight parameters.

The numeric fixture passes both interpreters, leaf JIT, compiled frames, and
host-native AOT with executable memory denied. AOT checkpoint restore also
passes. The VM compiler reaches byte identity at 7,573,844 bytes.
`tests/numeric-coverage.json` records the acceptance evidence and limitations.

Eager frame compilation of the larger corpus image exceeded 600 seconds before
any test ran. A stack sample located the work in Cranelift register allocation;
the default on-demand JIT completes the quaternion suite. This startup limit
remains open. Typed slot widths, complete integer register lowering,
primitive-wrapper removal, and the full corpus gate also remain open. The
historical coverage inventory above predates this math port; the storage
adapter below advances `utilstoretest` to its next provider dependency.

## Managed native storage (2026-10-13)

The VM serves `nupp.runtime.provider.nativestorage` with managed byte owners and
bounded views. Public scalar arrays and spans retain native byte order and
scalar widths without storing process addresses.

```sh
python3 native/crates/vm/tests/storage-smoke.py compiler.image --output /tmp/vm-storage
FRAME_AOT=1 NUPP_VM_BUILD_PROFILE=release sh native/crates/vm/tests/no-jit-smoke.sh \
  /tmp/vm-storage/storage.image nupp.tests.vmstorage run
cargo build -p nupp-vm --release
cargo test -p nupp-vm --release --test storage
```

The adapter supplies zeroed allocation, scalar codecs, byte copies and fills,
array descriptors, nested arrays, and pointer arithmetic within an owner.
Copies permit overlapping ranges. String and cast views are read-only. Reads,
writes, and requested extents are checked; signed and unsigned 64-bit elements
retain their complete bits. Views keep their owners alive through collection.
Worker transfer copies owned bytes, and binary graphs and checkpoints preserve
shared views of an allocation.

The compiler consumes the checker's span adapters for indexed reads, writes,
and lengths. Out-of-line instance functions enter the record's method table.
Imported affine cleanup functions use their declaration identities; local
cleanup functions keep their lexical bindings. `as` assertions erase, including
the library's nil scalar witnesses.

Raw external C pointers, pointer-valued storage elements, physical struct and
bitfield layouts, and the actual Tecs storage migration remain open. The adapter
does not provide the optional `layout`, `reference`, or `structs` services.

The unchanged storage provider contract and the checked array/span fixture pass
both interpreters, leaf JIT, and compiled frames with incremental collection,
the root oracle, and quarantine. Native AOT compiles all 87 fixture functions
and passes with executable memory denied, full collector stress, and checkpoint
restore. The compiler image rebuilds byte-identically at 7,578,636 bytes.
`tests/storage-coverage.json` records these results. At that milestone,
`utilstoretest` stopped at the missing `nupp.runtime.provider.nativeuuid`.
The data services below close that dependency.

## UUIDs and checksums

The VM supplies UUID generation and resumable CRC checksums through shared Rust
implementations. Public checksum and digest APIs run with managed storage and
require no FFI provider in their image.

```sh
python3 native/crates/vm/tests/data-services-smoke.py compiler.image --output /tmp/vm-data
FRAME_AOT=1 NUPP_VM_BUILD_PROFILE=release sh native/crates/vm/tests/no-jit-smoke.sh \
  /tmp/vm-data/data.image nupp.tests.vmdata run
cargo build -p nupp-vm --release
python3 native/crates/vm/tests/corpus-smoke.py compiler.image \
  --suite digesttest --suite utilbitsettest --suite utilstoretest \
  --engine threaded --gc-interleave --output /tmp/vm-data-corpus
```

UUID v4 and v7 retain the existing provider contract. CRC32, CRC32C, CRC64-ECMA,
and CRC64-NVME keep resumable state and snapshots as exact `uint64` values;
Adler32 uses Nupp. Calls borrow bounded byte views without retaining pointers.
Worker calls, graph transfer, collection, and checkpoint restore preserve these
contracts. The bit module also exports its existing rotate, byte-swap, and hex
operations for public MD5, SHA1, SHA256, and SHA512 implementations.

Integration exposed three semantic gaps. Ordinary record reads now find methods
without adding them to raw fields or iteration. Sparse numeric table keys move
into the array once as it grows. Overloaded instance and static methods use the
checker's selected member name for both definitions and references.

The 2026-10-13 acceptance run passes all 48 digest, bitset, and store cases on
both interpreters under collector verification. The bitset suite now allocates
through public storage; the other two suites are unchanged. Another 13 unchanged
hash-stream and digest-boundary cases pass both interpreters, on-demand JIT, and
compiled frames. UUID, checksum, overload, and worker fixtures pass those four
modes with an empty `PATH`. Native AOT compiles all 651 fixture functions and
passes the focused service fixture with executable memory denied, full collector
stress, and checkpoint restore.

The on-demand JIT passes the 33 digest and bitset cases. Store-suite compilation
now finishes too: all 15 cases pass in 92.691 seconds, including incremental
collector verification. Its earlier build timed out after 600 seconds before
running a case. Generic compiled frames dispatch at transfer, suspension, and
backedge boundaries; an interpreter checkpoint between those entries resumes
interpreted until the next entry. Typed SIMD entries retain their guard checks.
`tests/store-jit-coverage.json` records the baseline and three successful runs. The complete classified
corpus acceptance gate remains open.

## Root CLI

Install a complete CLI image and runtime to make the repository launcher use
the VM by default. Child compiler processes inherit that exact installation.

```bash
./scripts/vm-cli install --runtime build/rust/target/release/nupp-vm \
  --image /absolute/path/root.image
./bin/nupp check --json
./scripts/vm-cli status
```

Installation verifies the image and its root help command, then atomically
selects an immutable generation under `.nupp/vm-cli`. Existing workers retain
their generation when another is installed, and `nupp clean` preserves the
installation. Source edits require explicitly rebuilding and installing a new
image; `status` reports source changes and verifies the artifact hashes. A
checkout without an installation uses the existing bootstrap. Release and
bootstrap distribution remain open.

An explicit image overrides the installed generation for one invocation:

```sh
NO_JIT=1 NUPP_VM_CLI_IMAGE=/absolute/path/root.image \
NUPP_VM_BINARY="$PWD/build/rust/target/release/nupp-vm" ./bin/nupp check --json

python3 native/crates/vm/tests/root-cli-smoke.py /absolute/path/root.image \
  --output /tmp/nupp-root-cli --luarocks /absolute/path/luarocks
```

Emit the image with `nupp.tools.vm.project.emit`, entry `nupp.tools.vm.root`,
and these dynamic modules: `nupp.compiler.hostservices`, `nupp.compiler.fs`,
`nupp.compiler.project.projectconfig`, `nupp.compiler.project.store`,
`nupp.compiler.project.fingerprint`, `nupp.compiler.hash`,
`nupp.compiler.project.preludecache`, and `nupp.runtime.provider.nativeprocess`.
The image carries the configured compiler resources, templates, and bundled
library declarations. Source loading and source environments run interpreted.

The acceptance driver derives its command inventory from the CLI registry;
all 100 cases across 26 commands pass. See
[root-cli-coverage.json](tests/root-cli-coverage.json) for the original command
coverage and [launcher-package-coverage.json](tests/launcher-package-coverage.json)
for default installation, worker inheritance and repository-check evidence.
It exercises checking and cache reuse, builds, execution, tasks, tests,
benchmarks, bytecode inspection, Markdown documentation, C import/export,
templates, package installation, LSP sessions, generator workers, comptime
workers, and parallel check workers. File output and subprocesses use native
host services. Compiler cache and worker payloads use a plain-data graph codec
that preserves shared identity and rejects executable values on decode.

This coverage does not establish VM release packaging, cross-platform binary
targets, LuaJIT profiling, HTML documentation dependencies, or acceptance of
the full classified corpus. Those gates remain open before deleting the old
toolchain. Supply provisioned host tools on `PATH` for commands that need them.

The 2026-10-14 classified corpus run reports 68 passing suites, 23 failures,
and nine timeouts out of 100 suites, with 1,143 passing case or hook results
and 67 failures. The [inventory](tests/corpus-coverage.json) records every suite,
the artifact hashes, and the image-version limitation. It uses incremental
collector steps, the root oracle, and quarantine. The native TLS provider is
the sole explicitly unresolved module. The Rust ABI suite passes after retrying
with local socket access; the sandbox had denied listener creation.

## SIMD on the VM (2026-10-13)

Three commits brought the public `nupp.simd` API to the VM: the managed
operations (`28559ede2`), their allocation and validation costs
(`19f6488f0`), and checked native kernels lowered straight to Cranelift
vector registers (`158897100`). This section records what they landed, the
review that followed, and what the review changed. `tests/simd-coverage.json`
and `tests/native-simd-coverage.json` hold the authors' own records;
`tests/simd-perf-results.json` and `tests/native-simd-perf-results.json`
the measurements.

**Where SIMD runs.** Only on the typed tier and through linked AOT objects.
A function containing a `Simd`, span or vector instruction is refused by the
Rust interpreter and the threaded core with "SIMD function requires native
compilation or a matching AOT entry", at entry when no compiled frame is
active and at the instruction otherwise. So a no-JIT product runs SIMD only
through objects emitted by `aot IMAGE OBJECT --frames`; `tests/simd-aot-smoke.sh`
checks that path with executable memory denied. Both Rust suites are gated on
the `jit` feature.

**Two representations.** Public `species`, `splat`, `load`, `+` and the rest
lower to one `Simd` instruction each; the typed tier prepares a 2 KB packet on
its native stack through a helper, runs the operation in registers
(`simd_jit.rs`), and boxes the result as a managed byte object unless the
value's whole lifetime stays in one straight-line region, in which case the
packet is the value (`local_values`). Kernels the checker proves closed,
scalar-span and helper-free take the second path: `nupp.compiler.vm.native`
reuses the checked native IR of the LLVM backend, emits `SpanLoad`,
`SpanStore` and `VOp` instructions, and the tier keeps vectors in registers
across the whole loop, with span pointers and counts validated once per
activation, bounds proved by range analysis, and tails masked before memory
is touched. Anything the adapter cannot express is refused and keeps the
managed path; an internal failure is a compile error, never a silent
fallback.

**Measured.** `bench/simd11` map and explicitMap, 65,539 elements, warm
process medians, nine forks of twenty-one repeats in alternating order, with
a paired bootstrap of the geometric-mean speedup and a 5% practical margin
(`tests/simd-perf-compare.py`). Controls replay the preserved LLVM and C
artifacts on the same host.

| path | explicitMap | map (scalar) |
| --- | ---: | ---: |
| managed, before the allocation work | 17.44 ms | 49.72 ms |
| managed, after (`19f6488f0`) | 8.53 ms | 37.24 ms |
| checked native kernel (`158897100`) | 0.0212 ms | 37.33 ms |
| LLVM backend | 0.0082 ms | |
| clang, vectorised | 0.0082 ms | |
| clang, scalar | 0.0153 ms | |

The native kernel is 2.6x LLVM and 1.4x scalar C on this map, in line with
the direct-lowering experiment of 2026-10-10 (2.1 to 2.5x). The scalar map
does not take the kernel path. At 63 elements the first call costs 3 to 5 ms
of compilation and the warm call is dominated by the call and span boundary.
Two caveats on the record: no LuaJIT control was taken, so the product
baseline is absent from these files; and the candidate binary of the second
run is identified by its SHA-256 only, not a commit, while the binaries and
control artifacts live under `/private/tmp/nupp-simd` and are not
reproducible from the repository. The protocol is sound; the provenance is
not, and the next measurement should record commits for both sides.

**Review and fixes (2026-10-13).** Three independent reads, of the runtime
semantics, the lowering soundness and the tests and measurements, found no
memory-safety or GC-rooting defect. The elision analysis, the once-per-
activation span validation inside the admitted subset, the tail masking, the
verifier operand classes, the deferred NaN normalisation and the budget poll
were each traced and hold. What was wrong, and is fixed here:

- A 64-bit lane scalar refused what the reference wraps: `splat(-1)` on a
  `uint64` species is `2^64 - 1` in Lua (`0ULL + value`) and raised here.
  `lane_bits` now uses the same wrapping conversion as wide arithmetic.
- A dot reducer took its lane count from the left operand only, so
  `dot:add(2.0, vector)` failed with "wrong species" although the type admits
  a scalar on either side.
- The field and SoA `load`/`store` overloads have no VM descriptor; they were
  refused with a misleading type error and now say the form is unsupported.
- Every `Simd` instruction allocated its own 2 KB packet slot, so a long
  generated kernel on a worker's 2 MiB stack could overflow it. Non-elided
  packets die at `j_simd_finish` and now share one slot per function; worker
  threads get 16 MiB.
- The native range analysis assumed storage counts fit `i32`, which held only
  because `storage::LIMIT` says so; the constant is now taken from there.
- `j_native_span`, `j_native_raise` and `j_native_bounds_error` did not
  publish a helper frame as the other helpers do; benign today, now uniform.
- A test named for GC moves was renamed: the collector does not move.
- The public fixture checks `widen` by converting through the widened
  species rather than reading `.lanes`, and covers the two fixed cases.

**Known limits, from the coverage records and the review.** Pure-helper
maps, transpose, generic element functions and struct and SoA field memory
are not lowered; the full SIMD matrix, all simd11 workloads and other
platforms have not run; vectors that escape a region are boxed; the typed
adapter accepts only closed scalar-span kernels with one result. Typed-native
functions are compiled with a host ISA at `opt_level=speed` rather than the
module's, which diverges only if object emission ever targets another
triple. A non-frame compile of a typed-native function would not root the
span owner across `IBox`; none exists today. Nothing in this section runs in
CI; the JSON records and the commands in them are the evidence.

```sh
cargo test --offline -p nupp-vm --test simd --test native_simd
python3 native/crates/vm/tests/simd-smoke.py COMPILER_IMAGE --output OUT
python3 native/crates/vm/tests/native-simd-smoke.py COMPILER_IMAGE --output OUT
CARGO_TARGET_DIR=build/rust/target sh native/crates/vm/tests/simd-aot-smoke.sh COMPILER_IMAGE OUT/simd.image OUT typed
```

### Kernel loop: branches, not instructions (2026-10-13)

The 65,539-element map ran 2.6x slower than LLVM and 1.4x slower than scalar
C after the native lowering landed, although the P1 prototype had matched
LLVM on the same map. The loop body was read from the generated assembly
and changed in four places, each measured alone:

- **Branch polarity.** Cranelift lays a conditional branch's `then` target
  after its `else` subtree, and the lowering emitted `JmpIfIZero` and
  `JmpIf` with the fall-through as `then`. Every loop iteration therefore
  took a branch into its own body and another back. The exit is now the
  taken target and the body falls through, and the budget poll's blocks are
  cold. This was the largest term, worth more than the instruction count
  suggested, because taken branches bound the loop on this core.
- **Budget poll.** The bounded-turn budget was charged in memory on every
  backedge: a load, a compare, a select, a store and two branches. A
  register now counts the remaining budget clamped to a chunk of 64
  (`BUDGET_CHUNK`) and the shared budget is charged once per chunk, so a
  turn still stops exactly where it did and the loop pays a decrement and
  a never-taken branch.
- **Invariant splats.** The adapter re-splatted `scale` and `bias` into
  vector registers at every use. A second translation pass now hoists the
  splat of a parameter to the prologue and reuses its registers.
- **Canonicalisation.** The NaN blend after a stored float result selected
  on not-equal, which needs a mask inversion; it selects on equal now.
  Hoisting the NaN splat out of the loop was tried two ways and the
  optimiser rematerialised it at each use both times, so it stays inline.

| explicitMap, 65,539 elements | before | after |
| --- | ---: | ---: |
| direct call, median of three processes of 21 | 17.6 us | 14.2 us |
| under the scheduler, paired nine forks of 21 | 21.1 us | 17.9 us (1.17x, interval 1.15 to 1.20) |
| LLVM backend (control, same run) | | 8.1 us |
| clang scalar (control, same run) | | 16.1 us |
| LuaJIT, the product's `nupp.simd` without `@aot` | | 8,430 us |

The direct call now beats scalar C. Two measured terms remain on the loop:
the canonical-NaN blend after every stored float packet costs 3 us here
(14.2 to 11.2 us with it off), and the chunked poll 2 us; with both off the
loop runs at 10.6 us, 1.3x LLVM, which does `ldp`/`stp` pairs over an
unrolled body. The blend is a contract choice, that storage never holds a
NaN payload so its bytes are the same on every platform, not a limit of
the backend; LuaJIT's own `species:store` keeps payloads. Dropping it is a
decision for the contracts document, recorded here with its price.

One caveat. The 63-element rows do not measure the kernel: a `sample` of that call shows
its 2 us in the untyped harness around it, span views created through
builtins resolved by name and hashed on each call, with the interpreter
running the wrapper. That is the builtin-dispatch cost already on the P5
list, not the kernel's.

The LuaJIT control is the first in these records. It ran the same
`kernels.nupp` under `./bin/nupp run` from a bench module with `os.clock`,
best of nine rounds; LuaJIT executes the explicit species as one-lane Lua,
which is why it is three orders slower than any native path. Results and
provenance, including the commit of each binary, are in
`tests/native-simd-loop-results.json`.

### SIMD on the interpreter (2026-10-13)

The interpreter and the threaded core refused any function containing a
vector instruction, so SIMD ran only on the typed tier and linked AOT: a
checkpoint taken inside a kernel could not resume in a no-JIT process, the
replay plan's interpreter stepping had a hole, and the Cranelift lowering had
no independent implementation to be checked against. `simd_exec.rs` is that
implementation: every packet operation `simd_jit::emit` lowers, executed one
lane at a time in plain Rust over the same `Packet`, plus the span loads and
stores, splats, extracts, prefix masks and `VAny` over the interpreter's
16-byte vector registers. `prepare` and `finish` are the typed tier's own
helpers, so validation, allocation and rooting are shared; only the lane
arithmetic is interpreted. The threaded core takes its slow path into the
same arms.

Semantics follow the lowering, not the Lua reference, so the two tiers can
be compared bit for bit: integers wrap at their width, `float` lanes compute
in binary32, `fmin`/`fmax` order the zeros and propagate NaN as Cranelift's
do, division by zero and the signed minimum over minus one take the typed
tier's corner rules, float-to-integer conversion truncates through int64
and zeroes invalid lanes, and float results the typed tier canonicalises
are canonicalised. `tests/simd.rs` now runs every case on both tiers in the
same VM and asserts identical result bytes or values, so the 19 cases that
were the typed tier's specification are now an agreement test; the first run
agreed everywhere. Both public-source smokes gained interpreter cases
(`NO_JIT=1`, including tasks and workers for the public fixture and
collector stress for the kernels), and the Rust loop runs both fixtures
under stress as well. The refusal test became an interpreter run with the
plugin's side effect observed.

Where it runs is a policy. A JIT-capable host under `NO_JIT=1` interprets
SIMD freely; that is the oracle and the developer path. A linked no-JIT
host keeps the plan's rule that an unmatched bytecode plugin is refused
before its first side effect rather than running a kernel a thousand times
slower without saying so, and interprets only with `SIMD_INTERPRET=1`; the
public AOT smoke checks both the refusal and the opt-in.

It is a correctness tier, not a fast one: the 65,539-element map takes
21 ms interpreted against 14 us compiled, because every span instruction
revalidates its span through the record's named fields. That cost is in
`storage::native_span`, not in the lane loop, and is the first thing to cut
if the interpreter path is ever on a hot path; LuaJIT's one-lane fallback
for the same kernel is 8.4 ms.

```sh
cargo test --offline -p nupp-vm --test simd
NO_JIT=1 python3 native/crates/vm/tests/simd-smoke.py COMPILER_IMAGE --output OUT
```

### Struct and SoA field access: what it waits on (2026-10-13)

The language's `load(span, at, field)` and `store` field forms, over a span
of structs (strided) or a `nupp.mem.soa` column (contiguous), are refused on
the VM by name. They are not a SIMD feature to add; they are the last
consumer of a storage representation the VM does not have yet. The chain,
in order:

1. **Struct descriptors in VM storage.** `storage::layout` knows scalars,
   pointers and arrays and refuses anything else, so `array.newArray` of a
   struct witness cannot allocate here. The descriptor needs fields with
   name, kind and offset, and the struct's size and alignment: contracts 2.9's
   layout record, the same item the entity ID plan puts first.
2. **`nupp.mem.soa` off the FFI.** The module is LuaJIT `ffi` over a slab
   with one column per top-level field. On the VM it is one scalar storage
   per field under one owner, with the row count shared; the view and the
   affine tokens are unchanged.
3. **The two SIMD forms.** A strided field load is the plain lane load with a
   row stride and a field offset in `storage::simd_access`; a SoA field load
   is the plain load on that field's column. Both are descriptor arguments
   `prepare` already parses, so the managed path is small once 1 and 2
   exist, and the adapter admits the span parameter it refuses today
   (`p.soa`, a field name in the memory operation).

Nothing in 3 is worth building before 1, and 1 is a contracts item, so this
is recorded here and in the runtime plan rather than started.

### Allocation experiments

The VM executable can select an allocator without changing an embedding
application's allocator. Candidates are opt-in and mutually exclusive:

```sh
cargo build --release -p nupp-vm --features allocator-mimalloc
cargo build --release -p nupp-vm --features allocator-jemalloc
```

The default remains the system allocator. The experiment features admit
aarch64 and x86_64 macOS and GNU Linux; a successful local build establishes
only the host tested. The shared executable module also selects the allocator
for the persistence, compiler-checkpoint, and scheduler examples. Rust
integration test executables do not inherit the VM executable's allocator.
`tests/allocator-host-smoke.sh` builds an independent Rust application that
declares its own allocator and checks repeated graph, worker, channel, and
checkpoint teardown under all three dependency configurations.

Build candidates serially in the shared Cargo target directory and copy each
binary before the next build overwrites it. With identical pre-emitted images,
run the paired harness from the repository root:

```sh
python3 native/crates/vm/tests/allocation-perf.py SYSTEM CANDIDATE \
  --check-image CHECK_IMAGE --parser-image PARSER_IMAGE \
  --cli-image ROOT_IMAGE --tasks-image TASK_PERF_IMAGE --output NEW_DIRECTORY
```

The harness alternates seven independent process pairs and retains checksums,
binary/input hashes, raw output, first-call costs, warm medians, process wall
time, and peak RSS. Its paired bootstrap uses process pairs, with a 5% practical
margin. `--case` selects workloads. `--repository-only --cli-image ROOT_IMAGE`
runs one cold and warm repository check per binary with separate fresh caches.
It moves the existing project cache (`build/cache`, or `--project-cache`) into
the output directory, creates a fresh cache, and restores the original entry
after each binary, including on failure. Generated caches and a recovery journal
remain in the output directory. Original symlinks are preserved without following
them. The cache and output must be on the same filesystem and must not overlap.
Shared prelude caches use a separate fresh `NUPP_CACHE_DIR`. These runs establish
acceptance, with no duration verdict. Run measurements on an otherwise quiet
machine after builds and correctness tests finish. Keep other compiler commands
out of the worktree while its project cache is isolated.

For separate diagnostic processes, build with `allocation-metrics` and set
`NUPP_ALLOCATION_STATS=1`, or give diagnostic binaries to the harness with
`--diagnostics-only`. Normal builds contain no allocation instrumentation.
Heap reports distinguish construction, observed payload changes, GC
reclamation, and the final allocated-object snapshot. Changes observed through
capacity accounting and pointer refresh are not every native store. GC work
counts roots, scanned objects, child slots, occupied sweep objects, and all
visited sweep slots. Worker heaps report distinct IDs on teardown; the CLI
flushes before its process exit, which skips VM teardown.

Global reports count successful Rust allocator requests, including diagnostic
bookkeeping. They exclude direct C allocation and allocator-retained pages;
requested live bytes are not RSS. Heap byte counters distinguish object sizes,
rounded assigned slots, acquired chunks, and positive external-capacity deltas.
Use a separate process with `NUPP_ALLOCATION_STATS=global` for global request
totals with heap bookkeeping disabled; its report records that mode explicitly.
An embedding thread can destroy its diagnostic registry before its VM; its
final report marks that condition and still includes the live snapshot.


### Relocatable compiler AOT

The compiler image can run from linked native functions without Cranelift in the
runtime. Emit the object once, then build the runtime with that object:

```sh
cargo build --release -p nupp-vm --features aot --offline
build/rust/target/release/nupp-vm aot COMPILER_IMAGE /tmp/compiler.o --frames
NUPP_AOT_OBJECT=/tmp/compiler.o cargo build --release -p nupp-vm \
  --no-default-features --features aot-linked,c-headers --offline
python3 native/crates/vm/tests/compiler-aot-smoke.py COMPILER_IMAGE \
  --binary build/rust/target/release/nupp-vm --manifest /tmp/compiler.o.manifest \
  --frames --output /tmp/compiler-aot-acceptance
```

`nupp_vm_runtime_v3` supplies the executing VM's address table. It refreshes
addresses after dynamic image loading grows the function and shape tables.
Field caches belong to each VM's loaded functions; native objects contain no
shared mutable field-cache storage, and JIT teardown no longer leaks those
cache allocations. Workers and restored VMs start with independent caches.
Objects using the previous binding ABI must be emitted again.

The acceptance driver checks every manifest entry, rejects mismatched images,
compares compiler output across fresh processes against the interpreter, runs
the emitted program, and compares invalid-source diagnostics. On macOS it
verifies that both executable mappings and write-to-execute protection changes
are denied before running the compiler under the same denial. It requires all
functions in a frame object to compile and checks that Cranelift symbols are
absent. This is host-native acceptance; platform packaging and console targets
have separate gates.

### Unsigned registers

`UUnbox` checks the unsigned range before moving a dynamic value into a raw
64-bit register. `UBox` preserves every bit when returning to a dynamic value,
using the existing immediate-or-interned representation.

The lowerer emits raw unsigned addition, subtraction, and bitwise operations
for checked unsigned-producing expressions. Names and erased casts keep their
existing helper behavior, including truncation and wrapping of operands;
a type assertion alone does not change their runtime representation. Tests
cover both interpreters, native entries and frames, numeric keys, worker
transfer, graph persistence, and parked-register checkpoints. Ordinary
`integer` semantics and general propagation through typed locals remain open.


### Supervised VM replacement

`nupp.vm` exposes host-driven game handles over the existing worker VM runtime.
The supervisor owns checkpoint bytes and routing generations outside the game.

```sh
python3 native/crates/vm/tests/supervision-smoke.py COMPILER_IMAGE \
  --binary build/rust/target/release/nupp-vm --output /tmp/supervision.json
```

`spawn` returns an affine game owner. Its `capture`, `prepareRestore`, `replace`,
and `fork` operations reuse worker graph transfer and whole-VM persistence.
Preparation quiesces the old game and its descendants, reconstructs and validates
the candidate without running gameplay, and keeps the old game paused until
commit or discard. Failed preparation leaves the old game available. Replacing
consumes the candidate and advances a generation that never rewinds; `step` and
`poll` reject retired generations. Retirement errors are reported after
publication and do not undo the replacement.

Native entries are rebound only when the checkpoint preserves the original
code recipe prefix, including descendants. Appending code preserves earlier
function IDs and remains compatible with later capture and rewind. Changing
that prefix requires explicit migration. Native handle identity is checked
against its registry owner, and live supervision owners prevent capturing the
supervisor itself. Closing or dropping the owner retires its worker threads.

The synthetic fixture checks transactions on 10,000 two-field entity records
and measures full checkpoint capture. Its timing report records background-load
limits; it is not the Tecs snapshot benchmark. Self-capture/self-replacement,
resource restoration policies, direct host event rebinding, incremental history,
and launcher supervision remain separate work.

Capture and result bytes use ordinary uninterned strings. String equality,
table-key lookup, persistence, and collection preserve their normal behavior;
capture avoids hashing the full binary payload into the weak intern table.
Compare frozen runtimes with interleaved fresh processes:

```sh
python3 native/crates/vm/tests/capture-perf.py --baseline BASELINE_RUNTIME \
  --candidate CANDIDATE_RUNTIME --image SUPERVISION_IMAGE \
  --forks 5 --output /tmp/capture-comparison.json
```

The report retains all 101 captures in each process, including the first, and
compares process-level p99 values in pairs. `capture-coverage.json` records an
observed p99 reduction from about 4.8 ms to 1.59–1.67 ms across three execution
modes. Background load makes the measurements provisional; they do not close
the live-game capture gate.

### Struct layout queries

`NativeStorage.layout` returns compiler layout facts for a struct declaration or
instance. The VM image records the manifest's explicit `layoutTarget`:

```lua
return {
  include = {"src"},
  build = {entries = {"main"}, layoutTarget = "aarch64-apple-darwin"}
}
```

The descriptor includes target, ABI, canonical declaration identity, size,
alignment, fields, offsets, and a fingerprint that distinguishes scalar kinds
and same-named declarations. Scalars, fixed arrays, and nested plain structs
use the checker's resolved types and the compiler's target layout rules. Missing
targets and layouts containing managed references, pointers, bitfields, recursive
values, generic structs, or C aggregates report an error when queried.
Ordinary values without layout metadata return `nil`.

These facts describe the declared ABI. Struct instances still use boxed record
storage; the descriptor does not enable physical struct allocation or bounded
native row references. Checked bitfield widths survive interface caching, so
unsupported packed fields cannot become ordinary layouts after a reload.
The Tecs snapshot benchmark requires those operations and its native declaration
graph before its full acceptance gate can run.

The copied Tecs entity-column module replaces FFI allocation with managed
binary64 storage while retaining its count in slot zero and its indexing,
resize, and clear behavior. `tecs-storage-coverage.json` records 10,000 IDs,
exact values through `2^53 - 1`, and persistence preserving shared views across
Rust, threaded, and JIT execution under GC stress. Its original MIT license,
source hash, and adaptation patch accompany the fixture.

That integration exposed missing `__len` dispatch. Tables and records now call
the metamethod across all execution tiers, preserve arbitrary first results,
and keep native caller roots alive during callbacks. Numeric length operations
convert the result through the existing numeric rules. Linked AOT tests cover
the new helpers with executable memory denied and checkpoint restoration; the
old raw-length helper ABI remains available to existing objects.

The actual Tecs snapshot source graph currently stops at the `cdefFunc` in
`tecs.internal.assetnative`. The reproducible admission harness records that
failure separately from the entity-column acceptance. Physical struct rows and
the snapshot codec migration remain open.

## The one-shot, measured on the CLI (2026-10-14)

The number the relocatable compiler AOT was built for: a warm `nupp check` of
`src/nupp/compiler/syntax/lexer.nupp` through the installed launcher, against
LuaJIT's launcher on the same source in the main checkout. Wall time, three
runs each, this host under its usual background load.

| launcher | lexer.nupp | whole repository |
| --- | ---: | ---: |
| LuaJIT (main checkout) | 0.43 s | 0.80 s |
| VM, packaged interpreter, before this pass | 1.78 s | |
| VM, linked compiler AOT, before this pass | 1.60 s | |
| VM, linked, after this pass | 0.89 s | 1.19 s |
| VM, JIT on demand (for the record) | 44 s | |

Loading the 21 MB root image is 0.15 s of that; the rest was runtime glue
and the compiler's own cache path, not the checker, which runs in a quarter
of the time on its own. Three findings closed half the gap:

- **Builtin dispatch compared strings.** Every builtin call ran about 45
  name comparisons, one of them a linear `id_of` search over the whole
  builtin table, before reaching the `match` on its id. The classification is
  now computed once per id into a table; the same branches run from a
  single lookup. 1.78 to 1.47 s interpreted, 1.60 to 1.32 s linked.
- **The content digest ran in Nupp on the VM.** `nupp.compiler.hash.digest`
  is XXH64 under two seeds emulated over 32-bit halves, 6 MB/s. The VM has
  installed `nupp.compiler.nativehash` over `nupp_native_platform::cache_digest`
  since the CLI landed, byte-identical, but the prelude cache sealed and
  unsealed through the portable spelling. `hash.digest` now resolves the
  native module once and uses it where the host provides it, the pattern
  `fingerprint.contentDigest` already used; the portable compiler is
  unchanged. With the prelude cache's array validation also dropping a
  per-key dynamic call, 1.32 to 0.89 s linked.
- **With the JIT on, the CLI is unusable at 44 s**, because on-demand frame
  compilation reaches most of the compiler on a check. The packaged launcher
  already disables it; the linked runtime is the deployment, and the
  installed package in this worktree is now that runtime with the new image.

What remains, from the repository-check profile: the `stable` encoder of
cache records (number formatting, concatenation and pattern matching, a
fifth of the run), re-reading every source to validate the cache (file reads
and string construction, another fifth), and the dynamic call transfer
through the frame driver, which is lane 2's direct-call item. Each is a few
percent; none is the checker.

## Insertion-ordered tables (2026-10-14)

Tables hashed keys by their value bits, the address for an object or an
interned string, and `pairs` walked the slots in that order, so a program's
iteration order changed between runs, between platforms, and after a restore
rebuilt the hash from relocated keys. Replay from a checkpoint could not
reproduce any `pairs` loop. Contracts 2.13 now says iteration order is
insertion order and never address order.

The representation keeps every inline probe untouched: the open-addressed
`(key, value)` slots the C core and the typed tier read in place are
unchanged, and two side arrays record the order, `order` listing slot
indices by first insertion and `rank` giving each slot its position. `iter`,
`pairs`, `next` and the serialiser walk `order`; a key whose value is set to
nil keeps its place until the next growth drops it, and growth reinserts
the live entries in order, so the order a program sees is a function of its
operation sequence alone. `next` gets an `O(1)` continuation through `rank`.
The C core's hardcoded metatable offset moved with the payload.

Cost: 8 bytes per slot. Measured on the linked CLI, alternating five pairs
on the lexer check and three on the repository check, the difference is
inside the run-to-run noise: 0.91 against 0.92 s and 1.18 against 1.19 s.
Tests: the randomised map comparison and churn bound still hold; a new
case checks scrambled insertion, a nil-then-reset key, growth, and `next`;
a persistence case checks a restored table iterates in the original order
although every key object has a new address.

A stable per-object serial for snapshot deltas (snapshot plan section 4) is
not part of this: it would need a header word the 32-byte layout does not
have, and insertion order alone is what replay and restore needed.

## Corpus fix-forward (2026-10-14)

The 32 corpus suites that did not pass were rerun on the corrected runtime
and a new root image; six now pass (74 of 100, 1159 passing cases against
1143). What moved them, and what the work found along the way:

- **Safe navigation** (`?.name`, `?.[key]`, `?.(args)`, `?.:m()`, `:m?.()`)
  had no VM lowering. The checker also refused `t?.[k]` on an optional
  table, because only `?.name` stripped nil from its receiver.
- **Missing builtins**: `os.exit` (the test runner's refusals exited 1, not
  2), `debug.traceback` (every `xpcall(f, debug.traceback)` answered "error
  in error handling"), and `files.lines` in the VM's `nupp.io.files`, with
  an `io.Reader` adapter because a Lua handle answers nil at the end where a
  reader answers `""`.
- **`os` and `io` are looked up at call time.** The lowering bound them as
  builtin constants, so a program that replaced `os.getenv` to substitute
  its environment was not observed. The pure libraries stay bound.
- **Image closure follows `@requires-dynamically`.** The component build
  loaded `nupp.tools.build.package` by computed name, and the image lacked it.
- **`tostring` was lossy on non-UTF-8 strings.** It answered U+FFFD, so
  the lowerer's constant key merged `"\128"` and `"\255"` into one constant
  in any function holding both, on a VM-hosted compile. `print` and `%s`
  shared the helper; all three are byte-exact now.
- **Smaller host gaps**: build tools read `jit.os` (absent on the VM; they
  ask the host target key now), the C type probe accepted tags the
  declarations never named (LuaJIT refuses them, and NUPP2304 went silent),
  `loadstring`'s literal fast path accepted a raw newline inside quotes,
  dynamic `simd.vectors` raised instead of answering nil, and VM `bc`
  reported a missing file as a tool failure instead of NUPP0001.
- **`nupp run` outside the checkout** compiles a `nupp.` module the image
  lacks from the checkout's sources, in the checkout's own environment;
  LuaJIT finds the compiled copies on `package.path`.

The root image was emitted under LuaJIT from the same sources and then
VM-hosted from that image: the two are byte-identical.

What remains, by cause:

| Cause | Suites |
| --- | --- |
| LuaJIT bytecode, trace and bootstrap assumptions | bctest, bootstraptest, lspclitest (bytecode artifact), jsonschematest (trace aborts) |
| C modules the VM cannot load (`ffi`; LPeg was here until it went native, below) | evalstest, preludecachetest, coveragetest, examplestest |
| Native providers not ported | jsonpolicytest, jsonfuseddifferentialtest, tlstest, workerstartuptest |
| Stub catalog not carried by the VM CLI | perfbudgettest (hello world), releasetest |
| Environment capabilities (wasm, node, Chromium) | three simdwasm suites |
| Timeouts under collector interleave | nine, including serdecontracttest and publicclitest |
| Other | referencetest (one example only under the corpus image), perfbudgettest (checker allocation per module 2.5 MB against 2 MB) |

Errors carry no `file:line:` prefix. Images hold no line table, and a
builtin does not see its caller's pc on every tier. That is the plan's
per-instruction debug info, next.

`TRACE_FAILURES=1` prints the frame chain of a scheduled task that fails,
and `AOT_VERBOSE=1` restores the linked-entry banner the CLI used to print
on every run.

## Source lines and error positions (2026-10-14)

Every function in an image now carries a line table: one source line per
instruction, run-length encoded on a `lines` line before the code
(`lines 12x4 13 15x2`; 0 where no line is known). The lowerer already kept
the statement line for the `bc` listing; it now records it always, and a
closure starts at its definition's line. The loader checks that the table
covers every instruction. Backtraces print `(line N)` from it.

`error(message, level)` names its position the way Lua does,
`chunk:line: message`, with Lua's short chunk names (a long path keeps its
last 56 bytes behind `...`; `=name` is printed as written). A builtin does
not see its caller's pc on every tier, so the lowering passes the call's
line itself: `error(...)` becomes `error.site(error, line, message, level)`.
The callee is still the one the program names, so a replaced `error` is
called as written; level 0 adds nothing; level 2 reads the caller's saved
pc from the frame chain and its line from the table. Each function also
records its image's source path, since every loaded chunk shares the
module name `vm.chunk`.

`loadfile` now names its chunk `@path`, as Lua does, so `nupp run` on the
VM prints `err.lua:3: negative input` exactly as the LuaJIT host does. The
tables add 758 KB (3.6%) to the root image; the image emitted under
LuaJIT and the one the VM emits from it remain byte-identical, and the
linked CLI's `check` is unchanged (0.92 s warm).

Two gaps remain. Level 2 answers without a position when the caller is
compiled (JIT or linked AOT keep no frame chain), and the VM's own runtime
errors (`index of a non-table`) carry its function and pc rather than a
source position and Lua's wording.

## Native LPeg (2026-10-14)

`require("lpeg")` answers LPeg 1.1.0 implemented in `src/lpeg.rs`, so the
`peg` runtime, `re` and Scintillua run on the VM with no C module. It is a
port of the reference sources (lptree.c, lpcode.c, lpvm.c, lpcap.c): the same
trees, optimizations, instruction set, bounded backtrack stack
(`setmaxstack`, "backtrack stack overflow"), capture semantics and error
texts. Instructions take one slot with absolute jump targets and charsets
are full 256-bit sets; neither changes a result. Matching runs on an
explicit stack, so a deep subject never recurses in Rust; capture values
live on the handle stack exactly where LPeg keeps them on the Lua stack, and
are rooted there.

A pattern is a userdata, the heap's new kind 10: a metatable, a user value
(the pattern's ktable) and Rust data the collector drops with it.
`type(p)` is `"userdata"`, its methods come through `__index`, and the
arithmetic opcodes now dispatch `__mul`, `__div`, `__mod`, `__pow`, `__unm`
and `__len` the way `__add` and `__sub` already did. Persisting a pattern
is refused as an unsupported object kind.

`lpeg` is installed in `package.loaded` by `install_globals`; `re` is the
bundled `src/re.nupp`, which the CLI image carries and which requires
`lpeg` like any module. Unlike LuaJIT's `luaopen_lpeg`, requiring it sets
no global `lpeg` (Scintillua sets its own).

`tests/lpeg.rs` runs representative test.lua cases through the builtins
under every collector verification mode and the operators from bytecode on
each tier. `tests/lpeg-differential.lua` prints 160 checks and a thousand
random patterns against ten subjects; its output under LuaJIT with the C
module and under the VM is identical. LPeg's own test.lua passes on the VM
once five VM gaps unrelated to LPeg are worked around in a copy (seven
edits): a call delivers at most 128 results, `string.char` and `math.sin` do
not coerce numeric strings, and there are no weak tables and no
`os.setlocale`.

Measured on a linked AOT CLI against LuaJIT's C module: scanning 0.8 MB
1.0 ms against 1.1, splitting it into a 120 000-entry table 6.8 ms against
5.4, a `Cs` substitution over it 10.5 ms against 8.9, and a 1.7 MB JSON
grammar with folds and table captures 34 ms against 33.
