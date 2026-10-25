# Native runtime authoring experiment

This implements a native-authoring experiment against
`codegen-experiment@73d54b904cd014f666671407e4a1751fb8de2418`. The call and
return candidate passes the 2% noninferiority gate on every workload; the full
compiler check still regresses cold, so every candidate remains disabled.
This is an isolated experiment, not a completed Rust-removal migration.

The ordinary Nupp parser and checker validate private handler source. A small
Nupp compiler then emits a whole-function native IR, which a Rust bridge lowers
to Cranelift. The profile supports exact integer words, IEEE double operations and bitcasts,
raw pointer accesses, immutable locals, terminating branches, and guaranteed
tail dispatch. Anything
outside that profile is rejected. There is no interpretation fallback inside a
compiled handler, and no new C or handwritten assembly.

Two executables exercise different contracts:

- `runtime_tail` compares Rust `become`, directly constructed Cranelift, and
  Nupp-authored handlers over the same seven synthetic operations. It checks
  helper ABI preservation and bounded native stacks, emits objects for macOS
  ARM64, Linux x64, and Windows GNU x64, and can link the host object. Its call
  frames and helper are synthetic; it does not test the collector.
- `runtime_slice` emits 63 handlers against the real instruction, context,
  function, and heap layouts. `--integers-only` selects the original 18 integer
  and branch handlers; `--without=NAME,...` drops named handlers, which is how
  the 57-handler leaf slice reproduces. Float arithmetic, tagged numeric
  operations, closure captures, constants, array reads, record reads, lengths,
  and now ordinary calls, returns and result padding are authored in Nupp. The
  native chain returns before unsupported instructions or OSR transitions; the
  Rust core then executes that instruction once with its existing root/frame
  rules. No helper or allocation can run inside this native slice. Growth,
  GC, scheduler policy, and the remaining handlers retain their existing code.

A local function with the handler signature is a handler; any other local
function is a helper, inlined where a handler tail-calls it. The Rust core's
`push` and `dynamic_call!` have one Nupp spelling each this way, and the
dispatch stays a tail transfer. Bounded word loops (`copyWords`, `fillWords`)
are the only loops: parameter copies, nil fills and result copies.

The producer prints each handler as Cranelift's textual IR (CLIF), with the
structure offsets it names read from `runtime_slice --layouts`, which measures
the Rust layouts the object links against. The shim parses the text with
`cranelift-reader`, checks the handler contract on the parsed function (the
tail signature, no call or symbol, `return` only of the entry pc or the reenter
code, every dispatch preserving the context), and compiles it as printed. The
object this produces is byte-identical to the one the earlier Rust lowering of
the private JSON IR produced, so the measurements below hold for both; the JSON
path stays reachable through `--json-ir` until it is retired. Deciding the IR in
Nupp is the shape the rest of the migration takes: Nupp emits CLIF, and Rust
parses, compiles and links.

The native IR and object are trusted build inputs, not guest formats. The
generated sidecar checks opcode values, value tags, and all accessed structure
offsets at compile time.
The feature requires an explicit object and has no default or runtime switch.
The derived-frame object also links with `--no-default-features`, without a
Cranelift runtime dependency, and reproduces all six workload checksums.
Removing Rust handlers, changing bootstrap pins, or replacing the production
dispatch table requires the later correctness and performance gates.

## Reproduce

Preserve a release `nupp-vm` built with `--features aot` at the exact baseline
commit before making changes. Use the pinned stage-zero image as the seed.
Run from the experiment worktree:

```sh
python3 native/crates/vm/experiments/runtime/run.py \
  --baseline /absolute/path/to/preserved/nupp-vm \
  --seed /absolute/path/to/pinned/compiler.image \
  --compiler-image --derived-frame
```

The seed is the pinned stage-zero image, cached by `scripts/toolchain
stage0-image` as `compiler.image` under the toolchain cache.

