---
title: Performance and the JIT boundary
status: Implemented
created: 2026-08-19
---

## Summary

Nupp compiles to Lua source for a backend with a tracing JIT, so most of the
optimization catalog a Lua-targeting compiler would reach for duplicates work
the trace compiler already does better. Nupp optimizes what the JIT structurally
cannot see, and reports what the recorder will refuse — statically, from
bytecode, with no instrumentation in any build.

[Performance](../guides/performance.md) and
[JIT trace checking](../guides/jit-trace-checking.md) document the surface.

## Goals

- Spend optimization effort only where it is not competing with the trace
  compiler.
- Keep every optimization statically sound, since nothing can be revoked at run
  time.
- Answer whether a loop can be recorded at all, giving the same answer on any
  machine.
- Make claims exactly as strong as their evidence.

## Non-goals

- Repeating the JIT's work: inline caching, global-chain resolution, method-call
  specialization, loop-invariant motion, inlining, unrolling.
- Optimizations sound only "in the common case".
- Forking the runtime, parsing its textual output, or modelling its optimizer.
- Injecting counters or probes into ordinary builds.
- Claiming a function is hot, will be called, or will stay compiled.

## Motivation

### Competing with a tracing JIT is a losing trade

Implementing the standard catalog buys a soundness burden for gains that vanish
once a trace warms. The work is real, the risk is permanent, and the benefit is
bounded by how long the code runs cold.

### Four things the JIT cannot do

**Collector pressure, for values that escape.** The collector is the runtime's
weakest component and the JIT does not help with it. The qualifier is
load-bearing and was learned by measurement: a value that does not escape its
trace already costs nothing, because allocation sinking removes it — so an
optimization whose precondition is "proves it stays local" targets the case the
JIT already handled. What the collector walks is what escapes. Reification wins
6–9x on the array-of-structures benchmark precisely because two hundred thousand
particles held in an array escape as hard as a value can.

**Algorithmic shape.** A trace compiler makes each step of a quadratic loop fast
and cannot make there be fewer steps. String building is the case that matters,
and the one place the compiler is not competing with the JIT at all.

**Costs paid before the JIT sees anything** — boxed integer cdata, symbol
lookups, repeated type construction, pin machinery.

**Trace aborts.** Falling off a trace costs more than any lookup a compiler
could hoist.

### Falling off a trace is invisible to every other tool

A loop that aborts recording runs interpreted however hot it gets. A sampling
profiler shows it as slow without saying why; a benchmark shows a number without
saying what changed. The fact is structural — a property of the emitted bytecode
and the recorder — so it can be read rather than measured, needing no quiet
machine and giving the same answer every run.

The claim a user wants is "this function will run as machine code", and it
cannot be made: a loop may never run, may stay cold, may take runtime types the
recorder cannot specialize, or may side-exit for input-dependent reasons.

## Overview and specification

### Syntax

Optimization has no source syntax; one annotation makes recorder blockers a
checked contract.

```nupp
@jit
local function step(exclusive out: span.WriteSpan<float>): nil
    ...
end
```

```sh
nupp build -O1
nupp bc --check src/sim.nupp     # static, exits 1 on an unconditional blocker
nupp run --jit-aborts            # what the recorder actually refused this run
```

### Usage

A pass reports what it did as a remark, always a note and never a build failure:

```text
OPT3: folded `WIDTH * 4` to `256`
OPT6: span access proven in range by `indexed.range` at models.nupp:14
```

A loop that builds a function aborts recording, so it runs interpreted however
hot it gets:

```nupp
@jit
local function step(rows: span.WriteSpan<float>): nil
    for i = 1, rows.count do
        local scale = function(v: float): float return v * 2 end   -- blocker
        rows[i] = scale(rows[i])
    end
end
```

```text
src/sim.nupp:4:22: error: NUPP2707: this loop builds a function, which aborts
trace recording, so the loop is blacklisted and runs interpreted
```

### Lowering

Reification keeps values off the collector's heap:

```lua
local Particle = ffi.typeof("struct { float x; float y; }")
local particles = ffi.new("struct Particle[?]", count)
```

String building is rewritten for algorithmic shape:

```lua
local __buf = {}
for i = 1, n do __buf[#__buf + 1] = parts[i] end
local out = table.concat(__buf)
```

Trace checking injects nothing. Ordinary check, build, and run emit no counters,
edge probes, loop callbacks, hidden zone pushes, or alternate bytecode, so a
trace-checked build and an ordinary one generate the same Lua. Static checking
reads the emitted bytecode beside the source line each instruction came from:

```text
0009  FNEW     6   0      ; src/sim.nupp:4   <- unconditional blocker
0010  MOV      7   6
0011  CALL     7   2   2
```

