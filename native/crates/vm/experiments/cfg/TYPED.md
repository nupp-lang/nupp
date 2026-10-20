# Typed frame experiment

Explicit typed block arguments work with the production frame ABI. The measured compile-time improvement comes from compact dominance and shared liveness; this slice does not remove a frontend IR or lowering.

The experiment remains on `codex/cfg-ssa-prototype`. Enable the frame port with `NUPP_CFG_TYPED=1`; `NUPP_CFG_TRACE=1` identifies functions actually admitted. Neither `main` nor the active `codegen-experiment` branch was changed.

The subsequent [direct typed frontend slice](DIRECT.md) bypasses the structured AOT path for covered functions, widens the flow fixtures and corrects the port's return-edge handling. The measurements below belong to the earlier backend-only slice.

## Result

[Recorded evidence](typed-results.json) covers 13 existing typed kernels, 1,050 instructions, all ten SIMD element kinds, tails, nested loops and reductions. Sixteen paired processes balance all four mode positions and reverse alternate cycles. Each process measures four compilations after a warmup. Intervals resample paired process medians; the practical margin is 5%.

| Change against the original production backend | Paired compile-time ratio, 95% interval | Verdict |
| --- | --- | --- |
| Explicit typed block arguments only | 1.013 [1.007, 1.020] | Unchanged |
| Compact dominance and shared liveness, existing Variables | 0.774 [0.768, 0.780] | Improved |
| Both changes | 0.784 [0.776, 0.791] | Improved |
| Block arguments against the improved Variables path | 1.014 [1.003, 1.025] | Unchanged |

With both changes, median compilation takes 13.28 ms versus 16.87 ms. The paired estimate is a 21.6% improvement. The existing typed optimization policy and Cranelift verification are identical in every mode. Timing includes JIT construction, proof analysis, liveness, graph import, lowering, code generation and registration. It also includes collecting code-size and recovery records, identically in every mode.

Allocation metering runs separately from timing:

| Metric for compiling all 13 functions | Before | Both changes |
| --- | ---: | ---: |
| Requested allocation volume | 22,390,238 B | 16,909,202 B |
| Allocation calls | 143,966 | 107,513 |
| Peak additional requested heap | 1,195,004 B | 1,194,584 B |
| Median process peak RSS | 18,251,776 B | 17,629,184 B |
| Native code | 19,620 B | 19,576 B |

Allocation volume falls 24.5%; peak requested heap is unchanged. The allocator measures requested Rust heap bytes, excluding executable mappings and allocator overhead. RSS includes loading the input image. Neither measurement establishes a substantial peak-memory reduction.

Running the complete fixture process, including image loading, library code, compilation and assertions, takes a median 94.05 ms versus 97.53 ms. Its paired ratio is 0.962 [0.958, 0.965], unchanged at the 5% margin. This is not a whole-compiler or application throughput win.

The separate scalar control requested in the review also ran through production `compile_frame` on both instruction streams. The graph adapter's stream compiled in 2.96 ms versus 3.33 ms for the original lowering: ratio 0.891 [0.887, 0.897]. The adapter still emits 202 instructions versus 175. Instruction count alone does not predict this backend's compilation cost. This control compares equivalent behavior with different generated streams, not identical instruction selection.

## Runtime contracts

The typed port uses the existing native operation emitter. Integer, float and vector values cross blocks as explicit Cranelift arguments. Boxed roots, header and budget bookkeeping retain their existing handling. Logical PCs, physical register windows and frame recovery recipes remain the production ABI.

Resume dispatch still includes budget boundaries. Span addresses are reacquired at entry, span-length equalities and narrowed cursor ranges are revalidated after restoration, and invalid interior PCs are refused. Bounds checks, NaN normalization, error propagation, stack maps, code registration and version ownership remain in place.

The benchmark compares every recovery record between modes. All 13 kernels retain identical bounds-check elimination counts. Native code size is essentially unchanged.

