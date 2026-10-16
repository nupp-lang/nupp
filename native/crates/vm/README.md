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
| `heap` | the fixed 32-byte header, inline payloads, size-classed chunks, large objects, the incremental tri-color collector with stress, interleaved, quarantine and oracle modes, shapes, the weak intern table |
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
call and return path in C, with specialized helpers for field reads,
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
  the shared `seen` set skipped them when their own function was analyzed,
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
  path normalizes the count from `last_nres`. `PadResults` after a call that
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
verifier's optimization for the proven fifth.

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
- **The optimizer and the IR verifier bought nothing here.** `opt_level=none`
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
Binary graphs and checkpoints preserve shared views of an allocation. Worker
transfer copied owned bytes until "Memory across workers" below: shared
blocks now cross by reference and heap arrays move.

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
installation. `bin/nupp` rebuilds and installs a new generation itself when a
compiler source is newer than the stamp the last install left (see "The
launcher rebuilds the VM CLI" below); `status` reports source changes and
verifies the artifact hashes. A checkout without an installation uses the
existing bootstrap. Release and bootstrap distribution remain open.

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
verifier operand classes, the deferred NaN normalization and the budget poll
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
  optimizer rematerialized it at each use both times, so it stays inline.

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
  --no-default-features --features aot-linked,c-headers,native-ffi,compression,net,http --offline
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
`pairs`, `next` and the serializer walk `order`; a key whose value is set to
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

## Runtime semantics LuaJIT programs rely on (2026-10-15)

Six gaps the serde contracts and ordinary Lua programs ran into, closed in
the runtime rather than worked around in the programs.

**Weak tables.** A table whose metatable names `__mode` is scanned weakly:
the collector marks its metatable, its strong side and every string or boxed
integer in it (Lua treats those as values), remembers the table, and when
marking ends, before the sweep, clears each entry whose weak side is still
white. A key keeps its slot with a nil value, as any key set to nil does
here. No ephemerons, as in LuaJIT. A metatable a constructor built as a
record names its mode in a slot, so `{__mode = "k"}` in a typed module works
too. The serde cache-scope contracts then still failed, for a VM reason:
registers are not reused across temporaries and a new frame does not clear
its window, so a dropped value stayed reachable from a dead register for the
life of the function. An explicit `collectgarbage("collect")` therefore first
nils every value register the liveness pass says no instruction reads again,
in each frame of the calling task. Each frame's saved pc is exact there (both
interpreters note it before anything reaches Rust, and every call saves its
caller's); a compiled ordinary caller has no frame and clears nothing.
Automatic collection is unchanged and stays conservative.

**`string.buffer`** is native (`src/strbuf.rs`): the FIFO buffer userdata
with `put`, `putf`, `get`, `tostring`, `reset`, `free`, `skip`, `set`,
`encode`, `decode`, `#`, `tostring()` and `..`, and module `new`, `encode`
and `decode`. The serializer reads and writes LuaJIT 2.1's bytes (checked
against LuaJIT's own output), so either runtime decodes what the other wrote;
a table's array part is written from index 1 and its hash part in insertion
order, and exact 64-bit integers use the int64/uint64 tags LuaJIT gives
cdata. Error messages are LuaJIT's. Refused: the FFI pointer methods (`ref`,
`reserve`, `commit`, `putcdata`), serialization dictionaries, and
lightuserdata tags on decode. The VM's `text.buffer` provider is this buffer
now, and `nupp.serde.native` asks for `string.buffer` rather than for LuaJIT.
Concatenation dispatches `__concat`.

**Suspending inside `pcall`.** The PCall opcode already left a protected
record a park could cross, but a Lua chunk reaches `pcall` as a global, so
its calls went through the builtin, which runs the callee on a scratch task
that cannot park: `time.sleep` inside `pcall` in a spawned task blocked the
process. Under the frame driver a dynamic call of the `pcall` or `xpcall`
builtin now takes the opcode's path. xpcall's handler rides in the protected
record, rooted with it; a checkpoint writes it after the record, flagged by
bit 31 of the caller word, so older checkpoints read unchanged. The handler
runs at the raise, before cleanups unwind. `pcall(pcall, f)` still nests on
the builtin: two records over one callee frame could not settle in order.

**Metatables.** `getmetatable` answers a record's declaration (kept on its
shape, `\0nupp:recordType`) when the record has none of its own, and a
metatable's `__metatable` in its place; the lowering's inline fallback is
gone, since Lua chunks never reached it. Strings share a metatable whose
`__index` is the string library, so a function a program adds to `string` is
a method. A record's methods dispatch through its shape, but a program can
replace one on the declaration (a contract wraps one to count calls): the
declaration is marked when a shape names it, and a store to it replaces the
method the shape dispatches.

**Runtime errors** read as LuaJIT's, positioned from the line table:
`errors.lua:7: attempt to index field 'a' (a nil value)`, and the same for
calls, arithmetic, concatenation, length and comparison; a nil or NaN table
key raises. An operand is named when the instruction that loaded it, on the
same source line, was a global or field read or a method lookup. Images carry
no local or upvalue names, so those read "a nil value", LuaJIT's unnamed form.
Arithmetic converts numeric strings. A frame running compiled code has no
exact pc between boundary operations, so its errors carry no position rather
than a wrong one. Library argument errors still carry the `runtime error:`
prefix.

Not done: `error(msg, 2)` positions under an ordinary compiled caller. The CLI
runs every image through frame entries, where the caller's frame and pc
exist and level 2 already answers as LuaJIT does; only the unscheduled
`nupp-vm run` path uses ordinary entries, and naming its callers needs
return-address to pc maps in the code maps. `workerstartuptest` exercises
LuaJIT's `nupp.workers.native` C module directly; the VM's workers are its
own (`scope:fork`), so the suite is LuaJIT-host specific like `bctest`.

The serde contracts that failed on these, `codec_cache_scope.lua`,
`document_cache_scope.lua`, `debug_scope.lua`, `native_scope.lua`,
`transport_scope.lua`, `native.nupp`, `native_owned.nupp` and
`ergonomics.nupp`, pass on a linked runtime with a root image from these
sources.

Tests: `tests/weak_tables.rs`, `string_buffer.rs`,
`protected_suspension.rs`, `getmetatable.rs` and `error_wording.rs`, under
collector stress on the Rust loop, the threaded core and scheduled frames.


## Program binaries (2026-10-15)

`nupp build` on the VM CLI writes a binary target as one file: the VM
runtime with the program's image appended. The container is the one
`docs/reference/distribution.md` already specifies for LuaJIT hosts, payload
then 48-byte trailer, with trailer flag bit 1 marking a VM program; the
payload is the entry module's name, a newline, and the image. The packager's
existing Mach-O handling (unsign, grow `__LINKEDIT`, ad hoc sign) applies
unchanged, and `payload::read` finds the trailer before the signature the
same way the LuaJIT host does, reading only the trailer and load commands.

An appended payload rather than a linked section or a per-program AOT link:
the runtime already loaded text images, the format and signing code existed,
and stamping costs no Cargo invocation per program. A hello world starts in
under 10 ms. Linking a program's AOT object stays compatible: the AOT check
hashes the loaded image, which is the appended one.

The runtime is `scripts/toolchain vm-runtime FACILITIES`: `aot-linked` and
`native-ffi` without Cranelift, fat LTO, stripped. Compression, networking
and HTTP (with the URL parser) are now crate features, on by default; the
build links the ones the image requires through `nupp.vm.compression`,
`nupp.vm.net`, `nupp.vm.http` and `nupp.vm.uri`. A hello world is
2,295,072 bytes; with networking and HTTP, 4.9 MB. The compiler's own linked
runtime must name `compression,net,http` explicitly now.

The program is its entry module's body, run on a scheduled task with the
arguments in `arg` (`arg[0]` the executable), exiting 0 when it returns and 1
with the message when it raises; `os.exit` sets any other status. Module
paths in a program image are relative to the project or the compiler
checkout, so two builds of one tree are byte-identical. Resources ride as an
unchecked `nupp.embedded` data module, as the root CLI's do.

Open: functions with vector instructions still need a linked AOT entry or
`SIMD_INTERPRET=1`, so a SIMD program needs the per-program AOT link above;
cross-platform targets still read the LuaJIT stub catalog; a module-level
`...` does not lower, so the arguments arrive only through `arg`.

## Corpus after the lane merges (2026-10-15)

84 of the 88 portable suites pass (1,178 passing cases, 3 failing), every
suite under incremental collector steps, the root oracle and quarantine.
The portable set shrank from 100: the LuaJIT-era deletion removed twenty
suites outright, `workerstartuptest` tests LuaJIT's C worker module, and
`tlstest` loads generated Lua through `providerstate` like the other
port-required provider suites. What the merges and the fix-forward found:

- **Weak tables are ephemerons.** The collector first marked a weak
  table's strong side whatever became of the weak one, so a value pointing
  back at its dead weak key, or the object key of a dead weak value,
  outlived the entry the cycle dropped. The exact oracle refused that
  floating garbage in 53 suites. An entry's sides are now marked only once
  every weak side survives, revisited to a fixpoint when marking drains.
- **String constants are decoded by the lexer.** The VM lowering decoded a
  quoted literal with `loadstring("return " .. raw)`, which on the VM
  compiles a chunk holding the same literal: one the Rust fast path could
  not read, such as a CR line continuation, recursed until killed.
- **`load` and `loadfile` take LuaJIT's `mode` and `env`.** Scintillua's
  lexers load each other with an environment and found no `lexer` global.
- **A compiler running from `src`** finds the files a build would carry
  beside it (`nupp.compiler.bundled`), so a corpus image's checker no longer
  types `nupp.mem.span` as unknown.
- **The fused JSON scan read before its source.** Its first block's
  previous vector was loaded from offset `1 - lanes`, which the LLVM backend
  answered with zeros and `species:load` never promised; the VM refuses it.
- **Shape identities carry no control bytes.** A runtime declaration key
  separates its parts with NUL, and a `<chunk>` declaration has no module;
  both had reached the image's `identity=` token and broke the emitter's
  JSON.