Runtime observation is opt-in and uses the VM's own trace hook, so its cost
exists only while a session is active:

```lua
jit.attach(function(what, traceno, func, pc, otherno, err) ... end, "trace")
```

A compiler that owns its VM can be aggressive, because the VM can revoke an
optimization when it observes something invalidating. Nupp emits Lua source:
once a binding is hoisted into the output it is hoisted permanently, and there
is no runtime signal that can take it back.

Every optimization must therefore be statically sound or guaranteed by the type
system. "Sound in the common case, and users will not do the unusual thing" is
not available here, and this should be checked *before* an optimization is
designed rather than after.

Code generation is line-count-invariant, which is what buys correct stack traces
with no sourcemaps. Lua has no line directive: a prototype's line table is
derived mechanically from the physical line each token occupies, with no
supported way to rewrite it after load, and the only native lever is a constant
per-chunk offset.

Stating the invariant precisely — rather than as "do not move code" — is what
frees most of the catalog.

```text
 Verdict               Meaning
 ────────────────────  ────────────────────────────────────────────────────
 Unconditional         Recording aborts whenever the pinned recorder
   blocker             reaches that operation.
 Must-reach blocker    Unconditional on every repeatable path through the
                       named loop, so that loop cannot complete a root trace.
 May-reach blocker     Unconditional once reached, on only some paths.
 Conditional risk      Depends on runtime types, call targets, shapes,
                       limits, or target details. Advisory.
 Observed abort        Came from the VM hook in this execution.
 Expected stop         Ordinary completion, recursion, or loop exit.
                       Informational, not a failure.
```

The value of the design is in this table. A single "will it compile?" answer
would have to be wrong somewhere; six verdicts each carry exactly the confidence
their evidence supports, and the last one exists so ordinary behaviour is not
reported as a problem.

### One reason registry

Static checking reads compiler facts and emitted bytecode; runtime observation
reads the VM hook. Both normalize through one registry, so a statically
predicted blocker and an observed abort are the same identity. **Raw recorder
strings are not retained as diagnostic identities or public API** — they are
unstable, and a public surface on them would tie diagnostics to an
implementation detail of a component Nupp does not own.

The trace annotation does not imply the ahead-of-time one and they share no
eligibility catalogs; they are mutually exclusive execution contracts. And the
same source and target check identically without running the program: a profile
informs a person and does not change whether source is accepted.

### A pass exists when a benchmark says so

The catalog grows when measurement justifies it, not when an opportunity is
identified. An opportunity that has not been measured is a hypothesis.

## Risks and assumptions

- **This bets on the JIT staying good at what it is good at.** A regression, or
  a target without it, would require revisiting the division of labour rather
  than adjusting it.
- **"No deoptimization" is a permanent ceiling.** Speculative optimization is
  unavailable, which limits what source-to-source compilation can achieve.
- **Escape analysis is the precondition that matters and is hard to get right.**
  The reasoning is only as good as the benchmarks behind it.
- **The verdicts are claims about a specific runtime version.** A recorder change
  can turn a correct verdict into a wrong one with no signal.
- **"Unconditional blocker" is a strong claim from static reading**, and the one
  users will act on.
- **Advisory verdicts risk being tuned toward.** Rewriting to silence a
  conditional risk without a benchmark is how a codebase acquires unmotivated
  contortions.

## Alternatives considered

**Implementing the standard Lua optimization catalog.** It duplicates the trace
compiler on any code hot enough to matter, for a permanent soundness burden.

**Speculative optimization with runtime guards.** There is no deoptimization
path in generated Lua source, so a failed guard has nothing to fall back to.

**Giving up line-count invariance** to free the optimizer. The invariant
produces correct stack traces without sourcemaps, and Lua offers no mechanism to
restore attribution afterwards.

**Optimizing values proved not to escape.** Allocation sinking already removes
them; the work is in what escapes.

**Parsing the runtime's textual diagnostic output.** The format is unstable and
undocumented, and it would make Nupp's diagnostics a function of another
project's logging.

**Forking the runtime** for a supported query interface — a maintenance
commitment far larger than the feature.

**Maintaining an independent model of the optimizer.** A second implementation
that drifts, answering confidently and wrongly rather than not at all.

**Injecting counters and probes.** Instrumentation changes what is recorded, so
the measurement perturbs the thing being measured, and it costs in ordinary
builds.

**One verdict instead of six.** Any single answer overclaims for some evidence
and underclaims for other, and erases the useful distinctions.

**Reporting every side exit.** Ordinary trace stops are not failures, and a tool
reporting them trains people to ignore it.

**Making profile results affect checking.** Acceptance would depend on having
run the program, on a particular machine, with particular input.
