---
title: Const monomorphization
status: Draft
created: 2026-08-28
---

## Summary

A checked application of a runtime function with scalar `const` parameters may
produce a private body specialized to that application. The checker publishes
one canonical specialization key; ordinary optimized Lua and ahead-of-time
compilation consume the same key, substitute the const values, and run their
existing optimizers. Calls whose callee and complete key are known may name the
private body directly. The written declaration remains the one source function,
and its generic body remains the ordinary answer wherever specialization is
optional or AOT is disabled.

Specialization is an optimization, not compile-time evaluation. It executes no
source, generates no declaration, and changes no signature visible to source or
tools. An `@aot` contract is the exception to optional emission: when an
AOT-required build reaches a closed application of a const-generic annotated
function, that native specialization must compile or the build reports why.

This is the separate design for automatic specialization deferred by
[NEP 3](0003-comptime.md), using the artifact and target-tier machinery chosen
by [NEP 9](0009-ahead-of-time-compilation.md) and the private lane lowering
chosen by [NEP 11](0011-simd.md).

## Goals

- Give one checked const application one semantic identity regardless of which
  backend consumes it.
- Let ordinary LuaJIT benefit from constant substitution and fixed-trip
  unrolling before requiring native compilation.
- Let AOT lowering admit a closed const-generic body without inventing a
  parallel specialization or dispatch system.
- Preserve the generic declaration for indirect, open, unoptimized, and
  backend-disabled uses.
- Keep specialization deterministic from checked source and selected build
  configuration, with no profiling or machine-local decision in a build.
- Bound code growth per source module and attribute every required body to the
  call sites that demanded it.
- Give incremental builds, timing, code-size reports, generated symbols, and
  diagnostics body-level identities without redefining a module as several
  modules.
- Preserve source navigation, reference identity, effects, ownership,
  suspension, evaluation order, and error locations through every clone.

## Non-goals

- Specializing an ordinary function merely because one call happens to pass a
  literal. A scalar `const` binder is the source opt-in and the semantic key.
- Monomorphizing only type or pack parameters. Their concrete substitutions may
  participate in a const specialization's physical shape, but they do not cause
  a runtime body to be cloned on their own.
- Specializing `const` parameters in the `function` domain. Declaration
  identity remains available to the type system, but callback cloning and
  inlining need their own runtime evidence and design.
- Forced inlining, syntax generation, source quotation, AST access, or a user
  hook into lowering.
- Profile-guided specialization, build-time benchmarking, runtime adaptive
  cloning, or a machine-local cache of winning bodies.
- Promising that a specialization is faster. An optional optimizer may decline
  one, and `@aot` promises native compilation rather than a speedup.
- Removing AOT. Scalar optimized Lua may make it unnecessary for a workload;
  target lanes, fixed-width operations, native packaging, and predictable
  execution remain separate capabilities.
- Making generated private bodies addressable by a source name or visible as
  declarations through reflection or language tooling.

## Motivation

### The const fact currently ends before runtime lowering

A const parameter already gives the checker an exact value and distinguishes
generic applications. Erasing that fact before runtime emission leaves both
backends with a parameter that can vary, even when every checked call in a
deliverable supplies the same small value. A nested loop retains its test and
back edge; a branch retains both arms; an AOT lane pass sees a nested dynamic
loop rather than the straight-line map that the call actually selected.

The declaration should not be rewritten into several source functions to carry
that fact farther. The checker already has the semantic application, and a
private emitted body is enough.

### A literal bound is not the useful result on LuaJIT

The proving spike used a map whose inner recurrence ran four rounds. On the
same Apple arm64 machine, paired fifteen-sample ordinary-Lua runs gave the
generic body a baseline of `1.000x`, a separate body still containing
`for round = 1, 4` between `1.033x` and `1.071x`, and the same body with those
four rounds written straight-line between `11.703x` and `12.060x`.

LuaJIT's trace report explained the difference. Both loop spellings formed an
inner loop trace and side traces; the straight-line body kept the outer loop on
one trace. The specialization key alone is therefore insufficient. It must
reach the ordinary optimizer early enough for constant folding and bounded
unrolling to consume it.

### AOT gains twice from the same fact

The native spike first forced scalar emission, separating constant substitution
from vectorization. The closed four-round body was between `2.116x` and
`2.121x` faster than the runtime-count body while still scalar. Once unrolling
removed the nested loop, existing lane lowering admitted the outer map and the
complete body reached between `4.052x` and `4.176x`.

That is not evidence that every const application should clone. It is evidence
that the opportunity is material in both backends and that the compiler, not
LuaJIT or the C compiler, is the layer that can expose it to both.