The script refuses to overwrite a different baseline. It builds and checks the
Nupp producer, exercises JIT and host AOT ABI paths, emits the production slice,
runs rejection checks, builds the opt-in runtime, and records hashes under
`build/native-runtime`. `--integers-only` selects the narrower candidate;
`--skip-abi` avoids repeating the ABI probe. `--packed-state` keeps the dispatch
table in a tail-call argument and puts the context/frame pair in the entry
frame; the six-argument tail ABI remains within ARM64 argument registers.
`--derived-frame` instead checks `frame == regs - 32` at entry and derives
the frame from the boxed window. It keeps context and table in registers
without allocating the packed pair; a failed entry check returns unchanged
to Rust. The layouts are mutually exclusive. The ordinary layout reloads
the table in each handler. `--eager-conditions`
retains the materialized-boolean control for comparison with direct branches.
All native expressions are pure apart from explicit stores; raw loads are
nontrapping. Direct condition lowering may skip pure operands, while boolean
value expressions remain eager.

The bootstrap image must understand all source syntax; no stage-zero language feature was added here.

Use the existing xbench payload in a stamped template. The supplied stamper is
for thin ARM64 Mach-O binaries only and preserves runtime symbols:

```sh
python3 native/crates/vm/experiments/runtime/stamp.py \
  build/native-runtime/baseline/nupp-vm /path/to/xbench.template \
  build/native-runtime/baseline-app
python3 native/crates/vm/experiments/runtime/stamp.py \
  build/native-runtime/slice-runtime /path/to/xbench.template \
  build/native-runtime/candidate-app
python3 native/crates/vm/experiments/runtime/compare.py \
  build/native-runtime/baseline-app build/native-runtime/candidate-app \
  build/native-runtime/comparison.json --forks 12 --scale 2
python3 native/crates/vm/experiments/runtime/checks.py --forks 3 \
  --candidate /absolute/path/to/preserved/candidate-runtime \
  --output build/native-runtime/compiler-expanded.json
```

The process harness alternates execution order, checks every result, records
RSS, and resamples paired independent forks. Its inputs run through the actual
scheduler. The ABI pilot's inner timings are diagnostic only. The compiler
check harness extracts fresh pinned source archives and verifies that a cold
run checks modules and a warm run checks none; moving `NUPP_CACHE_DIR` alone
does not clear the project's build state.

For Rust tests, pass the generated object explicitly:

```sh
NUPP_NATIVE_RUNTIME_OBJECT="$PWD/build/native-runtime/slice.o" \
  cargo test --locked --release -p nupp-vm \
  --features aot,native-runtime-experiment -j 4
```

At the pinned commit, `aot_relocation` fails to compile because its hot-patch
call supplies `&String` where the API requires `&[u8]`; this also fails without
the experiment. Running the remaining targets explicitly passes 440 tests, with four existing
ignored tests. Thirteen tests directly exercise the native object, including
NaNs, signed zeros, saturation, aliases, bounds, shapes, metatables, capture and
constant layouts, OSR, and rejection of a nonconforming frame/window pair. The 24 rejection cases include float/word/boolean
representation mismatches and run malformed IR against all three layouts. No fixpoint
or Linux/Windows native execution is claimed. Cross-target object generation covers the synthetic ABI pilot and
does not establish native execution, stack walking, or exception correctness
on those platforms.

## Ordinary Nupp to CLIF

