---
order: 625
---

# Benchmarks

`nupp bench` finds every `bench/*.bench.nupp`, runs each case in its own
process at `-O1`, and merges the results. A benchmark is an ordinary program
that declares cases through `nupp.bench` and ends in `bench.report()`.

```bash
nupp bench                  # everything
nupp bench --list           # names and files, without running
nupp bench --file bench/presize.bench.nupp
```

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
# Result: point.sized  p50=13.472 ns/op  rounds=7  wall=3.181s

Benchmark     Mode  Cnt       Score  Units
point.sized    p50    7      13.472  ns/op
```

The body owns its loop and runs `b.n` times, because calling a one-iteration
closure `n` times would put a call boundary inside the measurement. `n` grows
until a round is long enough to time, then every measured round uses that same
`n`, so a loaded machine cannot change how much work was counted.

The score is the median of seven rounds divided by `n`. It is a median, not a
mean, which is why the column says `p50` and why there is no `±` column: seven
rounds in one VM are correlated samples.

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
Benchmark                      Mode  Cnt       Score  Units       Ratio
sum.floats.ipairs:size=100      p50  6772      70.958  ns/op      1.000x
sum.floats.index:size=100       p50  11308     43.625  ns/op      1.627x
sum.floats.ipairs:size=10000    p50    46   10898.750  ns/op      1.000x
sum.floats.index:size=10000     p50    98    5107.708  ns/op      2.134x

Winners
Workload               Winner   Speedup
sum.floats:size=100    index     1.627x
sum.floats:size=10000  index     2.134x
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

## Baselines

```bash
nupp bench --baseline build/bench-baseline.json           # compare
nupp bench --baseline build/bench-baseline.json --accept  # replace
```

Durations are never gated — they differ per machine and per run. Two things
are, because they are identical on every run of one binary:

- **allocation sites** the optimizer left standing, counted per file;
- **trace abort site identities** — severity, reason, location and zone.

```text
allocations rose from 3 to 5 in src/parser.nupp
sum.floats.index:size=100: new trace abort site: ...
```

Everything else — durations, the calibrated `n`, retained-heap delta, and the
`--remarks` set — is recorded and reported, never gated. A run with no
comparable baseline says so, which is a result and a different one from a pass.
A named baseline that is not there exits non-zero.

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
document holding every raw sample, suite identity, compiler account and trace
account — enough to compute any aggregate later. The latest complete record is
always at `build/bench-record.json`; `--history` appends the same thing as
NDJSON, once every selected case has produced a record.

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
