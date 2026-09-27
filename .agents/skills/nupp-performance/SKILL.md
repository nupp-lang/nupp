---
name: nupp-performance
description: Optimize or diagnose the performance of Nupp programs using compiler artifacts, profiles, deterministic counters, and controlled benchmarks. Use when asked to make .nupp code faster, find a Nupp performance bottleneck, compare performance candidates, or inspect LuaJIT, AOT CPU, Wasm, or GPU behavior for speed. Do not use for performance-neutral compiler work.
---

# Nupp performance

Improve the named workload on its real target and report the measured result. Use the compiler for facts and artifacts; keep experiment selection, source edits, and candidate history in the working tree.

Do not invent an optimization service or a `nupp optimize` command. Add compiler support only when a concrete experiment cannot obtain a necessary fact from the current CLI.

## Define the verdict

Before editing, identify:

- the benchmark or representative workload;
- the execution route and target: LuaJIT, AOT CPU tier, Wasm, or GPU;
- the primary metric and any secondary ceilings;
- the correctness oracle;
- the baseline revision, executable, or implementation;
- the time or candidate budget.

Infer harmless defaults from the request and repository. Ask only when a missing choice would materially change the work.

## Inspect before changing

Establish what is expensive and which layer owns it.

- Use `./bin/nupp check --json` or `./bin/nupp build --json` for compiler diagnostics, materialization facts, and timing.
- Use `./bin/nupp bc --check FILE` for hot LuaJIT loops. Treat trace-hostile bytecode as a concrete blocker, not a timing guess.
- Use `./bin/nupp run --jit-aborts=PATH --json FILE` when runtime trace aborts matter.
- Use `./bin/nupp run --profile --profile-out PATH FILE` or `./bin/nupp bench --profile DIR` to locate hot stacks.
- Use `--remarks` while investigating optimizer decisions. Use `--remarks-out` when a machine-readable account is needed; it currently writes `build/remarks.json`.
- Use `./bin/nupp aot --emit ir|llvm|asm --function NAME FILE` to inspect an AOT function. Use `wgsl` or `spirv` for the corresponding GPU route.

For native AOT, compare the emitted LLVM IR and assembly before proposing a scalar compiler pass. The IR is optimized at `-O3`; first determine whether LLVM already performs the transform. Prefer Nupp-side work when it depends on information the backend does not see, such as Nupp representation choices, view materialization, runtime allocation, ownership-derived disjointness, specialization before emission, or GPU semantics.

An artifact, profile, or optimizer remark explains where to experiment. It does not establish a speedup.

## Run one-candidate experiments

For source changes, use a task-specific worktree and preserve the baseline. Change one performance idea at a time unless the ideas cannot be separated.

Apply gates from cheapest to most expensive:

1. Check correctness and buildability.
2. Inspect deterministic evidence: allocations, materializations, trace aborts, optimizer remarks, emitted IR, C, or assembly.
3. Reject candidates that worsen a hard ceiling or fail to affect the intended mechanism.
4. Run a quick measurement only if it helps size or debug the experiment.
5. Pay for the full duration verdict only for surviving candidates.

Record the candidate, revision, target, commands, deterministic deltas, timing result, and disposition. Git remains under the caller's control; never stash, reset, commit, or modify another tree unless the task authorizes it.

## Measure duration correctly

Use `./bin/nupp bench --pilot` to estimate variance and fork requirements. Use enough forks and an explicit practical margin for a duration verdict.

Use `./bin/nupp bench --against BASELINE_NUPP --forks N --margin P` only when comparing compiler or runtime executables against identical benchmark sources. It interleaves and pairs the two executables.

For application-source alternatives, put equivalent implementations behind variants in the same `bench.suite`, or use a purpose-built harness that evaluates the preserved baseline and candidate equivalently. Do not use `--against` when both executables would read the same changed source and therefore run the same implementation.

Interpret benchmark outcomes as `improved`, `regressed`, `unchanged`, or `inconclusive`:

- retain a candidate only when correctness and ceilings pass and the requested metric is improved;
- reject a regression;
- treat `unchanged` as within the chosen practical margin;
- treat `inconclusive` as insufficient evidence, not as no change.

Do not call the spread from one process a confidence interval. Prefer deterministic counters for early rejection because they are cheaper and do not depend on machine quiet.

## Escalate compiler gaps narrowly

When the best remaining candidate is blocked by missing compiler information:

1. Name the exact missing fact or lookup.
2. Show which current command or artifact fails to expose it.
3. Specify the smallest structured output or position-based lookup that would unblock the experiment.
4. Keep candidate generation, editing, worktree management, and retention policy in this skill rather than moving them into the compiler.

Examples include structured profile output, causal declined/unavailable optimization remarks, or resolving an AOT function from a source position. A new optimizer pass is a separate proposal justified by blocker frequency and backend-subtraction evidence.

## Finish

Lead with the measured outcome for the exact workload and target. Include the comparison method, duration verdict and interval when available, important deterministic deltas, and any limit on the conclusion.

Stop when the goal is met, the agreed budget is spent, all remaining candidates fail a gate, or the next step requires a compiler capability outside the task. Never claim a performance win from inspection alone.
