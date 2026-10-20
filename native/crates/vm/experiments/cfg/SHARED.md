# Shared CPU and GPU graph

## Status, 2026-10-19

The shared producer is now the only typed-kernel path in the VM lowering,
and it is faster than the structured path it replaced. The typed native
adapter (`src/nupp/compiler/vm/native.nupp`) is deleted, so the VM lowering
no longer imports `aot/lower` or `aot/verify`; the graph modules moved out of
the experiment namespace into `src/nupp/compiler/vm/` as `graph`, `kernels`
(the frontend), `maps` and `regions`; the `NUPP_CFG_FRONTEND` and
`NUPP_CFG_MAP` flags are gone, as is their part of the emission-cache stamp.
The frontend also covers the adapter's remaining vector language: negation,
bitwise not, `math.sqrt`, `math.abs`, `math.floor` and `math.ceil` over
vectors, and `fma`; `typed-flow.nupp`'s `graphMath` exercises each. Left
refused, which lowers as ordinary code: `numeric_cast` to `uint32` or
`uint64`, `f32` narrowing and `i32` arithmetic. No `.nupp` kernel in the tree
used them on the VM path. The old WGSL and SPIR-V emitters remain the
production GPU path; the graph emitter still covers only uint32 maps.

The regression below was found by timing each phase of the shared path on
the same harness, then timing inside the phases. Its causes, in the order
they were removed:

- WGSL emission built every line by concatenation, declared a `var` for every
  SSA value and emitted two lines per edge argument through a temporary.
  It now joins one buffer of pieces once, binds instruction results with
  `let`, assigns edge arguments directly (an edge's sources are never its
  targets), and gives a parameter with one incoming non-exit edge its
  source's name, so most edges emit nothing.
- The map verifier ran one full-graph fixed point per header parameter.
  It now computes every value's copy origin in one pass.
- The verifier and the region walk were visited through a callback per
  event; both now consume one flat event list computed once.
- Every graph pass iterated with `ipairs` and checked with `assert`, each a
  builtin call per element on the VM; they use numeric loops and
  conditionals now.
- The frontend rescanned the whole environment on every binding to detect
  aliases, copied records generically per block, and rebuilt constant
  tables per function.

Twelve paired processes on the same harness as below, interpreted host:

| Metric | Existing | Shared graph |
| --- | ---: | ---: |
| Median phase time, three kernels | 0.952 ms | 0.858 ms |
| VM heap charge with collection stopped | 270,084 B | 217,368 B |
| WGSL source bytes | 5,207 | 5,138 |

The paired time ratio is **0.895**, 95% interval **[0.886, 0.904]**:
**improved** at the 5% margin, from 1.959 before. Validation: the GPU
harness's 168 cases, the CPU image in all five execution modes under
collector stress, the five source refusals and 21 damaged graphs, the
cache reproduction check, forced native compilation, the direct-frontend
harness over all 18 fixture kernels, the native SIMD smoke test with the
rebuilt compiler as its seed, and the three-stage fixpoint, which emits
byte-identically (`2f1df9984352aae46b8721a7ed3317be`).

The sections below are the slice as first recorded, before this work.

Three checked uint32 map kernels now feed both the production typed CPU path and a direct WGSL emitter from the same CFG/SSA object. The structured AOT program is not built on that shared path. This establishes the common representation, but it adds code overall and regresses compilation time and allocation in the measured phase. The work remains isolated on `codex/cfg-ssa-prototype`.

```text
checked CST -> typed CFG/SSA + region annotations
                         -> slot layout -> VM instructions -> frame JIT/interpreter
                         -> WGSL -> WGPU/Metal
```

## What is shared

The existing `typedcfg.frontend` now handles a bounded scalar map profile as well as the previous SIMD profile. It uses the same value identities, closed blocks, block parameters, edge arguments, pruning and slot layout. The map profile covers uint32 spans and uniforms, wrapping addition/subtraction, a complete-span counted loop, local assignments, selections and nested while loops. The fixtures exercise a map, a diamond and a nested loop with swapped local values.

Loop headers name their existing merge and continue blocks; selection headers name their merge blocks. `regions.walk` validates and visits these annotations without constructing a second statement tree. WGSL consumes the graph directly and assigns edge arguments simultaneously. The outer map loop becomes GPU dispatch; nested loops stay loops. CPU emission retains the outer loop and derives its instruction stream from the same graph.

`map.verify` owns this profile's parallelism and bounds argument. It checks the canonical induction step, equality preconditions for span lengths, each access's index identity, and the absence of mutable state carried between map iterations. Copy equalities use a removal worklist for each surviving header parameter. It also requires the skipped outer continue block to contain only its increment. Region and map metadata are checked against graph instructions and edges, rather than trusted as proofs.

The frontend emits checked `U32Load`, `U32Store` and `SpanEqual` operations. It does not reproduce the old syntactic SIMD bounds prover for maps. CPU lowering keeps `SpanBounds`; the production Rust verifier and proof pass remain. This is not yet a certificate protocol or a removal of the Rust bounds analysis. The earlier SIMD admission prover also remains for its existing profile.

## Integration and contracts

`NUPP_CFG_MAP=1` enables the scalar graph producer in the ordinary VM lowering. Unsupported functions keep the existing path. The environment choices for both this flag and `NUPP_CFG_FRONTEND` are now part of the emission-cache stamp. An old/direct/old sequence through one cache must reproduce each corresponding uncached image exactly.

CPU code uses the existing boxed entry parameters, typed register windows, span validation, budget resumes, root handling and recovery machinery. The three generated kernels are compiled explicitly as well as executed, so interpreter fallback cannot conceal a native refusal.