- The harness now gives suites the development rock tree and carries the
  `@aot` check's backend, which the check loads by name outside the module
  graph.

Open: `lspclitest` and `preludecachetest` exercise the Lua generator's
artifacts and LuaJIT's FFI prelude arena, and move with the tools lane;
`examplestest` and `serdecontracttest` time out on compile cost under
collector stress, the serde contracts recompiling the serde modules from
source in every child process.

## Runtime-compiled modules are kept (2026-10-15)

`nupp run` on the VM compiles every module the root image does not carry --
the standard library's own modules among them -- from source, in every
process. The serde contracts spent four minutes per program on that.
`compile.image` now keeps each image in `nupp.compiler.vm.imagecache`, one
sealed `nupp.compiler.project.store` value per module under
`<cache>/vm-images`, where the cache is `NUPP_CACHE_DIR` or the environment's
own build cache: the compiler checkout's for standard and VM-library modules,
so every project using that checkout shares them.

- **Key**: the module's bytes, path and load name, and what about its
  environment is not a file -- roots, type roots, the manifest's value and
  text, the layout target, `PWD` and `EMIT_STUBS`, which lowering reads.
- **Stamp**: the checker and lowering code and the carried declarations.
- **Recorded and compared on the way back in**: every module the environment
  had loaded when the check finished, by resolved path and bytes; every name
  the carried modules were asked for and what it resolves to; and the project
  index's inputs (`envMod.projectDigest`), which a check consults whenever it
  asks whether a module is internal. The VM library and its declarations are
  covered by these: the library is a root of the environment its overrides
  are checked in, and a declaration they reach is a loaded module.
- A check that reported anything, or read a file no module load accounts for
  (a C header, a derive provider input), is not kept.

The stamp exposed an older bug. Image chunk names are source paths, so
`nupp.compiler.project.fingerprint` took itself for a bundle and hashed "the
bundle" -- its own source file. Every VM store (headers, check results, build
state, prelude) was stamped with that one file, and an image rebuilt from an
edited checker went on believing what the old one stored. The runtime now
answers `__nupp_image_identity()`, the cache digest of the image it started
from, and that is the compiler's fingerprint on the VM; a runtime without it
gets a per-process stamp, so every store misses rather than lies. The program
image key (`nupp.tools.build.package`) names the compiler the same way rather
than rereading the file `NUPP_VM_CLI_IMAGE` names.

`bench/serde-spike/contracts/structure.nupp` on the linked CLI: 237 s cold,
1.2 s warm. Images are byte-identical whether a module is compiled after its
dependencies were checked or alone among cache hits.

