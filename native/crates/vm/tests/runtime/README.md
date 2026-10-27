# Native runtime measurements

This directory keeps runtime migration evidence. The Nupp runtime is the chosen
implementation; these records validate changes and track the remaining work.
The earlier measurements below predate the current `nupp-native-runtime` plan:

- the lowering of ordinary typed Nupp to Cranelift's textual IR is
  `nupp.compiler.clif.lower` (`src/nupp/compiler/clif/`), with its SSA
  construction in `nupp.compiler.clif.ssa`. Direct checked-syntax lowering is
  temporary; P1b moves it through the Nupp semantic graph;
- the handler sources are the modules under `src/nupp/runtime/vm/`, one
  per opcode group (`core`, `calls`, `protocol`, `lookup`, `boxing`), written
  against the intrinsics declared in `intrinsics.d.nupp`;
- the glue is `nupp-vm native (layouts | object | jit)` in
  `native/crates/vm/src/native_glue.rs`; the native contract tests are
  `native/crates/vm/src/native_tests.rs`;
- `python3 scripts/vm-cli runtime [--link]` (also `nupp task runtime`) builds
  the object into `build/native-runtime/`, and `scripts/vm-cli build
  --native-core` installs a compiler whose runtime links it;
- the paired measurement protocol is `nupp bench --against`, with the six
  workloads in `bench/vm/`.

`results.json` records the first 20-opcode slice and `results-expansion.json`
every later candidate: its input functions, hashes, paired timings, RSS and
compiler checks. The final candidate recorded there (`candidates.helpers`,
`compiler.helpers`) passed the 2% noninferiority gate on all six workloads
(fib 0.68, records 0.78, closures 0.86, tables 0.95, loops 0.99, strings
1.00) and ran the cold compiler check faster than the pinned Rust core
(43.70 s against 42.55 s, warm 0.599 s against 0.584 s). The baseline for
every number is `codegen-experiment@73d54b904cd014f666671407e4a1751fb8de2418`
built with `--features aot`.

The plan these numbers fed is `nupp-vm-in-nupp` in the plans repository;
what the evidence showed along the way (frame identity by address and by
function, eager condition flags, support functions past eight arguments, a
mistyped tag constant) is written into the handler sources' comments and the
contract tests rather than repeated here.

`n09-measurements.json` records partial N09 integration at `23cffbcca`, with
source and artifact hashes, verification, twelve paired forks of all six
workloads with the JIT on and off, and a quiet 24-fork interpreter loops run.
The native core remains opt-in: interpreter loops, tables and closures and
JIT loops and strings miss the 2% margin. The cold compiler check completes
after the OSR fix but remains slower than Rust in its diagnostic single
pair. These results do not close N09 or the default-runtime gate.

`interpreter-resize-measurements.json` records the helper change at
`53a063aad`: resizing a table's external vector cannot enter the VM, so it
keeps pending frame state and budget charges in the native context. Twelve
paired interpreter forks improve closures 27.0% and tables 7.4% against the
previous Nupp runtime. Against pinned Rust, closures improves 9.0% and tables
passes the 2% margin; 24-fork repeats settle the noisy fib and strings
comparisons. JIT-on results, exact hashes, raw samples, correctness checks
and the matched-control compiler failure are included. Interpreter loops,
the native-only compiler failure, D0 and the remaining migration stay open.

The performance baseline is now production LuaJIT on `main`, as directed by
the owner on 2026-10-26. Rust comparisons above describe historical runs.
Current comparisons must identify main's revision and LuaJIT executable,
leave LuaJIT enabled, and use the same source and checksum on both sides.
Record interpreter-only and JIT-on Nupp candidates separately.

`p0-controls-2026-10-26.json` records twelve paired fresh processes for every
workload against production `main@fca53ef827b72d314c5dc228353d50007eb95b03`,
with a 2% practical margin. The Nupp side is interpreter-only, with the native
core and the helper return-count and unlimited-budget corrections. Both sides
run identical guarded workload sources; every LuaJIT workload process asserts
its actual `jit.status()`. Inputs and executable/image hashes remain unchanged.
The two `luajit-main-*-2026-10-26.json` files retain the complete samples.

| Workload | Nupp / LuaJIT on | Nupp / LuaJIT off |
| --- | --- | --- |
| fib | 10.18 | 2.42 |
| loops | 2.74 | 1.12 |
| tables | 17.50 | 1.08 |
| strings | 4.25 | 2.46 |
| records | 4.36 | 0.98 |
| closures | 13.85 | 2.94 |

Ratios are geometric means of paired durations; lower is better. The interpreter
misses the production margin on all six cases. Against LuaJIT-off, five miss the
margin; records has an inconclusive duration verdict with its upper regression
bound below 2%. The production comparison remains the shipped-mode merge target.
The JIT-off row diagnoses interpreter costs.

That receipt also freezes the existing linked compiler at `ae66f972b`, with
6,113 AOT entries. Two fresh processes execute compiled compiler frames with
executable memory denied and emit byte-identical binary images. The harness
also verifies the emitted program, rejects a valid mismatched image and checks
compiler diagnostics. This is the existing AOT continuity control, not the
handler-derived AOT tier. Compiler timing and resource ceilings remain open.

