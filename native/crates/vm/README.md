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
