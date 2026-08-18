# Agent evaluation harness

Status: delivery steps 1 and 4 implemented as `evals/tier1.py` and
`evals/tier2.py`, one task per run rather than a whole corpus; steps 2, 3 and 5
proposed. Four divergences worth knowing. The tier-1 workspace needs a manifest
with a real build target, not the bare `return {include = {"."}}` that
`tests/explaintest.lua` uses -- a whole-project `nupp check` against that one
reported no diagnostics, so an agent doing the obvious thing was told nothing
was wrong; `nupp check --json` now answers `ok` so that case is distinguishable
at all, which is a compiler change this harness caused rather than observed,
against the plan's own non-goal of changing what the compiler reports. Part of
step 2 arrived with step 1: streaming the agent's events costs no more than
taking its final result, so tool counts and a full auditable transcript are
recorded from the first run. Tier 2 turned out to want a sharper rule than the
plan's "revert it and fix what broke" -- export the tree at the commit's
parent, carry only its tests forward, and fail any run that edits one, so the
suite is the whole specification and weakening it cannot score. The workspace
also has to have no `.git` in it: the first shape of this reverted files inside
a worktree at the commit, which left the answer in `HEAD`, and the first agent
to run it scored a pass with `git restore` without writing any code. And step 4
preceded step 3, because tier 2 needed no metrics work that step 1 had not
already done, where the before/after experiment needs a second checkout built
at an older commit.

## Decision

Build a harness that runs isolated coding agents against Nupp tasks in
disposable worktrees, grades each run mechanically against the compiler's own
structured output, and records success, cost and process-quality metrics per
run. Seed it first from data the compiler already produces for other reasons
— `explain.nupp`'s verified wrong/right corpus and `check --json`'s cache
accounting — rather than authoring a task bank from scratch. Use the results
to run before/after and configuration experiments, not to publish a single
score.

## Why

Nupp's tooling is designed for agents (`docs/diagnostics.md`, the LSP CLI
group, `nupp reference --format skill`), and every claim that design makes —
that a diagnostic is enough to self-repair from, that a slow check can be
read instead of waited out, that a worktree is cheap and disposable — is
presently untested against an actual isolated agent. It is tested against
whichever agent happens to be doing the current task, which finds gaps
opportunistically and unevenly. `plans/058-aot-candidate-advisor.md` makes
the same point about `@aot`: static analysis existed and nobody had wired it
to answer the question users actually had. The tooling here has the reverse
problem — the question is answerable, but nothing regularly asks it.

The prompting evidence for this already exists in-repo. Backfilling
`explain.nupp`'s worked examples and exposing `check --json`'s `timing`
object (see the CHANGELOG's "Unreleased" section) were both found by one
agent doing one real task and noticing the tooling didn't hold up, not by
anything that runs again. A harness turns that from a one-off audit into a
regression suite: the next AGENTS.md wording change, doc edit or CLI flag
gets to answer "did this help" with a number instead of a guess.

## Task suite

Three tiers, ordered by how much they cost to run and how much they prove.

### Tier 1 — diagnostic micro-repair

Source: `explain.nupp`'s `ENTRIES` table, which — after
`plans/065`'s prerequisite work — holds a `wrong` example for essentially
every code the compiler can emit, each already verified by
`tests/explaintest.lua` to compile to exactly the code it is filed under.

Task: an isolated agent receives one `wrong` source file and nothing else —
not the code, not `rule`, not `right` — and is asked to make it check clean.
Grading is mechanical: run `nupp check --json` (`--strict` when the entry's
`strict` field says so) and assert the filed-under code is gone from
`diagnostics[]` and no new fatal diagnostic was introduced. No LLM judge, no
diffing against `right` — a different correct fix is still a pass.

This tier costs nothing to author (the corpus exists), grades in the time one
`check --json` call takes, and covers the full diagnostic surface. Its
weakness is scope: a single-file, single-error task never exercises
`related`, multi-file project structure, or the LSP group. It measures
whether the diagnostic *alone* is enough, which is exactly what
`docs/diagnostics.md`'s design claims.

### Tier 2 — replayed history

Source: a real merged commit, reverted, with its test or check outcome as the
target. Concretely: pick a commit whose diff is small and whose net effect is
checkable (`nupp test --json` on the suite it touched, or `nupp check --json`
going clean, or `nupp fixpoint` passing again), revert it in an isolated
worktree seeded at the parent commit, and ask the agent to fix whatever the
revert broke — without telling it what the original commit did.

Grading: does the agent's diff make the same graders pass the original
commit made pass. The diff need not match; the check does.

This tier is self-refreshing — every future commit that lands with a clean,
narrow test story is a candidate case, so the suite grows with the project
without separate authoring. It costs more per run (a real build, a real test
subset, sometimes several edit/check cycles) and needs occasional curation to
retire cases that stop being representative (a case whose fix depended on
compiler internals since refactored away answers a different question than
it used to).

### Tier 3 — open tasks

Source: an item from `plans/019-todo.md`, an open plan's `Delivery` step, or
a task shaped like this plan's own worked example (review a subsystem,
propose and land a fix). No single mechanical grader; scoring is the same
verification loop AGENTS.md already prescribes for a human-facing change —
`nupp test`, `fixpoint` where compiler sources changed, format check, and a
review pass (human or a second agent) for whether the change is the right
shape, not just green.

