---
order: 625
---

# Benchmarks

`nupp bench` finds every `bench/*.bench.nupp`, runs each case in its own
process at `-O1`, and merges the results. A benchmark is an ordinary program
that declares cases through `nupp.bench` and ends in `bench.report()`.

```bash
nupp bench                  # everything, one process per benchmark
nupp bench --list           # names and files, without running
nupp bench --pilot          # how many processes a real answer would take
nupp bench --forks 12       # that many, for an interval you can quote
```

One run of one process gives you a number. It does not tell you whether a
number that moved actually changed, and most of this page is about the
difference.

## One case

```nupp
local bench = require("nupp.bench")

local function sized(b: bench.Case): nil
    for _ = 1, b.n do
        bench.keep({x = 1, y = 2})
    end
end

bench.case("point.sized", sized)
bench.report()
```

```text
# Benchmark: point.sized (bench/point.bench.nupp)
# Result: point.sized  p50=16.897 ns/op  rounds=7  wall=2.944s

Benchmark     Mode    Cnt       Score  Units                p25-p99
point.sized    p50      7      16.897  ns/op       [16.626, 17.916]

note: 1 fork per benchmark. p25-p99 is within-process spread, NOT a confidence
      interval: samples inside one process share its heap, traces and thermal
      state, so no population interval follows from them. A score far from the
      middle of that range means the samples are not centred on it. No interval or
      verdict is available below 10 forks; run --pilot to size a replicated run.
```

The body owns its loop and runs `b.n` times, because calling a one-iteration
closure `n` times would put a call boundary inside the measurement. `n` grows
until a round is long enough to time, then every measured round uses that same
`n`, so a loaded machine cannot change how much work was counted.

`p25-p99` is a **spread, not an error bar**. Rounds inside one process share a
heap, a set of compiled traces and a thermal state, so no population interval
follows from them — which is why one fork earns no interval and no verdict.

Read it as a sanity check on the score. Score near the middle of the range means
the samples are centred on it; score outside means they are not:

```text
Benchmark             Mode    Cnt       Score  Units                p25-p99
presize.point.grown    p50     73      46.015  ns/op      [19.469, 153.456]
```

Those samples alternate between ~21ns and ~140ns. The median lands in the empty
gap between the two clusters and describes nothing the benchmark does. The same
run used to report `40.702 ns/op` and look unremarkable.

The upper end is p99 rather than p75 because a slow mode holding a tenth of the
samples moves p99 and leaves p75 where it was. `p75Sec` is still in the record.

## `keep` is the one rule

LuaJIT deletes work whose result never escapes its trace. That is how a
benchmark comes out impossibly fast — the loop under test is gone and the
measurement is of nothing. `bench.keep` stores the value somewhere a trace
cannot sink it:

::: code-group
```nupp [Nupp]
bench.keep({x = 1})
local kept = bench.keep({y = 2})
```

```lua [Generated]
do const __nuppT2 = bench; __nuppT2.__nuppSink = {x = 1} end
local kept = bench.keep({y = 2})
```
:::

