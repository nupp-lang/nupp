# NEON Mask.any: two-word OR experiment

Not retained: replacing the byte maximum with OR of the two 64-bit halves
showed no reason to replace the production path. Machine-wide isolation was
not verified, so this run is diagnostic evidence, not a retention decision.
Production emission is unchanged.

The observed candidate/baseline throughput ratio was **0.99650**, with a
computed **95% interval of 0.99309–0.99993**: **0.351% longer elapsed time**.
Those descriptive statistics fall inside the preset 1% duration band, but
unknown external workload overlap prevents treating them as established
equivalence or a clean confidence result. The candidate remains rejected/on
hold; a verified isolated run would be needed for a production decision.

## Candidate and correctness

The matched native libraries came from compiler revision `cde40b27`, including
uint32 cursor overflow guards. Their generated C differs only in
`KS_EXP_ANY_BODY`; the candidate reads the canonical mask as two words:

```c
const uint64x2_t words = vreinterpretq_u64_u8(all);
return (vgetq_lane_u64(words, 0) | vgetq_lane_u64(words, 1)) != UINT64_C(0);
```

All 65,536 canonical 128-bit byte-mask patterns passed the predicate oracle.
The candidate passed all seven compiled JSON corpus, first-error, Unicode,
and tail differentials, including a fresh run under the measurement VM.

The ASCII instruction sequence changes from `movi/and/umaxv/fmov/tst` to
`cmlt/dup/orr/fmov/cmp`. This removes the horizontal maximum but does not reduce
the instruction count. The UTF-8 error predicate gains one instruction; no
further payload timing was performed because the primary ASCII observation
showed no improvement and its isolation was not established.

## Measurement

Apple M5 Pro, arm64 macOS 26.6, Apple Clang 21.0.0. Both implementations ran in
the same explicitly selected pinned LuaJIT 2.1.1785763465 with the `irt_size`
fix from `10d68880`; the exact VM path and SHA-256 are in the raw record.
Absolute throughput should not be compared with the earlier sum experiment,
which used another LuaJIT revision.

The frozen protocol used the unchanged 2,097,217-byte ASCII corpus
(`fnv1a32:7b49ddf0`), 25 fresh processes, 25 interleaved samples per process,
three warmups, 64 MiB native batches, and 2 MiB Lunajson control batches.
Implementation order rotates, collections precede each batch, and decoded
results are consumed. Registered C builder identities and both loaded library
paths establish native execution. This task's agents held builds and tests
throughout the run (2026-09-19, approximately 20:20:08–20:21:23 UTC). Unrelated
test activity was subsequently discovered in another task; whether it
overlapped this interval is unknown. Machine-wide isolation was therefore
unverified. Every fork is retained, with no selective exclusions.

Each process contributes its median paired log throughput ratio. The interval
uses Student's t with 24 degrees of freedom. The planned acceptance rule
required the entire interval to exceed a 1% duration reduction, but is not
applied as a valid decision to this run. The colocated Lunajson control's
process medians had 6.55% coefficient of variation, with a 107.0–140.0 MB/s
range. This variation and all paired observations are retained.

[Raw forks, frozen protocol, scripts, commands, and artifact hashes](arm64-macos-mask-any-or.json).
