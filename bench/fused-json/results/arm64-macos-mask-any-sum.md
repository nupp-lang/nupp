# NEON Mask.any: pairwise-sum experiment

Rejected: replacing the NEON byte maximum with a two-word sum did not establish
a faster fused JSON decoder. Production emission is unchanged.

The clean ASCII confirmation measured a candidate/baseline throughput ratio of
**0.9951**, with a **95% interval of 0.9872–1.0031**. That is **0.49% longer
elapsed time**, with an interval from 0.31% shorter to 1.29% longer. The verdict
is **inconclusive** at the preset 1% practical duration margin; it does not meet
the retention criterion. Absolute per-process median throughput was 2847 MB/s
for the candidate and 2903 MB/s for the baseline.

## Candidate and correctness

Both native libraries came from compiler revision `cde40b27`, including the
uint32 cursor overflow guards. They have identical generated C except for
`KS_EXP_ANY_BODY` in the embedded SIMD header. The candidate replaced the
sign-selector mask and `vmaxvq_u8` with:

```c
return vaddvq_u64(vreinterpretq_u64_u8(all)) != 0u;
```

Mask producers supply canonical zero/all-one lanes. At the lowest nonzero byte
position of two canonical words, the sum is either 255 or 510, so a nonzero
mask cannot sum to zero modulo 2^64. The existing register-wise OR for wider
vectors preserves that property. All 65,536 canonical 128-bit byte-mask patterns
passed an exhaustive predicate check. Each library also passed all seven
compiled JSON corpus, first-error, Unicode, and tail differential tests.

Clang replaced the ASCII-path `movi/and/umaxv/fmov/tst` sequence with
`cmlt/addp/fmov/cmp`. This smaller instruction sequence did not yield an
established workload improvement.

## Measurement

Apple M5 Pro, arm64 macOS 26.6, Apple Clang 21.0.0, LuaJIT 2.1.1787165859.
The harness follows the measured export to registered C builders, rejects
candidate/baseline identity, and records both loaded library paths. Both Lua
wrappers do the same work and build error messages only on failure.

The initial pilot used nine fresh processes, 15 interleaved samples, and five
payloads. ASCII native batches took only 0.72–0.77 ms; its ratio interval was
0.9855–1.0393, so a longer confirmation was specified before running it.

The confirmation kept the exact ASCII corpus (2,097,217 bytes, digest
`fnv1a32:7b49ddf0`) and both libraries. It used 25 fresh processes, 25 samples
per process, three warmups, 64 MiB native batches (32 decodes, about 23 ms), and
the original 2 MiB Lunajson batches. Implementations rotate order within each
sample, collect before each batch, and consume decoded results. A per-process
median paired log throughput ratio is the independent observation; the reported
interval uses Student's t with 24 degrees of freedom. Improvement requires the
entire interval to exceed a 1% duration reduction.

Another agent reported overlapping validation during the first confirmation.
That complete run is retained as contaminated and excluded from the decision;
no individual forks were removed. The complete frozen protocol was then rerun
while all other agents were explicitly paused. The clean run's colocated
Lunajson control had an 8.47% coefficient of variation across process medians;
its range and every paired observation are retained rather than hidden.

[Raw pilot, excluded run, clean confirmation, commands, and artifact hashes](arm64-macos-mask-any-sum.json).

To select a fixed corpus and extend only native batches, the harness accepts
`NUPP_FUSED_BENCH_PAYLOAD=ascii` and
`NUPP_FUSED_BENCH_BATCH_BYTES=67108864`. `NUPP_FUSED_BASELINE` names the separate
baseline module tree, and `NUPP_FUSED_BENCH_OUTPUT` records each process result.
