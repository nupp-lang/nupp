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
restore without that image file. SIMD, compiled suspension, plugin refusal and
actual console SDK validation remain gates for the full no-JIT target.

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

`nupp.compiler.vm.project` reads projects through the existing compiler module
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
Selecting/excluding roots is the caller's responsibility. Tecs lifecycle,
selection and skipped-value reporting remain future work; the current Tecs
snapshot path uses LuaJIT FFI storage and needs that storage migration first.

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
The initial implementation spills all windows and routes storage operations
through the driver; liveness-based spilling and performance tuning remain open.
The CLI selects frame entries for images with cleanup regions as well as for
`--tasks`. Ordinary native entries remain available for synchronous images
without those regions.
AOT frame-entry emission is not implemented; no-JIT builds execute these frames
with the interpreter.

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
code obtains VM addresses through `nupp_vm_runtime_v2` on the executing thread.
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
