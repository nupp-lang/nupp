---
title: Benchmarks are programs, not a subcommand
status: Implemented
created: 2026-09-10
---

## Summary

Measure Nupp code by linking a `nupp.bench` library into an ordinary program and
running it with `nupp run`, rather than by adding a `nupp bench` command that
discovers cases and launches them. One case is one process. Discovery,
aggregation, and baseline comparison live in a Nupp program under `bench/`
reached through a `nupp.lua` task, because none of that contains a compiler.

Gate on counters that are the same on every run of one binary. Key each one by
what it is a property of -- the optimization level for all of them, the recorder
identity for the ones that depend on a run -- and let compiler identity annotate
and never key, because the compiler moving is the regression most worth seeing
rather than a reason to stop looking.

Three compiler changes pay for it: optimizer remarks become a readable build
artifact, `keep` becomes an inline intrinsic, and the remark stream learns to
account for the allocations the optimizer left behind.

## Goals

- A benchmark can measure a real application's own loop rather than a copy of it
  maintained alongside.
- One case's trace state, blacklisted traces, and heap cannot reach another's.
- The measurement rules -- warmup, rounds, median, collection control, retained
  heap -- are written once instead of once per file.
- A report carries what only Nupp knows: trace aborts, zone paths, and which
  optimizations fired or declined on the measured code.
- A regression is detected by counters that are identical every run. Times are
  recorded, not gated.
- A compiler change that moves a counter is a reported difference, not a reason
  to stop comparing.
- Cost one library, one program, and three small compiler changes, each of
  which is useful on its own.

## Non-goals

- A general microbenchmark framework. This measures Nupp against itself, which
  is a narrower problem with sharper tools available.
- Comparison against other languages. That is a separate argument needing
  separately defensible workloads.
- A timing gate in required CI. Hosted runner timing is not stable enough, which
  is why `measurements.yml` is not required, and this proposal does not revisit
  that.
- Replacing [`nupp test`](../learn/projects/testing.md). A benchmark that got
  slower is not a failing test.
- Feeding the optimizer. A profile collected this way is evidence for a person
  or an agent reading a report, not an input to code generation.

## Motivation

Three problems, and the first one decides the design.

**A harness cannot measure an application.** A command has to launch the thing it
measures, so what it measures is a benchmark file. An application's hot loop --
a game's frame, a server's request path -- lives inside the application, with its
real asset load, its real allocation history, and its real trace population. A
benchmark file that reproduces it is a second implementation, and it drifts. A
library is called from the loop that already exists, so the measured program and
the shipped program are the same program.

**The measurement rules are copied.** `bench/` holds about forty entries and each
hand-rolls its own warmup, round count, median, and collection control. The rules
are not obvious: `bench/presize.lua` documents an earlier version of itself that
measured LuaJIT deleting the loop under test, because nothing in it escaped and
allocation sinking removed the work. Every author rediscovers that, or does not.

**Nothing gates.** `measurements.yml` runs two of the forty, enumerated by hand
in a shell heredoc, and uploads their text. A finding that stops holding is
caught only where an author wrote the check themselves, as
`bench/scratch-reuse.lua` and `bench/ffi-hoisting.lua` do.

### Why not a subcommand

The subcommand is the obvious answer and it loses on the first problem outright:
it cannot be called from a loop it did not start. That alone decides it.

It also has nothing left to do. Discovery over a directory, spawning a child per
case, and merging JSON are ordinary programming with no compiler in them. The
comparison with [`nupp test`](../learn/projects/testing.md) is instructive rather
than analogous: the test runner is a compiler surface because it needs the build
graph, suite sharding, and persisted timings to balance shards. A benchmark set
of a few dozen cases needs none of those, and the shared-process lane that makes
the test suite fast is precisely what a measurement must not have.

## Overview and specification

### A case is a program

```nupp
local bench = nupp.bench

local function sized(b: bench.Case): nil
    for _ = 1, b.n do
        bench.keep(makePoint())
    end
end

bench.case("presize.sized", sized)

bench.report()
```

Run it the way any program runs:

```sh
nupp run -O1 bench/presize.nupp
nupp run -O1 bench/presize.nupp --json --baseline build/bench.json
```

Program arguments already reach the loaded chunk, so the library reads its own
flags from `arg` and no new option parsing enters the compiler.

