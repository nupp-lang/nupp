# Agent evaluations

Measurements of how well an isolated agent completes a Nupp task, and what it
costs to do it. The design, and the tier above these two, are in
[plans/065-agent-evaluation-harness.md](../plans/065-agent-evaluation-harness.md);
this directory holds what is built, which is tiers 1 and 2.

These run real agents against the real compiler and **cost real money**.
No agent evaluation runs as part of `nupp test`, and none gates a build. The
ordinary test suite only exercises the harness itself without starting an
agent.

```
 Tier  Task                          Grader                     Per run
 ----  ----------------------------  -------------------------  -----------
 1     repair one diagnostic         the code is gone           seconds, ~$0.09
 2     make a reverted commit's      its suites pass, and the   minutes, more
       own tests pass again          tests are untouched
```

`evals/lib/harness.nupp` holds what both tiers share: starting an agent,
keeping its transcript, and counting what it did. A tier module owns only its
task and its grader.

## Tier 1: diagnostic micro-repair

One task is one diagnostic code. The program that reports it comes from the
compiler's own catalogue — the same `wrong` example `nupp explain` prints and
`tests/explaintest.lua` compiles and asserts really does report the code it is
filed under. The task bank is therefore data the compiler already maintains
for other reasons, not fixtures this directory has to keep true.

```sh
./bin/nupp run evals/tier1.nupp NUPP2105 --model sonnet
```

The agent gets a project with the broken file, a `nupp` on its PATH, and a
prompt that names no code and quotes no rule. It is expected to run `nupp
check` and repair what that reports. Grading re-runs the same command: the
code has to be gone and no error may be left behind. The catalogue's own
corrected program is never compared against, so a different correct repair
passes — the diagnostic decides, not the style.

Each run writes `results/<code>-run.json` (the verdict and the metrics) and
`results/<code>-transcript.jsonl` (every event, so what the agent did is
auditable after the fact rather than summarized away). Exit status is 0 for a
pass, 1 for a failure, so a shell loop over several codes scores itself.

### What a run records

```
 Field                     Means
 ------------------------  --------------------------------------------------
 grade.passed              the code is gone and no error remains
 grade.suspiciousShrink    the file lost more than half its length; look
 agent.turns               conversation turns
 agent.toolCalls           calls per tool, and the total
 agent.nuppInvocations     how many times it asked the compiler anything
 agent.costUsd             what the run cost
 agent.wallClockSeconds    how long it took
 finalSource               what the file ended up as
```

`nuppInvocations` is the one to watch. An agent that checks once, reads the
diagnostic and repairs is doing the thing the tooling exists for; one that
checks eight times is paying for something the first answer should have told
it.

### Running the whole corpus

One task is a sample. `batch.nupp` runs many and reports the distributions:

```sh
./bin/nupp run evals/batch.nupp --model sonnet --jobs 4
./bin/nupp run evals/batch.nupp --limit 4 --jobs 2 --model haiku
./bin/nupp run evals/batch.nupp --codes NUPP2105 NUPP2004
```

It writes every per-task record as usual, plus a `<label>-scoreboard.json`
holding the rates, the spreads, and the failures worth reading. `--label` is
how two conditions are told apart when the point is to compare them.

`--out` defaults inside the checkout, and `results/` is ignored rather than
committed, so removing a worktree takes a sweep's records with it. Name a
durable path for a sweep worth keeping; one has already been lost this way.

### What a sweep costs, and how to spend less

Almost all of it is input. On the first sweep, re-sent context was 87% of the
cost and generated output was 12%, for tasks whose prompt is six lines and
whose file is four — so the levers are the price of a token and the number of
turns, not the length of the answer.

The one that works is the model, though by less than a first look suggested.
On the five most expensive tasks Haiku matched Sonnet 5/5 for $0.31 against
$3.46, an 11x saving. Across the whole corpus it is smaller:

```
 model    pass      total    median    max      wall
 ───────  ────────  ───────  ────────  ───────  ──────
 sonnet   125/125   $26.46   $0.1611   $0.8166  30 min
 haiku    125/126   $10.40   $0.0311   $1.2627  31 min
```

5.2x cheaper at the median but only 2.5x over the sweep, because Haiku's cost
concentrates in runs that thrash: one task spent 172 tool calls and $1.26 —
an eighth of the whole sweep — and failed anyway. Sweep on Haiku, cap the
runaways, and keep Sonnet for confirming a result that matters.

One of Haiku's passes was degenerate: the deprecated-API task was "repaired"
by deleting the deprecated call and returning a constant. `suspiciousShrink`
flagged it, so the honest rate is 124/126. This is what that guard is for.

