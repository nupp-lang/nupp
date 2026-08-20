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

### Syntax

A small non-escaping vocabulary, available only inside an annotated function:

```nupp
@aot
local function classify(borrows bytes: span.Span<uint8>): uint32
    const block = simd.load(bytes, 1)
    const quotes = simd.eq(block, simd.splat(0x22))

    return simd.mask(quotes)
end
```

Scalar source needs none of it — an independent-iteration map loop lowers with a
target-chosen width already:

```nupp
@aot(simd = true)
local function scale(exclusive out: span.WriteSpan<float>, borrows src: span.Span<float>)
    for i = 1, out.count do
        out[i] = src[i] * 2
    end
end
```

### Usage

The vocabulary is for algorithms whose register is a data structure and whose
meaning depends on cross-lane masks — structural indexing, block validation —
which an independent-iteration map cannot express.

### Lowering

Scalar source lowers through private vector and mask IR, so the loop above
becomes a vectorized body plus an exact scalar tail:

```c
for (; i + 8 <= count; i += 8) {
    __m256 v = _mm256_loadu_ps(src + i);
    _mm256_storeu_ps(out + i, _mm256_mul_ps(v, _mm256_set1_ps(2.0f)));
}
for (; i < count; i++) { out[i] = src[i] * 2.0f; }
```

Explicit vocabulary maps to target intrinsics directly, and the values never
escape the function:

```c
__m256i block = _mm256_loadu_si256((const __m256i *)(bytes + 0));
__m256i quotes = _mm256_cmpeq_epi8(block, _mm256_set1_epi8(0x22));
uint32_t mask = (uint32_t)_mm256_movemask_epi8(quotes);
```

There are no boxed vector values and no ordinary-Lua fallback representation, so
a function using the explicit vocabulary is **not executable** with the backend
disabled — that build reports a dedicated diagnostic rather than emitting an
ordinary body. Every other annotated function keeps its dormant behaviour.

### Reviewable stages

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

### One build-policy exception

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
