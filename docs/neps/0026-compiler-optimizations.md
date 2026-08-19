---
title: What the compiler optimizes, and what it leaves to the JIT
status: Implemented
created: 2026-08-19
---

## Summary

Nupp compiles to Lua source for a backend with a tracing JIT, so most of the
optimization catalog a Lua-targeting compiler would reach for duplicates work
the trace compiler already does better. Nupp optimizes what the JIT structurally
cannot see: collector pressure for values that escape, algorithmic shape, costs
paid before a trace exists, and constructs that abort trace recording. Four
constraints — no deoptimization, line attribution, source-level output, and
gradual boundaries — rule out approaches that would otherwise be standard.

[Performance](../guides/performance.md) documents what exists today.

## Goals

- Spend optimization effort only where it is not competing with the trace
  compiler.
- Keep every optimization statically sound, since nothing can be revoked at run
  time.
- Add a pass only when a benchmark says it earns its place.

## Non-goals

- Repeating the JIT's work: inline caching, global-chain resolution, method-call
  specialization, loop-invariant motion, inlining, unrolling.
- Optimizations that are sound "in the common case".

## Motivation

### Competing with a tracing JIT is a losing trade

Implementing the standard catalog buys a soundness burden in exchange for gains
that vanish once a trace warms. The work is real, the risk is permanent, and the
benefit is bounded by how long the code runs cold.

### Four things the JIT cannot do

**Collector pressure, for values that escape.** The collector is the runtime's
weakest component and the JIT does not help with it.

The qualifier is load-bearing and was learned by measurement. A value that does
not escape its trace already costs nothing, because allocation sinking removes
it — so an optimization whose precondition is "proves it stays local" is aimed
at the case the JIT already handled. What the collector actually walks is what
escapes: kept in an array, returned, stored on something else. Reification wins
6–9x on the array-of-structures benchmark precisely because two hundred thousand
particles held in an array escape as hard as a value can.

**Algorithmic shape.** A trace compiler makes each step of a quadratic loop
fast and cannot make there be fewer steps. String building is the case that
matters, and it is worth naming separately because it is the one place the
compiler is not competing with the JIT at all.

**Costs paid before the JIT sees anything.** Boxed integer cdata, symbol
lookups, repeated type construction, pin machinery — all statically known.

**Trace aborts.** Falling off a trace costs more than any lookup a compiler
could hoist, so a checker that knows what the trace compiler will do can rewrite
or diagnose the constructs that abort recording.

## Overview and specification

### There is no deoptimization

A compiler that owns its VM can be aggressive, because the VM can revoke an
optimization when it observes something invalidating. Nupp emits Lua source:
once a binding is hoisted into the output it is hoisted permanently, and there
is no runtime signal that can take it back.

Every optimization must therefore be statically sound or guaranteed by the type
system. "Sound in the common case, and users will not do the unusual thing" is
not available here, and this should be checked *before* an optimization is
designed rather than after.

### Line attribution constrains the output shape

Code generation is line-count-invariant, which is what buys correct stack traces
with no sourcemaps. Lua has no line directive: a prototype's line table is
derived mechanically from the physical line each token occupies, with no
supported way to rewrite it after load, and the only native lever is a constant
per-chunk offset.

Stating the invariant precisely — rather than as "do not move code" — is what
frees most of the catalog.

### Folding is not comptime

The optimizer folds and propagates constants. It must remain invisible, is
absent at `-O0` and under a plain check, and may decline silently. Anything
whose *meaning* depends on a compile-time value belongs to
[comptime](0011-comptime.md) instead, and can never be a fold at any strength.

### A pass exists when a benchmark says so

The catalog grows when measurement justifies it, not when an opportunity is
identified. An opportunity that has not been measured is a hypothesis.

## Risks and assumptions

- **This bets on the JIT staying good at what it is good at.** If the trace
  compiler regressed, or a target without it appeared, the whole division of
  labour would need revisiting rather than adjusting.
- **"No deoptimization" is a permanent ceiling.** Speculative optimization is
  simply unavailable, which puts a hard limit on what source-to-source
  compilation can achieve regardless of effort.
- **Escape analysis is the precondition that matters and is hard to get
  right.** The measurement that produced this framing could be re-run with a
  different workload and suggest something else; the reasoning is only as good
  as the benchmarks behind it.
- **A catalog invites accumulation.** A list of identified opportunities reads
  like a plan, and every entry that has not been measured is a hypothesis
  someone may implement on the strength of it being written down.

## Alternatives considered

**Implementing the standard Lua optimization catalog.** Rejected: it duplicates
the trace compiler on any code that runs often enough to matter, and buys a
permanent soundness burden for gains that disappear once a trace warms.

**Speculative optimization with runtime guards.** Rejected: there is no
deoptimization path in generated Lua source, so a guard that fails has nothing
to fall back to.

**Giving up line-count invariance** to free the optimizer. Rejected: the
invariant is what produces correct stack traces without sourcemaps, and Lua
offers no mechanism to restore attribution afterwards.

**Making the optimizer the compile-time evaluation mechanism.** Rejected — see
[NEP 11](0011-comptime.md). A construct that only works at `-O1` is not a
language feature.

**Optimizing values proved not to escape.** Rejected as redundant: allocation
sinking already removes them. The work is in what escapes.

## FAQ

**Why not inline?** Because the trace compiler already does, better, on anything
hot enough to notice.

**Why can't an optimization be sound only in the common case?** Because there is
no way to revoke it. Generated Lua source has no deoptimization path.

**What does line-count invariance actually require?** That the physical line a
token occupies corresponds to the source line it came from, because that is the
only mechanism the runtime offers for attribution.

**When does a new pass get added?** When a benchmark says it earns its place.
