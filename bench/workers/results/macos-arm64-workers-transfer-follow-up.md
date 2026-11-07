# Worker array transfer follow-up

A direct frame for one owned fixed-width array reduces the transfer mechanism's
cost. It uses the existing native attachment transport and preserves ownership
on cancellation and refused handoffs.

Before: main `e8b2fe5cc9c6958cee4eda1e87fbd1b544dd36d4`. The exact production
provider and experiment source hashes are in [the paired data](workers-transfer-paired.json).
Hardware: Apple M5 Pro, 18 cores, 48 GiB, macOS 26.6 (25G72).

## Experiments

Three candidates were tried independently:

- Lazy loading of the copied-value codec: no useful startup or latency gain,
  and only about 64 KiB less retained RSS. Rejected.
- Carrying endpoint presence from decoding to dispatch: native lifecycle checks
  passed, but two timing batches showed no reliable benefit. Excluded.
- A direct frame for a single moved array: retained. It skips the general
  validation walk, placeholder tables and value codec for a checked, movable
  array leaf. Other argument packs retain the general path.

[All preliminary trials](workers-transfer-trials.json) are retained, including
noisy and unfavorable results.

## Same-pool comparison

Fresh-process timings varied substantially, including unchanged scalar and
string paths, while other work ran on the machine. The five-pair
[whole-process comparison](workers-transfer-processes.json) is inconclusive;
it does not establish an overall startup or scalar improvement.

The tighter experiment alternates both transfer paths in one persistent pool.
Three processes each run eight pairs, with 200 warmup tasks and 1,000 measured
tasks per workload per mode. The callable, payload size and public task API are
identical between modes. A temporary guard selects the general path in the
caller and every lane; it is absent from the production source. The disabled
path includes a selector call, so this isolates the mechanism rather than
reproducing the old executable byte for byte. The [fixture and runner](../paired/README.md)
make that instrumentation explicit.

Across 24 pairs, the median paired ratio improves by 26.5% for moved 4 KiB
arrays and 19.1% for moved 8 MiB arrays. The direct path wins 19 and 20 pairs,
respectively. Per-process changes below compare each mode's median latency:

| Process | Scalar control | Moved 4 KiB | Moved 8 MiB |
| --- | ---: | ---: | ---: |
| 1 | +6.4% | -25.6% | -30.3% |
| 2 | -2.7% | -5.7% | -12.5% |
| 3 | -0.4% | -26.0% | -19.0% |

These are observed process results, not confidence intervals. The scalar
control varies in both directions; this experiment supports the array-path
improvement, not a scalar speedup or an application-wide percentage.

## Retained memory and validation

Three alternating memory runs retain 36.672 MiB before and 36.734 MiB after at
100,000 settled scalar jobs, a 64 KiB increase. Both retain 20 threads. This is
essentially unchanged; the earlier 4.22 MiB increase remains. The
[raw memory data](workers-transfer-memory.json) includes each collection barrier.

The native payload fixture and service fixture pass. Added service cases cover
empty and populated signed arrays, a native refusal after ownership handoff,
and subsequent reuse of the lane. All 2,463 shared-suite checks pass, and the
pinned-bootstrap fixpoint rebuilds byte-identically.

Bytecode inspection still reports the worker dispatch loop's captured-upvalue
close (`jit/loop-upvalue-close`). This change leaves that loop intact and adds
no loops to the direct transfer helpers.