### Backend-local discovery would create two meanings for one key

Target tiers already duplicate native emission, but a tier is a closed list the
build enumerates. Const applications are an open set discovered while checking
calls. If Lua emission infers one set from syntax while AOT lowering reconstructs
another from parameter spelling, aliases, named calls, multiple carriers, and
future checker changes can make them disagree.

Discovery belongs after checking and before either backend. The backends
receive a canonical application; they do not infer one.

## Overview and specification

### Syntax and worked example

There is no new syntax. The opt-in is the existing scalar const parameter:

```nupp
local function transform<const Rounds: integer>(
    exclusive output: span.WriteSpan<number>,
    borrows input: span.Span<number>,
    rounds: Rounds
): nil
    if #output ~= #input then
        error("length mismatch", 2)
    end

    for index = 1, #output do
        local value = input[index]
        for round = 1, rounds as integer do
            value = value * 1.0009765625 + round * 0.125
        end
        output[index] = value
    end
end

transform(output, input, 4)
```

`Rounds` is inferred and checked exactly as without this proposal. The call
does not request a body, select an optimization, or acquire new failure modes
under `check`. It only supplies a specialization demand to an optimizing build.

### Eligibility

A demand is eligible when all of these hold:

- the callee resolves to one function declaration by semantic identity;
- that declaration has at least one `const` binder in the `string`, `boolean`,
  or `integer` domain;
- the selected call signature closes every const binder and every other generic
  component needed by the runtime signature;
- every const value came through the checker's admitted deterministic const
  expression rules; and
- the declaration's body is available to the deliverable being built.

Aliases and imports do not change declaration identity. Named arguments do not
change binder order. Two parameters that infer one binder contribute one tuple
entry, and the checker has already proved that their values agree. A call
through `any`, an unresolved callable value, or a binary dependency without the
body is not eligible.

Recursive calls with the same key reuse the body already being formed. A
recursive call that computes a different closed tuple contributes another
demand and is subject to the same module cap; the diagnostic carries the demand
chain so const recursion cannot turn compilation into an unbounded evaluator.

### Canonical identity

The checker publishes an ordered const tuple. Each entry contains the binder's
declared domain and canonical value, so integer `4`, string `"4"`, and a future
domain cannot collide. Strings are keyed by their bytes rather than their
quoted spelling. The tuple contains binder values once, not once per carrier
parameter.

The semantic specialization key is:

```text
canonical declaration identity
+ instantiated checked-signature fingerprint
+ ordered scalar const tuple
```

The declaration identity is nominal and module-qualified, not a source offset.
The checked-signature component includes concrete type and pack substitutions
that affect runtime representation, without making those substitutions an
independent reason to clone. A digest of this key supplies the private logical
symbol suffix; the existing target-tier suffix then supplies its physical native
symbol.

Source positions and call-site lists are diagnostic metadata and never enter
the key. Moving a call past a comment does not rebuild a body. Changing its
tuple does.

### Demand collection and ownership

A specialization body belongs to the module that declares the function. A
whole deliverable collects demands from every checked direct call in its module
graph, groups them by declaring module, sorts their canonical keys, and emits
each key once. Ten calls using the same tuple demand one body.

This is an incoming dependency on emission, not a reverse type dependency. A
caller that adds or removes a tuple invalidates the declaring module's
specialization manifest and the artifacts made from it; it does not make that
module or its ordinary dependents type-check again. The manifest fingerprint is
part of the build key independently of the module's checked-source fingerprint.

A dependency distributed without its checked body cannot accept new native
specialization demands. Its generic Lua callable remains usable, but a direct
call that requires an `@aot` specialization reports that the dependency did not
ship specializable source rather than silently choosing Lua.

### Ordinary Lua lowering

At `-O0`, const monomorphization emits nothing. The generic function and call
erase exactly as the source does.

At `-O1` and above, an eligible demand enters the ordinary optimization
pipeline with its const carriers bound to exact values. Existing constant
folding runs first, followed by a bounded loop unroller and the rest of the
catalog. If the resulting body passes the growth budget, the declaring module
emits a private clone. A direct call in the same module names that clone and
omits carrier arguments whose evaluation is already proved static and pure:

```lua
local function transform__const_Rounds_4(output, input)
    if output.count ~= input.count then error("length mismatch", 2) end

    for index = 1, output.count do
        local value = input:get(index)
        value = value * 1.0009765625 + 0.125
        value = value * 1.0009765625 + 0.250
        value = value * 1.0009765625 + 0.375
        value = value * 1.0009765625 + 0.500
        output:set(index, value)
    end
end

transform__const_Rounds_4(output, input)
```

