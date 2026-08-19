---
title: C header interoperation
status: Implemented
created: 2026-08-19
---

## Summary

C imports lower along two explicit paths: a declaration with an externally
addressable symbol binds directly through the FFI, and a header-only callable
goes through a deterministic generated C bridge compiled as part of a declared
native dependency. Both consume one target-aware semantic declaration graph and
expose the same types, ownership modes, effects, and diagnostics. A declaration
is direct, bridged, or skipped for one reported reason — nothing unsupported
becomes an untyped value or a guessed ABI.

[C interoperation](../concepts/c-interop.md) documents the surface.

## Goals

- Reach the parts of a real header the FFI cannot: `static inline` functions and
  explicitly typed expression-like function macros.
- Improve the direct path where the header already says enough — fixed arrays,
  function pointers in every legal position, typedef-named anonymous aggregates,
  exact enum storage, pointer nullability.
- Make it unnecessary to know which path a callable took, while always being
  able to find out.

## Non-goals

- Accepting every program a C compiler accepts. C++ templates, arbitrary
  preprocessor programs, statement macros, anonymous-member promotion, vector
  extensions, extended floating types, inline assembly, and unmodelled calling
  conventions stay visible refusals.
- Taking ownership information from the header.

## Motivation

### Header-only C is a real and unreachable surface

Much of a modern C API is `static inline` and function macros. Those have no
symbol to bind, so an FFI-only approach either cannot reach them or reaches them
through hand-written shims that a human keeps in sync with a header.

### The failure mode to avoid is a compatible-looking lie

The easy way to handle an unknown width, calling convention, aggregate, or
attribute is to substitute something plausible — an untyped value, a generic
pointer, a guessed ABI. That produces a declaration that checks, compiles,
links, and is wrong at run time in a way no diagnostic points at.

Everything in this design is arranged so that does not happen.

## Overview and specification

### Seven invariants, and they are the design

**The FFI remains the direct-call ABI authority.** A direct binding is emitted
only when the physical declaration is accepted by the selected FFI profile.

**The selected C compiler remains the bridge authority.** A bridge callable is
accepted only after that compiler parses the original header and compiles the
generated call for the selected target.

Those two mean Nupp never adjudicates an ABI question. It asks whichever tool
actually owns the answer.

**One semantic graph feeds every consumer** — header typing, generated modules,
manifest bindings, bridge signatures, documentation, editor types, ownership
auditing, and cache keys. Nothing reconstructs declarations independently, which
is what keeps them from disagreeing.

**The header is not an ownership specification.** Constness, nullability, and
physical calling convention may come from C. What a call borrows, takes,
retains, or releases, along with cleanup identity, counted relationships, and
effects, stay explicit Nupp contracts.

This is the most important one. A header does not contain those facts, so any
attempt to derive them is invention, and inventing an ownership contract at an
FFI boundary is worse than having none.

**No optimistic fallback.** An unknown anything is skipped with a stable reason.

**Arguments evaluate once.** A call evaluates every argument once before
crossing the boundary; a generated macro wrapper receives those values as C
parameters. A macro may mention a parameter repeatedly and cannot re-evaluate
the Nupp expression that produced it.

**Target facts come from the target.** Cross-target imports use the target
compiler, sysroot, preprocessor definitions, and layout model, and never inspect
the build host and relabel the answer.

### Refusals are visible and specific

A skipped declaration reports one reason. The list of unsupported shapes is
published rather than discovered.

## Risks and assumptions

- **The bridge path adds a C compiler to the build.** A header-only import is
  no longer a pure-Nupp operation, and reproducibility now depends on a
  toolchain outside the language.
- **Two paths with one surface can hide a performance cliff.** A direct binding
  and a bridged call do not cost the same. Build output says which was used, and
  nothing in the source does.
- **The refusal list is a maintenance surface.** Each entry is a shape someone
  will eventually need, and each addition has to preserve the no-optimistic-
  fallback rule rather than quietly widening what is guessed.
- **"The header is not an ownership specification" needs restating forever.**
  Every C API looks like it is describing ownership in its names and comments,
  and the temptation to infer from them will not go away.

## Alternatives considered

**FFI only, with hand-written shims for header-only callables.** The status quo.
Rejected: the shims are a second copy of the header maintained by hand, and they
are the part that silently goes stale when the header changes.

**Optimistic fallback** — substitute a generic pointer or an untyped value for
anything unmodelled. Rejected as the central failure mode: it produces
declarations that check and link and are wrong at run time.

**Deriving ownership contracts from C annotations.** Rejected: headers do not
contain the facts, and a plausible guess at an FFI boundary is worse than a
required annotation.

**Nupp adjudicating ABI questions itself**, rather than deferring to the FFI and
the C compiler. Rejected: it would mean maintaining a model of every target's
calling conventions and layout rules, and being wrong about them silently.

**Accepting whatever the C compiler accepts.** Rejected as a goal: it commits to
templates, arbitrary preprocessor programs, and inline assembly, none of which
have a Nupp meaning.

**Inspecting the build host for target facts.** Rejected: it is right by
accident when building for the host and wrong silently otherwise.

## FAQ

**Do I need to know whether a call is direct or bridged?** No, and you can
always find out — build output and inspection say which path was used.

**What happens to a declaration Nupp cannot model?** It is skipped, with one
specific reported reason. It never becomes an untyped value.

**Can a function macro double-evaluate my argument?** No. Arguments are
evaluated once and passed as C parameters; the macro may mention a parameter
repeatedly and cannot re-run the expression behind it.

**Where do `borrows` and `takes` come from?** From explicit Nupp contracts. The
header supplies physical facts only.