In the corpus (`--engine threaded --gc-interleave`, linked CLI),
`serdecontracttest` passes all 33 cases in 97 s once the cache is warm. Cold
it still times out at 600 s after two cases: the contracts compile 88
modules the image does not carry (36 standard, 52 their own), and filling the
cache takes most of an hour,
so a run that should pass needs the cache kept between runs (`NUPP_CACHE_DIR`,
or the checkout's `build/cache`). `examplestest` is unchanged: it checks the
documentation's examples in its own process and compiles no image.

## Stamps narrower than the image (2026-10-15)

Stamping every store with the whole image's identity was correct and coarse:
an edit to any command made every project start cold. The runtime now also
answers `__nupp_image_modules()` (`vm.imageModules`) for the image it started
from, and `nupp.compiler.project.fingerprint` walks that graph the way it
walks a LuaJIT tree, so a store is stamped with only the image modules its
answer came from. The answer is read off the loaded image, never off the
sources beside it, for the reason the identity stamp exists.

- **Digest**: a module's functions as the image spells them, with every
  image-wide index made stable: a function id (in calls, closures, `func`
  constants, shape methods, and the `fn<id>` an anonymous function is named
  after) becomes the owning module and its position there, and a shape index
  becomes the shape's own text. Two images that differ in one module differ in
  that module's digest alone, whether a LuaJIT or a VM compiler emitted them.
- **Edges**: literal `Require`s, the modules whose functions a module names,
  the modules defining methods of the shapes it uses, and what an
  `@requires-dynamically` constant declares. A name the image does not carry
  is no edge: that code is no more covered by the whole image's digest.
- **Incomplete**: a forward dataflow over each function that touches
  `require` (or `_G.require`) finds its calls. A string argument is that
  module; a concatenation starting with a literal counts as the literal, which
  is how the LuaJIT graph's token reader sees `require("nupp.compiler." ..
  name)`; any other argument, or `require` escaping as a value, makes the
  module incomplete unless it carries a marker. A subsystem reaching an
  incomplete module falls back to the whole image, and a runtime without the
  builtin gives the whole image too.

On the CLI image every root the compiler stamps with (headers, check records,
type functions, prelude, VM images) reaches a complete graph; only
`generatorworker` and `nupp.tools.vm.root` are incomplete. Describing the
21 MB image takes about 95 ms, kept per image in `modulegraph.buf`.

Measured on `bench/serde-spike` with `nupp check` on the linked CLI, the
machine shared with other runs: cold 1,187 s, warm 1.8 s. A CLI rebuilt with
a code change to `nupp.tools.cli.explain` alone (source restored before
checking, so only the compiler differed) stayed warm: 2.8 s on the first
command, which describes the new image, then 1.7 s. Before this every such
rebuild went cold. A CLI rebuilt with a message change in
`nupp.compiler.check.discard` went cold as it must, 180 s, then 1.7 s. Of the
three images' 336 module digests, only the edited module's differed.

Inherited from the LuaJIT graph, and open: the literal-prefix rule means
`compilerPrivate` in `env` and the trivia-arena provider `vm.root` installs
are not edges, so neither graph covers those modules for the stamps reaching
them; the runtime binary is in no stamp.

## Standard modules off `ffi` (2026-10-15)

Nothing the VM loads from `src/` reaches LuaJIT's `ffi` any more. What each
module that did became:

- **`nupp.mem.soa`, `nupp.mem.heap`, `nupp.mem.sharedbytes`** have VM
  implementations in `lib/nupp/mem` with the same public declarations. A SoA
  slab is one managed allocation of words, each column a typed view
  (`castWritableElements`) of its segment, laid out as LuaJIT lays it out; a
  heap array is managed storage of its element descriptor; a region's block
  is a shared block `copy` filled or a frozen builder's storage became. All of
  it is collected and checkpointed as storage is, so `close` and a builder's
  `drop` only drop the reference; regions and heap arrays cross workers as
  "Memory across workers" describes.
- **The lowering** (`metadata.expand`) makes `ffi.typeof<T>()` T's storage
  descriptor: a struct's declared `\0nupp:structType`, or raising its layout's
  reason where the target gives none, and the storage provider's scalar
  descriptor for a scalar. `soa.allocate` and `soa.layoutof` become calls to
  `_allocate`/`_layout` with the checker's field specification; `_layout`
  measures each field from the row's descriptor. A row, a row's field and a
  projected column (`rows[i]`, `rows[i].x`, `rows.x`, assignment and compound
  assignment included) call the view's checked `get`, `set`, `getField`,
  `setField` and `fieldBySlot`, as span views call `get` and `set`. The two
  SIMD field-load forms are still refused; they now have the port they waited
  on.
- **`nupp.log`** reads the second through `ffi.C.time` only where
  `require("ffi")` succeeds; the VM keeps `os.time`. **The trivia arena's**
  lazy default takes the table provider where there is no FFI. Both keep the
  require literal so the module graphs stay complete.
- **`nativehost`** is replaced by a provider that reports no host attached
  and refuses every request by name, as `nupp run` does under LuaJIT: the
  LuaJIT embedding's host channel is not linked, and the VM embedding has
  none yet. `nupp.host.internal.values` serves only the LuaJIT embedding and
  the browser, so the VM never loads it.
- **GPU** stays LuaJIT's. The VM's `nativegpu` reports no device (`available`
  false, `open` refuses by name, an empty cost record). Porting the LuaJIT
  provider is not mechanical: the `nuppNativeGpu*` entry points live in the
  LuaJIT host library (`native/crates/native` over `native/crates/gpu`), which
  the VM does not link and could not reach from a `cdef` until the loader
  binding of a native library lands; the provider and the bindings
  `aot/gpubinding` generates pack out-parameters and uniform blocks with
  `ffi`; and "GPU compute on the VM" replaces `gpu.Buffer` with storage
  residency, so a port of the buffer API would be thrown away.

`tests/memory-smoke.py` runs a fixture over SoA rows, fields, columns, slices
and copies, heap arrays, regions (slices, views, typed views, builders,
identity) including regions sent to a worker, the logging clock, and the
detached host and GPU, on all four engines under incremental collection with
the root oracle and quarantine.

Two VM gaps showed up on the way. Records have no `__eq` (nor does the VM
dispatch `__eq` at all), so a block hands out one region per extent and
identity is region equality. And `(view as any) + n` with an integer-typed `n`
lowers as numeric addition and raises "expected a number" instead of calling
the view's `__add`; the modules do view arithmetic through an `any`-typed
helper. Regions now reach a worker by reference and heap arrays move ("Memory
across workers").


## Coverage on the VM (2026-10-15)

`nupp test --coverage` runs on the VM CLI and writes the same `coverage.json`,
`lcov.info` and HTML pages. The generator's design carries over: statement,
function and branch sites, a manifest per module in the build state, counters
in `_G.__nuppCoverage.hits[path][key]`, and the runner's shard, which
`nupp.tools.coverage` reads unchanged.

- **One numbering.** `nupp.compiler.coverage` numbers a module's sites from
  its checked syntax, in source order. The generator used to number them in
  the order it happened to write probes; it now asks the same enumeration and
  writes a probe only where it holds a site, so the two backends agree by
  construction rather than by mirroring each other's traversal. A build
  enumerates before the optimizer runs, since the VM lowers the unoptimized
  source; a VM program build then records the lowering's own manifests.
- **What the generator counted differently.** Making the numbering a property
  of the syntax closed gaps the emission order hid: record methods are now
  function sites, statements in blocks holding automatic cleanup owners are
  counted wherever the cleanup region writes them, `if NAME = EXPR` clauses are
  branches, a statement-owner region's statement is counted once, and comptime
  functions and annotation schemas are no longer statement sites.
- **The lowering.** `lower.emit` takes a coverage request naming which modules
  to instrument. Each function of such a module reserves a register on entry,
  loads its file's counts table into it once
  (`nupp.runtime.coveragecounter`, carried in the image), and every site adds
  one to its key there; a branch counts `id:true` or `id:false` by Lua
  truthiness. Without a request the image is byte-identical to before (checked
  on four modules against the previous lowering; `coveragetest` checks a
  request naming nothing). `compile.image` instruments under `NUPP_COVERAGE=1`
  and keeps no such image in the cache.
- **Cost.** `narrowingtest` on the stamped runner, paired: 11.0 s plain, 38.4 s
  covered (3.5x). A first version called the recorder at every site, as the
  generated Lua does, and ran it in 156 s (12x); LuaJIT compiles that call
  away and the interpreter does not.
- **Parity.** `coveragetest` lowers a fixture and `nupp.compiler.switchplan`
  both ways and compares the manifests; on the VM it also runs the fixture's
  image and its generated Lua and compares every counter, and does the same
  for loading `nupp.compiler.aot.scalar`.

Writing the report took ten minutes on the VM, for two quadratic costs that
had nothing to do with coverage:

- `string.find`, `string.match` and `gmatch` with a pattern copied the whole
  subject on every call, so a decoder stepping through a large text with
  anchored patterns paid its length each step. Reading the 13.7 MB coverage
  build state took 388 s; borrowing the subject, as the plain search already
  did, makes it 2 s, and a 6.9 MB slice decodes in 0.9 s rather than 81 s.
- The highlighter appended each token to its line, so a generated file whose
  first line is a 172 KB prelude went quadratic: one page stalled the report
  for good. It now joins a line's pieces once (15 s to 0.6 s for that file).

The compiler's report is now about a minute on the interpreter, byte-identical
to what the slow run wrote.

Not instrumented: functions lowered from a native SIMD plan. The page's
"Generated Lua" view still shows the generator's output, which on a VM build is
not what ran. `coveragetest` now covers `coveragereporttest`, because the VM
runner leaves `pathtest` to LuaJIT and covered nothing.


## Incremental root emits (2026-10-15)

`scripts/vm-cli build` re-emitted the whole root image for any edit: check and
lower all 338 modules, 400-700 s VM-hosted. An emit now keeps, per module,
what lowering it produced and what that depended on, and the next emit
replays every module whose inputs are unchanged. The image is byte-identical
to an emit from nothing; `nupp fixpoint` emits without the cache.

**Relinking** (`nupp.compiler.vm.relink`). `lower.emit` numbers functions and
shapes across the whole image, so a module's lowering is a function of its
checked tree and of the shape registry it read on the way: which records,
structural constructors and export records were already numbered. While a
module is lowered fresh, the registry's two tables (by nominal or
declaration key, and by bare name) are read and written through proxies that
log every read with its answer, every write, and every shape allocated, in
order. The module's functions are kept as the image text lowering wrote, with
its own function ids (and the `fn<id>` in anonymous functions' names) made
relative and every shape operand -- the operands the image loader relocates:
`NewRecord`, `Get/SetSlot[F]`, `IsRec`, `TagCheckRec`, `SetMethod`, slot
`rec:` types -- named by position among the module's allocations or by the
shape's text. Relocating at the original base must reproduce the original
text, or the module is not kept. A replay runs the log against the registry
as it stands at the module's turn: allocations again in order, writes again,
and each read must answer as it did; one that does not undoes the replay and
lowers the module from source. Function and shape ids therefore come out as a
fresh lowering assigns them whatever moved before the module.

A registration by nominal object always comes with one by declaration key, so
a read by object is kept only when it found a shape and replayed as the read
by key. Nominals without a key (generic instantiations, whose origin has one)
are answered by identity alone; a module that registers one for another
module's record, or reads one and finds another module's shape, is not kept.

**When a module may be replayed** (`nupp.tools.vm.emitcache`). Every check an
emit makes -- the explicit check lowering reads, and the environment's check of
each module loaded on the way -- is bracketed, recording the modules it read
(`env.loaded`, through a proxy) and the project-index entries it looked up.
Each environment-checked module's interface is encoded the way parallel check
workers hand one to another (`interfaceimage`), kept, and digested with token
positions dropped and the offsets in its own declaration keys replaced by
their order, so a body edit leaves the digest alone. A kept fragment carries
the interface digest of every module in its check's closure and the index
answers that closure looked up; it is replayed when each still holds.

A module is *clean* when its bytes and index reads are as recorded and every
module it read has the interface it saw. Clean-ness is decided per strongly
connected group of the recorded load graph, lazily: a changed dependency is
checked only when something asks for its interface, which is the cutoff. When
a check needs a clean module, its kept interface is decoded into the run's
identities and installed in `env.loaded` instead of checking it, dependencies
first; anything refused falls back to a check. So a leaf edit checks the leaf,
not the ~300 modules it requires.

The cache lives under `build/vm-cli/emit-cache` (`NUPP_VM_EMIT_CACHE`, or
`project.emitCached`), stamped with the subsystem fingerprint of
`nupp.tools.vm.project` (the checker and lowering it reaches), the carried
declarations, the manifest's value, the roots and the layout target. Every
part is plain data and never load-bearing: a miss lowers from source.
`NUPP_VM_RELINK_TRACE=1` says why each module was lowered again;
`NUPP_VM_EMIT_RESTORE=0` checks every module a check needs.

Restoring makes the image depend on the interface image carrying everything
lowering reads of a type, and the first full-scale comparison found what it
did not: a decoded record counted its methods among its stored fields
(`fieldOrder` was rebuilt from the member view), so a derive's reflected
construction contract grew a parameter per method and `nupp.tools.cli.root`
lowered differently. Parallel check workers decode the same images, so they
had the same divergence. Images now carry `fieldOrder` (schema 7).

Order dependence that remains: a shared nominal's `runtimePath` is set by
whichever module's check names it last, and the VM metadata lowering reads
it; and in a require cycle, which member the environment enters first decides
what the others see in progress. An incremental emit checks fewer modules, in
a different order. No image has differed from its emit-from-nothing since the
`fieldOrder` fix, but the order is not proven irrelevant; the identity suites
are what would say so.

### Measured

The root image (338 modules), on this machine while other agents' emits ran.
"Emit" is the `vm emit:` line's own time; "rebuild" is what the launcher
reports, emit plus loading the 21 MB seed image, writing the new one, a no-op
Cargo build and installation (verifier and `--help`). VM-hosted emits run on
the pinned, linked generation.

| what changed | lowered | replayed | checked | restored | VM emit | VM rebuild | LuaJIT emit |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| nothing (cold cache, captures) | 338 | 0 | 342 | 0 | 331 s | 340 s | 165-171 s |
| a leaf's body (`tools.cli.explain`) | 1 | 337 | 1 | 60 | 4 s | 13 s | 8 s |
| the body of a module 31 others import (`tools.cli.report`) | 1 | 337 | 1 | 58 | 5 s | 14 s | 8 s |
| that module's exported signature | 32 | 306 | 30 | 298 | 21 s | 30 s | 20 s |

An emit from nothing takes 242 s LuaJIT-hosted here; capturing costs it the
interface encodings and the fragment files. Each incremental image was
compared with an emit from nothing of the same sources (LuaJIT-hosted, which
writes the VM-hosted image byte for byte), and the cold VM-hosted emit with
the LuaJIT one: all identical. `tests/vmemitcachetest.lua` holds the same
cases on a small project: a leaf, a widely imported module's body, an
exported record gaining a field, renumbering everything after an early
module, and a damaged fragment.

Linking is what the rebuild leaves to the background: the AOT of the root
image takes 120-128 s and the linked runtime's Cargo build 21-24 s (12-48 s
more the first time a checkout builds the AOT tool). The linked runtime runs
a warm `nupp check` of `lexer.nupp` in 0.94 s against the interpreter's
1.06 s, and a cold check of `check/expr.nupp` in 9.6 s against 11.5 s; it
also makes the pinned emitter faster once it is re-pinned to it. Installing
the interpreter first keeps a leaf edit's rebuild at 13 s instead of 2.5 min.

## The launcher rebuilds the VM CLI (2026-10-15)

`bin/nupp` keeps the installed generation current the way it keeps `build/`
current on the LuaJIT path. Every install leaves `.nupp/vm-cli/stamp` carrying
the time its build *started* (an installation older than that has its
`current` file's time); a file under `src`, `templates`, the VM crate's
`src`/`lib`/`decls`/`csrc`, the crates it links, the workspace manifests or
`scripts/vm-cli` newer than the stamp means the generation has not seen that
edit, and the command rebuilds before it runs:

```sh
python3 scripts/vm-cli build --seed pinned --no-aot   # what the launcher runs
```

- **One rebuild per checkout.** It runs under `.nupp/vm-cli-build.lock`, a
  directory holding the builder's pid; a command that finds it held waits, then
  runs what that build installed. A lock whose holder is gone is taken.
- **A failure keeps the previous generation.** The launcher says the compiler
  did not build, shows the end of `.nupp/vm-cli/rebuild.log`, and runs the
  generation it has. `.nupp/vm-cli/failed` remembers the failure, so later
  commands say so instead of retrying until another source changes.
- **What bypasses it.** An explicit `NUPP_VM_CLI_IMAGE` (and with it every
  worker and child command a compiler starts, which inherit it),
  `NUPP_ENGINE=luajit`, `NUPP_VM_AUTO_REBUILD=0`, help, and `__` worker
  commands.
- **The emitter is pinned.** The rebuild lowers with the generation whose
  lowering the emit cache holds (`.nupp/vm-cli/emitter`), not the newest one: a
  generation built after an edit to the checker or the lowering has a
  different stamp, and lowering with it would start the cache cold on every
  second rebuild of somebody working on them. That is the same one-pass
  semantics `--seed vm` always had, with an older seed. An explicit
  `scripts/vm-cli build` moves the pin to the installed generation, a pinned
  generation that cannot lower the sources falls back to the installed one,
  and `nupp fixpoint` remains the self-hosting check.
- **Interpreter first, linked in the background.** The rebuild installs an
  interpreter-only runtime, then starts `scripts/vm-cli link`
  (NUPP_VM_AUTO_LINK=0 skips it), which compiles the image's functions into a
  runtime in its own Cargo target directory and installs that pair under the
  build lock -- only while that generation is still the selected one; if a
  newer one was installed meanwhile it links that instead.
- **Old generations are pruned** after a day, except the selected and pinned
  ones; a generation is immutable and a running command keeps reading its own.



## Native libraries and C callbacks (2026-10-15)

A program names a native library the two ways it already could, and both now
load on the VM: a typed `cdef function f(...): T from "name"` declaration, and
a manifest's C or Cargo dependency, whose generated binding module carries
`from "@lib/<library file>"`. A `cdef` declaration binds its symbol when its
module runs, through `foreign.bind` with the library name, so a library or
symbol that is not there fails the `require` of the module that declared it:

- `cannot load native library "z" (as libz.dylib): <dlerror>`
- `native symbol "f" is not in native library "z"`
- `cannot find native library lib/libx.dylib at or above <directories>; the
  compiled library has to travel with the module that calls it`

**Names resolve as LuaJIT's `ffi.load` resolves them.** A path is opened as
written; a bare name gains the platform extension when it has no dot and, on
POSIX, the `lib` prefix, and the platform loader searches for it. An `@` name
is the build tree's: the generated binding lives in `build/generated/` and the
library in `build/lib/`, so the VM looks at or above the calling module's
source directory (its image path, relative to the working directory when the
image names it relatively), then at or above the running executable's, eight
levels each, the bound the LuaJIT spelling already had. A nil library is the
process's own namespace.

**A library is an owner.** Each VM caches a loaded library by resolved name
and visibility while anything holds it. `foreign.load(name, {global = true})`
returns a library object (RTLD_GLOBAL when asked); every function bound from
it and every pointer such a function returned holds the library too, so
closing the object refuses further binding through it while what it bound
keeps working, and the platform unloads the library only after the last
holder closes. The test proves the unload with a destructor in the fixture.
Libraries, functions, pointers and callbacks are external resources, so a
checkpoint refuses them, as it refused functions before.

**Callbacks are lent or retained.** A `cdef` parameter of function type
lowers to `{kind = "callback", params, result}`, and a Nupp function passed
to it is lent a trampoline for that call alone: trampolines come from a pool
per C signature and return to it, cleared, when the native call returns,
failed or not. `nupp.foreign.retain(f)` (on the runtime, `foreign.callback(nil,
f)`) makes a callback C may keep; it takes its C signature from the first
callback parameter it fills, and a parameter with another signature refuses
it rather than reinterpreting it. `rebind` changes the function behind a
stable C pointer, `release` clears it, and the handle is callable from Nupp as
the function. A function-typed `cdef` result is the other direction: a foreign
function callable under the declared signature, holding its library.

The rules C callers meet, none of which may unwind through C:

- A trampoline is never freed while its VM lives. A call through a released
  or no-longer-lent pointer returns zero to C and raises once the native call
  returns ("invoked after it was released", "after the call that lent it
  returned; retain a callback that C keeps"). Released trampolines go back to
  the pool only after 256 later releases, so what a program holds stays
  bounded and a stale pointer is refused for that long; past it, it reaches
  whatever reuses the trampoline, as a reused LuaJIT callback slot does.
- A call from a thread other than the VM's touches nothing of the VM: it
  returns zero and sets a flag the VM's thread raises when the native call in
  flight, or the next one, returns. So does a call on the VM's thread when no
  native call is in flight.
- An error in the callback returns zero to C and is raised to the Nupp caller
  when the native call returns; the callback stays usable.
- Arguments and results are scalars and opaque pointers. A pointer C passes a
  callback is a handle valid for that invocation; a callback may return a
  pointer C owns or nil, never managed storage, which is rooted for no longer
  than the call. Variadic callbacks and aggregates or functions by value are
  refused when the callback is declared, LuaJIT's own limits.

Every function a trampoline can call is rooted through the VM's trampoline
registry, so callbacks hold under collector stress in all four tiers; the
foreign call itself runs from whichever tier calls it, and the trampoline
re-enters the VM through `call_value`. `foreign.string(pointer, length?)`
reads the bytes at an address C returned, to the terminator or of a length,
which is what a `const char *` error message needs.

`nupp.foreign`'s handle is `any`: an exported generic `retain<F>(f: F): F`
cannot store `f`, because the ownership checker treats an unconstrained `F`
as a possible capability (NUPP2603/NUPP2611), and a bound does not change
that. The `cdef` parameter is what checks the function's type.

Evidence: `tests/foreign_loader.rs` against `tests/ffi/loader.c`, built with
the system compiler, and `tests/loader-smoke.py` running
`tests/loader-project` on the Rust, threaded, JIT and compiled-frame engines
under collector stress. `ffi-coverage.json` records the rows this moved.

**GPU.** The loader is enough to drive the GPU host library: a VM program
loads `libnupp_native.dylib` built with `--features gpu`, checks
`nuppNativeAbiVersion` (2) and the GPU feature bit, creates a Metal context
through a managed `uint64` out slot, reads its description, creates and
releases a buffer and releases the context. What stands between that and the
provider is not binding: typed `out` and counted-pointer mappings are still
refused by the VM lowering, so a port writes its out slots as managed arrays
through `nupp.vm.foreign` as that probe did; no runtime this repository builds
for the VM links or ships the GPU library, so a provider needs a location
policy (the LuaJIT one reads `NUPP_NATIVE_LIBRARY` or `lib/nupp_native` beside
the module); and "GPU compute on the VM" replaces `gpu.Buffer`, the uniform
packing and `aot/gpubinding` with storage residency, which a port of today's
provider would be thrown away for.

**The declaration duplicate.** `src/nupp/compiler/cinterop/cdecl.nupp` reads
LuaJIT's own C parser through `ffi.typeinfo`; the VM's
`lib/nupp/compiler/cinterop/cdecl.nupp` answers the same interface from
`cdecl.rs` over libclang. Both produce `cinterop.model`, which `cheader` and
`import-c` consume. Decided: `cdecl.rs` is the declaration front end. The
LuaJIT reader goes when `ffi` does, because nothing else can host it; a
parser written in Nupp would be a third C front end to keep in step with C,
where libclang is C's own. The cost is libclang at compile time for header
work only (`cheader`, `import-c`, binding generation); running a program
needs no C parser, since a `cdef` lowers to a signature descriptor. Its
release packaging is still open.

Open from here: typed `out` and count mappings and by-value nested unions in
`cdef` signatures; a typed retained-callback handle; callbacks under the
executable-memory-denied AOT gate (libffi closures allocate executable code);
Linux and Windows execution evidence. Compiled code that calls a callable
table which raises leaves the call's arguments on the handle stack; this is
not specific to foreign functions, and the Rust test checks compiled-tier
root balance only on success.


## Suites off the Lua generator and LuaJIT (2026-10-15)

The 108 suites classified `port-required` were ported, retired, or left
with a named gap, so deleting the Lua generator and the LuaJIT embedding
loses no coverage silently. Of the 108, 72 run on the VM (71 suites and the
`providerstate` helper), 11 are retired and 25 stay `port-required` (hot
reload among them, for the lane porting it), each with what it still needs in
`corpus-classification.json`. The corpus run over every non-retired suite
passed 152 of 183 on the threaded engine; a rerun of the suites fixed after
it brought that to 156.

How a suite runs Nupp without the generator:

- **`tests/program.lua`** lowers a checked fragment with
  `nupp.compiler.vm.lower` and loads the image with `__nupp_load_image`, laying
  structs out for the host target. A fragment's `require` of a module the
  running image does not carry compiles that module from source, as `nupp
  test` does for a suite. Under LuaJIT it falls back to generated Lua; that
  branch is the one line to delete with the generator.
- **`tests/providerstate.lua`** instances a module by lowering its Nupp source
  in environment mode (the mode `loadfile` chunks use), so each instance gets
  its own `require` where LuaJIT used `setfenv`. Instances are registered under
  a name of their own: an image registers the modules it declares, and an
  instance named as the module answered the process's later `require` of it.
- Assertions on the text of generated Lua were dropped, or retargeted to
  behavior (counting side effects) or to the image text where they encoded a
  semantic property such as erasure. Build and bundle cases build VM program
  binaries and run them.

The suites found these gaps in the VM, now closed:

- **Lowering**: binding patterns, `continue`, `e or return/break/continue`,
  `comptime do ... end` values and materialized values (with the PEG runtime,
  `re` and the keyed field codec installed as the Lua bootstrap did),
  interpolated and backtick strings, `&&`/`||`/`!=`/`!`, untyped bitwise
  operators, safe-navigation assignment targets, `is` against `where`
  refinements, `nupp.admit`, `%?` in formats, `nupp.log` severity sites as
  the intrinsic (level test at the site, module and line constants),
  annotation schemas and comptime helpers erased, a narrow unsigned
  complement kept in its width, `new` of a struct or qualified record
  another module declares, and records declared in a record's body as its
  members. Evaluation order now matches Lua's: assignment targets, span
  targets included, before values (held across a multiple assignment and
  stored right to left), a dynamic
  receiver's method before its arguments, a pluck's shared path once, and a
  compound assignment's table and key once. A `break` or `continue` in a
  `repeat`'s condition belongs to the enclosing loop, whose body owners close
  after the condition reads them.
- **Ownership**: a moved owner given a new value, or an optional owner filled
  later, is re-armed in its cleanup slot (`RearmAt`); an owned temporary
  loaned for one statement closes at its end; a field taken from a
  self-closing record is cleared; an absent optional aggregate is not
  destructured; each owner of `local a, b = ...` is registered as it is
  acquired; a `cdef` function named as a terminal is registered, and a
  cleanup whose callback is not bytecode runs in place instead of taking the
  process down. A body failure with suppressed cleanup failures prints as all
  of them.
- **Modules**: a declared module publishes its exports before its body runs,
  so require cycles see them, and unpublishes them when the body raises; a
  foreign record's module is loaded before the record is built.
- **Runtime library**: `__eq`; `rawequal` by value; `math.random`,
  `randomseed` and the rest of Lua 5.1's `math`; `table.new`; `bit` operands
  rounded as `tobit` and `tohex` widths clipped; `string.buffer` refusing
  negative counts; `select` refusing a non-number; `collectgarbage("step")`;
  `file:setvbuf`/`flush`; `tonumber` refusing a bad base; Lua's wording for a
  require cycle and for `loadfile` of a missing file; `debug.getinfo` naming
  the calling chunk (every chunk shares one module name), answering nil past
  the outermost frame, and giving `func`, `currentline` and `linedefined`;
  `error(msg, 2)` adds no position under `pcall`; `nupp.log` loads without
  `ffi`; a child's working directory may be a path value. Compiled and
  threaded field reads answer a string's fields from the string library and
  a reducer's methods, as the interpreter's `GetField` does: the AOT-linked
  CLI raised "attempt to index a string value" on `path.sub` once a method
  was read before its arguments.
- **C declarations** (libclang): parameter names, anonymous enums and
  members, only a unit's own structs, "size is unknown" for incomplete types,
  and the header line a declaration error is on. A bare library name (`from
  'z'`) loads as `ffi.load` spells it.
- **Programs**: a binary carries its build's whole source set (computed
  requires, the SPI index, generated C bindings) and the rock modules its
  target names, preloads `nupp.embedded`, and installs `nupp.reflect` when it
  reads it. A program that compiles grammars at run time gets
  `nupp.peg.compile` from one call; the full PEG runtime is installed only
  for materialized grammars.

Retired, with what they tested: the Lua optimizer (`optimizetest`,
`passpermutationtest`, `concatbuffertest`), the generator's own invariants
(`loweringinvarianttest`), LuaJIT cdata (`bulkcolumntest`, `sharedbytestest`),
the generator's one-lane SIMD routing (`simdlanetest`), the LuaJIT native
process provider's C ABI (`processprovidertest`), and the LuaJIT embedding
(`hostembeddingtest`, `hostbinarytest`, `hostchanneltest`). Their files stay
until what they test is deleted, since the LuaJIT runner still runs them; the
VM runner defers them. Hot reload (`hotreloadtest`, `hotreloadguaranteetest`)
stays `port-required` for the hot reload lane.

Still `port-required`, by what they need:

- **C layout**: bitfields, pointer, nullable-pointer, fixed-array, union and
  generic struct fields in VM struct storage, counted-pointer arguments and
  out-parameter results (`cdeftest`, `structtest`, `layouttest`,
  `importctest`, `ownershiptest`, `simdfixedlanestest`); `cheader(...)`
  namespaces are not lowered (`cheadertest`); a binding's `@lib/` library
  reaches dlopen unresolved (`projecttest`).
- **`nupp.mem.heap` and `nupp.mem.sharedbytes`** still need `ffi` or the
  engine host (`bundletest`, `ownershiptest`, `runtimetest`).
- **Semantics**: integer `% 0` answers nan (`operatortest`); an `xpcall`
  handler runs after the unwind (`orexittest`); a generic constructor at
  integer unboxes a float (`methodtest`); a dead register keeps an unused
  local type alive (`runtimereflectiontest`); comptime type caches lose a
  local record's identity (`typeleveltest`); materialized grammars with
  predicates fail in the generated matcher (`pegmaterializetest`); a bounded
  generic field's derived `Debug` sees `T` as opaque (`derivetest`).
- **Tools and hosts**: a module-level `...` is dropped because a module chunk
  is not vararg (`clitest`); `nupp run --watch` (`runtimetest`); the VM lib's
  time, workers and suspension providers bypass SPI selection (`spitest`); the
  browser URI provider is not in the image (`uritest`); a VM program check
  refuses a coroutine for a `thread` parameter and a rebuilt binary collides
  with the Lua modules build (`bundletest`).
- **Corpus only**: `nettest` and `filestest` each pass through `nupp run` but
  fail one case in the shared corpus image; `annotatedluatest` passes case by
  case but its migration cases outlast the 600 s suite budget.

Outside the 108: `perfbudgettest`'s generated-Lua case reports not-executed,
which the corpus runner counts as a failure, and `serdecontracttest` exceeds
the suite budget; both predate this work. A VM image keeps answering a module
name an earlier image declared after `package.loaded` forgets it
(`package.imageLoader` reads every registration), which `declaredmoduletest`
now sidesteps with a module of its own.

## `nupp.snapshot` (2026-10-16)

`require("nupp.snapshot")` is the public layer over the persistence mechanism
above (snapshot plan step 2). `nupp.vm.persist` stays as the primitive layer it
is written over, and existing callers keep working. The module is typed and
documented in `lib/nupp/snapshot.nupp`; its primitives are `nupp.vm.snapshot`
(`src/snapshot.rs`).

```lua
local snapshot = require("nupp.snapshot")
local bytes = snapshot.save(world, {policies = policies, resources = resources})
local prepared = snapshot.prepare(bytes, {policies = policies, resources = resources,
    validate = function(candidate: any): nil assert(candidate.version == 3) end})