`nupp.experiment.lower` compiles ordinary typed Nupp, checked by the ordinary
checker, to CLIF with nothing managed underneath: `int64`, `uint64`, `number`
and `boolean` values, `voidptr`, mutable locals, `if`/`elseif`/`else`, `while`,
`repeat`, numeric `for` with a literal step, `break`, `continue`, compound
assignment, `and`/`or`/`not` with short circuits, the arithmetic, bitwise and
comparison operators (floored `//` and `%` on `int64`, as the language
defines them), and direct calls between a module's functions, recursion
included. It builds SSA form itself, placing block parameters by the
sealed-block algorithm, and prints blocks in reverse postorder so every
definition precedes its uses. `clif_run` parses a CLIF file, resolves `%name`
calls between its functions, compiles it just in time and calls one function
through a one-shape trampoline, so a test needs no Rust.
Structs declared in Nupp are reached through raw pointers: a field read or
`@unsafe` write lowers to a load or store at the offset the compiler's own
layout model (`nupp.compiler.targetlayout`) gives the field, `nil` is the null
pointer, `as` between types of one representation is free, and the private
memory intrinsics the handler slice is written against are accepted, so that
profile is a subset of this one. `lower-check.py` compiles
`lib/nupp/experiment/samples/scalars.nupp` and `structs.nupp` and runs
fifty-six cases against answers computed in Python; `clif_run` passes
`buffer:N` arguments as the address of N zeroed bytes.

Three things the sample had to work around are findings about today's
language, not the lowering: a recursive local function's result needs its
declared type restated (`local a: int64 = fib(n - 1)`), numeric `for` ranges
over numbers rather than the fixed-width integers, and compound assignment
answers a number. A runtime written in this profile needs first-class
fixed-width integers.

## Frame transitions

The exit word a native chain answers is the address of the instruction Rust
resumes at, or `EXIT_REENTER` (1). Nothing inside a chain moves the stack, so
`ctx.cur` names the current frame at every instruction, as the Rust handlers
keep it; `native_segment` reads it back on exit and re-derives the windows when
the frame differs from the one the chain entered with, by address or by
function: a return followed by a call inside one chain puts another function's
frame at the same index, and its integer and float windows sit elsewhere. The
instruction named then runs exactly once through its Rust handler. `EXIT_REENTER` is taken when a
frame was pushed or popped in frame mode and the frame driver has a say over
it -- a compiled frame entry, a function with vector instructions, or JIT
frames -- and goes through `tail_entry` as the Rust call and return handlers
do, on the frame the chain already pushed or popped. Outside those cases the
chain continues into the callee's or caller's frame without leaving.

`Call`, `CallK`, `CallDyn` (the Rust handlers share one body; the table points
both opcodes at the one source function), `Ret`, `RetNil`, `RetN` and
`PadResults` are native. Everything the Rust handlers hand to Rust still goes
there, and before any state changes: stack growth, varargs, typed parameters,
the unavailable function, compiled entries, builtins, iterators, non-callable
values, feedback, the JIT's call threshold (counted as `count_call` counts,
with the hot call itself going to Rust), guarded returns, wide returns, and the
task's final return. A call that needs growth leaves before the count moves, so
it counts once.

The contract tests build real stacks and function tables, compare the native
push with the Rust core's own `push` word for word over argument and parameter
counts, every call opcode, closures and plain functions, and the frame-mode
policies; exercise each fallback and check that nothing changed; deliver
direct and indirect results; and run whole programs (recursion through dynamic
and static calls, three results padded to four, recursion past the initial
stack so growth happens in Rust under native frames, nil returns, and a return
and call that put two register layouts at one frame index) in both frame
modes. The last of these is the shape the specialization suite's `shapes`
program first caught: a field count of 4 for 340000.

On ARM64 the call handlers carry a stack frame of six callee-saved registers;
the return and padding handlers have none. The frame derived from the window
is required: a frame-changing handler is refused under `--packed-state`, whose
entry-owned pair would name the frame the chain entered with.

With all 63 handlers, the paired ratios against the pinned Rust runtime are
0.678 for fib (95% interval 0.673-0.684), 0.860 for closures, 0.797 for
records, 0.984 for tables (interval 0.971-0.996), 0.942 for loops (interval
0.904-0.982) and 0.989 for strings (interval 0.969-1.011). Every
workload passes the 2% noninferiority gate; this is the first candidate to do
so. Median maximum resident set is within 0.1% of the baseline.
`results-expansion.json` under `candidates.calls` and `compiler.calls` holds
the pairs, hashes and intervals; the recorded object and runtime reproduce from
the formatted source.

