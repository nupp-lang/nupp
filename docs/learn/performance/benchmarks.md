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

Benchmark     Mode    Cnt       Score  Units                p25-p75
point.sized    p50      7      16.897  ns/op       [16.626, 17.916]

note: 1 fork per benchmark. p25-p75 is within-process spread, NOT a confidence
      interval: samples inside one process share its heap, traces and thermal
      state, so no population interval follows from them. A score far from the
      middle of that range means the samples are not centred on it. No interval or
      verdict is available below 10 forks; run --pilot to size a replicated run.
```

The body owns its loop and runs `b.n` times, because calling a one-iteration
closure `n` times would put a call boundary inside the measurement. `n` grows
until a round is long enough to time, then every measured round uses that same
`n`, so a loaded machine cannot change how much work was counted.

The score is the median of seven rounds divided by `n`, and `p25-p75` is where
the middle half of those rounds fell.

That range is a **spread, not an error bar**. Rounds inside one process share
its heap, its compiled traces, its blacklist and the CPU's thermal state, so
they are not independent draws and no statement about a population median
follows from them. Reading it as `± something` is the mistake the note exists to
prevent, and it is why one fork earns no interval and no verdict.

The range still earns its column, because it says whether the score describes
anything. When the score sits near the middle of the range, the samples are
centred on it. When it does not, they are not — and that happens:

```text
Benchmark             Mode    Cnt       Score  Units                p25-p75
presize.point.grown    p50     62      47.837  ns/op      [21.399, 140.567]
```

Those samples alternate between roughly 21ns and roughly 140ns. The median
lands in the empty gap between the two clusters and describes no behaviour the
benchmark ever exhibited. Before this column existed the same run reported
`40.702 ns/op` and looked entirely unremarkable.

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
Benchmark                      Mode    Cnt       Score  Units                    p25-p75     Ratio
sum.floats.ipairs:size=100      p50   6724      72.792  ns/op           [72.500, 74.833]    1.000x
sum.floats.index:size=100       p50  10586      46.250  ns/op           [45.917, 47.125]    1.574x
sum.floats.ipairs:size=10000    p50     43   11778.208  ns/op     [11740.209, 11807.375]    1.000x
sum.floats.index:size=10000     p50     91    5506.542  ns/op       [5459.958, 5541.666]    2.139x

Winners
Workload               Winner   Speedup
sum.floats:size=100    index     1.574x
sum.floats:size=10000  index     2.139x
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

A `Ratio` of `2.139x` is safe to believe. A ratio of `1.03x` is not, and nothing
above distinguishes them. To get a number you can defend you need replicates
from **separate processes** — one process's samples cannot tell you how much
another process would differ.

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

The pilot is often the whole answer. Run it on `bench/presize.bench.nupp` and it
reports a between-fork CV around 15% and asks for **over 300 forks** to resolve
2%. That benchmark cannot support a small claim at any reasonable cost, and
knowing that is worth more than a number that pretends otherwise.

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

`96.14%` is computed, not chosen. For `n` fork summaries the interval
`[x₍ₖ₎, x₍ₙ₊₁₋ₖ₎]` covers the population median with exact probability
`1 − 2·P(Bin(n, ½) ≤ k−1)` — the sign test, which assumes nothing about the
distribution's shape. At twelve forks the harness picks `k = 3` and that
interval attains 96.14%.

This is also why **ten forks is the minimum**:

| Forks | Widest available interval | Coverage |
| ---: | --- | ---: |
| 3 | `[x₍₁₎, x₍₃₎]` | 75.00% |
| 5 | `[x₍₁₎, x₍₅₎]` | 93.75% |
| 6 | `[x₍₁₎, x₍₆₎]` | 96.88% |
| 10 | `[x₍₂₎, x₍₉₎]` | 97.85% |

At five forks, even taking the smallest and largest observations gives 93.75% —
so no 95% interval exists over five observations, however it is computed. Six is
the floor, but at six the interval *is* the two extremes. Ten is the first size
where both endpoints are interior, so no single unlucky process decides one.

Below ten the harness reports the range and withholds every verdict rather than
relabelling a narrower claim.

### `unstable` means the interval was withheld

`sum.floats.index:size=10000` shows `unstable` above:

```text
bench: trend-warning: sum.floats.index:size=10000: monotone trend in 7/12 forks;
       interval withheld and verdict forced to inconclusive
```

Each fork's samples are tested in execution order for a monotone trend
(Mann–Kendall, per process, never pooled). A benchmark still trending has not
settled, so its median is a moving target and an interval around it would be
false precision. Raise `warmupIterations` and run it again.

There is deliberately **no verdict asserting a steady state**. The harness can
say it found a trend or that it did not; it cannot say a benchmark has settled,
because failing to detect a trend does not establish one. Barrett et al. needed
changepoint analysis over 2,000 iterations in each of 30 processes to make that
claim, and simpler heuristics were shown to declare steady states that were not.

### Outliers are counted, not dropped

```text
bench: outliers: sum.floats.index:size=100: 815 severe of 10586 samples,
       max 2.3x median; classified only, all samples retained