local restored = prepared:publish()   -- or prepared:close() to discard it
snapshot.loadInto(bytes, world, {policies = policies, resources = resources})
local save = snapshot.durable(world, {application = "demo", version = 3,
    policies = policies, path = "slot1.save"})
local header = snapshot.inspect(save)  -- application, version, metadata, sections
local loaded = snapshot.loadDurable(save, {application = "demo", version = 3, policies = policies})
```

**Restores are transactions.** Resources restore, then every `afterLoad` hook,
then typed validation, then the caller's `validate`, all before publication. A
failure at any of those points discards the resources staged so far (each
registration's `discard`, newest first; every discard runs and failures are
reported together with the original error). `prepare` returns an affine
`Prepared` whose `close` discards and whose `publish` hands the value over.
`loadInto` is all or nothing: the target's slots, array part, extra fields and
metatable are saved before the load and put back, with barriers and payload
accounting, when anything after the first write fails. Hooks that modify
objects outside the restored graph are the hook's own business.

**Application resources.** `snapshot.track(table, kind)` marks a table as an
external resource of an application kind (`nupp.` kinds are reserved for the
runtime). A save that reaches it uses that kind's registration from the
operation's `resources` list: `capture(object)` returns a descriptor string,
and `restore(placeholder, descriptor)` rebuilds the resource in the restored
table. Capture needs a mutable VM, which `ResourceCodec::save` does not give,
so a save with registrations first walks the graph with recording codecs and
no hooks (transient fields still exclude), captures each reached resource,
then saves for real with the descriptors and the hooks running once. A
resource that only becomes reachable through a `beforeSave` hook is refused by
name. Registrations are per operation, like policies; a save that reaches a
tracked table with none names its kind.

**Standard providers in whole-VM checkpoints.** `nfiles`, `nnet`, `nhttp` and
`ncompression` keep handles in Rust side tables that Nupp values refer to by
number, so before this a checkpoint silently saved dangling numbers. Now
`save_vm` first registers a sentinel table per provider with open handles (a
`vm.loaded` entry under `nupp.vm.snapshot:<kind>`, rooted through
`registered`) as a resource, and installs standard codecs unless the caller
supplied one of the same kind; `load_vm` installs the same codecs. A VM that
never opened a handle checkpoints byte-identically to before.

- `nupp.io.files.handles`: every open file with its canonical path, mode,
  offset and handle number, restored under the same numbers with the counter
  past them. Read-only files default to `"verify"`: the size and SHA-256 at
  capture must match at restore (the digest is cached while size and mtime
  hold). Writable files default to `"refuse"`, which fails the capture naming
  the file. `snapshot.fileStrategy(path, "reopen" | "verify")` sets a rule by
  canonical path for files open now or later, and
  `snapshot.writableFileStrategy` the default. Rules are VM state: the codec
  carries them even with no file open. Reopening uses
  `OpenFile::reopen`, which never creates or truncates. A failure part way
  drops the files reopened so far before any is published.
- `nupp.net.handles`, `nupp.http.handles`, `nupp.compression.handles`: refused
  with the open handles counted, for example "1 network listener open; sockets
  cannot be restored into another VM". A caller-supplied codec of the kind is
  the explicit strategy.
- `io.open` handles, child processes and their streams, `io.popen` pipes,
  temporary paths and foreign libraries, functions, pointers and callbacks:
  refused with what to do instead, in checkpoints and graph saves alike.

Graph saves also refuse an open `nupp.io.files` file record inside a value: its
handle number names a file of this VM, and a copy would alias it.

**Durable saves in a scratch VM.** `durable` graph-saves the value and its
options (complete, no hooks, application resources as descriptors), builds a
VM from the live VM's code recipe on its own thread (as a worker does, without
running modules), loads the copy there with pass-through codecs that keep each
descriptor without opening anything, then runs `select`, `metadata`,
`sections` and the policies' `beforeSave` hooks on that copy and saves the
result. The scratch VM is dropped afterwards, so a hook cannot change the
running game. The output is a `saveData` envelope (format, format version,
application, version, metadata, root graph, named section graphs) with the
persistence framing's checksum and limits. Functions are refused, since they
bind a save to one build. With `path`, the bytes are published through
`writeAtomic` only after everything succeeded, so a failing hook leaves the
previous save in place. `loadDurable`/`prepareDurable` refuse another
application and a different version ("an explicit migration is required");
migrations are step 5.

Limits found along the way:

- A hook running in the scratch VM, like a worker body, sees a module whose
  functions are shape methods (an `export function` module) without its
  methods, because the copy does not run module initializers. Such hooks and
  bodies `require` the module again.
- Application resources are per graph operation. Whole-VM checkpoints still take
  resource codecs from the embedding host only: a Nupp registration cannot run
  in the candidate VM before it is assembled.
- `math.random` keeps its state in a thread-local, outside every checkpoint, so
  a restored game draws a different sequence. Random streams are part of the
  plan's acceptance and are not covered here.
- Selective saves do not yet report excluded or unresolved dependencies, and
  policies have no version or section descriptors of their own; the durable
  envelope carries the version and sections.

```sh
CARGO_TARGET_DIR=build/rust/target cargo test --release -p nupp-vm --offline --test snapshot
python3 native/crates/vm/tests/snapshot-smoke.py COMPILER_IMAGE
```

The Rust tests run under GC stress, oracle and quarantine: offsets after a
fresh-VM restore, changed and missing assets, writable strategies (reopen
without truncation, verify after further writes, the VM default, rules that
survive with no file open), socket and `io.open` refusals, staged discard and
in-place rollback, and the durable envelope. The smoke script compiles
`tests/snapshot-project` and runs it on the Rust, threaded and JIT tiers under
GC stress: graph policies with application resources, prepare/publish/close
and validation, all-or-nothing `loadInto`, durable saves with scratch-only
hooks, selection, metadata, sections and atomic publication, and supervised
games whose open file is restored at its offset, whose changed file refuses the
restore while the old game stays usable, whose writable file needs a strategy,
and whose listening socket is refused.


## Rust embedding and native extensions (2026-10-16)

`nupp_vm::embed::Vm` is the embedding API: one isolated runtime that loads
images, registers typed host modules, calls exports with typed values
(`Arg`/`Out`), keeps values alive with `Root`s, and drives the scheduler
(`spawn`, `run_ready`, `run`, `wait`, `cancel`, `finish`). A host module is a
`nupp_extension::Module` (the new `native/crates/extension` SDK crate): a name,
functions under their declared Nupp types, and resource types. The same module
built as a shared library with `nupp_extension::export!` is a native extension
a program loads with `require`. Both reach the VM through one versioned C ABI,
`include/nupp_extension.h`, mirrored field for field by `nupp_extension::abi`;
`tests/extension_header.rs` (the `c-headers` feature) reads the header with
libclang and holds every size and offset to the Rust layout.

**Declarations are the contract.** A module is checked against the `.d.nupp`
declaration its callers were checked with, before any of its code runs: the
returned record's function fields, spelled canonically without parameter names
(`declaration.rs`). A missing function or another type is refused by name
(`demo.counter.add is declared function(number, number): number, but the
extension registers function(integer, integer): integer`). An extension adds
ABI version, description size, module name and target (`<arch>-<os>`) checks,
and only then calls its `init`. A declaration names its library with
`@extension NAME`; the VM project emitter (`nupp.tools.vm.project`) appends the
`.d.nupp` text of every such module an image requires as an `extension NAME
"..."` line, so the runtime checks the library against the program's own
declaration, not one the library brought. A `require` that misses the image's
modules reaches `package.extensionLoader`, which loads the library by the
`foreign.load` naming rules (`foreign::native::{canonical_name,
search_bases}`).

**Boundary types.** `nil`, `boolean`, `number`, `string` by value; `integer`,
`int32`, `uint32`, `int64` as 64-bit integers range-checked both ways (an
`integer` result must be a double exactly); `T?`; `any`, function and table
types as handles. Arguments are checked before the native function runs and
results after, so typed code only receives what its types say. Named record and
union results, variadic and generic functions are refused at registration.

**Host functions are runtime functions.** Each gets a per-VM id at or above
`extension::FUNCTION_BASE` (2^20), so `CallDyn` reaches it through `host_call`
like a host service and a call from a task may park; a call from a frame that
cannot (`call_value`, compiled leaf code, callbacks, cleanups) runs to its end
and a suspension there is refused by name. Ids are recorded by name in the VM
table `nupp.vm.extensions`, which a checkpoint saves; persistence writes them
as `hostfn.N` and a restored VM binds each id again when its module is
registered or its library reloaded, lazily on first call if need be.

**Parking.** `host->suspend` hands the extension a request; the function returns
`NUPP_SUSPENDED` and the task parks on a key from `Host::defer`, counted as
outstanding. `complete` and `fail` are thread-safe and send
`Done::Extension` down the host channel, so both drivers (`main.rs`'s and the
scheduler's) deliver it with no new polling. The completion is kept per task
and the task's saved pc is rewound by one: the retried `CallDyn` answers with
the completion's values, checked against the declared results, or raises its
message at the call site with the call's own line. A request completed before
its function returns resumes without parking at all.

**Handles, callbacks, resources.** Call handles are serial-tagged indices into
the call's rooted values and are refused in any other call; retained handles
are generation-tagged slots of `Interp::registered`, reused after release.
`invoke` calls Nupp on the VM's thread inside the call and catches its error,
which the function re-raises with its original value by returning
`NUPP_ERROR`. A resource is a VM table listed in `Interp::resources` under
`nupp.extension.resource`: rooted until closed, owned data dropped by the
type's hook. The checkpoint codec (`extension::Codec`, also installed by
`nupp-vm` run and restore) saves module, library path, type and the hook's
bytes; restore binds the module first (reloading and rechecking the library, or
taking the embedder's module from `Vm::restore`) and then runs the type's
restore hook. A type without hooks fails the checkpoint by name.

**Lifetime.** Host function values are immediates, so reachability cannot
bound a library: an extension's library stays loaded while its VM lives, and on
VM drop resources are dropped, then `shutdown` runs, then the library closes.
Each VM loads a module once; two VMs share the platform's reference count.

Evidence: `tests/embedding.rs` (in-process module, both interpreter loops,
collector stress with the root oracle and quarantine: typed calls and refusals,
mismatched and incomplete registrations, three tasks parked on requests
completed from other threads, failed completion, cancellation draining,
callbacks, retained handles through 50 stressed calls, wide integers, resources
through checkpoint and restore, refusal of an unhooked resource and of a
restore missing its module); `tests/native_extension.rs` (the same module built
from `tests/extension/counter.c` with the system compiler and from the
`nupp-counter-extension` crate by a separate Cargo build into its own target,
loaded on require from an image declaration; refusal before `init` with
markers proving `init` never ran and the library closed; library unloading only
after VM drop; checkpoint restore in a fresh VM reloading the library before
its resource); `tests/extension-smoke.py` (the typed `tests/extension-project`
program lowered by a VM compiler seed and run against both libraries).
`examples/embed_host.rs` is the embedding walk-through.
`tests/extension-smoke.py` passes against both libraries on the Rust,
threaded, JIT and compiled-frame engines under collector stress: typed calls,
callbacks, a retained function, resources, a call parked in the run driver,
sibling tasks parked at once, a failed completion, and a CLI checkpoint whose
restore in a fresh process reloads the library before its counter.

```sh
python3 native/crates/vm/tests/extension-smoke.py COMPILER.image \
  --binary build/rust/target/release/nupp-vm --output /tmp/vm-extension