GPU execution is an isolated artifact harness using the existing WGSL storage-binding order, count/offset/uniform layout and multi-row dispatch convention. It runs actual shaders through WGPU on Metal. The production GPU artifact builder and generated host bindings have not been switched over. The host still owns view-extent validation and precondition errors; device count guards are not a substitute for that contract. Native SPIR-V still uses the old producer.

The graph remains table-backed, with per-instruction operand tables. It is not yet packed int32 storage or the persisted image. CPU code still crosses the bytecode boundary and the frame backend still reconstructs flow. The scalar prototype's separate codec has not been unified here.

## Measurements

Twelve paired processes compare the three kernels from checked CST through verified WGSL. Both producers run interpreted in the same standalone, source-built VM image. Parsing, checking, refusal tests and artifact writes precede timing. Each process alternates producer order, discards two warmups and keeps five samples. The old route includes `aot/compile.lower`, its verifier and WGSL emission; the new route includes graph construction, pruning, map verification and WGSL emission. Old SPIR-V emission and new CPU-cache emission are excluded from both timed paths.

| Metric | Existing | Shared graph |
| --- | ---: | ---: |
| Median phase time, three kernels | 0.973 ms | 1.916 ms |
| VM heap charge with collection stopped | 269,946 B | 676,815 B |
| WGSL source bytes | 5,207 | 9,378 |
| Complete CPU fixture text image | 303,763 B | 303,536 B |

The paired time ratio is **1.959**, with a bootstrapped 95% interval of **[1.946, 1.973]**: **regressed** at the predeclared 5% practical margin. The heap figure is allocation charged to the VM during the phase, not process allocation volume, peak memory or shipped compiler size. These are three small kernels and an interpreted compiler host, not a whole-compiler or installed-compiler result. The eager JIT-host probe was stopped before completing its first paired process; no JIT-host comparison is claimed.

Closed-block transport and SSA temporaries make this graph and its emitted WGSL larger. That deterministic observation does not attribute the timing regression to an individual pass. No compiler performance or memory win is established.

## Validation

- All 168 old/new GPU cases pass on Apple M5 Pro/Metal: empty and boundary lengths, wrapping values, four uniform values, nonzero view offsets, untouched padding and multi-row dispatches.
- Both complete CPU images pass JIT, explicit block arguments, interpreter, tasks and workers under GC interleaving, oracle and quarantine. Mismatched span lengths still raise. All three candidate kernels are also forced through native compilation.
- Five checked unsupported sources and 21 damaged in-memory graphs are refused. The graph tests cover region targets, induction identity and step, definitions, missing length preconditions, loop-carried state and an added store in the skipped GPU continue block.
- Replacing `aot/lower.program` and `aot/verify.program` with failures does not prevent the shared producer from generating its artifacts.
- Cache-mode switching reproduces both complete images exactly.
- All ten existing `vmemitcachetest.lua` functions pass when loaded and invoked directly, in sorted order, through the fresh fixpoint VM compiler image. The standard runner wrapper is not counted as validated: its native build was stopped, and the bundled internal runner discovered no suites.
- The earlier 17-function SIMD experiment and the full default-feature Rust VM suite pass, including budget park, body patch and checkpoint recovery under collector stress.
- With both graph frontend flags enabled, the VM compiler emits itself byte-identically across the three-stage fixpoint (`f97b6a56b23f14be1dc0bb5861576abf`). This checks compiler self-reproduction, not adoption of the map graph by compiler functions.

The in-memory checks do not constitute a hostile binary decoder. The measured samples and source/executable hashes are in [shared-results.json](shared-results.json); full logs and generated artifacts are under `build/cfg-experiment/shared`.

## Simplification assessment

This resolves the representation choice for the bounded slice: one frontend and one graph can serve CPU and GPU without translating through the structured AOT program. It provides an executable replacement path for these kernels, rather than another import of the old IR.

It is not yet a net compiler simplification. No production IR or lowering has been deleted. The new WGSL emitter covers less than the old emitter, so their line counts are not evidence of savings. Retirement still requires migrating the remaining GPU semantics and bindings, switching native consumers to the graph boundary, and removing the superseded paths. The measured regression also needs addressing before promotion. This slice supports the single-CFG architecture; it does not justify a speed claim.

## Reproduction

Build the runtime and `typed_cfg_bench` as described in [DIRECT.md](DIRECT.md). With a source compiler seed at `build/vm-fixpoint/root.image`, build the standalone driver and run:

```sh
NUPP_COMPILER_ROOT="$PWD" NO_JIT=1 \
NUPP_VM_EMIT_CACHE="$PWD/build/cfg-experiment/shared-cache" \
build/rust/target/release/nupp-vm run build/vm-fixpoint/root.image \
  nupp.tools.vm.project emit "$PWD" nupp.experiment.typedcfg.shared \
  nupp.compiler.hostservices,nupp.compiler.fs,nupp.compiler.project.projectconfig,nupp.compiler.project.store,nupp.compiler.project.fingerprint,nupp.compiler.hash,nupp.compiler.project.preludecache,nupp.runtime.provider.nativeprocess \
  --output build/cfg-experiment/shared-driver.image
RUSTC_WRAPPER=sccache cargo build --offline --release -p nupp-native-gpu --example shared_cfg
python3 native/crates/vm/experiments/cfg/run_shared.py --forks 12
```

`--check-only` runs correctness and cache checks without paired measurements. `--host jit` selects a JIT-enabled compiler host with threshold one, including its cold compilation cost before the samples; it is not the recorded measurement.