```

Samples beyond three interquartile ranges are classified and reported. None is
removed: a real warmup or deoptimization phase falls exactly where those fences
do, so excluding what they catch would delete the behaviour the trend test is
looking for. The median is robust enough not to need them gone.

## Did my change do anything?

Two ways to ask, and they are not equally strong.

### `--against`: interleaved, and causal

```bash
nupp bench --against build/baseline/bin/nupp --forks 12 --margin 2
```

Both executables run inside the same session, adjacent in the same shuffled
permutation, so fork *k* of each meets the same thermal and scheduling state.
That pairing is what licenses a causal reading, and the comparison uses it:
Hodges–Lehmann on the paired log ratios with an exact signed-rank interval.

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

`unchanged` is a claim that has to be demonstrated by a narrow interval, not the
residue left when a test fails to find significance. A change of `0.0%` with an
interval of `[−20%, +20%]` is `inconclusive`, not `unchanged`: the run could not
tell, which is a different fact from nothing having moved.

Expect `inconclusive` to dominate on a busy machine. That is the tool working.
The remedy is `--pilot`, a quieter machine, or a wider margin — not a narrower
interval.

### The family is accounted for

Forty-nine benchmarks compared at a nominal 5% produce significant results from
unchanged code by construction. Per-benchmark p-values are adjusted with
Benjamini–Hochberg across the comparisons a run actually made, and the family
size is printed beside the margin.

This is also why "run unchanged code and never see `regressed`" is not a valid
check of the harness. The right one is an A/A study: repeat the comparison and
confirm the rate of non-`inconclusive` verdicts across the family sits at or
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
and applies the gate, so a frame loop needs no second call. It does need that
one: nothing hands the library a callback when the chunk returns, so a session
that is never reported produces no record and the runner says so.

Frames are timed on the monotonic clock, not `os.clock`. A frame that waited on
presentation or I/O spends little processor time and misses its budget anyway,
and missing the budget is the measurement.

## Selecting cases

`--case`, `--variant` and `--parameter` are Lua patterns over the logical case
name, the variant name, and the canonical `key=value` parameter text.
Dimensions combine; repeating one supplies alternatives, since Lua patterns
have no alternation:

```bash
nupp bench --case '^floats$' --parameter '^size=10000$'
nupp bench --case '^floats$' --variant '^ipairs$' --variant '^index$'
```

Every case gets its own process — not every file. Two cases sharing a process
would share its heap, its compiled traces and its blacklist, so a program
declaring more than one benchmark refuses a direct run too:

```text
nupp: bench: this program defines more than one benchmark; use --case NAME or nupp bench
```

Each child has a 120-second deadline; `--timeout-ms` sets another. Case names
are printed and flushed before the child starts and results as each one
finishes, so a stuck child is visible while the set is still running.

Execution order is shuffled, and reshuffled for every fork round. Running all of
one benchmark's replicates back to back would give it one contiguous slice of
the machine's thermal history, which is exactly the confound replication is
meant to break. The seed is printed and `--seed N` reproduces an order.

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

Everything else — durations, the calibrated `n`, retained-heap delta, and the
`--remarks` set — is recorded and reported, never gated. A run with no
comparable baseline says so, which is a result and a different one from a pass.
A named baseline that is not there exits non-zero.

Replication makes the abort gate stricter rather than noisier. Whether a loop
aborts is timing-dependent, so forks legitimately disagree; only a site present
in **every** fork can gate, and the rest are reported:

```text
bench: flaky abort site: peg-kernels.capture-list.lpeg: NYI:return-to-lower-frame
       in 3/12 forks; reported, not gated
```

Allocation sites and remarks are the compiler's account of its own output, so
every fork of one binary must agree. A disagreement is a defect rather than a
measurement, and is reported as one instead of being averaged away:

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

## Profiles and JSON

```bash
nupp bench --case '^floats$' --profile build/bench-profiles
```

```text
# Profile: build/bench-profiles/001-sum.floats.ipairs:size=100.collapsed
```

Profiling is a separate pass after timing, so sampler overhead does not change
the reported score, and the sampler is resumed only around each `run` callback.
The collapsed-stack files open directly in speedscope, FlameGraph and inferno.
`--profile-interval-ms` changes the one-millisecond interval and
`--profile-zone` retains one `nupp.profile.zone` subtree.

```bash
nupp bench --json > build/benchmark-export.json
nupp bench --schema
nupp bench --history build/bench-history.ndjson --label before-parser-rewrite
```

`--json` suppresses the progress lines and tables and writes one merged
document. Its top level is `benchmarks`, and each entry keeps **every fork
whole** rather than reducing it to a summary:

```
benchmarks[].forks[].measurement    each process's own ordered samples, trend,
                                    outlier count and abort sites
benchmarks[].summary                fork summaries, the interval or the reason
                                    it was withheld, the unanimous abort sites
benchmarks[].summary.intervalWithheld   below-minimum-forks | trend-warning
root.forks, root.seed               replication and the permutation order
root.machineKey                     what durations are compared across
root.comparison                     interleaved | observational
```

The forks are kept because a summary cannot give them back. Recomputing the
interval needs the per-fork summaries, and a properly calibrated warmup
classifier — which this does not ship — needs each process's ordered series.

The latest complete record is always at `build/bench-record.json`; `--history`
appends the same document as NDJSON, once every selected benchmark has produced
a record. `--schema` prints the whole shape.

## What is in `bench/`

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

The `.bench.nupp` suffix is a convention, not a discovery: `bench/` also holds
hand-written comparisons, spikes and probes, and root-level `.lua` files are
compiler-output controls. Subdirectories like `base64/`, `sha256/` and
`workers/` are cross-runtime projects with their own `run.sh` drivers.

`nupp.bench` measures from inside a program; `nupp bench` discovers and isolates
those programs. Neither replaces an application's own hot loop — a game's frame
or a server's request path, with its real asset load and trace population.

::: seealso
- [profiling.md](profiling.md) for where the time went in one program
- [jit-trace-checking.md](jit-trace-checking.md) for finding recorder blockers
  without running anything
- [index.md](index.md) for the optimizer whose account a record carries
:::
