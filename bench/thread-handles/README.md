# Thread handle experiment

This experiment measures genuine LuaJIT thread handles for cooperative tasks and
native worker jobs. The baseline uses main's table handles.

```sh
python3 bench/thread-handles/compare.py /tmp/baseline /tmp/candidate /tmp/results.json
```

Build this project from its directory with `../../bin/nupp build`. Preserve each
binary before changing the runtime. Run the baseline with `EXPECT_THREAD=0` and
the candidate with `EXPECT_THREAD=1`.

The typed entry selects the native worker provider. The Lua harness calls the
runtime's function-first methods through an untyped parameter and closes scopes
explicitly. Application code uses the public callback-last contracts. This lets
the harness retain completed handles and inspect GC behavior independently of
the checker's borrow rules; it does not establish static task/thread parity.

Each process checks native pooled and dedicated jobs, cooperative self-results,
repeated await after collection, collection of dropped handle cycles, queued
cancellation dropping captures, dynamically loaded chunks retaining their
original globals, raw coroutine transfers, and worker failure propagation.

The comparison runs one warmup process per binary followed by 30 alternating
fresh-process pairs. Each measured process runs 1,000,000 cooperative spawn/await
operations, retains 10,000 completed task handles, measures 1,000 native worker
round trips and 1,000 completed worker handles, and resumes a raw generator
1,000,000 times. Durations use the native monotonic clock. Heap deltas follow two
full Lua collections. The practical duration margin is 5 percent; reported
intervals bootstrap the median of paired process ratios.

`metrics` reports cooperative microseconds per task, worker microseconds per
round trip, raw generator microseconds per resume, bytes per retained task,
bytes per retained worker, dropped-heap KiB, final heap KiB, and a result
checksum. Heap figures measure Lua allocations, not process RSS or native
worker heaps.

## Results

Keep the LuaJIT bridge experimental. It passes the runtime checks, but increases
cooperative task and raw coroutine costs and leaves static task adoption open.
The `thread<F>` ergonomics landed separately on main at `9af61dd59`.

The native comparison ran on macOS 26.6 arm64 with 30 fresh-process pairs and a
5 percent practical margin. Changes are medians of per-pair ratios; the baseline
and candidate columns are separate process medians.

| Operation | Baseline | Candidate | Paired change, 95% interval | Verdict |
| --- | --- | --- | --- | --- |
| Cooperative spawn and await | 1.578 us | 1.688 us | +8.0%, +5.7% to +9.1% | Regressed |
| Native worker round trip | 12.161 us | 12.470 us | +2.7%, +0.9% to +3.7% | Within margin |
| Raw generator resume | 15.03 ns | 17.00 ns | +13.0%, +10.4% to +16.3% | Regressed |

Retaining completed handles also retains their coroutine objects:

| Retained handle | Baseline Lua bytes | Candidate Lua bytes | Increase |
| --- | --- | --- | --- |
| Cooperative task | 872 | 1,532 | 660 bytes, 75.8% |
| Native worker | 657 | 1,233 | 576 bytes, 87.7% |

After dropping handles, the candidate process retains about 776 KiB more Lua
heap in this workload. The weak lookup table retains its allocated capacity;
the handle cycles themselves pass the collection checks. These figures do not
measure native worker memory or process RSS. Full samples, binary hashes, and
harness hashes are in [results.json](results.json).

## Representation

The cooperative handle is its actual execution coroutine. A worker handle is a
local completion coroutine whose initial closure owns the provider handle; the
job executes in the existing native lane VM. The candidate changes Nupp source
and uses existing LuaJIT APIs without changing VM code.

A weak-key, weak-value lookup supplies the task methods. A completed cooperative
coroutine anchors its outcome in a private thread environment. Live coroutines
keep their state through their frames, so dynamically loaded chunks inherit the
original globals. Queued cancellation drops the body and arguments while the
handle can remain alive. A shared resume guard refuses manual resumption of
managed handles; the scheduler keeps the original primitive.

The bridge therefore adds completion state anchoring, retained coroutine stacks,
worker proxy closures, and a lookup on ordinary resumes. A native implementation
could store managed-task state directly on a thread object. This experiment does
not measure the new core.

## Static typing

`Task<F>` still derives a structural method shape. The runtime prototype does
not change that representation in the checker. The intentionally refused
[static-probe.nupp](static-probe.nupp), outside this project's `src` include,
reports that the task shape cannot initialize a `thread`; see
[static-probe.json](static-probe.json).

A worker whose `await` returns 42 reports `done` through `job:status()` while
`coroutine.status(job)` still reports `suspended`. Its local completion proxy has
not executed. Raw coroutine queries need an explicit policy as well.

Full adoption needs managed-thread typing and explicit rules for queries,
resumption, and erasure. Runtime identity alone does not provide those rules.
Browser targets and other Lua hosts were not validated in this experiment.

## Validation

All 134 selected task, failure, suspension, worker, and timer cases passed. Each
of the 62 native comparison processes also passed the correctness checks before
its measurements. Completed self-results and loaded-chunk results collect when
their handles are dropped; repeated await survives collection.

## Reproduction

Use a separate checkout at the recorded baseline and copy only tracked harness
files into it:

```sh
./scripts/worktree thread-handle-repro /private/tmp/nupp-thread-repro 9af61dd59
git archive HEAD bench/thread-handles | tar -x -C /private/tmp/nupp-thread-repro
cd /private/tmp/nupp-thread-repro
(cd bench/thread-handles && ../../bin/nupp build)
cp bench/thread-handles/build/binary /private/tmp/thread-handle-baseline
git apply --unidiff-zero bench/thread-handles/candidate.patch
(cd bench/thread-handles && ../../bin/nupp build)
cp bench/thread-handles/build/binary /private/tmp/thread-handle-candidate
python3 bench/thread-handles/compare.py /private/tmp/thread-handle-baseline \
    /private/tmp/thread-handle-candidate /private/tmp/thread-handle-results.json
```

The zero-context patch targets the exact baseline revision. Its source hash and
the measured binary hashes are recorded in `results.json`. The production task
runtime on main keeps its table handles.