The spelling above is explanatory. Generated names use the key digest, and all
statements retain the original declaration's source positions.

An exported function, a function stored as a value, and a cross-module call
keep the original callable identity. Its generated wrapper may tail-dispatch a
known runtime carrier tuple to a private clone and otherwise tail-call the
generic body. Direct same-module calls bypass that branch. Declining an
ordinary Lua clone is silent unless optimization remarks were requested, and
never makes valid source fail to build.

Substitution does not imply unrolling. The ordinary optimizer applies its
normal proof and growth limits, and may retain a literal-bound loop or decline
the clone if no profitable rewrite remains. `--remarks` identifies the tuple,
the resulting body, and the proof or budget that declined it. The pass receives
its own stable `OPT-n` code and may be disabled for miscompile bisection like
the rest of the catalog.

### Ahead-of-time lowering

An `@aot` declaration with const parameters denotes a family of required closed
native bodies. In an AOT-required or emit-C build, every eligible demanded key
must lower to verified IR or the build fails at the demanding call. This keeps
[NEP 9](0009-ahead-of-time-compilation.md)'s no-silent-fallback contract.

The specialized checked signature and exact const tuple enter AOT lowering;
the generic CST is not copied or rewritten. Const carriers become IR constants,
then the ordinary AOT optimizer, verifier, lane decision, and emitter run in
their established order. The four-round example becomes four scalar statements
and, where profitable, one private lane body plus its exact scalar tail.

Each logical specialization reuses target multiversioning. If a deliverable
carries baseline, AVX2, and AVX-512 tiers, one const key produces the same
logical body under three existing physical tier names. The loader selects the
widest safe physical entry once for each const key. Tuple dispatch then chooses
among those already-selected logical entries; it does not repeat feature
detection on every call.

With AOT disabled, the annotation retains its ordinary dormant behavior and
the generic Lua body remains available. In an AOT-required build, a checked
direct call never falls back to Lua. An unmatched call entering from unchecked
Lua reports that no compiled const application exists. An indirect Nupp call
whose declaration identity cannot be proved is rejected when satisfying the
annotated contract, because the build cannot attribute its required body.

### Evaluation and observable behavior

The specialized and generic routes have one source meaning. Const carrier
expressions are already restricted to compile-time-known, effect-free values,
so omitting them from a private ABI removes no evaluation. Every other argument
is evaluated once, left to right, before the selected body is entered.

The clone retains the declaration's effects, ownership modes, suspension
contract, result policy, source lines, and logical debug name. Navigation,
references, hover, reflection, and diagnostics continue to identify the written
declaration. A generated body may appear in IR, assembly, timing, and
optimization reports under its tuple-qualified artifact name, but never as a
second source symbol.

`nupp check` neither emits nor requires optional specializations. It may publish
the canonical demands used by a later build, but the result of checking is
independent of optimization level. A required AOT refusal and a module-cap
refusal remain build diagnostics because they depend on the selected backend
and the whole deliverable's demand set.

### Body cap and diagnostics

A source module may emit at most eight logical const specialization keys. The
cap is counted before target tiers multiply physical bodies and is shared by
ordinary Lua and AOT, because both consume one logical plan. Repeated calls with
one key count once.

Required AOT keys take precedence. If they alone exceed the cap, the build
reports the declaration, every tuple at the boundary, and every call site that
demanded those tuples. The ninth call is not blamed alone: the conflict is the
set. If required keys fit, optional Lua keys beyond the remaining budget stay on
the generic route and appear only as declined optimization remarks.

The cap is a compatibility floor: a compiler may raise it but does not lower it
within a supported language line. A project cannot configure it upward, because
an artifact whose validity depends on a local body-count setting would not
travel reproducibly.

### Incremental accounting and code size

`timing.compiledModules` continues to count modules whose checked source was
compiled. It does not count specialization bodies. Build timing adds logical
bodies emitted and reused, with phase time and the slowest tuple-qualified
bodies reported independently.

Native code-size output attributes text bytes to `(declaration, tuple, tier)`.
Ordinary output reports generated Lua bytes per tuple and, where the build emits
bytecode, private prototype bytes. The module total includes dispatch and
generic fallback separately, so a specialization cannot appear cheap by
charging its shared boundary elsewhere.

Two specialization keys whose backend-canonical optimized bodies are
byte-identical may share one physical body and dispatch entry. They remain
separate semantic keys in diagnostics and incremental demand records, and the
code-size report names the deduplication rather than counting the bytes twice.

## Risks and assumptions

