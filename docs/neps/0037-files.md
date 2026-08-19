---
title: Filesystem access
status: Implemented
created: 2026-08-19
---

## Summary

A filesystem namespace implemented in the feature-gated native library that
already backs paths, URIs, and data operations, exposed through the byte I/O
vocabulary the language already defines, and waiting through the suspension
effect rather than through an API of its own. One API, no asynchronous variant.

[The standard library](../concepts/standard-library.md) documents the surface.

## Goals

- One call that blocks in a command-line program, parks under a scheduler, and
  is a compile error where waiting is forbidden.
- No per-platform declaration set inside the compiler.

## Non-goals

- An asynchronous variant, a policy parameter, or a mode query.
- Binding platform C interfaces by hand.

## Motivation

### Two APIs is the outcome to avoid

A filesystem library that blocks is unusable under a scheduler; one that is
asynchronous is unusable without one; one that takes a policy parameter pushes
the decision into every caller. [NEP 19](0019-suspension.md) exists so a library
can be neither, and this is the first place that pays off.

### Hand-binding platform C would put a per-platform declaration set in the compiler

Declaring the C interface for a program's own libraries is what the C
interoperation features are for. A standard-library namespace binding each
platform's filesystem interfaces by hand is a different thing: a set of
per-platform declarations maintained inside the compiler, wrong on whichever
platform nobody is testing.

## Overview and specification

### Blocking operations submit and poll; metadata does not

Anything that can block is a submit/poll request driven by a readiness source
the suspension runtime already pumps. Metadata operations stay synchronous,
because a request costs more than the call it would replace.

### The native side is one feature, not a binding layer

It is the same feature-gated library already backing neighbouring namespaces, so
platform differences are handled once, in a language with libraries for it.

## Risks and assumptions

- **A native dependency for the standard filesystem** means a build
  configuration that omits the feature has no filesystem namespace.
- **The submit/poll boundary is a judgement call per operation**, and moving one
  across it later changes whether it can suspend — which is visible in a
  forbidding region.
- **Consumers adopt by deleting**, which is the intended outcome and means their
  behaviour now depends on this library matching what they removed.

## Alternatives considered

**Blocking and asynchronous variants.** Rejected: two APIs, and callers split
into two populations that cannot share code.

**A policy parameter.** Rejected: it puts scheduling into signatures that have
nothing to do with it.

**Binding platform C interfaces directly.** Rejected: a per-platform declaration
set inside the compiler, maintained by hand.

**Making metadata operations submit/poll too**, for uniformity. Rejected on
cost: the request would be more expensive than the call.

## FAQ

**What happens with no scheduler installed?** It blocks, which is what a
command-line program wants.

**Can I call it inside a region that forbids waiting?** No — that is a compile
error, which is the point of the effect being checked.
