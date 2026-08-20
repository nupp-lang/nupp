# Profiling

The profiler ships with the compiler, so finding out where a program spends its
time costs a flag rather than a dependency. There are two channels, and they
answer different questions.

- **Sampling** (`--profile`) says where the time went. A timer interrupts the
  program and writes down the stack, and the result is collapsed-stack text
  that speedscope.app, FlameGraph.pl and inferno all read.
- **Trace aborts** (`--jit-aborts`) say whether that time was spent compiled or
  interpreted. Every place LuaJIT tried to record something and gave up becomes
  a row.

The second question is the one a conventional profiler cannot answer, and on
LuaJIT it is usually the one that matters. Code the compiler refused runs an
order of magnitude slower than code it took, and nothing says so out loud: the
function looks the same, it just is not fast.

Both sessions satisfy `profile.Session`. Its associated `Report` is whichever
report the channel behind the session produces, so a helper written once over
the lifecycle still hands back the concrete one:

```nupp:playground
local profile = require("nupp.profile")

local function finish<S is profile.Session>(session: S): S.Report
    return session:stop()
end

local samples: profile.SampleReport = finish(profile.sample())
local aborts: profile.TraceReport = finish(profile.trace())
```

## Sampling a program

```bash
nupp run --profile app.nupp
```

That writes `profile.out` and prints a summary:

```text
nupp: 2043 samples on 61 stacks every 10ms, written to profile.out
```

Drop `profile.out` on [speedscope.app](https://speedscope.app) and you have a
flame graph. `--profile=2` samples every 2 ms instead of the default 10; below
about 10 the timer begins taking real time from the thread it is measuring, so
spend a fine interval on a short window. `--profile-out` puts the text somewhere
other than `profile.out`.

### Stack lines

Each line is one stack: frames separated by semicolons, then the sample count.

```text
frame;physics;app.nupp:0;app.nupp:step_[N] 431
```

The leaf carries the VM state most of that stack's samples were in:

- `_[N]`: running compiled machine code.
- `_[I]`: in the interpreter.
- `_[C]`: inside a C function.
- `_[G]`: in the garbage collector.
- `_[J]`: inside the JIT compiler.

`_[I]` on something hot is the finding. The compiler is not running that code,
and `--jit-aborts` says why.

### Frames the report omits

The stacks start at your program. The frames underneath it, the loader that read
it and the pcall that guards it, belong to `nupp run` rather than to what you
asked about, so they are cut.

LuaJIT also inlines a compiled call chain into a single trace, and inlined
frames are not on the stack to be walked, so a hot call chain arrives shorter
than it reads in the source. That is the compiler doing its job, not the
profiler losing frames.

## Zones

Frames say which function ran. Zones say which phase it ran in, and that is
usually the question, because the same `sort` called from loading and from
rendering is two different problems.

`nupp.profile.zone` is a stack of names that the profiler reads:

```nupp
local zone = require("nupp.profile.zone")

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

Samples taken inside those pushes lead with the zone path, so the flame graph
opens on your phases and drills into the code under each:

```text
frame;physics;app.nupp:stepWorld_[N] 812
frame;render;app.nupp:drawWorld_[N] 233
```

### Push and pop are intrinsics

Pushing and popping costs nothing while no profiler is listening, because the
module checks one boolean and returns. While a session is running, the cost is
the call itself, and a call on the hottest path can stop a trace forming.

So `push`, and a `pop` whose result is discarded, are lowered rather than
called. Written in statement position on a receiver that is a bare `local zone =
require("nupp.profile.zone")`, they are generated inline against the module's
own state, leaving nothing on the hot path to pay for.

| Spelling | Lowered | Reason |
| --- | --- | --- |
| `zone.push("frame")` | yes | |
| `zone.pop()` | yes | the popped name is discarded |
| `local name = zone.pop()` | no | the popped name is kept |
| `holder.zone.push("frame")` | no | the receiver is not a bare name |
| `other.push("frame")` | no | `other` is not `nupp.profile.zone` |

Mark warm paths rather than the innermost loop even so. Every other spelling
calls through the ordinary API, and `enter` and `leave` always do.

### `enter` and `leave`

Use `zone.enter` and `zone.leave` in place of `push` and `pop` when the two
halves might not run in the same session, such as a coroutine resumed after the
profile stopped. `enter` hands back a token that a late `leave` discards rather
than popping somebody else's zone.

## Trace aborts

```bash
nupp run --jit-aborts app.nupp
```

That writes `jit-aborts.csv`:

```csv
severity,count,reason,location,zone
warn,7,NYI: bytecode FNEW,app.nupp:41,frame/spawn
```

Each row is one place the compiler gave up, how often it did, and which zone was
open. `severity` orders the file:

- `blacklist`: always worth fixing. The trace is demoted to the interpreter for
  the rest of the process and is never retried.
- `warn`: a refusal. Whether it matters depends on whether it is hot, which is
  what the sampling channel is for.
- `info`: trace formation working as designed, such as a loop being left or
  recursion being found. Left out unless you ask for it.

`NYI: bytecode FNEW` above is a closure being created inside a loop, which
LuaJIT will not record. Hoisting the closure out of the loop is the fix, and
running again is how you find out whether it was the only one. [LuaJIT trace
checking](jit-trace-checking.md) carries the whole reason catalog, source,
bytecode, editor and runtime alike, with an example of every current diagnostic.

### Structured output

```bash
nupp run --jit-aborts=jit-aborts.json --json app.nupp
```

Each site keeps the raw VM detail and adds a stable `reasonId` and `class`, and
the report names the exact trace profile and reason catalog it was produced
under. CSV is unchanged for existing consumers.

## Profiling from a program

The flags are a thin wrapper over `nupp.profile`, which is worth using directly
when the interesting window is not the whole run: a single frame, one request,
or the part after warm-up.

```nupp
local profile = require("nupp.profile")

local session = profile.sample({intervalMs = 2, zone = "frame/render"})
renderEverything()
local report = session:stop("render.out")

print(report.samples, report.stacks)
```

`stop` ends the session and returns the report, whose `tostring` is the text
that was written. `pause` and `resume` leave a window out without ending
anything, which is how a benchmark keeps its own setup out of the numbers.

The `zone` option narrows the report at `stop` rather than filtering while
sampling, so it costs nothing at runtime. The prefix is fixed when the session
starts: what fell outside it was still collected, but the report cannot be
widened afterwards.

### Collecting aborts

The trace channel has the same shape:

```nupp
local session = profile.trace()
runTheWorkload()
local report = session:stop()

if report.blacklisted > 0 then
    print(tostring(report))
end
```

### Session lifecycle and cost

Both channels attach to VM hooks, which are process-wide, so one session of each
kind runs at a time. Starting a second while one is live is an error rather than
a silent replacement, and a handle dropped without stopping leaves the timer
running or the hook attached for the rest of the process.

Neither channel is free. A sample session pays a timer interrupt, a stack walk
and a table write at every interval; a trace session pays a callback inside the
compiler at every abort. Stop a session once the question it was opened for has
an answer.