In statement position on a local holding the module, it is generated as that
store rather than a call — a call per iteration is exactly the cost a sink must
not add. Bind the result and you get an ordinary call instead. Same terms as the
[profiler zone intrinsics](profiling.md#zones).

## Comparing implementations

A suite runs several implementations against the same workloads, expanding
every case × parameter × variant into its own isolated benchmark:

```nupp
local bench = require("nupp.bench")
const {type Invocation} = require("nupp.bench")

local function numbers(invocation: Invocation): any
    local values: {number} = {}
    for index = 1, invocation.parameters.size as integer do
        values[index] = index * 0.5
    end

    return values
end

local function byPairs(values: any, _: Invocation): number
    local total = 0.0
    for _, value in ipairs(values as {number}) do
        total = total + value
    end

    return total
end

local function byIndex(values: any, _: Invocation): number
    local total = 0.0
    const rows = values as {number}
    for index = 1, #rows do
        total = total + rows[index]
    end

    return total
end

bench.suite(
    {
        name = "sum",
        baselineVariant = "ipairs",
        variants = {
            {name = "ipairs", setup = numbers, run = byPairs},
            {name = "index", setup = numbers, run = byIndex},
        },
        cases = {{name = "floats", parameters = {size = {100, 10000}}},},
        sampleIterations = 1000,
    } as bench.SuiteOptions
)
bench.report()
```

```text
Benchmark                      Mode    Cnt       Score  Units                    p25-p99     Ratio
sum.floats.ipairs:size=100      p50   7261      68.166  ns/op           [67.834, 81.416]    1.000x
sum.floats.index:size=100       p50  11168      43.792  ns/op           [43.291, 53.750]    1.557x
sum.floats.ipairs:size=10000    p50     46   10889.875  ns/op     [10875.750, 11042.334]    1.000x
sum.floats.index:size=10000     p50     99    5094.625  ns/op       [5069.042, 5248.041]    2.138x

Winners
Workload               Winner   Speedup
sum.floats:size=100    index     1.557x
sum.floats:size=10000  index     2.138x
```

`Ratio` is the baseline's p50 over this variant's, so above `1x` is faster.
Add `--geo` for a per-variant geometric mean across the whole suite.

Only `run` is timed; `setup` and `teardown` are outside the clock. Its result
is kept for you, so a suite needs no `keep`.

| Option | Default | Use |
| --- | --- | --- |
| `sampleIterations` | 1 | `run` calls per timed sample. Leave at 1 for a mutating workload; raise it when one call is too short to measure |
| `operations` | 1 | Operations one `run` call represents, so the score stays `ns/op` |
| `warmupIterations` | 10 | Untimed calls before sampling |
| `minSamples`, `minDurationSec` | 15, 0.5 | Sampling stops once both are satisfied |
| `maxSamples`, `maxDurationSec` | 100000, 10 | Safety bounds; hitting one is an error, not an under-sampled result |

Drop `sampleIterations` from the suite above and the fastest pair says so
rather than publishing a number off a clock it outran:

```text
nupp: bench: sum.floats.index:size=100 reached its sampling limit after 100000
samples and 0.028538s measured; increase sampleIterations or the maximums
```

The collector runs normally during warmup and timing. Allocation is measured in
a separate pass with collection paused, so forcing a collection per sample does
not turn the benchmark into a GC benchmark.

## Replication, and what an interval costs

A `Ratio` of `2.139x` is safe to believe. `1.03x` is not, and nothing above
distinguishes them. That needs replicates from **separate processes**: one
process's samples cannot say how much another would differ.

Ask how many first:

```bash
nupp bench --file bench/sum.bench.nupp --pilot
```

```text
bench: pilot over 5 forks, one shuffled permutation per round

Benchmark                     Between-fork CV  Forks for +-2%  Forks for +-5%
sum.floats.ipairs:size=100               2.2%             10             10
sum.floats.index:size=100                2.2%             10             10
sum.floats.ipairs:size=10000             2.9%             13             10
sum.floats.index:size=10000              1.3%             10             10

bench: --forks 13 covers every selected benchmark at +-2%
```

The pilot is often the whole answer. On `bench/presize.bench.nupp` it reports a
CV near 15% and asks for **over 300 forks** to resolve 2% — that benchmark
cannot support a small claim at any price, which is worth more than a number
pretending otherwise.

Then run them:

```bash
nupp bench --file bench/sum.bench.nupp --forks 12
```

```text
Benchmark                      Mode  Forks       Score  Units                   Interval   Coverage     Ratio
sum.floats.ipairs:size=100      p50     12      73.292  ns/op          [73.167, 144.917]     96.14%    1.000x
sum.floats.index:size=100       p50     12      46.834  ns/op           [46.542, 69.625]     96.14%    1.565x
sum.floats.ipairs:size=10000    p50     12   11730.958  ns/op     [11710.625, 18245.708]     96.14%    1.000x
sum.floats.index:size=10000     p50     12    5499.875  ns/op                   unstable          -    2.133x
```

### Coverage is attained, not requested

`96.14%` is computed, not chosen. The interval `[x₍ₖ₎, x₍ₙ₊₁₋ₖ₎]` over `n` fork
summaries covers the population median with exact probability
`1 − 2·P(Bin(n, ½) ≤ k−1)` — the sign test, which assumes nothing about the
distribution's shape.

That formula is also why **ten forks is the minimum**:

| Forks | Widest available interval | Coverage |
| ---: | --- | ---: |
| 3 | `[x₍₁₎, x₍₃₎]` | 75.00% |
| 5 | `[x₍₁₎, x₍₅₎]` | 93.75% |
| 6 | `[x₍₁₎, x₍₆₎]` | 96.88% |
| 10 | `[x₍₂₎, x₍₉₎]` | 97.85% |

At five forks even the smallest and largest observations only reach 93.75%, so
no 95% interval over five exists to compute. Six is the floor and there the
interval *is* the two extremes; ten is the first size with both endpoints
interior. Below ten you get the range and no verdict.

### `unstable` means the interval was withheld

`sum.floats.index:size=10000` shows `unstable` above:

```text
bench: trend-warning: sum.floats.index:size=10000: monotone trend in 7/12 forks;
       interval withheld and verdict forced to inconclusive
```

Each fork's samples are tested in execution order for a monotone trend
(Mann–Kendall, per process, never pooled). Still trending means not settled, so
the median is a moving target. Raise `warmupIterations` and run it again.

There is deliberately **no verdict asserting a steady state**. Failing to detect
a trend does not establish one, and Barrett et al. needed changepoint analysis
over 2,000 iterations in each of 30 processes to earn that claim.

### Outliers are counted, not dropped

```text
bench: outliers: sum.floats.index:size=100: 815 severe of 10586 samples,
       max 2.3x median; classified only, all samples retained
```

Samples beyond three interquartile ranges are classified and reported, never
removed: a real warmup or deoptimization phase falls exactly where those fences
do, so excluding them would delete what the trend test is looking for. The
median is robust enough not to need them gone.

## Did my change do anything?

Two ways to ask, and they are not equally strong.

### `--against`: interleaved, and causal

```bash
nupp bench --against build/baseline/bin/nupp --forks 12 --margin 2
```

Both executables run in one session, adjacent in the same shuffled permutation,
so fork *k* of each meets the same thermal and scheduling state. That pairing is
what licenses a causal reading, and the comparison uses it — Hodges–Lehmann on
the paired log ratios with an exact signed-rank interval.

```text
Durations: candidate vs build/baseline/bin/nupp  (interleaved, paired)
Benchmark                        Change                Interval  Verdict
json-decode.large.nupp-peg       +18.4%       [+16.2%, +20.7%]   regressed
soa.particle-update.generated     -9.7%       [-11.1%, -8.2%]    improved
sum.floats.index:size=100         -0.4%        [-1.3%, +0.6%]    unchanged
peg-kernels.single-span.lpeg      +6.2%        [-1.3%, +14.0%]   inconclusive

bench: 49 compared, equivalence margin +-2.0%, Benjamini-Hochberg adjusted
       1 regressed, 1 improved, 1 unchanged, 46 inconclusive
```

### `--baseline`: historical, and observational

```bash
nupp bench --baseline build/bench-baseline.json --forks 12 --margin 2
```

Same verdicts, weaker warrant, and the output says so — nothing controls for
what changed on the machine between the two sessions. Where the machine itself
differs, the duration section is withheld entirely while the deterministic gate
is unaffected.

### The four verdicts

`--margin` is required and has no default, because three of the four answers are
undefined without one.

| Verdict | Means |
| --- | --- |
| `regressed` / `improved` | The whole interval lies beyond the margin, on one side, and the adjusted p-value survived the family |
| `unchanged` | The whole interval lies **inside** the margin |
| `inconclusive` | Everything else |

`unchanged` must be demonstrated by a narrow interval, not inferred from a test
that found nothing. `0.0%` with an interval of `[−20%, +20%]` is
`inconclusive`: the run could not tell, which is a different fact from nothing
having moved.

Expect `inconclusive` to dominate on a busy machine. That is the tool working;
the remedy is `--pilot`, a quieter machine, or a wider margin.

Forty-nine benchmarks at a nominal 5% produce significant results from unchanged
code by construction, so p-values are Benjamini–Hochberg adjusted across the
comparisons a run actually made and the family size is printed. That is also why
"run unchanged code and never see `regressed`" does not check this harness — an
A/A study does, by confirming the rate of non-`inconclusive` verdicts sits at or
below the adjusted level.

## Frame loops

A frame loop is a latency question, and a distribution answers it: one frame in
a hundred over budget is a visible stutter and an unmoved mean.

```nupp
local bench = require("nupp.bench")

local frames = bench.frames("frame", 16.6, 60)
while running and frames:more() do
    frames:begin()
    step()
    render()
    frames:finish()
end
frames:report()
```

```text
Benchmark   Mode  Cnt       Score  Units
frame        p50   60       0.103  ms/frame
frame        p99   60       0.134  ms/frame
frame      p99.9   60       0.134  ms/frame
```

`more` is false once `count` frames are recorded, and `report` writes the record
and applies the gate — but it must be called: nothing hands the library a
callback when the chunk returns, so an unreported session produces no record.

Frames are timed on the monotonic clock, not `os.clock`. A frame that waited on
presentation or I/O spends little processor time and misses its budget anyway,
and missing the budget is the measurement.

## Selecting cases

`--case`, `--variant` and `--parameter` are Lua patterns. Dimensions combine;
repeating one supplies alternatives, since Lua patterns have no alternation:

```bash
nupp bench --case '^floats$' --parameter '^size=10000$'
nupp bench --case '^floats$' --variant '^ipairs$' --variant '^index$'
```

Every case gets its own process — not every file. Two sharing one would share
its heap, compiled traces and blacklist, so a program declaring more than one
benchmark refuses a direct run too:

```text
nupp: bench: this program defines more than one benchmark; use --case NAME or nupp bench
```

Order is shuffled, and reshuffled every fork round: running one benchmark's
replicates back to back would hand it a contiguous slice of the machine's
thermal history, which is the confound replication exists to break. `--seed N`
reproduces an order. Each child has a 120-second deadline, and `--timeout-ms`
sets another.

## What actually fails a run

Durations never do, in any mode. Every verdict above is a report; nothing there
changes the exit status. Two things gate, because they are identical on every
run of one binary:

- **allocation sites** the optimizer left standing, counted per file;
- **trace abort site identities** — severity, reason, location and zone.

```bash
nupp bench --baseline build/bench-baseline.json           # compare
nupp bench --baseline build/bench-baseline.json --accept  # replace
```

```text
allocations rose from 3 to 5 in src/parser.nupp
sum.floats.index:size=100: new trace abort site: ...
```

Everything else — durations, the calibrated `n`, retained-heap delta, the
`--remarks` set — is recorded, never gated. A run with no comparable baseline
says so, which is a result and a different one from a pass; a named baseline
that is not there exits non-zero.

Replication makes the abort gate stricter, not noisier. Whether a loop aborts is
timing-dependent, so forks legitimately disagree; only a site present in
**every** fork can gate:

```text
bench: flaky abort site: peg-kernels.capture-list.lpeg: NYI:return-to-lower-frame
       in 3/12 forks; reported, not gated
```

Allocation sites and remarks are the compiler's account of its own output, so
every fork of one binary must agree. Disagreement is a defect, not a
measurement, and is reported as one:

```text
bench: json-decode.large: nondeterministic compiler output: fork 4 reported
       different allocation sites
```

::: deepdive Why those choices
Allocations are counted per file rather than by line and column: a comment
inserted above unchanged code would otherwise look like every allocation below
it was newly introduced.

Remarks are diffed both ways but not gated, because nothing in a remark says
whether a pass fired or declined — a pass that started firing adds one remark
and removes another.

An allocation site is one the Nupp optimizer left in the Lua it wrote. It says
nothing about whether LuaJIT went on to sink it. This catches that optimizer
regressing, which is narrow and real, and is not a count of allocations
performed.

Baselines are keyed by optimization level and `-Zno-opt` set, and abort sites
additionally by the recorder's `traceProfile` identity. The compiler digest is
recorded and never keys anything: an optimizer change that moves an allocation
site is exactly the regression this exists to catch, and keying by the digest
would discard it as uncomparable the moment it appeared.
:::

## Where did the time go?

```bash
nupp bench --case '^floats$' --profile build/bench-profiles
```

```text
# Profile: build/bench-profiles/001-sum.floats.ipairs:size=100.collapsed
```

One collapsed-stack file per benchmark, sampled in a separate pass after timing
so the sampler cannot change the score, and resumed only around each `run`
callback. Drop one on [speedscope.app](https://speedscope.app).

See [profiling.md](profiling.md#profiling-a-benchmark) for reading the result,
and for the other question a slow benchmark usually needs answered: whether it
ran compiled at all.

## Machine-readable output

```bash
nupp bench --json > build/benchmark-export.json
nupp bench --schema
nupp bench --history build/bench-history.ndjson --label before-parser-rewrite
```

`--json` writes one merged document whose top level is `benchmarks`. Each entry
keeps **every fork whole** rather than reducing it to a summary:

```
benchmarks[].forks[].measurement    each process's ordered samples, trend,
                                    outlier count and abort sites
benchmarks[].summary                fork summaries, the interval or why it was
                                    withheld, the unanimous abort sites
benchmarks[].summary.intervalWithheld   below-minimum-forks | trend-warning
root.forks, root.seed               replication and the permutation order
root.machineKey                     what durations may be compared across
root.comparison                     interleaved | observational
```

A summary cannot give the forks back: recomputing the interval needs the
per-fork summaries, and a calibrated warmup classifier — which this does not
ship — needs each process's ordered series.

`build/bench-record.json` always holds the latest complete record. `--history`
appends the same document as NDJSON once every selected benchmark reported.

`nupp.bench` measures from inside a program; `nupp bench` discovers and isolates
those programs. Neither replaces an application's own hot loop — a game's frame
or a server's request path, with its real asset load and trace population.

::: seealso
- [profiling.md](profiling.md) for where the time went, and whether it compiled
- [jit-trace-checking.md](jit-trace-checking.md) for finding recorder blockers
  without running anything
- [index.md](index.md) for the optimizer whose account a record carries
:::
