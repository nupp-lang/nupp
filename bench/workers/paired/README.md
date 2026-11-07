# Compare array transfer paths

This development fixture alternates the general codec and the direct array
frame inside one persistent worker pool. It keeps the callable, payload size,
and task API identical while reducing variation from fresh process placement.

In a task worktree, apply the temporary selector guard and run the comparison:

```sh
python3 bench/workers/paired/instrument.py .
RUSTC_WRAPPER= python3 bench/workers/paired/run.py --nupp "$PWD/bin/nupp" \
  --runs 3 --output /tmp/worker-paths.json
python3 bench/workers/paired/instrument.py . --undo
```

The runner requires the instrumented compiler source. The guard is applied only
in the comparison worktree. It lets `jobs.mode` select the path independently in
the caller and every lane, without a production runtime API. Apply and remove
it before committing any runtime change.

Each process opens one pool, then runs eight pairs in alternating order. Each
mode configures and collects every lane, warms each workload for 200 tasks,
then measures 1,000 scalar, 1,000 moved 4 KiB, and 1,000 moved 8 MiB round trips.
The scalar workload is a control. The disabled path includes one selector call
before using the general codec, so this isolates the transfer mechanism rather
than reproducing the old executable byte for byte. Process-level startup and
memory still need the separate existing worker benchmarks.
