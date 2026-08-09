# Profiling

Nupp ships a profiler, so finding out where a program spends its time does not
mean adding a dependency first.

There are two channels, and they answer different questions:

- **Sampling** (`--profile`) says *where* the time went. A timer interrupts the
  program, writes down the stack, and the result is collapsed-stack text that
  speedscope.app, FlameGraph.pl and inferno all read.
- **Trace aborts** (`--jit-aborts`) says *how* the time was spent there —
  compiled or interpreted. It records every place LuaJIT tried to compile
  something and gave up.

The second one is the one a conventional profiler cannot answer, and on LuaJIT
it is usually the one that matters. Code the compiler refused runs an order of
magnitude slower than code it took, and nothing says so out loud: the function
looks the same, it just is not fast.

## Sampling a program

    nupp run --profile app.nupp

That writes `profile.out` and prints a summary:

    nupp: 2043 samples on 61 stacks every 10ms, written to profile.out

Drop `profile.out` on [speedscope.app](https://speedscope.app) and you have a
flame graph. `--profile=2` samples every 2 ms instead of the default 10; below
about 10 the timer begins taking real time from the thread it is measuring, so
treat a fine interval as something you spend for a short window. `--profile-out`
puts the text somewhere other than `profile.out`.

Each line is one stack: frames separated by semicolons, then the sample count.

    frame;physics;app.nupp:0;app.nupp:step_[N] 431

The leaf carries the VM state most of its samples were in:

    _[N]  running compiled machine code
    _[I]  in the interpreter
    _[C]  inside a C function
    _[G]  in the garbage collector
    _[J]  inside the JIT compiler

`_[I]` on something hot is the finding. It means the compiler is not running
that code, and `--jit-aborts` will say why.

The stacks start at your program. The frames underneath — the loader that read
it, the pcall that guards it — belong to `nupp run`, not to what you asked
about, so they are cut.

One thing to know about reading the frames: LuaJIT inlines a compiled call
chain into a single trace, and inlined frames are not on the stack to be
walked. A hot call chain therefore arrives shorter than it reads in the source.
That is the compiler doing its job, not the profiler losing frames.

## Naming the parts of a program

Frames tell you which function ran. Zones tell you which *phase* it ran in, and
that is usually the question — the same `sort` called from loading and from
rendering is two different problems.

`nupp.zone` is a stack of names that the profiler reads:

```nupp
local zone = require("nupp.zone")

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

    frame;physics;app.nupp:stepWorld_[N] 812
    frame;render;app.nupp:drawWorld_[N] 233

Pushing and popping costs nothing while no profiler is listening — the module
checks one boolean and returns. What it does cost, when a session *is* running,
is a function call in the code being measured, and a call on the hottest path
can stop a trace forming. Mark warm paths, not the innermost loop.

Use `zone.enter` and `zone.leave` instead of `push`/`pop` when the two halves
might not run in the same session — a coroutine resumed after the profile
stopped, say. `enter` hands back a token that a late `leave` discards rather
than popping somebody else's zone.

## Finding what the compiler refused

    nupp run --jit-aborts app.nupp

That writes `jit-aborts.csv`:

    severity,count,reason,location,zone
    warn,7,NYI: bytecode FNEW,app.nupp:41,frame/spawn

Each row is one place the compiler gave up, how often, and which zone was open.
`severity` orders the file:

- `blacklist` — always worth fixing. The trace is permanently demoted to the
  interpreter for the rest of the process. It will not be retried.
- `warn` — a refusal. Whether it matters depends on whether it is hot, which
  is what the sampling channel is for.
- `info` — trace formation working as designed: a loop was left, recursion was
  found. Left out unless you ask for it.

`NYI: bytecode FNEW` above is a closure being created inside a loop, which
LuaJIT will not record. Hoisting the closure out of the loop is the fix, and
running again is how you find out whether it was the only one.

## From a program rather than the command line

The flags are a thin wrapper over `nupp.profile`, which is worth using
directly when the interesting window is not the whole run — a single frame, one
request, the part after warm-up.

```nupp
local profile = require("nupp.profile")

local session = profile.sample({intervalMs = 2, zone = "frame/render"})
renderEverything()
local report = session:stop("render.out")

print(report.samples, report.stacks)
```

`stop` returns the report and ends the session; `tostring` on it is the text
that was written. `pause` and `resume` leave a window out without ending
anything, which is how a benchmark keeps its own setup out of the numbers.

The `zone` option filters at `stop` rather than while sampling, so narrowing it
costs nothing at runtime — but it also means you cannot widen it afterwards.
What fell outside the prefix was still collected; the prefix is fixed when the
session starts.

The trace channel works the same way:

```nupp
local session = profile.trace()
runTheWorkload()
local report = session:stop()

if report.blacklisted > 0 then
    print(tostring(report))
end
```

One session of each kind runs at a time — both are process-wide, because the VM
hooks they attach to are — and starting a second while one is live is an error
rather than a silent replacement. A handle dropped without stopping leaves the
timer running or the hook attached for the rest of the process.

Neither channel is free. A sample session pays a timer interrupt, a stack walk
and a table write at every interval; a trace session pays a callback inside the
compiler at every abort. Stop a session once the question it was opened for has
an answer.
