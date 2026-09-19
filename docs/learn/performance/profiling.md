---
order: 620
---

# Profiling

Nupp includes a sampling profiler and a LuaJIT trace-abort report. Use them to
find slow code and investigate why it stays interpreted:

```bash
nupp run --profile app.nupp       # where the time went
nupp run --jit-aborts app.nupp    # whether it ran compiled
```

LuaJIT can leave a loop interpreted when it cannot compile an operation inside
it. The program still works, but may run much slower. Sampling shows where it
spends time; the trace-abort report helps explain failed compilation.

For benchmarks, see [Profiling a benchmark](#profiling-a-benchmark).

Both are available through `nupp.profile`. Sampling and trace sessions implement
`profile.Session`. Its associated `Report` type lets a shared helper return the
appropriate report type:

```nupp:playground
local profile = nupp.profile

local function finish<S is profile.Session>(session: S): S.Report
    return session:stop()
end

local samples: profile.SampleReport = finish(profile.sample())
local aborts: profile.TraceReport = finish(profile.trace())
```

See [Associated types](../language/types/associated-types.md) for details on
`S.Report`.

## Sampling a program

```bash
nupp run --profile app.nupp
```

A timer periodically records the call stack. When the program finishes, Nupp
writes the samples to `profile.out` and prints a summary:

```text
nupp: 2043 samples on 61 stacks every 10ms, written to profile.out
```

Drop `profile.out` on [speedscope.app](https://speedscope.app) to view a flame
graph. `--profile=2` samples every 2 ms instead of the default 10 ms. Shorter
intervals increase profiling overhead; use them for short captures.
`--profile-out` changes the output path.

<a href="/images/speedscope-profile.jpg"><img src="/images/speedscope-profile.jpg" width="1280" height="720" style="max-width: 100%; height: auto" alt="A captured Nupp documentation-build profile rendered as a flame graph in speedscope's Left Heavy view"></a>

A documentation build captured with `nupp.profile.sample`, shown in speedscope's
**Left Heavy** view. Wider blocks account for more samples. Click the screenshot
to enlarge it.

### Stack lines

Each line is one stack: frames separated by semicolons, then the sample count.

```text
frame;physics;app.nupp:0;app.nupp:step_[N] 431
```

Each stack has a separate row for every observed VM state, with that state's
actual sample count. The final frame identifies the state:

- `_[N]`: running compiled machine code.
- `_[I]`: in the interpreter.
- `_[C]`: inside a C function.
- `_[G]`: in the garbage collector.
- `_[J]`: inside the JIT compiler.

C, GC, and JIT work has an explicit `<C>`, `<GC>`, or `<JIT>` leaf, so native
work is not charged to a Lua callback. LuaJIT captures the state at the timer
interrupt and inspects the stack later; native states therefore retain their
zone but make no claim about which Lua frame called them.

If a hot function shows `_[I]`, it is running in the interpreter. Use
[`--jit-aborts`](#trace-aborts) to check for failed compilation attempts.

<a id="frames-the-report-omits"></a>

### Omitted frames

The report omits the loader and `pcall` frames belonging to `nupp run`, so
stacks start at your program.

LuaJIT can inline several function calls into one trace. Those inlined calls
have no separate stack frames, so the profile may show fewer calls than the
source.

## Zones

Zones label phases such as loading, physics, and rendering. They let you
distinguish calls to the same function from different phases of your program.

`nupp.profile.zone` is a stack of names that the profiler reads:

```nupp
local zone = nupp.profile.zone

local function frame()
    zone.push("frame")

    zone.push("physics")
    stepWorld()
    zone.pop()

    zone.push("render")
    drawWorld()
    zone.pop()

    zone.pop()
end
```

Each sample starts with the active zone path, grouping the flame graph by phase:

```text
frame;physics;app.nupp:stepWorld_[N] 812
frame;render;app.nupp:drawWorld_[N] 233
```

::: deepdive Avoiding allocations while profiling
`zone.path` caches the joined path until the zone stack changes. Repeated reads
reuse the string, avoiding allocations and extra garbage collection caused by
the sampling callback itself.
:::

### Push and pop are intrinsics

When no profiler is active, `push` and `pop` check a boolean and return. During
profiling, calls inside a hot loop can interfere with trace compilation.

Nupp inlines `push` and `pop` when called as statements through a local binding
such as `local zone = nupp.profile.zone`. This removes the function call;
`pop` is only inlined when its return value is unused.

| Written as | Lowered | Reason |
| --- | --- | --- |
| `zone.push("frame")` | yes | |
| `zone.pop()` | yes | the popped name is discarded |
| `local name = zone.pop()` | no | the popped name is kept |
| `holder.zone.push("frame")` | no | the receiver is not a bare name |
| `other.push("frame")` | no | `other` is not `nupp.profile.zone` |

Place zone boundaries around phases, outside inner loops. The other forms
above make ordinary function calls, as do `enter` and `leave`. `bench.keep`
has similar inlining rules; see [Benchmarks](benchmarks.md#keep-is-the-one-rule).

### `enter` and `leave`

Use `zone.enter` and `zone.leave` when a zone might outlive the profiling
session, such as in a coroutine resumed after profiling stops. `enter` returns
a token. If the session has ended, `leave` ignores that token, so it cannot pop
a zone from a later session:

```nupp
local token = zone.enter("request")
serveRequest()
zone.leave(token)
```

## Trace aborts

```bash
nupp run --jit-aborts app.nupp
```

The command writes `jit-aborts.csv`:

```csv
severity,count,reason,location,zone,rootLocation
warn,7,NYI: bytecode FNEW,library.nupp:41,frame/spawn,app.nupp:20
```

Each row gives the root trace's starting location, the location where recording
stopped (including runtime libraries), its count, and the active zone. Rows are
ordered by severity:

- `blacklist`: LuaJIT has stopped retrying this trace for the rest of the process.
  Prioritize these when they affect hot code.
- `warn`: a failed compilation attempt. Use sampling to see how much time the
  affected code takes.
- `info`: normal trace events, such as leaving a loop or encountering recursion.
  Included by `run --jit-aborts`; `profile.trace()` omits them unless
  `includeBenign = true` is requested.

`NYI: bytecode FNEW` means LuaJIT encountered function construction while
recording a trace. If the function is created inside a loop, move its declaration
outside the loop and pass changing values as arguments. Run again to check for
other blockers. See [LuaJIT trace checking](jit-trace-checking.md) for the reason
catalog and examples.

### Structured output

```bash
nupp run --jit-aborts=jit-aborts.json --json app.nupp
```

Each entry includes the raw VM details, a stable `reasonId`, and a `class`.
`rootLocation` identifies the original trace across calls and side traces.
The report also identifies the trace profile and reason catalog used. Compilation
of lazily loaded modules is excluded from both CLI profiling sessions.

## Profiling a benchmark

`nupp bench --profile` writes one collapsed-stack file per benchmark:

```bash
nupp bench --case '^floats$' --profile build/bench-profiles
```

```text
# Profile: build/bench-profiles/001-sum.floats.ipairs:size=100.collapsed
```

Sampling happens in a **separate pass after timing**, so profiling overhead does
not affect the measured result. Only the `run` callbacks are sampled; setup,
teardown, and benchmark harness code are excluded.
`--profile-interval-ms` changes the one-millisecond interval and
`--profile-zone` keeps one zone subtree.

When using multiple forks, only the first is profiled.

If a benchmark slows down and its profile shows `_[I]`, check for trace aborts:

```bash
nupp run -O1 --jit-aborts bench/sum.bench.nupp --case 'sum.floats.index:size=100'
```

`nupp bench` also records abort sites. A new abort seen in every fork fails a
comparison against a baseline. See
[Benchmarks](benchmarks.md#what-actually-fails-a-run).

## Profiling from a program

Use `nupp.profile` directly to capture part of a run, such as one frame, one
request, or the work after warm-up:

```nupp
local profile = nupp.profile

local session = profile.sample({intervalMs = 2, zone = "frame/render"})
renderEverything()
local report = session:stop("render.out")

print(report.samples, report.stacks)
```

`stop` ends the session and returns a report. `tostring(report)` gives the same
text written to the file. Use `pause` and `resume` to exclude work without ending
the session; `nupp bench` uses them to exclude setup and teardown.

The `zone` option filters the report when you call `stop`, adding no filtering
overhead during sampling. All zones are sampled, but the filter is fixed when
the session starts and cannot be widened afterwards.

### Collecting aborts

Use `profile.trace()` to collect trace aborts:

```nupp
local session = profile.trace()
runTheWorkload()
local report = session:stop()

if report.blacklisted > 0 then
    print(tostring(report))
end
```

### Session lifecycle and cost

Profiling hooks apply to the whole process. One sampling session and one trace
session can run at a time; starting a second session of either kind is an error.
Always call `stop`: dropping the session handle leaves its timer or hook active.

Each sample requires a timer interrupt, a stack walk, and a table write. Trace
profiling runs a callback on each abort. Keep captures short to limit overhead.

::: seealso
- [Benchmarks](benchmarks.md) for measuring performance changes
- [LuaJIT trace checking](jit-trace-checking.md) for finding trace blockers
  without running the program
- [Performance](index.md) for compiler optimizations
- [CLI reference](../../reference/cli.md#run) for all `nupp run` options
:::
