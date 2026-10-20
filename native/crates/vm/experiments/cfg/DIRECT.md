# Direct typed frontend experiment

## Status, 2026-10-19

This producer is now the only typed-kernel path: `NUPP_CFG_FRONTEND` is
gone, the adapter in `vm/native.nupp` is deleted, and the modules live in
`src/nupp/compiler/vm/` (`kernels`, `graph`, `maps`, `regions`). `run_direct.py`
is now the end-to-end check only; the old-versus-direct measurement below is
history, since there is no old producer to pair against. See `SHARED.md`.

The checked-CST producer now reaches the production typed VM path without constructing the structured AOT program for the functions it covers. It has not eliminated a production lowering or demonstrated a whole-compiler speed or memory improvement. It remains an opt-in experiment on `codex/cfg-ssa-prototype`.

```text
checked CST
    -> typed closed-block graph
    -> slot layout and parallel edge copies
    -> production bytecode, verifier and frame JIT
```

Enable it with `NUPP_CFG_FRONTEND=1`. The existing lowering handles refused functions. `NUPP_CFG_TYPED=1` independently enables the previous experiment's explicit block arguments inside the frame JIT. The timing comparison uses the normal Variables backend on both sides.

## What this removes from the covered path

The frontend reads resolved types, nominal span identity, ownership modes and intrinsic identities from the checked CST. It constructs typed operations, blocks and edges directly. Closed blocks have explicit parameters; a worklist removes unused transported parameters. Instructions remain, including potentially failing conversions and span operations. Graph verification checks definitions, classes, edge arity and slot conflicts before deriving executable instructions.

For admitted bodies, `vm/native.plans` skips `aot/lower.program`, `aot/verify.program` and the legacy native translation. The harness asserts that none of those bodies enters the old structured lowering. Candidate discovery and fallback remain in the integrated path and are included in its timing.

The bounds fragment accepts a zero-based induction cursor, a full-width or tail guard, an owned span parameter and an optional preceding span-length equality guard. Cursor assignments invalidate the relevant facts. Every `SpanBounds` remains in the executable stream; Rust still independently verifies bounds and restoration. This is not a certificate format or a removal of the second proof.

The graph currently uses ordinary Nupp table columns, including an operand table per instruction. It is not the packed 32-bit storage proposed for the final design. This typed graph also has no binary codec yet; the first scalar experiment's codec is separate.

## Measurements

| Timed operation | Direct / existing, 95% interval | Verdict at 5% |
| --- | --- | --- |
| Native planning, ten element-kind variants | 0.906 [0.901, 0.911] | Improved |
| Native planning, three existing SIMD kernels | 1.088 [1.085, 1.090] | Regressed |
| Native planning, four added flow functions | 0.759 [0.753, 0.765] | Improved |
| Native planning, combined | 0.957 [0.954, 0.960] | Unchanged |
| Production backend compilation | 1.038 [1.025, 1.055] | Inconclusive |
| Full project emission | 0.998 [0.994, 1.001] | Unchanged |
| Warm complete-fixture execution | 1.000 [0.993, 1.006] | Unchanged |

Combined native planning takes a median 19.16 ms versus 20.10 ms. Full project emission takes about 4.14 seconds in both modes. The integrated comparison matters: timing only the new producer omitted retained discovery and fallback and overstated the saving. The existing-kernel subset's 8.8% regression remains a reason not to promote this implementation as a performance improvement. Backend timing does not exclude a regression exceeding the chosen 5% margin.

| Deterministic or memory metric | Existing | Direct |
| --- | ---: | ---: |
| Native-planning VM heap charge, three modules | 5,409,284 B | 5,165,750 B |
| Backend requested allocation volume | 19,753,362 B | 20,362,734 B |
| Backend peak additional requested heap | 1,195,004 B | 1,212,529 B |
| Median full-emission peak RSS | 280,600,576 B | 280,690,688 B |
| Typed bytecode instructions | 1,249 | 1,136 |
| Generated native code | 23,540 B | 24,656 B |
| Complete text image | 354,838 B | 353,424 B |

Frontend accounted heap growth falls 4.5%, while backend allocation volume rises 3.1% and generated native code grows 4.7%. Fewer bytecode instructions do not establish better code generation. No substantial peak-memory improvement is established.

The [recorded samples](direct-results.json) use twelve paired runs on an Apple M5 Pro. Each run measures the three native-planning modules in separate processes. Native planning alternates producer order within each process, discards two warmups and retains five samples. Both producers run interpreted in the same standalone compiler image built from these sources. Each mode performs the complete `native.plans` operation, including discovery and retained fallback. Parsing and checking happen before this phase timer.