`--timeout` (default 300s) kills a run that will not converge and grades it a
failure. It is the only lever that touches the tail rather than the median,
and the tail is where a cheap model's money goes.

`--lean` sends only the tools a repair needs. It measured as no saving at all
on a cheap task, which says the tool schemas are not what fills the context,
and it is kept for the harder tasks and for honesty about what was tried.
A run using it is only comparable with another using it.

`--bare` would trim more and is deliberately unused: it authenticates strictly
from `ANTHROPIC_API_KEY`, so under an OAuth login every run returns "Not logged
in" having done nothing, and grades as a failure that says nothing about the
agent.

Results are sliced by whether the compiler offered a fix for the diagnostic.
A code whose diagnostic carries an edit is a different task from one that only
describes the problem, and a single average over both mostly reports how many
of each the catalogue happens to hold.

A task that could not be posed at all — a code with no worked example, or one
whose example stopped reporting it — is counted as `invalid` rather than as a
failure, so the denominator stays honest.

## Tier 2: replayed history

One task is one merged commit that touched both the compiler and its tests.
The tree is exported at the commit's *parent*, the suites the commit added are
carried forward into it, and what remains is a suite failing for exactly the
reason the commit was written. The commit is the known-good answer, so nobody
authors a fixture and nobody writes an expected diff.

The workspace has no `.git` in it, and that is load-bearing rather than tidy.
The first version of this made a worktree at the commit and reverted the files,
which left the answer sitting in `HEAD`: the first agent to run it never wrote
a line of code — it ran `git restore --staged --worktree` and scored a pass in
eight shell commands. An empty recorded diff beside a passing suite is what
caught it. History has to be absent, not discouraged.

```sh
./bin/nupp run evals/tier2.nupp --candidates 60
./bin/nupp run evals/tier2.nupp e56083fd --model sonnet
```

The agent is told which suite fails and that the tests are the specification.
Grading is that the suites pass **and that nothing under `tests/` was
touched** — weakening the spec until it goes green is the one repair that must
never score, so it fails the run outright whatever the suite says afterwards.
The agent's whole diff is kept in the record.

Docs the commit changed stay at the parent version along with the code. A
guide written alongside a feature describes it, and leaving it in place would
hand over in prose the specification the test is supposed to be.

Cases refresh themselves: every future commit that lands with a narrow test
story is a candidate, so the bank grows with the project rather than being
maintained. What it costs is time — the compiler has to be built at the commit
under test, which is minutes, not the seconds tier 1 takes.

## Known limits

- **Isolation is by prompt, not enforced.** The agent is told to work only in
  its workspace and not to go looking for the compiler's source, and the
  workspace reaches `nupp` through a shim so no prompt names the checkout.
  Nothing stops a determined agent from finding `explain.nupp`, where the
  corrected programs live. The transcript is kept so that consulting it is at
  least visible; a run whose transcript shows it is not a measurement of the
  diagnostic.
- **A degenerate repair passes the grader.** Deleting the offending code also
  stops the code being reported. `suspiciousShrink` flags a file that lost
  more than half its length, and `finalSource` is recorded for every run, but
  neither fails the grade — a mechanical grader should not be guessing at
  intent. Read the source on a pass that looks too easy.
- **One task is a sample, not a measurement.** Two runs of the same task on
  the same model differed by a turn and a tool call. Compare distributions
  across repeated runs, not single numbers.
- **Tier 1 does not discriminate on pass/fail.** The first full sweep, 125
  tasks on Sonnet, passed **125**. That is a real answer — an agent given only
  the compiler's output repairs every diagnostic the catalogue holds an example
  for — but it means the pass rate is at its ceiling and cannot move. Compare
  effort instead: it ranged from 4 tool calls and $0.08 to 37 and $0.82, and
  that spread is what an experiment can shift.
- **The fix/no-fix slice explains nothing here.** The guess was that codes
  carrying a machine-applicable fix would be the easy ones. Only 7 of 125 tasks
  had one, and the other 118 passed anyway. The slice is still recorded because
  it is cheap and the populations are genuinely different, but it did not turn
  out to be where difficulty lives.
- **A tier-2 pass is the suite's opinion, not a review.** The commit's tests
  decide, so a repair that satisfies them by a route the original commit would
  not have taken still passes. The diff is recorded on every run for exactly
  this reason; read it before believing a surprising pass.
- **Tier-2 candidates are not uniformly hard.** `--candidates` finds commits
  by shape — small, touching both source and tests — which says nothing about
  whether the change was obvious or subtle. Curate before drawing a trend from
  a set of them.
