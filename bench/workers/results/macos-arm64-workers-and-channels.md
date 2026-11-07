# Workers and channels acceptance

WC-M1 through WC-M5 add dedicated workers and scope-bound, typed channels to
main's LuaJIT and browser implementations. Core adoption and Tecs audio are
separate work.

## Execution evidence

The stamped native service fixture exchanges 100 commands and replies in each
of three service lifetimes, checks dedicated-lane retirement, cancels a blocked
publisher, and exercises local cooperative channels. It also recovers an owned
array from a refused `trysend` and checks that failed public admission releases
both endpoint and array arguments. Static fixtures reject direction and payload
mismatches, moved endpoints, scope escape, endpoint task results, pointers, and
borrowed spans.

The actual Chromium package uses the public API and two dedicated workers. A
periodic producer and consumer exchange 256 messages through a four-message,
128-byte channel while the page stalls for 3,000 ms. Message 32 arrives after
606 ms and the last arrives after 1,625 ms. Cancellation passes, cross-origin
isolation is false, and the browser reports no errors. The raw result is in
[workers-and-channels-browser.json](workers-and-channels-browser.json).

The Node transport and lifecycle checks cover credits, startup failure,
cancellation, teardown, and resource counts. Native queue and registry tests
cover bounds, ownership, closure races, stale handles, and forged userdata.

## Comparison method

Before: `b5646cb02a3aac40395adf63e19c33bb3ba4332d`.
After: `e0470c1fa2a37ff6df695869ac07bf7250875479`.
Machine: Apple M5 Pro, 18 cores, 48 GiB, macOS 26.6 (25G72).

The same benchmark sources were built with each revision. Three fresh
processes per variant ran in alternating order after builds and browser runs
finished. Each latency process reports the median of nine samples after two
warmups. Tables below take the median across those three process results; they
are observations, not confidence intervals. The comparison includes the
compiler/runtime prerequisites between these revisions and does not isolate
the queue extraction alone. The later feature-profile fix only makes the same
endpoint types available to non-worker host builds; it does not change the
worker-enabled code measured here.

Reproduce with already-built binaries:

```sh
python3 bench/workers/compare.py BEFORE AFTER --runs 3 --output performance.json
python3 bench/workers/memory/measure.py BEFORE_MEMORY AFTER_MEMORY \
  --runs 3 --output memory.json
```

The CPU loop calibrates independently in each process. Its raw durations are
retained for inspection; they are not an equal-iteration CPU comparison across
revisions. By-reference and moved-buffer rates likewise do not represent copied
memory bandwidth.

## Pooled latency and startup

| Workload | Before | After | Change | Unit |
| --- | ---: | ---: | ---: | --- |
| cold scheduler | 17.59 | 18.80 | +6.9% | ms |
| scalar round-trip | 11.28 | 11.65 | +3.3% | us/op |
| text 4 KiB | 11.65 | 12.34 | +5.9% | us/op |
| record 4 KiB | 14.25 | 15.31 | +7.4% | us/op |
| record via any | 14.25 | 15.66 | +9.9% | us/op |
| record dynamic | 13.83 | 14.95 | +8.1% | us/op |
| optional 4 KiB | 14.31 | 15.17 | +6.0% | us/op |
| text 1 MiB | 92.12 | 92.80 | +0.7% | us/op |
| region 1 MiB | 13.70 | 14.85 | +8.4% | us/op |
| region scan 1 MiB | 413.98 | 410.62 | -0.8% | us/op |
| text scan 1 MiB | 495.58 | 487.42 | -1.6% | us/op |
| moved 4 KiB | 16.64 | 19.31 | +16.0% | us/op |
| moved 8 MiB | 14.07 | 17.92 | +27.4% | us/op |
| text 8 MiB | 563.05 | 564.01 | +0.2% | us/op |

Copied payload throughput counts request and response bytes:

| Workload | Before MiB/s | After MiB/s |
| --- | ---: | ---: |
| text 4 KiB | 670.55 | 633.00 |
| text 1 MiB | 21711.53 | 21552.76 |
| text 8 MiB | 28416.59 | 28368.44 |

The scalar round trip rises by 0.37 microseconds. Owned 8 MiB handoffs rise by
3.85 microseconds; the implementation now guards owned arguments through
admission failures and releases partially prepared transfers. This is a
measured cost, not a claim that pooled performance is unchanged. Removing
repeated public/provider guards and skipping endpoint scans on primitive frames
reduced the initial small-message regression. Large copied payloads and CPU
scaling are close in these runs.

## Retained memory

Each memory process completes 1,000, 10,000, then 100,000 sequential scalar jobs.
Collection barriers run in every lane, followed by two full caller collections.
The parent samples RSS and OS thread counts during a flushed marker pause.
Lua bytes below describe the caller heap only; RSS includes every lane, native
queues, stacks, libraries, code, and allocator retention. These are retained
samples, not peak RSS.

| Barrier | Before RSS MiB | After RSS MiB | Before caller Lua bytes | After caller Lua bytes | Threads before / after |
| --- | ---: | ---: | ---: | ---: | ---: |
| before pool | 5.406 | 5.500 | 966,802 | 1,103,422 | 2 / 2 |
| after 1000 jobs | 31.625 | 35.391 | 1,093,158 | 1,233,206 | 20 / 20 |
| after 10000 jobs | 32.453 | 36.641 | 1,120,370 | 1,253,062 | 20 / 20 |
| after 100000 jobs | 32.453 | 36.672 | 1,137,674 | 1,259,094 | 20 / 20 |

At 100,000 jobs the process retains about 4.22 MiB more. Both variants retain
20 threads after opening the 18-lane pool. RSS plateaus between 10,000 and
100,000 jobs; this workload shows bounded retention rather than growth with the
number of settled jobs. Dedicated workers are retired and joined separately by
the service lifecycle checks.

Raw process runs, executable hashes, source hashes, and comparison metadata are
in [the performance data](workers-and-channels-performance.json) and
[the memory data](workers-and-channels-memory.json).

## Compiler budgets

The checker retains its 2 MiB per-module allocation ceiling. Functions that take
no captures skip capture-root bookkeeping; the allocation and channel lifetime
checks pass together. The full test-runner code-size allowance is 0.84 generated
bytes per source byte: the prerequisites already measure 0.827 with the optional
const-specialized JSON decoder bodies, and the channel implementation measures
0.830. The previous 0.82 ceiling did not cover that fully populated target.

## Validation

The broad run exercised 5,928 test entries: 5,891 passed initially, with 18
skips and four explicitly unavailable Wasm/browser checks. Its failures were
non-worker host feature builds and the two compiler budgets described above.
All 12 distinct failed cases pass after correction, including the packaging and
owned-resource service fixtures. The native host also passes its no-feature
compile check and worker-enabled unit/integration tests.

The final shared-lane run passes all 2,463 checks without skips. The compiler
fixpoint starts from the pinned `v0.0.15-workers.1` release and rebuilds
byte-identically. Four Wasm/browser checks were unavailable in the broad run;
the separate Chromium channel package above supplies the real-browser channel
acceptance evidence.