- **Incoming demand edges widen invalidation.** Editing a caller can re-emit a
  callee module whose source did not change. Separating emission identity from
  type-check identity keeps that cost visible but does not remove it.
- **Eight bodies may be the wrong ceiling.** The retained workloads exercise a
  few hot tuples, not libraries with many dimensions. The cap protects builds
  while risking an AOT refusal for a legitimate family.
- **Lua cloning can fragment traces.** A clone gets its own hot counters and
  machine traces. The measured fixed-loop case benefits dramatically, but a
  small body can lose to extra prototypes, dispatch, and instruction-cache
  pressure.
- **Cross-module wrappers add a branch.** Same-module direct calls avoid it;
  exported and indirect calls do not. The selected clone has to do enough work
  to amortize that boundary.
- **Source identity and runtime frames can drift.** Private clones must map back
  to one declaration without exposing generated names in ordinary stack traces
  or coverage.
- **Recursive const applications can exhaust the cap deliberately or by
  accident.** The demand chain has to remain finite, deterministic, and
  diagnosable rather than becoming a hidden evaluation budget.
- **Backend opportunity will differ.** One tuple may help Lua tracing, another
  may unlock lanes only on some tiers, and another may change no optimized body.
  A shared key does not imply a shared profitability answer.
- **Binary dependencies cannot grow new native families.** Requiring source for
  downstream AOT specialization constrains how generic annotated libraries are
  packaged.
- **The C compiler still participates.** Verified IR fixes meaning and shape,
  but final instruction selection and additional vectorization remain toolchain
  decisions and can move code size or timing.

## Alternatives considered

**AOT-only const monomorphization.** This was the original scope. Rejected after
the ordinary-Lua spike: substituting and unrolling the same four-round body
improved LuaJIT by roughly twelve times. Making native compilation the only
route through a useful source-shape optimizer would overuse AOT and give two
backends separate application discovery.

**Rely on LuaJIT's trace specialization.** A call with a literal four and a
separate function containing a literal four both retained the nested loop trace.
LuaJIT specializes runtime paths and types; it does not consume Nupp's const
binder or perform this bounded source unrolling.

**Rely on C interprocedural optimization or LTO.** The native entry is exported
through a shared-library FFI boundary, and its literal call exists in generated
Lua rather than in the C translation unit. A visible C wrapper could expose the
constant, but discovering, naming, dispatching, caching, and capping that wrapper
is the specialization design, and leaving it to C would hide the specialized IR
from Nupp's verifier and lane reports.

**Specialize every literal argument.** More opportunities and no indication in
the declaration that one value creates a runtime family. Small caller edits
would clone arbitrary APIs, code growth would be difficult to predict, and
function authors could not see which parameters participate in identity. The
existing const binder is the explicit finite boundary.

**Emit clones in caller modules.** Avoids an incoming demand edge on the
declaring module and duplicates private helpers, constants, layouts, and bodies
across callers. A declaration owns its implementation and its private names, so
its module owns the clone.

**Always dispatch through the public wrapper.** Simple across modules and adds a
tuple branch to the hottest direct calls. A semantically resolved same-module
call can name the private body without changing function-value identity, so it
does.

**Make every specialization mandatory.** Predictable and turns an optimization
budget into a source-validity rule for ordinary Lua. Only `@aot` already carries
that contract; unannotated calls retain optional optimization semantics.

**Emit specializations at `-O0`.** Makes the clearest, fastest development build
clone functions and changes generated Lua shape where `-O0` promises a direct
erasure. Required AOT bodies follow the AOT policy; ordinary Lua clones begin at
`-O1`.

**Configure or auto-tune the cap and winning tuples.** A local setting or timed
build makes identical source produce different artifacts and invalidation. A
deterministic future tuning artifact is a separate decision, not part of body
identity.

## FAQ

### Is this comptime?

No. Comptime executes authored code and must produce its declared result at
every optimization level. Const monomorphization executes nothing: the checker
has already established the tuple, and an optimizing backend may duplicate an
equivalent runtime body or decline it. That is why NEP 3 deferred this design
rather than admitting it as another comptime output.

### Does this make `@aot` unnecessary?

For some scalar LuaJIT loops, yes, and that is a successful outcome rather than
a conflict. Specialization repairs a trace-hostile source shape before Lua
emission. AOT still supplies target-selected lanes, fixed-width native work,
native packaging, and predictable execution without recorder or warm-up
behavior.

### Why does an optional optimization ever report an error?

It does not for ordinary Lua. The error belongs to the explicit `@aot`
contract: an AOT-required build promised that every reached annotated body is
native. Exceeding the body cap makes that promise impossible, so silently using
the generic Lua route would violate NEP 9.
