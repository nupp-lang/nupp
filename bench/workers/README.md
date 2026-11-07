# Worker benchmark

This benchmark measures pooled `coroutine.Scope.work`. It separates
pool startup, warm scalar task latency, copied payload throughput, prepared
record restoration, the same record through the dynamic fallback, and
CPU-parallel scaling so improving one cannot conceal a regression in another.

Run it on a quiet machine from the repository root:

```sh
bench/workers/run.sh
```

The harness reports the median of nine measured samples after two warmups.
Payload throughput counts both the request and response bytes. CPU scaling
calibrates one job to at least 20 ms, warms that loop in every lane, and compares
the same number of serial and parallel jobs.

Compare already-built revisions:

```sh
python3 bench/workers/compare.py BEFORE AFTER --output /tmp/worker-performance.json
```

The runner alternates fresh processes and retains raw output and binary hashes.
Retained-memory sampling has a separate [workload and runner](memory/README.md).

The [workers and channels acceptance record](results/macos-arm64-workers-and-channels.md)
records the implementation comparison, including its transfer and memory costs.

The [array transfer follow-up](results/macos-arm64-workers-transfer-follow-up.md)
records the retained optimization, rejected candidates and timing limitations.
