---
order: 625
---

# Benchmarks

A benchmark in Nupp is a program, not a case a runner discovered. It links
`nupp.bench`, runs under `nupp run`, and reports itself:

```nupp
local bench = nupp.bench

local function sized(b: nupp.bench.Case): nil
    for _ = 1, b.n do
        bench.keep({x = 1, y = 2})
    end
end

bench.case("presize.sized", sized)
bench.report()
```

```bash
nupp run -O1 --remarks-out build/remarks.json bench/presize.bench.nupp
```

There is no `nupp bench`. A command has to launch what it measures, and an
application's hot loop lives in the application — a game's frame, a server's
request path — with its real asset load and its real trace population. A library
is called from the loop that already exists, so the program being measured and
the program being shipped are the same program. [NEP
32](../../neps/0032-benchmarks-as-programs.md) records that decision.

## `keep` is the one rule

LuaJIT removes work whose result does not escape its trace. That is correct, and
it is also the most common way a benchmark comes out impossibly fast: the loop
under test is deleted and the measurement is of nothing. `bench.keep` stores its
argument where a trace cannot sink it.

Written in statement position on a bare `local bench = nupp.bench`, it is
generated as that store rather than called, on the same terms as the [profiler
zone intrinsics](profiling.md#zones) — a call inside the measured loop is exactly
the cost a sink must not add.

| Call | Lowered inline |
| --- | --- |
| `bench.keep(value)` | yes |
| `local kept = bench.keep(value)` | no; the result is bound |
| `other.keep(value)` | no; `other` is not the module |

## The measured body owns its loop

`case` hands the body a `Case` and the body iterates `b.n` times. Calling a
one-iteration closure `n` times instead would put a call boundary inside the
measurement and change what the recorder sees.

`n` is chosen by growing it until a round takes long enough to time, and a size
is accepted only when it holds twice: the first round at any size also pays for
whatever the recorder had not compiled yet. The chosen `n` is recorded and every
measured round runs at it, so a loaded machine cannot change how much work was
counted.

## Frames

A frame loop is a latency measurement, and a distribution rather than a median
answers it. A budget missed one frame in a hundred is a visible stutter and an
unmoved mean.

```nupp
local frames = bench.frames("frame", {budget = 16.6, count = 600})
while running and frames:more() do
    frames:begin()
    step()
    render()
    frames:finish()
end
frames:report()
```

`more` is false once `count` frames are recorded. An application that ignores it
still has to call `report`: nothing hands the library a callback when the chunk
returns, collection before shutdown is not guaranteed, and the compiler's entry
point ends in `os.exit`, so there is nowhere to hang an exit-time fallback. A
session that is never reported produces no record, and the runner says so.

## What is gated, and what is only recorded

Gated, because they are the same on every run of one binary:

- the allocation sites the optimizer left standing;
- the trace abort site identities — severity, reason, location and zone.

Recorded, never gated: every duration, the calibrated `n`, the retained-heap
delta, and the remark set. Remarks are diffed and reported both ways rather than
gated, because nothing in a remark says whether the pass fired or declined, so a
pass that started firing would add one remark and remove another.

An **allocation site** here is one the Nupp optimizer left in the source it
wrote. It says nothing about whether LuaJIT went on to sink it, which happens
later and in another compiler that reports nothing here. It detects this
optimizer regressing, which is narrow and real, and is not a count of
allocations performed — `nupp.profile` has no channel that observes the
allocator.

`report` raises when a gated counter moved. A chunk's return value is discarded
and a run that did not raise exits zero, so raising is how a status reaches the
shell; `os.exit` would also produce one and would discard the run's own
`--profile` and `--jit-aborts` reports, which are written after the chunk
returns. The record is written before the raise, so a case that trips the gate
is still a case whose record the runner can merge.

## What keys a baseline

A counter is keyed by whatever it is a property of.

| | Keyed by | Why |
| --- | --- | --- |
| Everything | the optimization level and `-Zno-opt` set | `-O0` and `-O1` are different questions, not regressions of each other |
| Abort sites | the recorder's `traceProfile` identity | whether a loop aborts depends on the architecture, OS, recorder features and LuaJIT revision |
| Allocation sites, remarks | nothing further | properties of the compiler's output, which compare across hosts unchanged |

The compiler digest is recorded and **never** keys anything. An optimizer change
that moves an allocation site is precisely the regression this exists to catch,
and a baseline keyed by the digest would discard it as uncomparable at the moment
it appeared. A differing digest is reported beside the diff instead.

A run with no comparable baseline says so. That is a result, and a different one
from a pass.

## Running the set

```bash
nupp task bench
nupp run bench/run.nupp --baseline build/bench-baseline.json
nupp run bench/run.nupp --accept
```

Cases are `bench/*.bench.nupp`. The name is a convention rather than a
discovery, because `bench/` also holds programs that are not cases — hand-written
comparisons, spikes and probes — and running one to find out produces "wrote no
record", which is the right answer for a case that failed to report and the wrong
one for a file that was never a case.

One case is one process. Trace state, the trace budget, blacklisted traces and
the heap are all process-wide, so two cases sharing a process measure each other.

::: seealso
- [profiling.md](profiling.md) for where the time went in one program
- [jit-trace-checking.md](jit-trace-checking.md) for finding recorder blockers
  without running anything
- [index.md](index.md) for the optimizer whose account a record carries
:::
