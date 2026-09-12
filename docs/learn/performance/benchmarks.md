---
order: 625
---

# Benchmarks

A benchmark in Nupp is a program that declares cases through `nupp.bench` and
reports itself:

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
nupp bench --file bench/presize.bench.nupp --case '^point$' --variant '^grown$'
```

```text
# Benchmark: presize.point.grown

Benchmark             Mode  Cnt       Score  Units       Ratio
presize.point.grown    p50  311      15.681  ns/op      1.000x
```

Each case is announced and flushed before calibration starts. The set runner
also names its source file, then prints its p50 score and child wall time as soon
as it completes. A slow or stuck child is identifiable while the set is still
running; results do not wait for the final table.

The table follows JMH's compact final-report shape. `p50` is explicit because
Nupp reports the median of seven measured rounds rather than an average and
confidence interval. A case's score is the median round divided by its calibrated
iteration count, so the displayed unit is nanoseconds per operation. Exact round
times and the iteration count remain in the JSON record. The output has no `±`
column: seven rounds in one VM are correlated samples, so treating them as
independent observations and printing `1.96 × stdev / sqrt(n)` would not be a
valid confidence interval.

`nupp bench` runs cases at `-O1` and captures the compiler's optimization
account automatically. `build/remarks.json` is its fixed internal handoff with
`nupp run`; benchmark callers do not choose or pass that path.

`nupp.bench` measures from inside the program, while `nupp bench` discovers and
isolates those programs. An application's hot loop lives in the application — a
game's frame or a server's request path — with its real asset load and trace
population. The command does not replace that loop; it launches the program
that owns it.

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

## Comparative suites

Use a suite when several implementations should run against the same workloads.
It expands every case, parameter combination and variant into a separately named
benchmark:

```nupp
local bench = nupp.bench
const {type Invocation} = nupp.bench

local function prepare(invocation: Invocation): any
    return makeInput(invocation.parameters.size as integer)
end

local function current(input: any, _: Invocation): any
    return currentImplementation(input)
end

local function candidate(input: any, _: Invocation): any
    return candidateImplementation(input)
end

bench.suite({
    name = "parser",
    baselineVariant = "current",
    variants = {
        {name = "current", setup = prepare, run = current},
        {name = "candidate", setup = prepare, run = candidate},
    },
    cases = {
        {
            name = "document",
            parameters = {size = {1024, 65536}},
            operations = 1,
        },
    },
    sampleIterations = 1,
} as bench.SuiteOptions)
bench.report()
```

`setup` and `teardown` run outside the clock. `run` is the only timed callback,
and its result is kept automatically. `sampleIterations` repeats `run` against
one prepared state inside each sample; leave it at one for a mutating workload,
or raise it when one call is too short to measure. `operations` says how many
operations one call represents, so the table can still report `ns/op`.

By default a suite warms each pair ten times, then samples until it has at least
15 samples and 0.5 seconds of measured work. It stops with an error after 100,000
samples or 10 seconds of wall time rather than publishing an under-sampled
result. All five bounds can be set on the suite.

The collector runs normally during warmup and timing. Allocation is measured in
a separate pass with collection paused, so forcing a collection before every
sample does not turn the benchmark into a GC benchmark. The record retains every
normalized sample plus min, mean, sample standard deviation, p50, p90 and p99.
The human table stays compact and reports p50; when the runner has every variant,
`Ratio` is baseline p50 divided by that variant's p50, so values above `1x` are
faster. A winners table names the fastest variant for each workload. Pass
`--geo` to also compare variants by the geometric mean of those ratios,
weighting parameter expansions equally within a logical case and then weighting
logical cases equally.

## Frames

A frame loop is a latency measurement, and a distribution rather than a median
answers it. A budget missed one frame in a hundred is a visible stutter and an
unmoved mean.

```nupp
local frames = bench.frames("frame", 16.6, 600)
while running and frames:more() do
    frames:begin()
    step()
    render()
    frames:finish()
