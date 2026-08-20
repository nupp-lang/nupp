---
title: Checked ahead-of-time functions
status: Implemented
created: 2026-08-19
---

## Summary

An annotation states that a function must compile as one checked ahead-of-time
unit. The body is ordinary Nupp — same parser, name resolution, type system,
operators, diagnostics, and source positions — and the annotation adds a
compilation and effect constraint after ordinary checking rather than
reinterpreting anything. Four ordinary language capabilities landed first, each
useful with the feature disabled. Where a target has feature tiers, one library
carries one translation unit per tier.

[Ahead-of-time compilation](../guides/ahead-of-time.md) documents the surface.

## Goals

- Give a function a checked guarantee that it compiles ahead of time, or a build
  error saying why not.
- Introduce no second expression language.
- Keep the safety boundary in Nupp's own IR rather than in a backend.

## Non-goals

- Operating-system code, GPUs, promised vectorization, or permitted unsafe
  operations.
- Silent fallback. A backend regression is a build error and a compiler defect,
  never permission to quietly compile one function the ordinary way.
- Sharing eligibility vocabulary with trace checking. They are mutually
  exclusive execution contracts.

## Motivation

### The failure to avoid is a second language

The obvious way to build this is a restricted sublanguage with its own
semantics — the shape most "compile this part natively" features take. That
gives two languages to learn, two sets of diagnostics, and a boundary at which
the meaning of ordinary-looking code changes.

Stating it as a *contract over ordinary Nupp* means the body is the same program
either way. Removing the annotation may change performance and artifacts, not
the source-level result. Adding it may reject constructs the backend cannot
represent, and may not make an otherwise invalid operation valid.

That is the same shape as trace checking: an annotation makes an execution
property a checked requirement without inventing expression semantics.

### The foundations had to be worth landing on their own

Four capabilities landed first — canonical C identities and header export for
reified structs, explicit fixed-width scalar arithmetic, richer checked span
views, and transported allocation and raising guarantees — each required to be
useful and testable with ahead-of-time compilation disabled.

Eligibility is not their public meaning and was not an acceptance criterion. A
capability justified only by an unlanded consumer is a capability designed
against a guess.

## Overview and specification

### Syntax

```nupp
@aot
local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end

    for i = 1, output.count do
        output[i] = input[i] * scale
    end
end
```

The body is ordinary Nupp: same parser, name resolution, type system,
operators, diagnostics, and source positions.

### Usage

The annotation is a contract, not a request. Build policy is selected once:

```sh
nupp build --aot=off       # emit every body as ordinary Nupp
nupp build --aot=require   # lower every @aot body, or fail saying why
nupp build --aot=emit-c    # verify the IR and write private C for a vendor build
```

Removing the annotation may change performance and artifacts, never the
source-level result.

### Lowering

The body lowers to verified IR and then to private generated C, with a checked
Nupp wrapper calling it through the FFI:

```c
/* generated, private */
void nupp__scaleAdd(float *output, const float *input,
                    uint64_t count, float scale) {
    for (uint64_t i = 0; i < count; i++) {
        output[i] = input[i] * scale;
    }
}
```

```lua
local __lib = ffi.load("@lib/libapp_aot.so")
local function scaleAdd(output, input, scale)
   if output.count ~= input.count then error("length mismatch", 2) end
   __lib.nupp__scaleAdd(output.__base + output.__offset,
                        input.__base + input.__offset, output.count, scale)
end
```

With the backend off, the annotation is dormant and the same ordinary body is
emitted:

```lua
local function scaleAdd(output, input, scale)
   if output.count ~= input.count then error("length mismatch", 2) end
   for i = 1, output.count do output[i] = input[i] * scale end
end
```

Where a target has feature tiers, one library carries one translation unit per
tier, and the symbol suffix distinguishes them:

```c
void nupp__scaleAdd_avx2(float *output, const float *input, ...)
```

A shared library is mapped rather than run, so loading a tier the machine cannot
execute is not a hazard — what would fault is a call, and selection is what
prevents it.

