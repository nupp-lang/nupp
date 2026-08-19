---
title: AOT block kernels and scoped SIMD
status: Implemented
created: 2026-08-19
---

## Summary

Ahead-of-time compilation generalizes from map-shaped span loops to block
kernels, and exposes a small non-escaping SIMD vocabulary *only* inside an
annotated function. There are no boxed vector values, no ordinary-Lua fallback
representation, and no second spelling for scalar map loops — an earlier
portable-vector design was built, measured, and removed in favour of lowering
ordinary scalar source through private vector and mask IR.

[Ahead-of-time compilation](../guides/ahead-of-time.md) documents the surface.

## Goals

- Cover algorithms whose register is a data structure and whose meaning depends
  on cross-lane masks, which scalar lowering cannot express.
- Keep vectors out of the ordinary language entirely.
- Prove the capability against a real workload without letting that workload
  become part of the compiler.

## Non-goals

- Boxed vector values or ordinary-Lua fallback values.
- Fixed architecture widths in source.
- Inferred outlining.
- A second spelling for scalar map loops.
- A general SIMD library.

## Motivation

### Scalar source covers most of it

Ordinary scalar Nupp under an annotation, asserting that one top-level numeric
map loop has independent iterations, lowers with a target-chosen width. That
covers the bulk of what vectorization is wanted for, in the language people
already write.

### It does not cover algorithms whose register is a data structure

Structural indexing, block validation, and anything whose meaning depends on
cross-lane masks cannot be expressed as an independent-iteration map. That was
deliberately deferred, and it is the only case this reopens.

## Overview and specification

### Staged deliberately, in reviewable pieces

Generalize to block kernels; expose a small non-escaping vocabulary inside
annotated functions; use it to build a structural tape and validate encoding by
blocks; parse that tape into caller-owned native arenas before materializing
managed values; and add further operations only when profiles of that parser
require them.

**Do not land a broad SIMD library first.** The vocabulary grows from a
workload's measured needs rather than from what an instruction set offers.

### The acceptance workload stays out of the compiler

The proving workload lives entirely in a benchmark directory, and **deleting
that directory must remove the experiment without removing or invalidating any
compiler feature.**

That is the test that separates a capability from a specialization. If deleting
the workload breaks the feature, the feature was the workload.

### One build-policy exception, stated rather than hidden

A function using explicit SIMD is not executable with ahead-of-time compilation
disabled, and that build reports a dedicated diagnostic. Every other annotated
function keeps its dormant ordinary-body behaviour.

This breaks the otherwise-uniform rule that the annotation is dormant when
disabled. It is called out explicitly rather than smoothed over, because a
silent exception to a uniform rule is worse than a stated one.

## Risks and assumptions

- **The exception erodes the dormancy invariant.** One construct now behaves
  differently with the feature disabled, and every future addition will cite it.
- **A vocabulary grown from one workload will fit that workload.** Profiles of a
  single parser are a narrow basis for a permanent instruction surface.
- **Non-escaping is doing a lot of work.** The moment a vector value can be
  stored or returned, representation and escape rules come back, which is
  exactly what the removed design foundered on.
- **Staged landing depends on the stages actually being reviewed separately.**
  The value of the decomposition is lost if the stages land together.

## Alternatives considered

**Portable boxed vectors**, with an ordinary-Lua fallback representation — the
model Java's vector API offers. **Built, measured, and removed.** It did not
clear its gate: the ordinary fallback needs boxing, escape rules, and
predictable inferred outlining before it can honestly promise that model, and
none of those were close.

**Ahead-of-time-only explicit vector values**, which avoid boxing. Also removed:
they still create a second spelling for the same map-oriented work, so a
programmer choosing between scalar source and explicit vectors is choosing
between two ways to say the same thing with different performance.

The spike that settled it showed scalar source lowering through private vector
and mask IR while preserving ordinary semantics — which is strictly better than
either, because there is only one spelling and the ordinary one is it.

**Landing a broad SIMD library first**, then finding uses. Rejected: the
vocabulary would be shaped by an instruction set rather than by a workload, and
every operation in it is a permanent surface.

**Combining the stages into one change.** Rejected: each stage is independently
reviewable and the combined form is not.

**Letting the acceptance workload into the compiler or standard library.**
Rejected: the deletion test is what proves the capabilities are general.

**Fixed architecture widths in source.** Rejected: it makes source
target-specific for a benefit the target-chosen width already provides.

## FAQ

**Can I use vectors in ordinary Nupp?** No. The vocabulary exists only inside an
annotated function and the values do not escape it.

**Why did the portable vector design get removed?** It could not honestly
promise its ordinary fallback, and it duplicated scalar map lowering. Its
measurements are the evidence for the current design.

**What happens if I build with ahead-of-time compilation off?** A function using
explicit SIMD is not executable and the build says so. Every other annotated
function emits its ordinary body.

**How does the vocabulary grow?** From profiles of a real workload requiring an
operation, not from what an instruction set makes available.
