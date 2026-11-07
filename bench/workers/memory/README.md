# Retained worker memory

This workload samples memory after completed jobs and explicit collection in
both the caller and every pooled lane. It records process RSS, caller Lua heap
bytes, and OS thread counts before opening the pool and after 1,000, 10,000,
and 100,000 sequential scalar jobs. These are retained-memory samples, not peak
RSS or an allocation count.

Build identical copies with the before and after compilers, then run on a quiet
machine:

```sh
python3 bench/workers/memory/measure.py /path/to/before/memory-benchmark \
  /path/to/after/memory-benchmark --runs 3 --output /tmp/worker-memory.json
```

The runner alternates process order, collects three independent runs per
variant, and reports medians alongside raw samples. Each child has a five-minute
timeout. A marker flush and a short pause let the parent sample the process
before the next phase. Collection jobs occupy each lane briefly so all lanes
participate in the barrier.

The binary uses POSIX `getpid` and `usleep`. The measurement runner supports
macOS and Linux `ps`; this fixture is not a Windows memory probe. RSS includes
native queues, Lua heaps, runtime libraries, stacks, and the stamped program.
Allocator retention and OS accounting can vary between runs, so compare the
whole sequence rather than treating one RSS sample as a leak verdict.