### Eligibility is a versioned compatibility promise

Within a supported language line, a source function accepted for a target
remains accepted. The admitted subset may widen and does not silently narrow.

Without that promise the annotation would be a request rather than a contract,
and a compiler upgrade could quietly turn a compiled function into an
interpreted one.

### Build policy is selected before eligibility is checked

Off checks and emits every body as ordinary Nupp, and does not run the subset
checker, find a C compiler, generate C, or package native code. Required lowers
every annotated body and fails when the subset, backend, compiler, SDK, or
artifact validation is unavailable. An emit-only mode verifies the IR and emits
private C without building it, so a platform build can hand that C to its vendor
compiler.

### The IR is the boundary; C is a backend

Generated private C compiled by a pinned toolchain is the initial backend. The
IR remains the safety boundary and the stable architecture. Direct machine-code
emission is deferred unless measured toolchain, latency, packaging, or
specialization requirements show generated C cannot meet the release gates.

### No transitional implementations

One implementation of each capability, with design questions resolved from
existing behaviour and permanent semantic tests *before* implementation — no
characterization path committed as a fallback, alternate API, or experimental
runtime.

Concretely: no temporary named runtime representation for structs to remove
later; no parallel fixed-width modules beside the existing namespace; no
per-call boxes, per-call scratch allocation, or one-call-per-operation numeric
fallbacks; no public strided span unless ordinary uses justify its final API
first; and nothing implemented in a benchmark spike and then reimplemented in
the compiler.

This is the rule that keeps a staged feature from accumulating two of
everything, where the temporary half outlives the reason for it.

### Feature tiers

A tier is already a whole-translation-unit flag, so compiling each tier as its
own translation unit needs no new mechanism — the flag path, the artifact key,
and the link step all work as written, once per tier instead of once.

One library rather than one per tier, because a library is a thing that travels:
it is named, resolved against the module that loads it, and copied beside the
artifact so a single file carries its compiled code. Two libraries is two of all
of that, in every place, to avoid a suffix on a symbol name.

**Loading code for an unavailable instruction set is not a hazard.** A shared
library is mapped, not run; what would fault is a call, and the point of
selection is that the call never happens.

## Risks and assumptions

- **A pinned C toolchain is now a build dependency.** Reproducibility depends on
  a compiler outside the language, and the emit-only mode exists partly because
  that will not always be acceptable.
- **The compatibility promise is hard to keep.** "May widen, does not narrow"
  constrains every future change to the admitted subset, including changes made
  for correctness.
- **No fallback means a backend defect breaks builds.** That is deliberate — a
  silent fallback would make the contract meaningless — and it means a compiler
  defect is felt as a hard failure rather than a slowdown.
- **The ordinary-semantics invariant is easy to erode.** Every future extension
  will be tempted to admit a construct by giving it a slightly different meaning
  inside an annotated body. One exception ends the property.

## Alternatives considered

**A restricted sublanguage with its own semantics.** Rejected: two languages,
two diagnostic surfaces, and a boundary where ordinary-looking code changes
meaning.

**Silent per-function fallback** when a target cannot compile a body. Rejected:
the annotation is a contract, and a contract that degrades quietly is a comment.

**Direct machine-code emission** rather than generated C. Deferred rather than
rejected — the IR is the architecture, and the backend can change if measured
toolchain, latency, packaging, or specialization requirements demand it.

**Landing the foundations as part of the feature**, justified by it. Rejected:
each had to be useful with the feature disabled, or it would have been designed
against an unlanded consumer.

**Transitional implementations** — a temporary representation, a parallel
module, a fallback path — to unblock staging. Rejected explicitly, because the
temporary half reliably outlives its reason.

**One library per feature tier.** Rejected: a library is a thing that travels,
and per-tier libraries multiply naming, resolution, and packaging everywhere, to
avoid a symbol suffix.

**Guarding tier libraries against being loaded on unsupported machines.**
Rejected as unnecessary: mapping is not executing.
