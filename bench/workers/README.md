# Worker benchmark

This benchmark is the performance contract for `nupp.workers`. It separates
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