```

The seed must carry this branch's `nupp.tools.vm.project`; an older one emits
no `extension` line and the script says so.

Open from here: named record and union types at the boundary (a result is
refused at registration today); variadic and generic host functions; a typed
`nupp.extension` surface for `any` resources (a resource is a plain table to
Nupp); embedder-registered modules in worker VMs, which load image-declared
extensions themselves but not modules the embedder registered on the parent;
retained handles and `Root`s across a restore (they end with their VM);
parking from leaf-compiled code (refused, as for host services); a C hosting
header over `embed` (the plan's "C hosting Nupp" item; this header is the
extension direction); the `nupp` CLI's build integration (a manifest entry
that builds and ships an extension beside a program binary); Linux and
Windows evidence.



## Metatables and metamethods (2026-10-15)

The runtime dispatches every metamethod LuaJIT 2.1 does, plus Lua 5.2's
`__len` and `__pairs` on tables (LuaJIT's compatibility build), identically
on the Rust loop, the threaded core, the typed tier and scheduled frames.
`tests/metamethod-differential.py` runs thirteen programs
(`tests/metamethods/*`) under LuaJIT, or stock Lua for the 5.2 pair, or the
LuaJIT host for a typed record's declared metamethods, and on each tier, and
compares the output; `tests/metamethods.rs` replays the emitted image against
the recorded outputs under full collector stress.

| metamethod | what the VM does now |
| --- | --- |
| `__eq` | consulted when two tables (records are tables) or two userdata are not raw-equal and share one handler; the result is a boolean. `lua_equal` (5fa7ed203) now runs through the guarded, rooted `equals`, and the typed tier's helper records its frame for the collector. |
| `__lt`, `__le` | as before, plus `__le` falling back to `not (b < a)`; `table.sort` without a comparator orders tables by `__lt` (it raised). |
| `__add` … `__pow`, `__idiv`, `__unm` | unchanged; numeric strings convert. |
| `__concat` | a chain that may dispatch it joins from the right, as Lua does (`a .. t .. b` asks `t .. b` first); a chain of strings and numbers keeps the accumulator. |
| `__len` | honored on tables and records, as before. |
| `__index`, `__newindex` | functions and tables, chains of any depth; string fields now read on every tier (the core and the typed tier raised on `("x").len`). |
| `__call` | a non-function handler or a missing one raises LuaJIT's `attempt to call a table value`. |
| `__tostring` | `tostring` passes a non-string result through, as LuaJIT; `print` and `%s` accept a number and refuse anything else. |
| `__pairs` | `pairs` returns the handler's triple. |
| `__metatable` | `getmetatable` answers it, `setmetatable` refuses a protected metatable. |
| `__gc`, `__close`, `__name`, bitwise | ordinary fields, as on LuaJIT; ownership and `with` are the close path. |

**What a program that uses none pays.** The heap keeps one bit per
metamethod name whose string was ever interned (`Heap::mm_seen`): a key that
was never a string is in no table. Each record shape caches which handlers
its declaration holds (`Shape::mm_cache`), dropped by `redeclare` and
`set_method`. Lookups use the names' interned keys, held as roots, so none
hashes bytes. The checker on `lexer.nupp`, typed tier, seven interleaved
pairs of seven repeats on the loaded machine: base 518 ms, this branch 462 ms
(medians of the medians; same result and checksum). The gain is the absent
field and method lookups that used to intern `__index` and the declaration
key on every miss.

**Dynamic lookups.** Every table an `__index` lookup walks, as a metatable or
as an `__index` target, is flagged `F_PROTO`; a store to one bumps
`Heap::proto_epoch` (it rides `schema_write`, like the storage schema), and
the core's and the typed tier's raw store fast paths refuse flagged objects.
`(metatable, key)` lookups are cached against the epoch and cleared before
each sweep, so a class chain of any depth is one probe of the receiver and
one cache probe. A record with a metatable of its own reads and writes a
present slot raw on every tier, since `__index` and `__newindex` only see
absent keys.

The class benchmark (`tests/metamethod-bench/classbench.lua`: setmetatable
classes three deep, an operator-overloaded vector), medians of seven:

| section | Rust loop | threaded | typed tier | LuaJIT interpreter | LuaJIT |
| --- | ---: | ---: | ---: | ---: | ---: |
| `methods` | 44.3 ms | 52.1 ms | 64.5 ms | 14.2 ms | 2.2 ms |
| `vectors` | 195.0 ms | 190.8 ms | 161.5 ms | 42.4 ms | 12.0 ms |
| `text` | 5.8 ms | 5.4 ms | 5.2 ms | 0.5 ms | 0.0 ms |
| `main` | 237.3 ms | 224.3 ms | 210.8 ms | 56.6 ms | 13.7 ms |

All columns ran in one window with the load average near 20 (other lanes'
suites), so read the ratios: the interpreters are about four times LuaJIT's
interpreter here. On a quieter machine earlier the same image ran `main` in
about 95 ms on every tier (120 ms before the cache and the present-slot
paths). `methods` is slower on the typed tier than interpreted: a compiled
`CallMethod` goes through `j_call_method`, which walks the receiver and
copies the arguments, where the interpreter pushes a frame.

**Plain `.lua` files.** The checker refused `t + 1`, `t()`, `t .. s` and
`t < u` on a table, and typed `setmetatable`'s result as the bare table, so a
Lua program using metatables did not compile for the VM at all. A `.lua` file
checked without the strict rules now treats a table or an unknown operand as
dispatching at run time (result unknown), and `setmetatable` answers `any`.

**Roots on a raise.** A helper that pushed handles and then raised (a
`__call` from compiled code, any metamethod helper) left them pushed until the
task ended. Every catch point that recovers (`guarded`, `pcall`, the run
loop, the core's single-op step) now truncates the handle stack to its depth
on entry; `raising_handlers_release_their_roots_on_every_tier` checks it.

Not done, from the plan's interception item: typed operators on records still
lower to the generic opcode and dispatch through the declaration (no direct
`CallK`), interface tables are not in the image, and a metamethod call runs
its handler on a scratch task (`call_value`), which is most of what the
vector section costs. Handing the handler a frame of the caller's task needs a
delivery mode in the frame header (first result only, converted to a boolean
for comparisons) that every return path on every tier honors.




## Memory across workers (2026-10-16)

A worker used to receive a copy of everything it was given. Now an immutable
region crosses by reference and a heap array moves; both cost the same
whatever their size. `src/sharing.rs` holds both, `persist.rs` hands it the
bytes owners it answers for, and `workers.rs` and `channels.rs` carry the
results beside their messages.

**Shared blocks.** `ByteBuffer::Shared` is a bytes owner over an
`Arc<sharing::Block>`: one immutable allocation any number of VMs hold, each
through its own owner object, so every collector traces only its own heap and
the last owner to be swept frees the bytes. Every storage view over a shared
owner is read-only (`storage::view` and the physical fast path both ask), so
readers never synchronize; publication and release are the reference count.
`nupp.mem.sharedbytes` makes its blocks this way through the storage
provider's `share`: `copy` copies its string once into one (as the name and
LuaJIT's library say), `readFile` likewise, and `freeze` turns the builder's
own allocation into the block without copying.

**Moves.** A `nupp.mem.heap` array (a record of shape identity
`nupp.mem.heap:Array`) reachable from a worker's arguments or a settled task's
results moves: the crossing takes the `AlignedBytes` out of the sender's
owner, leaving `ByteBuffer::Moved`, and the receiver's owner adopts the same
allocation. The checker already allows such an array to cross only where the
sender gives it up (`nupp.workers.spi`: a `takes` parameter or a result), so
the sender has no binding left; a view it still reaches through an alias
raises "storage was moved to another worker". Channel sends do not consume
the sender's binding, so arrays are still copied through a channel, while
regions cross channels by reference too.

**The crossing.** `sharing::send` runs a graph encoding with an outbox:
shared owners become attachment indexes, claimed arrays become move
indexes, and only once the whole message encoded are the claimed allocations
detached, so a failed encoding leaves the sender untouched. `receive` decodes
with the attachments as an inbox; anything not adopted drops with it, so a
delivery that fails after extraction (a callee the worker cannot start, a
cancelled worker, a result the parent cannot load) frees a moved allocation
exactly once. Ownership on failure is therefore: before the crossing the
sender keeps it, after it the in-flight message owns it and frees it.

**Checkpoints.** A checkpoint has nobody to share with, so it writes a block
self-contained: its id (a random process nonce and a counter), alignment and
bytes, once per owner object in the graph. Restoring looks the id up in a
process-wide registry of live blocks (weak references, pruned as it grows)
and shares the live block when its bytes match; otherwise it rebuilds the
block once and registers it, so a restored worker naming the same id shares
the parent's restored block. That is the channel registry's protocol. A
moved husk checkpoints as a husk. A channel's queued messages keep their
attachments in the same self-contained form (queue format 2; format 1
still restores).

**What a worker body needed besides.** Moving an array is only useful if the
worker can write it, and that exposed two gaps unrelated to copying: a
worker runs none of its modules' bodies, so record shapes whose methods are
set as a module loads (the span implementations a heap array's `read` and
`write` return) had none, and `_G.__nuppCleanupRegistry`, which `with`
consults for an affine terminal, was empty. `src/worker_context.rs` finds
what the body can reach -- its graph's objects, the functions they and their
code name, the shapes those functions create or test, transitively through
those shapes' methods -- and carries those shapes' methods and the registry
entries those functions name. The worker loads the same code, so shape ids
agree.

`fork` no longer snapshots the new worker's whole VM into the parent at once:
that snapshot copied every argument the crossing had just shared or moved,
and the parent's own checkpoint refreshes every worker snapshot anyway
(`snapshot_workers`). A worker record without a snapshot is only an error if
the worker is lost before any checkpoint captured it.

### Measured

`cargo test --release --lib sharing::measure -- --ignored --nocapture`
times one crossing between two VMs (encode with attachments, decode); the
`worker_memory` measurement times a whole worker round trip (spawn, run,
settle, results back). Best of seven and of five, on a machine at load
average 26, so the small rows are noisy:

| bytes | shared region | moved array | string, copied |
| ---: | ---: | ---: | ---: |
| crossing, 1 KiB | 29.5 us | 32.2 us | 2.6 us |
| crossing, 1 MiB | 28.8 us | 29.9 us | 237.9 us |
| crossing, 64 MiB | 34.9 us | 30.7 us | 14,562 us |
| worker round trip, 1 KiB | 1.60 ms | 1.61 ms | 1.40 ms |
| worker round trip, 1 MiB | 1.82 ms | 1.80 ms | 3.02 ms |
| worker round trip, 64 MiB | 3.29 ms | 1.91 ms | 67.5 ms |

A region or array crossing costs about 30 us at every size: the view's
descriptor graph, not its bytes. Below tens of kilobytes a plain string's
copy is still cheaper, the same guidance the LuaJIT libraries give.

### Evidence

`tests/worker_memory.rs` (collector stress on both sides): a 1 MiB block
crossing into a worker and back as the same `Arc`, read-only shared views,
an array moving and its stale sender view refused, a failed delivery,
`tasks.fork` through the scheduler, graph and whole-VM checkpoints restoring
onto the live block, channels carrying blocks by reference across a
checkpoint, live workers checkpointed and restored sharing the parent's
block, and a cancelled worker releasing what it was given.
`tests/memory-smoke.py` adds regions crossing by reference (a slice, a frozen
builder, a 1 MB region, a region a worker made coming back) and an array
moved to a worker, written there, moved back and moved again, compared by
address, on all four engines with incremental collection, the root oracle
and quarantine.

Open: a string crosses as a copy (its bytes live inline in the sender's
heap; a region is the by-reference vehicle). Lent disjoint mutable regions
under a join and the VM-free job entry belong to the parallel-jobs plan and
are not started.

## Semantics the ported suites found (2026-10-16)

The semantic gaps listed above as still `port-required` are closed:

- **Module chunks** read `...`: `require` passes the module name and `nupp
  run` the program's arguments. Only a chunk whose top level reads `...` is
  vararg, so every other chunk stays compilable.
- **Integer `%` and `//`** by zero are nan or an infinity, as the language and
  LuaJIT answer, so their results never enter an integer register: a local
  that holds one, or is ever assigned one, keeps a float register, and the
  integer fast paths do not take them.
- **xpcall's handler** runs where the error is raised, before any frame or
  cleanup unwinds, on both the builtin path and the frame driver's protected
  record. A scratch task records the task whose builtin started it, so
  `debug.traceback` and `debug.getinfo` levels continue through builtins as
  Lua's stack runs through C functions, and a handler sees the raising frame.
- **Generic fields**: a field a generic record declares at a type parameter
  holds whatever the record's own code stored there, and `as T` erases, so a
  read of one does not enter a typed register on the instantiation's word.
- **Record declarations** are held through their shape only while an instance
  of the shape is marked, as an instance's metatable holds its declaration
  under LuaJIT; constructing one names the declaration, so the code that can
  make an instance keeps it. A `local record` type nothing uses is collected,
  and its shape forgets it before the sweep. The diagnosis above was a dead
  register; it was the shape.
- **Type functions**: an input an application supplies is the one its blueprint
  names, before a source an in-process envelope carries, so a cached result
  never answers another application with a look-alike local record. A self
  binder another environment's declaration already claimed (interning is per
  process, nominals per environment) stays that declaration's, which is what
  gave a bounded generic's derived `Debug` a `T` it could not render.
- **`package.imageLoader`** answers a module an image loaded at run time
  declared only until `require` has loaded it; after `package.loaded` forgets
  it, the loaders behind reload it, and loading a newer image makes that image
  current again. The running image keeps answering for its own modules.
- **Providers**: the VM's clocks, worker lanes and suspension implementation
  are the native providers (`nupp.runtime.provider.nativetime`,
  `.workers`, `.suspension`) the shared facades select through SPI, so a
  program's own provider wins as on LuaJIT. The VM registers
  `nupp.workers.native` as the bridge marker the selection reads.
- **`math.random`** keeps its state in the VM: each worker VM draws its own
  stream, and a checkpoint restores the sequence where it was.

The derive path-spelling case compared a project file with a file outside the
project, which are two modules; it now spells one file two ways, and the images
agree.

All eight suites ran on the VM afterwards. `operatortest`, `orexittest`,
`methodtest`, `runtimereflectiontest`, `derivetest`, `typeleveltest` and
`spitest` pass and are `portable`; `spitest` also needed a module that loads
SPI providers to publish its exports only once it has loaded, as the Lua
backend does, so a provider never sees a half-built facade. `clitest` passes
every case it reaches, the program-arguments one included, but on a loaded
machine the last four do not start inside the 600 s suite budget.

## Specialization and deoptimization (2026-10-16)

Runtime specialization in the typed tier (`src/specialize.rs`, the
specialized lowering in `src/jit.rs`), as the runtime plan's JIT section
decided on 2026-10-16 and its design document
(`~/projects/nupp-plans/todo/jit-specialization-design.md`) lays out. Off
by default: `JIT_SPECIALIZE=1` turns on feedback and specialization of
direct entries, `JIT_SPEC_FRAMES=1` also of heap-frame entries,
`JIT_FEEDBACK=1` feedback alone, `JIT_SPEC_STATS=1` prints the counters at
exit and `JIT_SPEC_TRACE=1` every plan and the weighing behind it.

**Feedback.** Per dynamic site (`CallDyn`, `CallK`, `CallMethod`,
`GetField`, `SetField`), up to three observed keys with counts and an
overflow count: a call target's function id, or a receiver's shape, its
metatable, or (for the Lua class idiom, whose objects are structural records
with a metatable of their own) both. The Rust loop records in the site
operations' arms of `step`, the threaded core in `h_calldyn` and
`h_getfield` through `rt_observe`. Instrumented generic compiled code counts
its calls and records only where it is already slow: method calls and field
stores in the helper they always call, a field read where its site cache
missed on a record. (Computing a call target's key inline at every dynamic
call cost the parser 25% more compile time for specializations that did not
pay, so compiled code does not record call targets.) Records live in `Interp::spec`, outside the heap, within
a byte budget (`JIT_SPEC_BYTES`, 8 MiB) that covers sites and pc maps, is
checked before anything is allocated, and remembers what it refused.

**Specialized versions.** At `JIT_SPEC_CALLS` (1,000) calls of an
instrumented direct entry, or entries of a heap-frame entry, the function is
compiled again from a `Plan`, if it is worth it: the plan must have a
method call, a field store or a field read that met several shapes, and
those sites must have recorded at least `JIT_SPEC_BENEFIT` (2) slow
executions per instruction of the function. A single dynamic target or a
monomorphic field read rides along but never pays for a recompile; on the
parser, versions for those alone cost more compile time (one large closure
took 100 ms) than they saved. The plan's sites: a method site becomes guards on the receiver's
shape or metatable (and, for a table or a metatabled record, a probe that
no field of its own shadows the method) followed by a direct call to the
method's compiled entry; a dynamic call with one target becomes the `CallK`
guard and direct call; a field read becomes shape compares and loads at
fixed offsets; a field store becomes a guarded store with the barrier. A
failed guard counts a miss and takes the generic helper in place. Past
`JIT_SPEC_MISSES` (1,000) misses the function is planned again from the
feedback the misses added; past `JIT_SPEC_VERSIONS` (3) versions it settles
on its generic entry for good. Direct and heap-frame entries keep separate
version counts. Object code never specializes.

Measured (2026-10-16, interleaved, 5 repeats, load 12 to 22, whole
processes including the eager compile; `tests/specialize-perf.py`):

| workload | generic JIT | `JIT_SPECIALIZE=1` |
| --- | ---: | ---: |
| Lua class idiom (`classes.lua`), process wall | 319 ms | 169 ms (0.53) |
| interface-typed records (`shapes.nupp`), process wall | 351 ms | 169 ms (0.48) |
| interface calls, one record type / three | 101 / 137 ms | 23 / 23 ms |
| Lua method calls, one class / three / replaced mid-run | 90 / 63 / 28 ms | 26 / 16 / 7 ms |
| a field read in a function called once (no OSR) | 19 ms | 21 ms |
| parser.nupp parse (`parsebench`, typed), process wall | 2.58 s | 2.67 s (1.03) |
| peak resident set, all of the above | | within 1% |

The heap-frame path (`--tasks`, `JIT_SPEC_FRAMES=1`) lost 5 to 9% on the
class and interface benchmarks against generic frame entries: every call
there is a boundary that returns to the driver, which no field guard saves,
and the per-entry counting and recompiles cost more than the known-shape
facts after a deopt exit gain. Feedback off costs nothing attributable on
the interpreter: the compiler's interpreted `check` of the lexer ran 3%
slower than the branch point both with the hooks in and with them compiled
out, so the difference is layout, not the hooks. The compiler workloads
(root emit, the lexer one-shot) run linked AOT, where specialization is off
by construction; the compiler-speed lane's hot-site list names no site
speculation would fix.

**Invariants.**

- Every guard is checked at every execution; nothing is hoisted. Method
  resolution depends only on state that bumps `Heap::proto_epoch` when it
  changes, and every method site compares it: shape descriptors
  (`set_method`, `redeclare`, an image installing methods), any table an
  `__index` walk visited (`F_PROTO`: stores, `setmetatable`, its free), and,
  since this change, a weak entry cleared from such a table
  (`Heap::clear_weak`). So a reentrant call, a suspension or a mutation is
  seen at the next use of the site.
- A method found through a weak table is not specialized at all.
- Feedback and versions are not program state: never traced, never in a
  checkpoint or snapshot, absent from a restored VM and from worker VMs.
- `Interp::invalidate_specializations(fid)` drops a function's feedback and
  versions for a body that changed (the hot-reload hook: `hotpatch.rs`'s
  `invalidate_function` should call it once that branch lands here).

**Deoptimization.** On heap-frame entries, a field guard that fails leaves
through a deopt exit instead: every value register live into the operation
is stored to the heap frame as is, every live integer, float and vector
register into its window, and the entry returns the operation's own pc, so
the interpreter runs it generically and nothing of it runs twice. The
closure, varargs, cleanups and protected calls are already the frame's and
the task's. After a guard that cannot fall through, the code that follows
knows the register's shape, which a field access on it uses. Past
`JIT_SPEC_DEOPTS` (100) exits the entry is planned again. What the exit
does not reconstruct yet: inlined callee frames (nothing is inlined),
eliminated allocations (nothing is eliminated), and values held in a
representation the frame lacks (none exist; the first one adds a recipe).

**Shared contracts.** Every specialization goes through the same five
pieces, so a new one reuses their correctness machinery:

- *Operation effects* (`src/effects.rs`, in every build): what an operation
  or helper may do (allocate, mutate assumed state, raise, reenter, transfer
  the frame). `frame::boundary` is its transfer class; anything unlisted is
  assumed to do everything but transfer.
- *Facts and assumptions* (`specialize/facts.rs`): each planned site's
  dependencies, miss action (generic fallback on direct entries, a deopt
  exit on heap frames) and the fact it leaves. `validate` checks a plan
  before compiling; the lowering keeps facts per value and block, ends
  mutable ones after effects that may falsify them, and records each use so
  a compile is checked for guard dominance.
- *Recoverable state* (`specialize/recovery.rs`): one description of a heap
  frame at a pc and one emitter (`spill_state!` in `jit.rs`) for boundary
  spills, polls and deopt exits; each recovery point names its body and
  resumes before its operation.
- *Version lifetime* (`specialize/versions.rs`): a compile returns a
  `Version` (body, convention, policy, code range, registered stack maps,
  dependencies, recovery points, feedback owner); `spec_install` checks it
  is still current before any entry points at it. Retired code, field-cache
  banks and feedback records stay alive and charged until teardown.
- *Tier policy* (`specialize/policy.rs`): direct and heap-frame entries are
  conventions; which specializations a compile emits is a `Policy`.

The `CallDyn` target specialization goes through the same plan, guard, miss
and installation as the method and field sites. Making the test fixture size
the entry table as the CLI does (before the globals add functions) found
that an install which grew the table moved it under compiled code; nothing
grows it now.

**Tests.** `tests/specialization.rs` runs the programs of
`tests/specialize/` on the Rust loop, the threaded core, eager, lazy and
heap-frame entries with feedback off, on and specializing, under the
collector's interleaved, stress, oracle and quarantine modes, and with
`JIT_SPEC_CHAOS` forcing guards to fail every 1, 3 and 17 executions; plus
guard hits, misses, invalidation by a replaced method, metatable and
instance field, the version cap, deopt exits with each live value kind and
a pending cleanup, a patched body, checkpoint neutrality and the byte
budget. `tests/specialize-emit.py` writes the two images;
`tests/specialize-perf.py` times the class and interface benchmarks.
