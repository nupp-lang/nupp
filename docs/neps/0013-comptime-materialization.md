---
title: Comptime materialization
status: Implemented
created: 2026-08-19
---

## Summary

A comptime block may return a compiler-owned opaque value. An explicitly
declared expected runtime type at the block's position selects a materializer
from a closed, compiler-owned table, and that materializer emits the runtime
value the opaque result represents. It is a second serializer beside the
canonical literal one — not a macro system.

## Goals

- Let comptime produce values richer than the quotable literal set, without
  giving comptime any ability to observe or generate source.
- Keep the selection of what gets emitted a property of a declared type, not of
  inference.

## Non-goals

- User-registered materializers. The provider table is compiler-owned.
- Declaration or module generation. A materializer emits an expression that
  constructs one explicitly typed value.
- Implicit specialization of existing runtime functions.

## Motivation

### Quotable values are a small set for a good reason

[NEP 11](0011-comptime.md) keeps the quotable set to literals and plain tables,
because every entry commits to a source spelling permanently. That is right for
literals, and it means a comptime computation whose useful result is a compiled
matcher, a codec, or any other structured artifact has nowhere to put it.

### The obvious answer is a macro system, and it is the wrong one

Letting comptime emit source solves this and gives up the property the whole
design rests on: that a program's meaning does not depend on text the reader
cannot see. Materialization is the narrowest mechanism that produces a rich
runtime value without granting that.

## Overview and specification

### One extra exit from the same evaluation

Ordinary comptime is:

```text
ordinary Nupp evaluation -> quotable value -> canonical literal source
```

Materialization adds one parallel exit:

```text
ordinary Nupp evaluation -> compiler-owned opaque value
                         -> expected-type materializer
                         -> runtime expression source
```

Comptime still evaluates ordinary Nupp and returns a value. It cannot name a
declaration to add, inspect the source program, construct a syntax tree, paste
text, or choose an emitter.

### Four invariants separate this from a macro system

**The provider table is closed and compiler-owned.** User code, packages,
plugins, and manifests cannot register a materializer. Adding one is a language
change: a prelude surface, a semantic specification, compiler implementation,
diagnostics, and acceptance tests.

**The boundary is an explicitly declared runtime type.** A materializer is never
selected by inference from a distant call, an overload, or an inferred return.
Removing the declaration reports that an opaque result needs an explicit
materializable type; it never silently selects different code.

**The value cannot observe the program.** It is assembled through a sealed,
typed constructor API — no syntax tree, no name or scope enumeration, no
captured runtime binding, no filesystem, no say in where generated code goes.

**Comptime does not choose the emitter.** The declared type does. The value and
its serialization are separate concerns, which is what keeps this a value
feature rather than a code-generation feature.

### The framework was not finished by its first provider

The first materialized value was a statically compiled matcher, and it was
explicitly the proving case rather than the shape of the mechanism. The
completion criterion was a *second* provider, driven by semantic type
information, landing without changing the evaluator, worker protocol,
expected-type rule, cache model, or emission interface.

This is worth keeping as a pattern: a framework with one user is a
specialization with extra steps, and the second user is what demonstrates
otherwise.

### Acceptance gates were frozen before measuring

The prototype work fixed its thresholds before running anything, with the rule
that missing a gate *deleted* the feature rather than deferring it, and that
changing a threshold afterwards required a new benchmark decision and a written
explanation.

That discipline is the transferable part. A gate chosen after seeing the numbers
is not a gate, and "we'll revisit it" is how a feature that failed its own test
ships anyway.

## Risks and assumptions

- **A closed provider table is a permanent bottleneck.** Every new materializer
  is a language change. That is the intended cost and it means legitimate uses
  wait for the compiler rather than solving their own problem — which will be
  experienced as the language being unhelpful.
- **"Explicit declared type" has to stay explicit.** Any future inference that
  reaches through a materialization boundary would silently change which code is
  emitted, which is exactly the property invariant two exists to prevent.
- **Opaque values are invisible to ordinary tooling.** A comptime value that is
  not quotable cannot be printed, diffed, or inspected the way a literal can, so
  debugging a wrong materialization means debugging the provider.
- **Architecture moved under the first proving case.** The general machine the
  original prototype measured was replaced by a native library, and the bytecode
  interpreter it compared against was removed. The mechanism survived the
  workload that motivated it, which is evidence the boundary was drawn in the
  right place — but it also means the original measurements describe an
  architecture that no longer exists.

## Alternatives considered

**A macro system** — let comptime emit source. Rejected: it makes a program's
meaning depend on invisible text, which [NEP 11](0011-comptime.md) excludes from
the language rather than from a feature.

**Growing the quotable set until it covers structured artifacts.** Rejected:
each addition permanently commits to a literal spelling, and the artifacts in
question have no natural literal form. Serializing through a provider keeps the
spelling an implementation detail of the compiler.

**User-registrable materializers**, so a library could serialize its own
compile-time values. Rejected: it makes the provider table open, which makes
what a program compiles to depend on which packages are installed. The
bottleneck is the feature.

**Selecting the materializer by inference** rather than by a declared type.
Rejected: it would make removing an annotation silently change emitted code,
with no diagnostic and no visible cause.

**Letting the comptime value pick its own emitter.** Rejected: that is a
value choosing how it is compiled, which is a macro system with one step of
indirection.

## FAQ

**What happens if I drop the type annotation?** The compiler reports that an
opaque comptime result needs an explicit materializable type. It does not pick
one.

**Can a materializer add a declaration?** No. It emits an expression that
constructs one explicitly typed runtime value.

**Why is a closed table not just a limitation?** Because an open one makes
compilation depend on installed packages, and makes "what does this program
compile to?" unanswerable from the source.

**Is this how derives work?** No. Derives are a separate compiler-owned
mechanism named at the declaration they affect — see
[NEP 14](0014-derives.md).
