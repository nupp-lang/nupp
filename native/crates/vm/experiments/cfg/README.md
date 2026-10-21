# CFG and SSA experiment

## Status, 2026-10-21: the image is the graph (P4)

The lowering builds labeled blocks rather than an instruction stream with
offsets. `nupp.compiler.vm.lowerstate` gives each function `label`,
`place`, `jump` and `branch`; an instruction that leaves the function ends
its block, and code after it lands in a block nothing reaches. There are no
offsets, patches or compaction pass.

A lowered function ships in register form: its reached blocks in order,
jumps threaded past blocks that hold nothing but a jump, instructions with
their raw register operands, and a terminator whose key names the class and
register it tests or returns. Edges carry no arguments and there is no
value table, live-in list or region tree, because nothing at run time reads
them. `nupp.compiler.vm.convert` produces it straight from the lowering's
blocks and `nupp.compiler.vm.graphimage` encodes it one function at a time,
so no intermediate graph is built. Kernels keep SSA form: the frontend's
own graph, verified by the graph verifier, with regions and certificates.
Inspection (`nupp bc`, the editor's listing) renders the stream the runtime
derives.

The runtime loads graph images by their magic everywhere it loaded text:
`nupp-vm run`, `exec`, `verify`, `aot`, `--load`, `vm.loadImage`, a
program's payload, the embedding API, hot patches, checkpoints and
workers. `graph::load` streams one function at a time. A register-form
function is checked once at load (`verify_registers`: operand bounds,
register windows, physical plans, SIMD descriptors, block endings,
reachability); the stream class check runs only for functions that need
native code. Liveness is one block-level dataflow whose leaders come from
control instructions alone, and `graph_gate analyses` cross-checks it
against the per-instruction reference over the whole image. The text
loader stays for the Rust tests' fixtures and for bridging a format change
through the text-default generation; a cold bootstrap runs the tree's own
lowering under LuaJIT, so it emits graphs.

Image words are shifted varints (NONE is a single zero byte). The emit
cache keeps each module's blocks with relative function ids.

The compiler's own root image, against the previous compiler on the same
sources:

| | previous (text) | register form |
|---|---|---|
| functions | 6,221 | 6,221 |
| image | 19.4 MB | 8.86 MB |
| load (`verify`) | 120 ms, 99 MB | 40 ms, 72 MB |
| liveness, whole image | 1,245 ms | 79 ms |
| whole emission | 161 s, 2.3 GB | 156 s, 2.4 GB |

The first graph format, with values, live-ins and edge arguments, was
24.8 MB, loaded in 138 ms and emitted in 168 s; none of that information
was read after load.

## Status, 2026-10-20: P1

The single-IR plan's P1 promoted this experiment: the graph module is
`src/nupp/compiler/vm/graph.nupp`, its image codec is
`src/nupp/compiler/vm/graphimage.nupp`, and `native/crates/vm/src/graph.rs`
decodes, verifies and derives the interpreter stream. The scalar frontend in
`src/nupp/experiment/cfg.nupp` now emits the production graph on value-class
operations (constants, call windows, branches on values, park terminators)
rather than the first slice's private format, and the first slice's Rust
example (its private-ABI Cranelift path and adapter) is gone with it; the
numbers below are its recorded evidence. The P1 gate is

```sh
python3 native/crates/vm/experiments/cfg/run_p1.py --build-driver
```

which writes to `build/cfg-p1`: the scalar fixture through both paths and
`graph_gate scalar` (every input on the interpreter, the threaded core and
the JIT, with hostile-input checks over the image), the typed fixtures
through `graph_gate typed` (derived streams held equal to the Nupp lowering),
the whole native SIMD fixture program run on graph-derived streams
(`NUPP_GRAPH_IMAGE`), and `graph_gate size` timing decode plus derive of a
checker-sized image against the text parse of the compiler's own image.

The shared graph works for this bounded compiler slice. Checked CST lowers directly to a serializable CFG with block arguments, and the same graph feeds Cranelift and the existing VM interpreter.

The first slice's runner, `run.py`, and its example are deleted; `run_p1.py` above is the current harness. The runner wrote graphs, CLIF listings, logs, timing samples and source hashes to `build/cfg-experiment`.

The first slice starts at `codegen-experiment` revision `a6a5d00a23bb534c6e65d2b5009db47fc93a264f` and added no production-path changes. Follow-ups test the [production typed frame backend](TYPED.md) and a [direct typed CST frontend](DIRECT.md). All slices remain isolated on `codex/cfg-ssa-prototype`. The architecture and measurements below describe the first scalar slice; the typed frontend currently derives production bytecode and does not persist its graph.

```text
parser + checker
      |
      v
checked CST
      |
      v
CFG / block-argument SSA ---> binary graph image
      |                            |
      |                       decode + verify
      |                            |
      +<---------------------------+
      |
      +-- prune dead values and block parameters
      |
      +-- direct Cranelift SSA --> native code
      |
      +-- slot hints + parallel edge copies --> existing Op interpreter
```

## What the graph replaces

The frontend emits branches, loop backedges, joins and resume edges while it walks the checked syntax. It assigns a distinct value ID to each definition. A block explicitly takes every value it reads from outside itself as a parameter, so its uses can be verified in one forward scan of that block. There is no bytecode scan to discover blocks, no dominator matrix, and no mutable-variable SSA construction in the direct Cranelift path.

One worklist follows value dependencies and incoming block arguments to remove dead instructions and parameters. Its remaining resume arguments describe the state the native experiment saves. This pass is linear in the graph's values and edges. The block-local discipline can carry more parameters than conventional SSA; eliminating trivial parameters or permitting dominating cross-block references is a subsequent design choice.

The VM adapter assigns register slots and resolves parallel copies. It removes identity copies and handles cycles with a scratch register. Those are backend decisions that still have to happen. Existing VM machinery continues to own its production verification, GC maps and PC-based runtime contracts; the experiment does not replace those with graph metadata.

Closed blocks make every edge a parallel copy, and a positional register window turned most of those copies into real moves. The frontend therefore gives each lexical name a stable slot index and emits it on every block parameter as a preferred-register hint. The adapter keeps a parameter in the register its hint names, and places a node result that feeds such a parameter in that register when nothing still live occupies it; the copy on the edge then becomes an identity and disappears. The hint is advice, not an allocation: a value feeding two different slots, a swap cycle, or an overwritten value that stays live still produces moves, and the entry parameters must keep positional slots for the call ABI, which the adapter checks.

## Storage and persistence

The Nupp builder uses table columns for opcodes, results and operands. It allocates no table per instruction, but its columns are ordinary runtime tables, not four-byte arrays.

The Rust graph stores instructions in a dense `Vec<[u32; 4]>`, blocks and edges as fixed records, and parameter/argument lists in one `Vec<u32>` addressed by offset and length. Value types and constant pools are separate. IDs are unsigned 32-bit indices. There is no heap object per instruction or edge. A chunked builder could preserve this indexing contract without requiring contiguous growth.

The binary image persists the graph itself, including block parameters, their slot hints, edges and yield continuations. It has a version header (`NCFG0002`), little-endian 32-bit fields, names, a numeric constant pool and a per-function slot count. Constants use round-trip decimal strings in this experimental format. The reader bounds counts, validates types, definitions, local use order, targets, edge arity and reachability before compilation, and requires every hint to name a slot below the count with no two parameters of one block sharing a slot. Pruning renumbers surviving slots densely, entry parameters first. Decoding currently copies into the dense arrays.

This demonstrates replacing bytecode as the canonical persisted compiler artifact. The VM can still cache an executable instruction layout derived from it. Whether to ship that cache alongside the graph depends on measured startup and image-size costs.

## Evidence

The ten source fixtures cover joins, nested loops, early returns, branch-local bindings, two- and three-register assignment cycles, checked byte reads, and numeric and string state across yields. The 255 input cases include empty strings, embedded NULs, all byte values, fractional and negative byte indexes, NaNs, infinities and signed zero where applicable.

Every result agrees between direct Cranelift at `none` and `speed`, graph-derived Rust and threaded interpretation, and the original CST lowering. Yield traces are also compared with the original coroutine implementation running under the real scheduler. The graph's native execution uses a private resume ABI. The current scheduler is the reference, rather than the host for that native code.

All 255 cases also pass with GC interleaving, the collector oracle and quarantine enabled. The repository compiler's three-stage fixpoint passes byte-identically. The compiler does not yet self-host through this experimental graph path.

Additional checks reject unsupported source, malformed graph definitions, bad types/edges/arity, unsupported opcodes, oversized VM constant pools, a hint outside the slot count, two parameters of one block with the same hint, a slot count larger than the function's values, and every truncated prefix of the fixture graph. Optimized graphs survive serialization and deserialization unchanged. Repeated frontend runs emit identical graphs and original VM images. Every case runs through the adapter with and without hints, threaded and unthreaded.

The fixtures contain 45 blocks and 79 graph instructions after pruning. The worklist reduces 198 value IDs to 179. Their serialized graph is 4,810 bytes with hints (one word per surviving parameter and one per function); the existing text image is 4,393 bytes, including its module initializer and source metadata. This does not establish an image-size win. Peak compiler memory has not been measured.

The saved `results.json` contains eleven warm samples after two warmups. Frontend lowerings and native compilation alternate order. Frontend checking is measured separately. The current compiler's native timer is wrapped externally so its prerequisite analyses are included. Both native paths have Cranelift verification enabled and optimization set to `none` for timing.

The [recorded run](sample-results.json) on an Apple M5 Pro, taken while other builds shared the machine, measured approximately 1.00 ms for graph construction plus serialization, versus 8.48 ms for the existing lowering plus text emission, over all ten small functions. Graph decoding and verification took about 16 microseconds. These are small fixtures, with a smaller admitted language and less metadata in the graph; they establish feasibility rather than whole-compiler performance.

The direct native compilation measurement (`graph_to_native`, about 0.53 ms) is recorded for investigation, but it cannot establish a production speedup. Its private ABI omits production GC, deoptimization, body patching, cleanup, exception and scheduler obligations, so it does not compare with the frame rows below. The old image also contains a module initializer and source metadata that the graph image does not yet carry.

Two rows isolate the representation from the backend. `old_to_native_frame` feeds the original lowering's instruction stream through the production `Jit::compile_frame`; `adapter_to_native_frame` feeds the hinted graph adapter's stream through the same call, with the same verifier, optimization level and runtime obligations. The two alternate order every round. The recorded medians are 4.08 ms and 3.64 ms, a ratio of 0.89, consistent with the 0.891 paired ratio measured separately in [TYPED.md](TYPED.md). Agreement between the rows would mean the graph-derived stream costs the production backend the same as the old one, so any compile-time difference lives in the frontends; a lower adapter row means the stream it produces is cheaper for this backend to analyze, not that the graph compiles faster, because the frontends that produced the two streams are timed elsewhere; a higher one would mean the adapter's stream shape, not the graph, is the problem. Absolute values in this run are above the earlier quiet-machine samples; only the paired ratio is comparable across runs.

Slot hints bring the adapter's instruction total from 202 to 175, the same as the existing lowering, and leave no data moves except the genuine swap and rotate cycles, the `string.byte` call sequence and the parked value. Per function:

| Function | Existing lowering | Adapter, positional | Adapter, hinted |
| --- | ---: | ---: | ---: |
| diamond | 12 | 16 | 14 |
| loop | 16 | 24 | 20 |
| swap | 19 | 21 | 18 |
| bytes | 19 | 23 | 20 |
| byte | 8 | 8 | 8 |
| suspend | 18 | 18 | 15 |
| early | 14 | 14 | 13 |
| nested | 17 | 25 | 21 |
| rotate | 26 | 27 | 23 |
| suspendBytes | 26 | 26 | 23 |

The remaining excess on `loop` and `nested` is control flow, not data movement: the adapter emits an unconditional jump to the block laid out next and a `JmpIf` plus `Jmp` pair where the existing lowering uses `JmpIfNot`. The runner writes both streams beside each function as `NAME.old.ops` and `NAME.adapter.ops`. Block layout and conditional-branch selection deserve the same treatment before replacing that backend; SSA alone does not produce a better interpreter stream.

## Scope and decision

The admitted slice has `number` and `string` parameters, numeric returns, local assignments, numeric comparisons and arithmetic, `if`, `while`, string length, `string.byte(s, i) or 0`, and discarded-result `coroutine.yield`. Unsupported constructs fail explicitly. This is checked string access, not the typed span/SIMD proof problem. Closures, arbitrary calls, cleanup, GPU structure, full source maps and production recovery metadata remain outside the experiment.

The test host supplies binary64 numbers and immutable strings, with the standard `string` and `coroutine` bindings unchanged. Production admission must account for other numeric carriers and establish intrinsic identity or guard it; recognizing a qualified name and a `number` annotation does not establish those facts by itself.

Proceed with the shared graph design. This experiment makes the ideal concrete enough to evaluate directly, without first designing a permanent bytecode side-table format. The next decisive slice should preserve production runtime obligations and retire an existing path, such as the typed native adapter, rather than merely adding another backend. Then measure compiler and application workloads, peak memory, startup and generated-code quality. The prototype adds files; production IRs and lowerings have not yet been deleted.

Later slices: `TYPED.md` (block arguments inside the frame JIT), `DIRECT.md`
(the checked-CST producer), `SHARED.md` (one graph for CPU and GPU, now the
only typed-kernel path in the compiler).