`source-inventory-2026-10-26.json` maps all 159 tracked Rust files and all 15
workspace members to their deletion phase or narrow bridge responsibility. It
counts 58,532 nonblank production lines in 92 files, 19,253 test/example/fixture
lines in 67 files, 14 product crates and one test fixture crate. The 301-package
all-feature dependency union includes platform, dev and build dependencies;
it is not a default executable dependency count. Planned Nupp owners are marked
separately from existing modules. The migration plan's acceptance ledger keeps
unfinished history/replay and platform capabilities explicit.

`native-result-count-2026-10-26.json` closes the reproduced native compiler
`Move` failure. `unlimited-budget-2026-10-26.json` records the budget correction
and its finite/unlimited call/back-edge regressions. Full native compiler
acceptance, handler contracts, remaining interpreter groups and Rust deletion
remain open.

`logical-slots-2026-10-26.json` records the logical slot contracts added to
current value, integer and float windows, including argument copies and varargs.
Each access names its frame, window and logical index; checked Nupp metadata
identifies the class, scalar type and read/write operation. The current direct
lowering only emits the corresponding memory access. Slot promotion and other
semantic optimization remain work for the common Nupp graph. Absolute return-link
addresses, immutable program loads, vector slots and publication/root proofs
remain open in P1a/P2.

All six workloads meet the 2% refactor-cost margin against the preserved Nupp
control. Each has twelve fresh pairs; loops has a 48-pair repeat whose upper
regression bound is 1.0%. These timings establish no speedup. Production
acceptance still uses the LuaJIT-on main control recorded above.

`native-contracts-2026-10-26.json` records retained program-body loads, logical
caller destinations and ordinary specialization functions with checked Nupp
metadata. Code-body loads do not classify live function tables or heap-bearing
constants as immutable. Specialization contexts are no-ops in the interpreter;
constant proofs, context balance and slot promotion belong to the common Nupp
graph.

The equality helper now publishes native frame state before guest callbacks and
reloads it on success and error. GC, parked frames, typed windows, captures,
varargs and result packs have focused regressions. In the native interpreter,
finite calls and taken back edges charge once; untaken edges and parked attempts do not charge, and terminal
returns can finish at zero. Finite method and protected calls retain their
existing Rust boundary until P2 replaces it. General graph root/publication
proofs remain open.

The checker change passes 1,972 shared cases and the integrated contracts pass
113 native/annotation cases. The final object passes all 114 crate tests, with
two existing ignores. The pinned-seed fixpoint matches the installed compiler;
all 6,128 AOT entries link, and fresh processes execute compiled compiler
frames with executable memory denied. All six interpreter workloads still miss production LuaJIT's margin.
The receipt keeps that comparison separate from refactor-cost measurements
against the preserved Nupp runtime.
The cost comparison meets the 2% margin on five cases. Fib remains inconclusive
after 96 pairs: +1.18%, with an interval from +0.88% to +2.02%.

`native-graph-2026-10-27.json` records the first eight complete integer handlers
through the existing Nupp graph. Exact types, retained code loads, logical slots
and the handler ABI survive verification and pruning; CLIF emits graph operands
mechanically. Invalid selected handlers fail instead of taking the temporary
direct path. The graph-only object and executable are byte-identical to the
preserved native control. Other handlers still use `compileDirectFunction`.

Running the full compiler on the native interpreter exposed an existing record
lookup bug: fresh string and slice keys missed canonical shape names. The Nupp
table handler now canonicalizes those keys through the existing helper, preserving
unknown-key identity and nil-key callbacks. The final native compiler emits
byte-identical runtime CLIF to the normal compiler. The linked native regressions
and table suite pass; the graph compiler passes shared coverage, AOT continuity
and the pinned-seed fixpoint. All 6,156 compiler functions link, and fresh
processes execute compiled frames with executable memory denied. Performance
tuning and further measurements are deferred by the owner.

`p2-interpreter-2026-10-27.json` records the next interpreter ports: record and
physical-field handlers, 27 SIMD/storage handlers, three integer leaf handlers,
protected-frame pushes and method-call budget ordering. Nupp owns instruction
control and scalar lane arithmetic. Temporary named services retain managed
object dispatch, storage codecs, SIMD preparation and result packaging. These
services and the remaining instruction fallbacks still block Rust loop deletion.

Logical vector halves extend the frame-slot contract. The temporary direct
lowering supports scalar helper composition and preserves declared storage kinds;
it remains scheduled for deletion under P1b. Context transport validation checks
unchanged ABI inputs without rewriting or optimizing CLIF. The normal compiler
retains its linked AOT route while the Nupp interpreter gains coverage. P2's
remaining instruction semantics, number model and per-platform cold seed pair
remain open. No performance measurements accompany this receipt.

`p2-opcodes-2026-10-27.json` records Nupp entries for all 168 guest opcodes.
The encoder has no default route to `Slow`, and linked-handler coverage checks
every opcode. Numeric, byte/buffer, module, state, typed-call and complete return
pack decisions now live in Nupp. Conditional instruction fallbacks still have
50 source callsites, and temporary managed services remain Rust deletion work.

Cleanup callbacks previously overwrote large result tails in both Rust and
native execution. The shared cleanup service now retains and roots the tail and
its explicit count, including trailing nils across suspended cleanup snapshots.
This uses the existing serialized unwind table and changes no snapshot format.

The receipt distinguishes final runtime checks from the broader native group
and pinned-seed rebuild at the immediately preceding compiler-equivalent
revision. The normal compiler retains 6,157 linked AOT functions. P2's conditional
fallback removal, number model and cold-bootstrap seed pairs remain open, as do
P1b's common-graph migration and the final Rust budget. Performance work remains
deferred.