### `report` raises, because returning a status cannot work

A chunk's return value does not become a process status: `nupp run` calls the
chunk under `pcall`, discards what it returns, and exits zero unless it raised.
So `report` writes the record first and then raises when a gated counter moved,
and the raise is what the shell sees.

`os.exit` would also produce a status and is the wrong instrument. A run's own
`--profile` and `--jit-aborts` reports are written after the chunk returns, so
exiting from inside the chunk discards exactly the diagnostic a failing
benchmark most needs. A raise unwinds into the same path a program error takes
and leaves those reports intact.

Writing the record before raising is not an ordering detail. A case that trips
the gate is a case whose record the runner has to merge, or the report says
only that something failed.

### The measured function contains its own loop

`b.n` is handed to the case and the case iterates. The alternative -- calling a
one-iteration closure `n` times -- puts a call boundary inside the measurement
and changes what the recorder sees, so the loop belongs to the body being
measured.

Calibration and measurement are separate phases, because a calibrated `n` is a
timing-derived number and every gated counter has to be independent of timing.
The library grows `n` until a round takes long enough to time, records the `n`
it settled on, and then runs the measured rounds at that fixed value. A
comparison against a baseline re-runs at the baseline's recorded `n`, so the two
records counted the same work. Without that, a loaded machine calibrates to a
different `n`, attempts a different number of traces, and reports it as a
regression.

### The sink is a primitive, not a convenience

`bench.keep(value)` is why a benchmark measures anything. LuaJIT's allocation
sinking removes work whose result does not escape its trace, which is correct
and is also the single most common way a benchmark comes out infinitely fast.

