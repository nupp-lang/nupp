# CFG and SSA experiment

The shared graph works for this bounded compiler slice. Checked CST lowers directly to a serializable CFG with block arguments, and the same graph feeds Cranelift and the existing VM interpreter.

Run from the worktree root:

```sh
python3 native/crates/vm/experiments/cfg/run.py
```

The runner writes graphs, CLIF listings, logs, timing samples and source hashes to `build/cfg-experiment`. It uses the installed compiler to compile the experimental frontend, with automatic compiler rebuilding disabled. Cargo needs the branch's cached dependencies for its offline build.

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
      +-- slot assignment + parallel edge copies --> existing Op interpreter
```

## What the graph replaces

The frontend emits branches, loop backedges, joins and resume edges while it walks the checked syntax. It assigns a distinct value ID to each definition. A block explicitly takes every value it reads from outside itself as a parameter, so its uses can be verified in one forward scan of that block. There is no bytecode scan to discover blocks, no dominator matrix, and no mutable-variable SSA construction in the direct Cranelift path.

One worklist follows value dependencies and incoming block arguments to remove dead instructions and parameters. Its remaining resume arguments describe the state the native experiment saves. This pass is linear in the graph's values and edges. The block-local discipline can carry more parameters than conventional SSA; eliminating trivial parameters or permitting dominating cross-block references is a subsequent design choice.

The VM adapter assigns register slots and resolves parallel copies. It removes identity copies and handles cycles with a scratch register. Those are backend decisions that still have to happen. Existing VM machinery continues to own its production verification, GC maps and PC-based runtime contracts; the experiment does not replace those with graph metadata.

## Storage and persistence

The Nupp builder uses table columns for opcodes, results and operands. It allocates no table per instruction, but its columns are ordinary runtime tables, not four-byte arrays.

The Rust graph stores instructions in a dense `Vec<[u32; 4]>`, blocks and edges as fixed records, and parameter/argument lists in one `Vec<u32>` addressed by offset and length. Value types and constant pools are separate. IDs are unsigned 32-bit indices. There is no heap object per instruction or edge. A chunked builder could preserve this indexing contract without requiring contiguous growth.

The binary image persists the graph itself, including block parameters, edges and yield continuations. It has a version header, little-endian 32-bit fields, names and a numeric constant pool. Constants use round-trip decimal strings in this experimental format. The reader bounds counts, validates types, definitions, local use order, targets, edge arity and reachability before compilation. Decoding currently copies into the dense arrays.

This demonstrates replacing bytecode as the canonical persisted compiler artifact. The VM can still cache an executable instruction layout derived from it. Whether to ship that cache alongside the graph depends on measured startup and image-size costs.

## Evidence

The ten source fixtures cover joins, nested loops, early returns, branch-local bindings, two- and three-register assignment cycles, checked byte reads, and numeric and string state across yields. The 255 input cases include empty strings, embedded NULs, all byte values, fractional and negative byte indexes, NaNs, infinities and signed zero where applicable.

Every result agrees between direct Cranelift at `none` and `speed`, graph-derived Rust and threaded interpretation, and the original CST lowering. Yield traces are also compared with the original coroutine implementation running under the real scheduler. The graph's native execution uses a private resume ABI. The current scheduler is the reference, rather than the host for that native code.

All 255 cases also pass with GC interleaving, the collector oracle and quarantine enabled. The repository compiler's three-stage fixpoint passes byte-identically. The compiler does not yet self-host through this experimental graph path.

Additional checks reject unsupported source, malformed graph definitions, bad types/edges/arity, unsupported opcodes, oversized VM constant pools and every truncated prefix of the fixture graph. Optimized graphs survive serialization and deserialization unchanged. Repeated frontend runs emit identical graphs and original VM images.

The fixtures contain 45 blocks and 79 graph instructions after pruning. The worklist reduces 198 value IDs to 179. Their serialized graph is 4,370 bytes; the existing text image is 4,393 bytes, including its module initializer and source metadata. This does not establish an image-size win. Peak compiler memory has not been measured.

The saved `results.json` contains eleven warm samples after two warmups. Frontend lowerings and native compilation alternate order. Frontend checking is measured separately. The current compiler's native timer is wrapped externally so its prerequisite analyses are included. Both native paths have Cranelift verification enabled and optimization set to `none` for timing.

The [recorded run](sample-results.json) on an Apple M5 Pro measured approximately 1.54 ms for graph construction plus serialization, versus 4.43 ms for the existing lowering plus text emission, over all ten small functions. Graph decoding and verification took about 10 microseconds. These are small fixtures, with a smaller admitted language and less metadata in the graph; they establish feasibility rather than whole-compiler performance.

The direct native compilation measurement is recorded for investigation, but it cannot establish a production speedup. Its private ABI omits production GC, deoptimization, body patching, cleanup, exception and scheduler obligations. The old image also contains a module initializer and source metadata that the graph image does not yet carry.

The simple VM adapter still emits more instructions for some functions: the nested loop uses 25 versus the existing lowering's 17. SSA does not automatically produce a better interpreter stream. Register coalescing and block layout deserve measurement before replacing that backend.

## Scope and decision

The admitted slice has `number` and `string` parameters, numeric returns, local assignments, numeric comparisons and arithmetic, `if`, `while`, string length, `string.byte(s, i) or 0`, and discarded-result `coroutine.yield`. Unsupported constructs fail explicitly. This is checked string access, not the typed span/SIMD proof problem. Closures, arbitrary calls, cleanup, GPU structure, full source maps and production recovery metadata remain outside the experiment.

The test host supplies binary64 numbers and immutable strings, with the standard `string` and `coroutine` bindings unchanged. Production admission must account for other numeric carriers and establish intrinsic identity or guard it; recognizing a qualified name and a `number` annotation does not establish those facts by itself.

Proceed with the shared graph design. This experiment makes the ideal concrete enough to evaluate directly, without first designing a permanent bytecode side-table format. The next decisive slice should preserve production runtime obligations and retire an existing path, such as the typed native adapter, rather than merely adding another backend. Then measure compiler and application workloads, peak memory, startup and generated-code quality. The prototype adds files; production IRs and lowerings have not yet been deleted.

Later slices: `TYPED.md` (block arguments inside the frame JIT), `DIRECT.md`
(the checked-CST producer), `SHARED.md` (one graph for CPU and GPU, now the
only typed-kernel path in the compiler).