This tier is what actually validates "can an agent do a real Nupp task." It
is also the expensive one: real wall-clock, real token cost, and judgment
calls a script cannot make. Run it least often, and treat its outcomes as
qualitative signal that tier 1/2 regressions should be checked against, not
as a number to average.

## Metrics

Outcome alone hides where cost goes. Record per run, not just per suite:

```
 Metric                         Source                          Why
 ------------------------------ ------------------------------- --------------------------------
 pass/fail                      tier's mechanical grader         the baseline
 tool calls / turns             harness transcript                efficiency independent of pass
 tokens spent                   harness transcript                the actual cost lever
 wall-clock                     harness transcript                includes compiler rebuild time
 check/build invocation count   harness transcript                cache-thrashing signal
 timing.compiledModules trend   check --json (this session's      did the agent understand its
                                 addition)                         own cache state, or re-run
                                                                    blind
 hygiene compliance             git status in the worktree at      worktree removed, fmt clean,
                                 run end                           CHANGELOG entry present
```

`timing.compiledModules` and hygiene compliance are specifically the two
metrics this session's own changes made measurable that were not measurable
before: whether an agent used the cache-accounting data `check --json` now
exposes, and whether it followed the worktree-cleanup step
`scripts/worktree`'s new reminder names. Neither existed as an observable
signal before those changes landed, which is itself worth treating as tier 1
data once there is a baseline to compare against.

## Harness architecture

- **Isolation**: one disposable worktree per trial, seeded through
  `scripts/worktree` exactly as a real task would be, so the seeded caches
  and native target reuse this plan's metrics are meant to observe are
  actually present rather than assumed.
- **Runner**: fan out trials in parallel, one agent per worktree, task prompt
  in and transcript + resulting worktree out. `pipeline()`/`parallel()` over
  a task list is a direct fit for this — each trial is independent and
  bounded, which is exactly what a workflow's fan-out is for.
- **Grader**: tier-specific, always a `nupp` command or a diff against a
  known-good graded state, never a prose judgment for tier 1/2. Tier 3 keeps
  a human or a second, differently-prompted agent in the loop, per
  `plans/058`'s own distinction between a deterministic answer and an
  advisory one.
- **Aggregator**: a scoreboard keyed by (tier, task, condition) — condition
  being whatever the experiment varies — reporting success rate and the
  metrics table above as distributions, not single numbers, since trial
  variance is real and a suite run once is a sample, not a measurement.

## Experiments

Ordered by cost to run, cheapest first:

1. **Before/after this session's changes**, on tier 1 only: run the current
   `explain.nupp` corpus task through an agent that only sees the pre-backfill
   compiler (checked out before `b6d89f58`) versus the current one. Answers
   directly whether backfilling the examples changed measured behavior, which
   is the one claim in this plan's own "Why" section that has not yet been
   checked against data.
2. **Model tier x task tier**: Haiku/Sonnet/Opus (or whichever tiers are
   current) against tier 1 and tier 2, to find where cost drops without
   success dropping. Routine diagnostic repair is the likely candidate for a
   cheaper default; open tasks are the likely floor.
3. **AGENTS.md wording A/B**: hold the compiler fixed, vary one guidance
   sentence (the `timing` mention added this session is a ready-made first
   case), and check whether tool-call efficiency or hygiene compliance moves.
4. **Warm vs. cold worktree cache**: run the same tier-2 task with
   `scripts/worktree`'s seeding intact versus stripped, to quantify what the
   seeding is actually worth in wall-clock and token cost rather than trusting
   the docstring's claim about it.
5. **Reference skill loaded vs. not**: `nupp reference language --format
   skill` costs real context; measure whether tier 1/2 success or efficiency
   actually depends on having it loaded, per task category, since AGENTS.md
   currently recommends reading it unconditionally.

## Non-goals

This plan does not add:

- a public leaderboard or a single blended score;
- a change to any diagnostic, lint, or checker behavior — the harness
  observes the compiler, it does not gate it;
- coverage of every plan or TODO item as a tier-3 case; curate a small,
  representative set instead of exhaustively enumerating one;
- an LLM judge for tier 1 or tier 2, where a mechanical grader exists;
- retry-until-pass scoring — a trial's first outcome is the data point;
- a claim that any one experiment's result generalizes across model
  providers or versions without rerunning it there.

## Delivery

1. Tier 1 only: a runner that, for each `explain.nupp` entry with a `wrong`
   example, spawns one isolated agent given just the source and the compiler
   diagnostic text (not the code, not `rule`), and grades on `check --json`.
   No experiment conditions yet — this step's only goal is a baseline number
   and a working grade-and-record loop.
2. Metrics capture: wire tool-call count, token cost, wall-clock, and
   `timing.compiledModules` into the runner's output per trial, and land the
   aggregator that turns many trials into a scoreboard.
3. Experiment 1 from the list above (before/after this session's changes),
   since it needs no new infrastructure beyond re-running step 1 against an
   older checkout, and it answers whether the premise of this plan's own
   motivating example holds up.
4. Tier 2: commit-replay task generation and the worktree-revert setup, plus
   curation criteria for retiring stale cases.
5. Tier 3 and the remaining experiments, once tier 1/2 data says where the
   interesting variance actually is rather than guessing in advance.