Three paired full compiler checks still regress cold: median 43.79 s for Rust
and 46.55 s for the candidate, a 6.3% gap against the leaf slice's
7.4%, but not gone. Warm medians are 0.608 s and 0.616 s. Every cold run
checks 504 modules without diagnostics; warm runs check none. The whole-program
gate is the one that governs promotion, so the experiment stays disabled: the
compiler's time is in field and index lookup, the helpers they call, and the
remaining boundary crossings around them, not in calls and returns.

With the final object, 446 Rust tests pass across 66 targets with four ignored
and the pre-existing `aot_relocation` compile failure excluded; the
specialization suite, whose `shapes` program caught the frame-identity exit
bug, passes; 18 native contract tests and 30 rejection checks pass.

## Initial slice

The 20-opcode candidate regresses loops, tables, and closures; excluding Move
and Nil reduces but does not remove those regressions. See `results.json` for
paired estimates and artifact identities. Do not enable either split or delete
its Rust counterparts. The next native-core candidate needs longer contiguous
coverage or a cheaper boundary, followed by the same whole-program comparison.
A separate loop profile puts 156 of 743 samples in the boundary functions.
Disassembly shows 43 bridge/entry/exit instructions and 80 bytes of fixed stack
frames per native segment. The three paired full compiler checks also run
about 4% slower cold; all recheck 504 modules without diagnostics.
The pure handler pilot leaves that possibility open; it does not prove parity
for a complete interpreter or justify a self-hosting compiler migration.

## Expanded slice

`results-expansion.json` records each successive candidate, its exact input
functions, hashes, paired timings, RSS, and compiler checks. The first two
candidates use 37 functions, the next uses 51, and the complete slice uses 57.
The earlier eager-condition IRs reproduce from the final source by selecting
those function names from an `--eager-conditions` build. The final formatted
source reproduces the measured direct-branch object and runtime byte-for-byte.

Passing the table as a seventh ordinary argument was rejected before duration
measurement: ARM64 put it on the stack and added a frame and argument traffic
to every handler. The packed pair keeps the hot chain register-only, at the
cost of entry setup and context/frame loads where needed. Deriving the frame
removes those loads while preserving the existing public entry ABI. On ARM64,
its 57 handlers have no stack frames, and only the entry materializes the table
address. None of the layouts adds C or assembly, changes guest compilation, or
moves a GC-capable helper into the native segment.

With the derived-frame layout, the paired ratios against the pinned Rust
runtime are 0.949 for loops, 0.947 for tables, and 0.787 for records. Their 95%
intervals all clear the 2% improvement margin. Fibonacci regresses to 1.081
(95% interval 1.077–1.084). Strings pass noninferiority; closures remain
inconclusive, with an upper bound of 1.022. These are 12 paired independent
processes per candidate, not a claim about an interpreter written in Nupp in
general or about a newer Rust core.

Three paired full compiler checks still regress: median cold time is 44.17 s
for Rust and 47.44 s for the derived-frame candidate; warm time is 0.613 s and
0.635 s. Every cold run checks 504 modules without diagnostics; warm runs
check none. These three pairs support the decision but are not a separate
statistical noninferiority verdict.

A separate Fibonacci profile attributes 131 of 747 exclusive samples to the
entry/exit boundary, 268 to Rust calls, frame entry, and return, and 37 to Rust
result padding. This supports prioritizing the frame-transition protocol;
it does not prove the eventual speedup from porting it. A separate five-second
window during a cold compiler check records 240 exclusive boundary samples;
field/index lookup is prominent as well. The next work must address the
compiler's lookup/helper paths alongside ordinary calls.

The slice remains a disabled authoring and ABI experiment. Allocations,
writes that require barriers, growth and every helper still cross to Rust.
The next migration needs the helper protocol -- explicit effects per helper,
roots and execution state published before an allocating or reentrant call
and reloaded after -- and the field and index fast paths the compiler profile
names. Passing the six workloads is necessary and not sufficient to remove
the Rust core. The remaining work is tracked in
https://github.com/nupp-lang/nupp/issues/75.