end
frames:report()
```

`more` is false once `count` frames are recorded, and `report` writes the record
and applies the gate — a frame loop needs no second call. An application that
ignores `more` still has to call `report`: nothing hands the library a callback
when the chunk returns, collection before shutdown is not guaranteed, and the
compiler's entry point ends in `os.exit`, so there is nowhere to hang an
exit-time fallback. A session that is never reported produces no record, and the
runner says so.

Frame times are elapsed on the monotonic clock, not `os.clock`. A frame that
waited on presentation, on I/O, or on a sleep spends little processor time and
misses its budget anyway, and missing the budget is the measurement.

## What is gated, and what is only recorded

Gated, because they are the same on every run of one binary:

- how many allocations of each kind the optimizer left standing **in each file**;
- the trace abort site identities — severity, reason, location and zone.

Allocations are counted per file rather than identified by position. An identity
of file, line and column would make inserting a comment above unchanged code look
like every allocation below it was newly introduced, failing the gate for a
change that allocated nothing.

Abort sites are absent rather than empty when no session could be opened —
`nupp run --jit-aborts` holds the one process-wide session, so a case run under
it reports `aborts uncollected`. Nothing aborted and nobody looked gate very
differently.

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

Every top-level Nupp benchmark in `bench/` uses the harness and is discovered by
`nupp bench`:

| Program | Entries | Comparison |
| --- | ---: | --- |
| `aos.bench.nupp` | 2 | tables and reified carray |
| `frames.bench.nupp` | 1 | application-owned frame loop |
| `json-lpeg.bench.nupp` | 18 | JSON decoding and recognition across Nupp PEG, LPeg, and the runtime codec |
| `nupp-lpeg-shapes.bench.nupp` | 6 | Nupp PEG and native LPeg by grammar shape |
| `peg-kernels.bench.nupp` | 8 | automatic PEG specialization and forced LPeg |
| `peg-lpeg.bench.nupp` | 7 | forced-LPeg recognition, captures, actions, and recursion |
| `peg-result-packs.bench.nupp` | 2 | native result packs and table capture |
| `presize.bench.nupp` | 2 | grown and presized tables |
| `soa.bench.nupp` | 3 | generated SoA, handwritten SoA, and AoS |

That is 49 isolated entries. Root-level `.lua` files are hand-written compiler
output controls or compiler probes, not Nupp source benchmarks. Subdirectories
such as `base64/`, `sha256/`, and `workers/` are cross-runtime benchmark projects
whose own `run.sh` drivers build and compare multiple implementations; they are
not callback cases for the in-process Nupp measurement API.

```bash
nupp bench
nupp bench --list
nupp bench --baseline build/bench-baseline.json
nupp bench --baseline build/bench-baseline.json --accept
nupp bench --geo
nupp bench --case '^point$' --variant '^grown$'
nupp bench --file bench/presize.bench.nupp --case '^point$' --variant '^grown$'
nupp bench --case '^lookup$' --variant '^table$'
nupp bench --parameter '^size=1000$'
```

`--case`, `--variant`, and `--parameter` are Lua string patterns over the
logical case name, variant name, or canonical comma-separated `key=value`
parameter text. Different dimensions combine; repeating one selector supplies
alternatives. Lua patterns do not have regular expression alternation, so select
`table` or `array` by repeating the variant selector:

```bash
nupp bench \
  --case '^lookup$' \
  --variant '^table$' \
  --variant '^array$'
```

Each `bench.case` gets its own process, not each file: a file is asked what cases
it defines with `--list-cases` and then run once per case with `--case NAME`. Two
cases sharing a process would share its heap, its compiled traces and its
blacklist.

The same rule is enforced for direct runs: a program that declares more than one
benchmark must be given `--case NAME`. This prevents a convenient-looking direct
run from sharing JIT and heap state. This direct-program option takes the complete
`suite.case.variant:key=value` name; the `nupp bench` selector matches only the
logical case component.

Each listing and case child has a 120-second deadline. Set another one with
`--timeout-ms MILLISECONDS`. The runner prints and flushes the case name before
starting the child, prints that child's result when it completes, then prints
the merged table and winners after the set finishes. `--geo` adds geometric-mean
variant comparisons.

## Sampling the measured window

```bash
nupp bench --case '^lookup$' --profile build/bench-profiles
```

Profiling is a separate pass after timing, so sampler overhead does not change
the reported score. The sampler is resumed only around each variant's `run`
callback; setup, teardown, and harness bookkeeping stay out. One
`NNN-case-name.collapsed` file is written per isolated benchmark. Use
`--profile-interval-ms` to change the one-millisecond interval and
`--profile-zone` to retain one `nupp.profile.zone` subtree. The files open
directly in speedscope, FlameGraph, and inferno.

## Machine-readable output

```bash
nupp bench --json > build/benchmark-export.json
nupp bench --schema
```

`--json` suppresses the progress lines and human result tables, leaving one
merged JSON document on standard output. It contains every selected case's raw
samples, suite identity, compiler account, and trace account. `--geo` changes
only the human report; consumers can calculate any aggregate they need from the
raw measurements.

The latest complete machine-readable result is always
`build/bench-record.json`. To retain append-only NDJSON history, name a file and
optionally label the run:

```bash
nupp bench \
  --history build/bench-history.ndjson \
  --label before-parser-rewrite
```

Every history line contains the raw samples, suite identities, compiler account
and trace account needed to analyze that run later. History is appended only
after every selected case produced a record.

The baseline belongs to the runner, not to a case — children comparing against it
would each read and overwrite one file describing all of them. A named baseline
that is not there exits non-zero rather than reading as a clean run.

Cases are `bench/*.bench.nupp`. The name is a convention rather than a
discovery, because `bench/` also holds programs that are not cases — hand-written
comparisons, spikes and probes — and running one to find out produces "wrote no
record", which is the right answer for a case that failed to report and the wrong
one for a file that was never a case.

`build/remarks.json` is written twice by `nupp run --remarks-out`: once before
the program starts, so the program can read it, and again after it returns, once
every module it `require`d has been compiled. The second is the complete account,
and it is the one the runner merges into each record.

::: seealso
- [profiling.md](profiling.md) for where the time went in one program
- [jit-trace-checking.md](jit-trace-checking.md) for finding recorder blockers
  without running anything
- [index.md](index.md) for the optimizer whose account a record carries
:::