The backend comparison compiles both emitted streams through the same production backend, compact analyses and Cranelift verification. Its timer also collects code sizes and formats recovery records in both modes. Four samples follow a warmup. Full project emission runs in separate processes, with balanced old/direct order, and includes dependency checking, all lowering and image formatting; its internal timer excludes compiler startup and writing the final file. Warm execution uses the complete fixture program after warmup. Intervals bootstrap paired process medians with a 5% practical margin. Every repeated image must be byte-identical to its mode's first image.

Frontend heap measurements are separate runs with collection stopped and use the VM's accounted heap growth. They are not process allocation volume or peak memory. Backend requested-allocation measurements use a separate metered executable. Peak RSS includes the same compiler host containing both producers, so it cannot establish a smaller shipped compiler.

An earlier pilot through `./bin/nupp run` reused compiler modules already loaded in the host and compared unequal execution tiers. Those timings were discarded. The standalone source-built host avoids that problem. These results do not establish the same speedup in the installed linked compiler.

## Coverage and runtime contracts

All 17 typed functions in the fixture project use the direct producer: ten element-kind variants of one loop, the three existing SIMD benchmarks, and four new flow functions. The latter exercise retained aliases, parallel assignment cycles, a branch within a span loop, a wider scalar loop, and vector state across budget boundaries. This remains a small workload, not a representative compiler corpus.

Both complete images pass the same assertions through ordinary JIT, explicit block arguments, interpretation, tasks and workers, with GC interleaving, the collector oracle and quarantine. Eight checked sources outside the admission rules and four malformed in-memory graphs are refused. These include oversized register demand and unsupported scalar representations; signed wrapping arithmetic must not become binary64 arithmetic. This graph verifier is not a hostile binary decoder.

The budget/patch/checkpoint regression now includes the actual graph-produced vector loop. The harness checks that the committed body matches current frontend output. The test forces compilation, parks the activation, patches its body, restores its checkpoint and verifies old-body continuation and new-body entry under collector stress. Body identity, roots, logical PCs, resume validation, budget handling and recovery recipes remain production responsibilities.

The wider fixtures found two existing problems. The legacy native adapter read parallel-assignment sources from mutable registers after earlier writes; it now captures every right-hand side first. Both benchmark modes include this correction. The experimental block-argument port invented fallthrough state after a return preceding another laid-out block; returns now terminate that path. A focused Rust regression covers it.

The complete default-feature VM Rust suite passes with `NUPP_CFG_TYPED=1` and `JIT_VERIFY=1`. The final three-stage VM compiler fixpoint also passes byte-identically with `NUPP_CFG_FRONTEND=1`, producing digest `7750fa4b510dba3cdceb936dfa4dd4cd`. This checks compiler self-reproduction with the opt-in integration present; the compiler does not self-host through the typed graph.

## Simplification assessment

This removes work for covered functions, but it is not yet a net compiler simplification. No production lowering or IR has been deleted. In the native path, a typed graph replaces the structured AOT IR; the number of intermediate representations has not fallen. The experiment adds a frontend, a graph and a graph-to-bytecode lowering while retaining the legacy fallback. `aot/lower` and `aot/verify` also still serve GPU compilation.

The frontend does not cover the legacy adapter's full admitted language, including several SIMD intrinsics, casts and uniform types. Deleting `vm/native` now would remove supported behavior. The backend still reconstructs flow and liveness from derived bytecode. The typed source graph is not yet authoritative for persistence or recovery, and it is not yet unified with the scalar graph.

The next deletion requires completing that frontend coverage and making the common graph the production consumer boundary. Then the typed adapter and bytecode-to-graph import can disappear rather than coexist indefinitely. Removing the adapter alone would not guarantee fewer lines: this producer must become part of the common frontend instead of remaining another independently maintained lowering. Keep bytecode as a derived interpreter cache if useful; replacing it as the canonical image remains the architectural goal. The experiment makes that next deletion testable; it does not establish that SSA alone made the compiler faster or smaller.

## Reproduction

Build `nupp-vm` and `typed_cfg_bench` with `RUSTC_WRAPPER=sccache cargo build --offline --release -p nupp-vm --bin nupp-vm --example typed_cfg_bench`. Copy the normal example to `build/cfg-experiment/direct/bench`, then rebuild the example with `--features allocation-metrics` and copy it to `build/cfg-experiment/direct/bench-meter`. Keep the normal runtime. A previously built source compiler seed must exist at `build/vm-fixpoint/root.image`.

```sh
python3 native/crates/vm/experiments/cfg/run_direct.py --build-driver --forks 12
```

`--check-only` runs admission and complete-image execution checks without measurements. The runner currently uses macOS `time -l` for RSS. Full logs, generated projects, images and raw samples live under `build/cfg-experiment/direct`. The recorded report retains source and executable hashes and per-process measurements.
