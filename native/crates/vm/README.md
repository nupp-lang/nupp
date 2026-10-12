# nupp-vm

The Nupp runtime of the runtime plan (`~/projects/nupp-plans/todo/nupp-runtime.md`,
contracts in `nupp-runtime-contracts.md`), started 2026-10-11 as the real P3
build after the prototype in `bench/runtime-experiment` had answered its design
questions. No JIT here: that is P5. What is here is the object model, the heap
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
| `host` | a pool of host threads serving file, sleep, process and directory requests as plain data |
| `threaded` and `csrc/dispatch.c` | the tail-call-threaded core and its helpers |
| `jit` | the typed tier: Cranelift lowering, its helpers, the stack-map root walk |
| `emit/emitmod.lua` | the module-graph emitter from the checker's tree, run with `nupp run` from `emit/` |

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
- **Snapshots are prepared for, not built.** `Heap::each_child` is the one
  walk the marker and the oracle share and the serialiser will share; the
  roots are enumerable through one trait; task stacks are plain words. The
  serialiser and the restore path are P5 work.

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

Ahead-of-time compilation of the bundled compiler, scoped: the lowering
bakes addresses as constants (the extras and result-count words, the
entries, call and shape tables, each site's cache, the current closure
word), which an object file cannot carry; they become loads from one
runtime table reached through a symbol, with per-site caches in an area
the image owns. `cranelift-object` then emits the image's functions with
the helpers as undefined symbols, the build links them into the binary
or a shared object, and loading binds the helpers and the table. Nothing
in the lowering changes shape otherwise; the stubs become ordinary
functions of the object.