Validation passes the complete `nupp-vm` Rust test suite with the typed port enabled. The native SIMD smoke test passes direct, task and worker execution plus the interpreter reference under GC interleaving, oracle and quarantine. Existing tests cover corrupted span lengths, corrupted cursors, illegal resume PCs and NaN payloads. A new test parks a typed vector loop on its budget boundary, patches its body, checkpoints it, and confirms that the old activation finishes on the old body while a new call uses the new body. Compilation is requested explicitly there so interpreter fallback cannot conceal a rejected port.

No `.nupp` compiler source changed in this slice. The earlier compiler fixpoint remains evidence for the first slice, not evidence that the compiler self-hosts through the graph.

## What was removed

The typed frame compile now computes liveness once and supplies it to both frame handling and deferred NaN handling. The two quadratic per-instruction dominance sets are replaced by immediate-dominator trees and interval queries. Storage is linear in nodes and edges; fixed-point construction is not claimed to have linear worst-case running time. A differential test checks reachable-node queries in 1,380 generated graphs against the old set-intersection algorithm, including multiple entries and cycles. Unreachable components separately check the new conservative rule that only a node itself dominates it.

The block-argument port still imports the existing typed bytecode. Its parameter columns and spans are compact, but its producer is not yet the direct CST graph frontend. Production still has `aot/lower`, `aot/verify`, `vm/native` and `vm/lower`; typed images still persist bytecode. Deleting `vm/native` here would remove supported behavior. Moving its translation into a graph module would change its location without removing a lowering.

A real deletion requires the common graph producer to own the typed span/SIMD operations and admission rules now supplied by the checked native IR and adapter. Bounds facts must be independently verified at the image boundary and reestablished where resume semantics require it. The runtime port demonstrates that these contracts can coexist with block arguments; it does not yet supply that frontend or a persisted typed graph.

## Assessment of the review

The review correctly separates the private ABI timing from production compilation and identifies the same-backend control. Its warning about the closed-block parameter cost is useful.

A resume edge describes live values; the production frame also needs body identity, logical PC, roots and restoration checks. The scalar prototype's pruning is exact for its supported effects and intrinsics, not a replacement for those contracts in the general language.

Closed blocks already are SSA. Allowing arbitrary dominating references would require dominance verification, but local simplifications can retain closed blocks: duplicate parameters can be merged, and known constants can be materialized locally. There is no requirement to choose every lexical binding forever or unrestricted SSA immediately.

Preferred lexical slots are useful hints, not a complete allocation algorithm. One value can feed parameters with different preferred slots, simultaneous assignments can form cycles, and overwritten values can remain live. Hints alone do not guarantee an instruction stream identical to the old lowering. This experiment has not implemented that proposal.

The suggested 2.8 KB binary-bytecode comparison is an estimate for an unimplemented lossless format. Constants, side tables and metadata must be included. The existing 16-byte `Ins` cache is lossy and cannot serve as that baseline.

Keep the graph direction open, but do not attribute the measured win to SSA or count a lowering as retired. Compact verified analyses are reusable if the frontend later emits the graph directly.

## Reproduction

The original backend and the block-argument-only control are frozen at `6610760fe`, whose normal code path has the same analyses as `a6a5d00a2`. Build that revision in a separate worktree created with `scripts/worktree`; keep the candidate worktree separate.

For each revision, build `typed_cfg_bench` normally and with `--features allocation-metrics`, using `RUSTC_WRAPPER=sccache cargo build --offline --release -p nupp-vm --example typed_cfg_bench`. Also build `nupp-vm`. Copy the baseline executables to `build/cfg-experiment/typed-cfg-bench-plain`, `typed-cfg-bench-meter-before` and `runtime-before`. Copy the candidate executables to `typed-cfg-bench-after`, `typed-cfg-bench-meter-after` and `runtime-after`. The normal benchmark must be copied before the metered build overwrites its output.

Generate the shared image with `native/crates/vm/tests/native-simd-smoke.py`, using the compiler seed and `--output build/cfg-experiment/typed-native`. Run the original `run.py` once to produce `fixture.cfg`, `fixture.image` and the scalar example binary. Then run:

```sh
python3 native/crates/vm/experiments/cfg/run_typed.py
```

The runner currently uses macOS `time -l` for RSS. It records source and executable hashes, raw fork measurements and the statistical comparisons. Generated images, CLIF, assembly and test logs remain under `build/cfg-experiment`.