It lowers to a store into a slot on the library's own module table. A store
across the module boundary escapes the trace, which is the whole requirement,
and it is the cheapest construct that does. It is generated inline on a receiver
statically known to hold `nupp.bench`, on the same terms as the
[profiler zone intrinsics](../learn/performance/profiling.md#zones), because a
call in the measured loop is exactly the cost a sink must not add.

A no-op function call was the first design and is wrong twice: the call is the
overhead, and a call the optimizer can see through sinks anyway.

### Frames

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

A frame report is a distribution, not a median: p50, p99, p999, the count over
budget, and trace aborts per frame. A throughput benchmark answers how fast the
average case is, and for a frame loop that is the wrong question -- a budget
missed one frame in a hundred is a visible stutter and an unmoved mean.

This is the shape a command cannot reach. The loop belongs to the application.

#### Completing

A frame session has to end, and the application is the only thing that can end
it, so the design gives the application a condition rather than taking control
of the loop. `more` is false once `count` frames have been recorded; a loop that
consults it terminates on its own, and `report` then writes the record and
raises on a gated mismatch exactly as a case's does.

An application is free to ignore `more` -- a game measured over a play session
has no frame count in mind -- and it still has to call `report`. There is no
exit-time fallback, because there is nowhere to hang one: the library is handed
no callback when the loaded chunk returns, collection before shutdown is not
guaranteed so a finalizer is not a mechanism, and the compiler's entry point
ends in `os.exit`, which runs nothing that was waiting for a normal return.

So a session that is never reported produces no record, and the runner says so.
That is a case-authoring error with a clear report, which is a better trade than
a shutdown hook in `nupp run` added for one consumer. A program that neither
reports nor exits is what the runner's per-case timeout is for.

The application decides whether to exit; nothing in the library exits for it.
That is the same decision as `report` raising rather than calling `os.exit`,
for the same reason.

### One process per case

The case is the process. Trace state, the compiler's trace budget, blacklisted
traces, and the heap are all process-wide, so two cases in one process measure
each other. Spawning per case also means `--profile` and `--jit-aborts` apply to
a single case with no plumbing: the runner passes them through.

It also means the runner owns a timeout and a kill, which is what makes an
application-hosted frame session safe to run unattended.

### The runner

`bench/run.nupp` globs the directory, spawns one `nupp run` per case with
[](nupp.io.process), merges the records, and compares against the
baseline. `nupp.lua` exposes it as a task, so the set runs as
`nupp task bench`, and `measurements.yml` invokes the task instead of naming
cases.

It stays under `bench/` rather than in `src/`. If it ever needs the build graph,
sharding, or persisted timings, it earns promotion and moves as the same code.

### What this asks of the compiler

Three changes, none of them large and none of them free. Naming them together is
the point: the library is the visible half of this proposal and the smaller one.

**Remarks become an artifact.** A benchmark's most useful line is often not a
time but which optimization declined and where. The optimizer already computes
that and prints it; this adds a machine-readable copy beside the build output,
keyed like every other artifact, so a running program can read the remarks for
the modules it measured. Nothing about what a remark says changes; see
[optimization passes](../learn/performance/index.md#inspecting-controlling-and-measuring).
Useful on its own, and the same artifact an optimization advisor would want.

**`keep` becomes an intrinsic.** The sink has to lower inline, which means the
compiler recognizes it on a receiver statically known to hold `nupp.bench`, on
the terms the profiler zone intrinsics are already recognized on. That is
compiler work, not library work, and it is the reason the sink is specified here
rather than left to the library to arrange.

**The optimizer accounts for what it left behind.** Gating on emitted allocation
sites needs the optimizer to report them, which it does not do today. It is
plausibly a small addition to what the passes already track on their way to a
remark, and it is still a change to the compiler and belongs in the cost.

### What is gated

Two counters, and they answer to different authorities.

**Nupp-level allocation sites, and the remark set.** Both are properties of the
emitted Lua: which allocations the Nupp optimizer left in the source it wrote,
and which passes fired or declined on the way there. They are the same on every
run because they are not run at all -- they are read out of the build.

The name is doing work. A Nupp-level allocation site is an allocation *present in
the emitted source*, and it says nothing whatever about whether LuaJIT sank it at
run time. The allocation sinking this proposal keeps invoking happens later and
in another compiler, and no remark can see it. So this counter detects the Nupp
optimizer regressing, which is a real and narrow thing, and it must not be read
as a statement about allocations performed.

**Trace abort sites.** Identities, not totals: the severity, reason, location,
and zone tuple the trace report already records per site. A count is partly a
function of how much work ran, and a new abort site is the finding -- a hot loop
that started aborting is a regression whether it aborted forty times or four
hundred. Totals stay in the recorded column.

Recorded, not gated: every duration, the calibrated `n`, and the retained-heap
delta a case measures around a forced collection.

**Not available, and therefore not promised:** a count of allocations performed,
and whether a given allocation survived into machine code. `nupp.profile` offers
a sampling channel and a trace-abort channel and nothing that observes the
allocator or the trace's own optimizer. The approximation existing benchmarks
use -- stopping collection and reading the heap -- is a size rather than a
count, and a frame loop with the collector stopped is not the frame loop being
shipped. Both gaps want the same missing instrument, a runtime observation
channel; if one is ever built, what it reports joins the recorded column first
and the gated one only after it has been shown to be stable.

### What keys a baseline, and what merely annotates it

Three things are easy to confuse here and the distinctions are the whole rule.
A counter is keyed by whatever it is a property of, and annotated by everything
else.

**The execution profile keys the baseline.** The optimization level and any
`-Zno-opt` exclusions are part of what is being measured, not a source of drift:
`-O0` and `-O1` answer different questions and their counters were never
comparable. A record carries the level and the exclusion set, and a run at a
different profile finds a different baseline rather than a failing one.

The runner spawns cases at `-O1` and a case run by hand passes it, because
`nupp run`'s ad-hoc default is `-O0` and a benchmark measured there is measuring
a program with no optimizer in it -- which makes the remark half of its record
say nothing. A deliberate `-O0` run, or one with a pass excluded, is a normal
thing to want: comparing a pass against itself is what the existing span
lowering benchmark does, and the key is what keeps those runs from being read as
regressions of each other.

**The trace profile keys the dynamic counters.** Whether a loop aborts is a
property of the recorder that watched it: the architecture, the operating
system, the enabled recorder features, the LuaJIT revision, and the bytecode
schema. A Linux baseline held against a macOS run would report the whole
difference between two recorders as a regression in the program.

The key already exists and is already carried. `profile.TraceReport` includes a
`traceProfile` identity with exactly those fields, recorded there for exactly
this reason, so abort sites are keyed by it verbatim rather than by a key
invented here. A run whose trace profile has no matching baseline is reported as
having none -- which is a result, and a different one from a regression.

The static counters are not keyed this way. Emitted allocation sites and remarks
are properties of the compiler's output and compare across hosts unchanged.

**Compiler identity annotates everything and keys nothing.** The compiler digest
is recorded and never suppresses a comparison. An optimizer change that moves an
allocation site, a remark, or an abort site is precisely the regression this
design exists to catch, and a baseline keyed by compiler digest would discard it
as uncomparable at the moment it appeared. So the comparison runs and the
differing digest is reported beside the diff: the reader sees "two allocation
sites appeared, and the compiler moved", which is an explanation to evaluate
rather than a silence.

Re-baselining is therefore an act. The runner accepts a diff only when asked to,
which is the point at which somebody decides the change was intended.

## What changed on the way in, 2026-09-11

Two things this proposal decided did not survive being built, and one it did not
anticipate. Recorded here rather than edited into the body, which says what was
decided at the time.

**The remark set is not gated.** It is diffed and reported both ways. A remark
carries no field saying whether the pass fired or declined, so a pass that
started firing adds one remark and removes another, and a gate on the set would
call that improvement a regression. Adding such a field is what would let the
gate be what this proposed; until then the counter is reported, not enforced.

**The per-case deadline is not enforced.** `nupp.io.process` does not expose
`Process` or `Options` on its module type in this tree -- the tour's own example
does not check either -- so the runner spawns with `os.execute`, which has no
timeout. A case that finishes without reporting is still caught, because it
leaves no record; a case that hangs is not. The deadline returns when that
surface does.

**A case is named, not discovered.** `bench/*.bench.nupp`. `bench/` already held
forty-odd programs that are not cases, and running one to find out reports "wrote
no record" -- which is the right answer for a case that failed to report and the
wrong one for a file that was never a case.

## Corrections, 2026-09-11

A review of the first implementation found defects that changed the design
rather than only the code, which is what this section is for.

**A case is a process, not a file.** The first runner started one child per file
and a file may define several cases, so the second case inherited the first's
heap, traces and blacklist — the exact sharing the proposal cites as the reason
to spawn at all. Files are now asked what they define and run once per case.

**Trace collection must start before calibration.** It started after, so a loop
that aborted and was blacklisted while being calibrated had already been demoted
by the time anything was watching, and the one finding that mattered was the one
guaranteed to be missed. A session is also optional now: `--jit-aborts` holds the
single process-wide session, so a case run under the flag most likely to be set
while investigating one used to fail outright.

**The baseline belongs to the runner.** Forwarding it to each child had every
child read and overwrite one file describing all of them, and a missing baseline
exited zero, which is how a lost baseline comes to look like a pass.

**Frames report themselves.** `FrameSession:report` recorded but did not write,
so the documented loop produced no record. It now writes and gates, and
`bench.report` is idempotent for a program that does both.

**Frame time is elapsed, not processor time.** `os.clock` counts the latter, and a
frame that waits on presentation or I/O misses its budget while spending almost
none of it.

**Allocations are counted per file, not identified by position.** A file, line and
column identity made inserting a comment look like every allocation below it was
new. The walk also counts declared functions, which it had been omitting, so the
account no longer depends on how the source spelled a function.

## Risks and assumptions

- **A compiler change moves the static counters all at once.** An optimizer
  change that shifts emitted allocation sites or remarks across the project
  reports against every case at once. Refusing to suppress that is deliberate,
  so the cost is a wall of diffs somebody reads and accepts in one go. The bet
  is that a noisy true report beats a quiet false one, and it is a bet: if broad
  changes are frequent enough that diffs get accepted unread, the gate has
  stopped working and nothing will say so.
- **A LuaJIT upgrade loses the dynamic baselines quietly.** Keying abort sites
  by the trace profile is what stops a recorder difference from reading as a
  program regression, and the same key means a LuaJIT upgrade leaves every
  dynamic comparison with no baseline to match. That is the correct answer and
  it is also a coverage hole shaped like a pass: a run reporting "no comparable
  baseline" looks a lot like a run that was fine. The runner has to distinguish
  the two loudly or this trades false alarms for silence.
- **The gated counters see the Nupp compiler and not the run.** Emitted
  allocation sites and remarks detect the Nupp optimizer regressing and nothing
  else. A library that started allocating per call, a LuaJIT upgrade that stopped
  sinking something, a trace that silently began materializing a value -- none of
  those move a gated counter. Abort sites catch the subset that shows up as a
  recorder giving up. The rest is a blind spot this accepts in order not to
  claim an instrument it does not have.
- **The sink assumes a store the trace compiler keeps, and nothing checks it.**
  `keep` works because a store into a visible object escapes, which is a
  property of LuaJIT's optimizer rather than a promise it made. A build that
  learned to eliminate the repeated store would turn every case into a
  measurement of nothing, all at once. The gated counters do not defend against
  this -- they are static and the store is removed at run time -- so the only
  signal is a collapse in the recorded durations, which a person has to notice.
  Of everything here this is the failure most likely to go unseen.
- **The library perturbs what it measures.** Zone and frame markers are calls in
  the code under test. The profiler documentation already says to mark warm paths
  rather than the hottest ones, and that constraint is inherited here.
- **Discoverability is worse than a command.** `nupp bench` would appear in
  `nupp --help`; a task appears only in `nupp tasks`. This bets that a benchmark
  set is found through the repository rather than through the CLI.
- **The runner may grow into the thing it declined to be.** Parallel scheduling
  and shard balancing are the signals; see the promotion note above.
- **A case is compiled by the compiler it measures.** Fine for the runner, which
  is a parent process, and intended for the cases, which is what the digest
  keying records.
- **A frame session depends on the application cooperating.** The library
  provides a condition and a report and cannot make a main loop consult either.
  An application that does neither yields its record only on exit, or not at
  all, and the runner's timeout is the floor under that rather than a fix for
  it.
- **This assumes the interesting number is a counter.** If the regressions that
  actually matter turn out to be timing-only, the gate is measuring the wrong
  thing and the non-required timing artifact is doing the real work.

## Alternatives considered

**A `nupp bench` subcommand.** Loses on the deciding property: it must launch
what it measures, so it cannot measure an application's own loop. See
[Why not a subcommand](#why-not-a-subcommand).

**A benchmark mode on `nupp test`.** Shares discovery and reporting for free, and
inherits a shared-process lane built to make correctness runs fast, which is the
opposite of what a measurement needs. It also conflates two verdicts: a test that
fails is broken, and a benchmark that slowed down is information.

**A shell script runner.** What `measurements.yml` does today. It works up to the
point where records have to be merged, compared against a baseline, and turned
into an exit status, and then it is a program written in the worst available
language for the job.

**Timing gates in required CI.** Rejected for the reason `measurements.yml`
already records: hosted runner timing is not stable enough to fail a trunk on,
and a gate that is flaky gets ignored, which is worse than no gate.

**Returning a status from the chunk.** The first shape this proposal had, and it
does not work: a chunk's return value is discarded and a run that did not raise
exits zero. Recorded because it reads as though it should work.

**`os.exit` from `report`.** Produces the status directly and discards the run's
own profile and trace-abort reports, which are written after the chunk returns.
See [`report` raises](#report-raises-because-returning-a-status-cannot-work).

**Keying the baseline by compiler digest.** Also the first shape, and wrong in
the same direction as the gate itself: it makes every compiler change
uncomparable, which silently excuses the one class of regression the counters
were chosen to detect.

**Counting allocations by stopping collection and reading the heap.** What the
existing benchmarks do, and sound enough for a case that can afford it. It
measures bytes rather than allocations, and a frame loop with the collector
stopped is not the frame loop being shipped, so it stays in the recorded column
and gates nothing.

**A shutdown hook in `nupp run`.** Would let a frame session report on normal
exit, and is a change to how every program runs made for one consumer. Requiring
an explicit `report` costs a line in the application and nothing anywhere else.
Worth revisiting if a second consumer ever wants the same hook.

**Gating abort totals rather than abort sites.** A total is partly a function of
how much work ran, so it moves with a recalibrated `n` and with anything that
changes trip counts. The site identity is the finding anyway: a loop that
started aborting is a regression at any count.

**An external benchmark framework.** None can read remarks, trace aborts, or
zone paths, which is most of what makes a Nupp benchmark worth more than a
stopwatch.

## FAQ

### Why not gate on times at all, even locally?

Because a gate that a developer's other process can trip gets disabled, and then
the counters go with it. Times are in the record and a person comparing two runs
sees them; nothing exits non-zero over one.

### What stops a benchmark from being deleted by the optimizer?

`bench.keep`, and nothing else. It is the one rule an author of a case has to
know, which is why it is a primitive with a reason attached rather than an
idiom.
