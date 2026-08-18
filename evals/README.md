# Agent evaluations

Measurements of how well an isolated agent completes a Nupp task, and what it
costs to do it. The design and the tiers above this one are in
[plans/065-agent-evaluation-harness.md](../plans/065-agent-evaluation-harness.md);
this directory holds what is built, which is tier 1.

These run real agents against the real compiler and **cost real money**,
about nine cents per tier-1 task on Sonnet at the time of writing. Nothing
here runs as part of `nupp test`, and nothing here gates a build.

## Tier 1: diagnostic micro-repair

One task is one diagnostic code. The program that reports it comes from the
compiler's own catalogue — the same `wrong` example `nupp explain` prints and
`tests/explaintest.lua` compiles and asserts really does report the code it is
filed under. The task bank is therefore data the compiler already maintains
for other reasons, not fixtures this directory has to keep true.

```sh
evals/tier1.py NUPP2105 --model sonnet
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
- **Easy codes measure less than they look like they do.** `NUPP2105` on a
  near-miss typo carries a fix in the diagnostic, so an agent that can read
  is expected to pass. It is a good plumbing test and a weak difficulty
  signal. The codes worth the money are the ones whose diagnostic carries no
  fix and whose repair is a judgement — see the tier-1 discussion in the plan.
