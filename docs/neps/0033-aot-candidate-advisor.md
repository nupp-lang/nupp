---
title: AOT candidate advisor
status: Draft
created: 2026-08-19
---

## Summary

An advisory analysis that finds unannotated functions the ahead-of-time backend
could compile, and explains why they are worth benchmarking. It answers three
separate questions and never combines them into a promise it cannot make. It
does not add annotations, compile anything, change generated code, or affect
whether source checks.

Nothing below exists.

## Goals

- Surface candidates a programmer would not find by reading.
- Keep each claim exactly as strong as its evidence.

## Non-goals

- Predicting a speedup.
- Adding the annotation automatically.
- Participating in whether source checks.

## Motivation

Eligibility for ahead-of-time compilation is a property of a function body that
a programmer cannot determine by inspection — it depends on the admitted subset,
the selected target, and the backend. So the functions most worth annotating are
exactly the ones hardest to identify, and the practical result is that the
feature gets used on whatever someone happened to think of.

## Overview and specification

### Syntax

None. The advisor adds nothing to a source file — that is the point of it being
advisory.

```sh
nupp aot --suggest
nupp lsp aot-candidate --json src/sim.nupp
```

### Usage

Each finding presents the three answers separately:

```text
src/sim.nupp:42  integrate
  eligible      lowers to verified IR for aarch64-apple-darwin
  opportunity   bulk loop over a float span, 4 fixed-width operations
  observed      11.4% of samples, 0 trace aborts   (profile: bench/sim.speedscope)
```

An editor shows only the strongest static findings, and the text is deliberately
modest — it says a native comparison is worth measuring, not that one would win.

### Lowering

Nothing. The advisor does not add the annotation, compile a native library,
change generated Lua, or participate in whether source checks:

```lua
-- before and after running the advisor: identical
local function integrate(rows, delta) ... end
```

Its inputs are facts the compiler already has. Eligibility comes from the same
subset checker the backend uses, static opportunity from a deterministic cost
model over the admitted body, and observed importance from a supplied profile —
so the analysis is reproducible and adding a profile changes only the third
line.

### Three questions

**Eligibility** — can this body lower to verified IR for the selected target?
This is a proof.

**Static opportunity** — does the admitted body have a bulk-loop, fixed-width,
lane, span, or runtime property making a native comparison worthwhile? This is a
deterministic cost-model judgement.

**Observed importance** — did a supplied profile see this body consuming time,
running interpreted, or aborting traces? This is evidence from one workload.

Only the first is a proof, and none of them predicts a speedup. Presenting them
separately is the design: a combined score would imply a claim no part of the
analysis supports.

### The annotation stays a durable source contract

A programmer adds it after inspection or measurement. A required build must
compile it, and a regression may not quietly fall back. The advisor changes none
of that.

## Risks and assumptions

- **Advice becomes an obligation.** An editor hint saying a function is eligible
  will be read as a recommendation, and a codebase can acquire annotations
  nobody measured.
- **A cost model with no hotness input is guessing about importance.** The same
  gap that deferred perfect-hash dispatch in
  [NEP 4](0004-switch-expressions.md) applies here.
- **Three separate answers may be collapsed by whoever presents them.** The
  discipline lives in the presentation, which is the part most likely to be
  simplified.

## Alternatives considered

**A single score.** Rejected: it implies a prediction none of the inputs
supports.

**Automatically applying the annotation** to eligible functions. Rejected: the
annotation is a contract that makes a build fail, and nothing should add one
without a person deciding.

**Making eligibility part of checking**, so ineligible functions report.
Rejected: eligibility is a backend property, and most functions are ineligible
and should be.
