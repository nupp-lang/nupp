---
title: Agent evaluation harness
status: Implemented
created: 2026-08-19
---

## Summary

A harness that runs isolated coding agents against Nupp tasks in disposable
worktrees, grades each run mechanically against the compiler's own structured
output, and records success, cost, and process-quality metrics per run. It is
seeded from data the compiler already produces for other reasons rather than
from a hand-authored task bank, and it is used for before/after and
configuration experiments rather than to publish a score.

## Goals

- Measure whether a change to diagnostics, documentation, or tooling actually
  helps an agent working in the language.
- Grade mechanically, from structured output, rather than by judgement.

## Non-goals

- A published score.
- A hand-authored task bank.

## Motivation

### The compiler already produces the corpus

The diagnostic catalogue contains verified wrong/right program pairs, compiled
as part of the test suite. Structured check output contains cache accounting.
Both exist for other reasons and are already maintained, which makes them a
better seed than tasks written for the harness — those would be maintained only
as well as the harness is used.

### A single score would be the wrong output

An absolute number invites comparison across configurations that are not
comparable, and encourages tuning toward the benchmark. Before/after on one
change, with cost and process metrics beside the result, answers the question
that was actually asked.

## Overview and specification

### Syntax

A harness invocation and a task definition; nothing in the language.

```sh
python3 evals/tier1.py --agent claude --runs 20
python3 evals/tier1.py --compare baseline.json candidate.json
```

### Usage

Tasks are seeded from data the compiler already produces:

```text
 Source                       Task shape
 ──────────────────────────   ────────────────────────────────────────
 explain.nupp wrong/right     "this program reports NUPP2603; fix it"
 check --json cache counts    "make this project check clean"
```

A run is graded from structured compiler output rather than by judgement:

```json
{"task": "NUPP2603", "ok": true, "turns": 4, "tokens": 18420,
 "checkedModules": 2, "diagnosticsRemaining": 0}
```

### Lowering

Each run happens in a disposable worktree, so runs cannot contaminate each other
or the tree:

```text
 harness
 ├── worktree run-001  ->  agent  ->  nupp check --json  ->  grade
 ├── worktree run-002  ->  agent  ->  nupp check --json  ->  grade
 └── ...                                    (worktrees removed after grading)
```

The results are before/after comparisons for one change, with cost and process
metrics beside the outcome. There is no aggregate score, because an absolute
number invites comparison across configurations that are not comparable.

Disposable worktrees per run, mechanical grading against structured compiler
output, and per-run records of success, cost, and process quality.

## Risks and assumptions

- **Mechanical grading measures what the compiler can see.** A run that
  produces passing code by a bad route grades the same as a good one, unless a
  process metric catches it.
- **The seeded corpus is shaped by what the diagnostics happen to cover**, which
  is not the same as what is hard.
- **Results are per configuration and go stale.** A measurement of one agent
  against one tree on one date is not a property of the language.

## Alternatives considered

**A hand-authored task bank.** Rejected as the seed: it would be maintained only
as well as the harness is used, where the diagnostic corpus is maintained
because the test suite compiles it.

**Human grading.** Rejected: not repeatable, and not affordable per
configuration.

**Publishing a single score.** Rejected: it invites incomparable comparisons and
tuning toward the benchmark.
