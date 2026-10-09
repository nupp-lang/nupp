# Approximate traversal results

Measured on 2026-10-08, Apple M5 Pro, macOS arm64, LuaJIT 2.1.1787165859 -- Copyright (C) 2005-2026 Mike Pall. https://luajit.org/.

Five fresh-process forks per case, three timed samples per fork, a 25 ms calibration target, normal GC, default JIT settings, and randomized case order. Values below are medians of per-process median CPU times, in nanoseconds per complete root value. These are exploratory measurements, not statistical equivalence verdicts. See [method and limitations](README.md) and [raw samples](results.json).

## JSON encoding

| Workload | Generic callbacks | Generated callbacks | Cursor | Prepared loop | Direct reference |
| --- | ---: | ---: | ---: | ---: | ---: |
| small | 90.7 | 65.0 | 86.8 | 69.4 | 61.2 |
| wide | 359.6 | 237.0 | 344.0 | 346.6 | 233.6 |
| slots | 361.3 | 245.7 | 321.7 | 332.2 | 240.1 |
| list | 2866.0 | 1783.4 | 2817.4 | 2815.6 | 1771.6 |
| nested | 301.3 | 239.4 | 320.4 | 267.0 | 195.7 |
| mixed16 | 256.4 | 177.4 | 248.5 | 242.5 | 181.2 |

## Token decoding

| Workload | Generic callbacks | Cursor | Prepared loop | Direct reference |
| --- | ---: | ---: | ---: | ---: |
| small | 91.5 | 94.2 | 89.2 | 71.3 |
| wide | 301.9 | 310.7 | 297.0 | 672.1 |
| slots | 238.3 | 223.2 | 242.2 | 578.8 |
| list | 3391.6 | 3458.7 | 3375.0 | 2712.7 |
| nested | 333.7 | 380.6 | 326.6 | 247.6 |
| mixed16 | 232.7 | 245.8 | 237.1 | 426.6 |

## What this supports

- Cursors show no consistent advantage over explicit-state callbacks. In JSON encoding their paired median speedups range from 0.94x to 1.12x. Small differences often cross the 5% practical margin across forks and are inconclusive in this rough run.
- Generated member callbacks improve JSON encoding by 1.25x to 1.60x across these cases. The mixed-schema result is 1.47x, with paired fork ratios from 1.41x to 1.54x. This is evidence for specialization of traversal, not for removing the callback abstraction.
- The specialization has a trace-size cost. Mixed-schema JSON encoding has median live-trace counts of 14 for generic callbacks and 41 for generated callbacks, with 1,256 versus 11,863 IR instructions. These are IR counts, not machine-code bytes.
- Token decoding is generally close between generic callbacks and the prepared loop. Nested cursor decoding takes about 14% more CPU time than callbacks here. There is no parser in this test, so these are not JSON decode throughput numbers.
- The direct reference is not an upper bound: wide-record decoding takes 672 ns versus 302 ns for callbacks. The [trace log](wide-direct-traces.txt) shows repeated loop-unroll limits and interpreter fallbacks. Generating straight-line calls alone does not ensure a good trace.
- GC-paused heap growth for wide-record decode is 448 bytes/root in all four variants; nested decode is 608 bytes/root. The cursor is allocation-free as a traversal interface in this approximation. Construction allocations are shared. These heap deltas are a diagnostic, not exact allocator counts.

Keep callbacks as a viable extension contract, retain prepared traversal as the optimization boundary, and leave the final control-flow choice open until the real Nupp contract is measured. There is no evidence here for rewriting everything around cursors or for requiring runtime code generation.

## Reproduction and retained evidence

- [Harness](compare.lua) and [process runner](run.py); the raw results record their SHA-256 hashes and baseline revision.
- [Separate instrumented run](diagnostics.json); its timings include diagnostic hooks and must not be used as performance verdicts.
- [Mixed generated-callback trace log](mixed-generated-traces.txt) and [wide direct-decode trace log](wide-direct-traces.txt).

The initial calibration pilot was discarded after isolating setup and negative tests from JIT training. Only the final harness and five-fork run above support these conclusions. This is Lua-only, uses a deliberately small scalar/structure subset, and does not replace the planned Nupp-source, protocol, provider, or AOT experiments.
