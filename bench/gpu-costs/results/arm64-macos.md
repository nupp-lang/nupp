# CPU AOT and GPU operation costs on Apple M5 Pro

The workload applies 64 rounds of the same wrapping-u32 mix to 64, 4,096 or
262,144 elements. Both routes return every output element to host memory.
The CPU entry is compiled AOT with explicit SIMD; the GPU entry uses the
compiled SPIR-V binding. The harness asserts both routes and compares all
outputs with the CPU result after every sample.

## Operation accounting and correctness

[`arm64-macos-operation-proof.json`](arm64-macos-operation-proof.json) preserves
an instrumented 262,144-element CLI smoke run, source/artifact hashes, and the
packaged compiler's embedded-VM and statically linked GPU proofs. It records
initialization and pipeline creation once, distinguishes the first dispatch
from subsequent dispatches, and joins buffer layout/version and authored
kernel identity to each dispatch. Download mapping and the final host copy
are separate records. These records were collected during concurrent
validation; their durations are diagnostic evidence, not the comparison below.

GPU timestamp queries are resolved in a later submission after the measured
compute submission completes. A standalone wgpu reproduction showed that
same-submission resolution on this Metal environment could return zero or
the preceding dispatch's counters. Alternating large and small checked
workloads now verifies current-dispatch attribution. Raw ticks remain exact
decimal strings; equal or reversed counters are unavailable, not a zero or
wrapped duration. Instrumentation is disabled for the timing comparison.

The packaged compiler's 300,000-call C-ABI check passed; an attached observer
confirmed 150 completed JIT traces. Its 4,096-element GPU/profile smoke also
passed from an isolated directory without provider or compiler path overrides.
The final package at `8a2f444d` is 22,751,552 bytes; the preserved GPU-free control
is 13,791,744 bytes. The control predates several small compiler
changes, so the approximately 8.54 MiB difference is a packaging observation,
not an isolated size experiment. The final package includes the timestamp
resolution fix, and all three of its checked GPU dispatches produced positive
intervals with exact raw counters.

An earlier GPU pilot is rejected in full: it exposed a traced LuaJIT ARM64
stack-argument corruption, fixed in the pinned toolchain before these proofs.
No durations from that pilot are reused.

## Timing protocol

Each benchmark sample allocates its own state. GPU setup includes device,
buffers, pipeline, binding and one verified first dispatch, outside the timed
sample. Timed GPU operations include upload, dispatch, queued download,
synchronization, map/readback and the host copy. Timed CPU operations read the
same source and fill the same-sized host output. Cleanup and full output checks
are outside timing. Cost recording is disabled. Cases and variants are shuffled
once per fork round so the CPU control is colocated with GPU measurements.

## Five-fork exploratory curve

All thirty cases passed in the common quiet window on 2026-09-19. The run used
revision `a3ffeb10`, seed `20260919`, the preserved artifacts in the operation
proof, and this command:

```sh
env -u NUPP_GPU_COSTS ./bin/nupp bench --file bench/gpu-costs/costs.bench.lua --forks 5 --seed 20260919 --timeout-ms 120000 --json
```

[`arm64-macos-size-curve.json`](arm64-macos-size-curve.json) contains every fork
and sample; [the log](arm64-macos-size-curve.log) preserves all diagnostic notes.
The table reports the median of the five fork medians, with their observed
minimum–maximum in parentheses, in microseconds per complete invocation.
These are exploratory ranges, not confidence intervals. The harness withholds
its duration verdict because fewer than ten forks were collected.

| Elements | CPU AOT SIMD, µs | GPU with transfers, µs | GPU / CPU median latency |
| ---: | ---: | ---: | ---: |
| 64 | 0.442 (0.441–0.444) | 243.1 (231.9–248.6) | 549.922× |
| 4,096 | 28.77 (28.74–28.80) | 264.8 (225.4–275.9) | 9.204× |
| 262,144 | 1843.0 (1836.9–1848.7) | 595.7 (575.7–712.8) | 0.323× |

For this workload, the observed GPU route costs much more at the two small
sizes and has about 3.09× lower median latency at 262,144 elements. The crossover
lies somewhere between the tested 4,096 and 262,144 elements; this experiment
does not locate it more precisely or establish the result for other kernels.

The 4,096-element GPU samples are scattered: 43% lie within 10% of their median.
The tiny CPU and GPU cases reported `failed to allocate mcode memory` warnings
at the benchmark loop in two and one forks respectively. Their native kernels
and all output checks still ran; these warnings limit conclusions about the
Lua calling loop. All samples, warnings and outliers remain in the record; no inference
of a small performance difference is justified by this run. Cross-fork CPU CV
was below 0.3%; GPU CV ranged from 2.8% to 9.3%.

A second attempted pilot was interrupted after unrelated CPU tests entered its
window. It is also excluded. The final curve above ran after all participating
tasks explicitly paused workloads. No instrumented timing records or discarded
pilot samples enter the table.
