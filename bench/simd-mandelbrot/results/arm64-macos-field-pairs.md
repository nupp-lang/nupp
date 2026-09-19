# NEON field-pair deinterleaving, Apple M5 Pro

The restored field-pair lowering reduces Mandelbrot latency by **1.32%**:
candidate/baseline ratio **0.98677**, with a 95% interval of
**[0.98219, 0.98962]**. This is an improvement at the predeclared 1% margin.
It is a small gain on this workload, not a claim about every paired load.

| Implementation | Median across process medians |
| --- | ---: |
| Independent field gathers | 4.509 ms |
| NEON deinterleaving | 4.458 ms |
| Colocated forced-scalar control | 14.558 ms |

Measured September 19, 2026, on an 18-core Apple M5 Pro, macOS 26.6,
Apple clang 21.0.0. The compiler is `643cab93`, based on `cde40b27`.
Both libraries use the same compiler and source. The baseline overrides
`nupp.compiler.aot.cplan.fieldPairs` with a function returning an empty table
before invoking `bench/simd-mandelbrot/compile.lua`; the candidate leaves it
unchanged. Both include the uint32 overflow guard and checked fallback.
Assembly contains zero `ld2.4s` instructions in the baseline and two in the
candidate. No speculative Mask.any rewrite is included.

C compilation uses `-std=c11 -O3 -ffp-contract=off -fno-fast-math -Wall
-Wextra -Werror -Wno-parentheses-equality -fPIC -dynamiclib`. The workload is
1024 × 768 pixels, with a maximum of 256 iterations. Before timing, both
native libraries must agree with the forced-scalar function on every pixel;
the iteration checksum is 46,373,131.

`../compare.lua` calls the preserved libraries directly through FFI. Nine
fresh processes each warm all implementations three times, then collect 21
rounds with rotating implementation order. The control runs in every round.
Other task builds were paused before measurement.
The estimate is the geometric mean of the nine paired process-median ratios.
The interval uses 20,000 percentile bootstrap resamples of those paired log
ratios, with seed 20260919; samples within one process are not independent
replicates.

[Raw samples, per-process medians, artifact SHA-256 hashes and environment](field-pairs-20260919/summary.json)
are retained with the nine CSV files and their native correctness logs.
