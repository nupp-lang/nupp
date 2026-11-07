# Tests

Tests live beside other tests of the same subject. Run a suite by its unique
file stem from the repository root:

```sh
./bin/nupp test doctest
./bin/nupp test --group=project
./bin/nupp test --lane=shared
./bin/nupp test --list-suites
```

## Directories

The directory names describe what a test exercises:

- `compiler/`: syntax, checking, types, lowering, and compiler projects
- `stdlib/`: public APIs, grouped by their current module names
- `tools/`: CLI tools, documentation, formatting, packaging, and the test runner
- `integration/`: programs and contracts spanning components or execution targets
- `fixtures/`: inputs shared by tests in several subjects
- `helpers/`: shared test utilities

Keep fixtures used by one subject under that subject. Existing harnesses keep
their scripts and inputs together under `integration/`.

The `project`, `derive`, `template`, and `bundle` groups select related packages.
Shared helpers contain setup and fixture production; each package keeps its own
cases so editing one behavior does not change every package.

## Discovery

`tests/run.lua` discovers `*test.lua` and `*test.nupp` recursively. Suite names
must be unique across directories and languages; duplicate names are errors.
Directories named `fixtures`, `corpus`, `sessions`, `helpers`, `data`,
`node_modules`, `.git`, `.rocks`, or `build` are excluded from discovery.

A directory does not choose an execution lane. The runner retains its isolation
rules and source checks, and `tests/groups.lua` defines named selections by suite
name. Use `require("helpers.paths")` in Lua suites for the repository root or
shared test directory, rather than counting parent directories from a suite.
The `tests` field preserves relative paths; use `absoluteTests` for commands that
change their working directory, and `root` for the absolute repository root.

## Validation

`scripts/test-changed [REF]` selects the union of a batch's CI surfaces. Use
`--list-suites` to inspect its selection and `--fresh` for an authoritative run.
The default base is `origin/main`; working-tree and untracked files count too.

`tests/groups.lua` returns named groups and repository policy. Its scope map
assigns every suite a coverage obligation; `--scope=NAME` selects that obligation,
while `--lane=NAME` selects its execution constraints. Delivery is explicit and
CI uses `--scope=all --fresh` to keep its coverage.

Package result caching is opt-in. Add `cache = true` only after its complete
inputs are covered, and declare shared files with `inputs`. Dynamic loads,
subprocesses and unresolved modules remain uncached. See
[testing.md](../docs/learn/projects/testing.md#passing-result-cache) for the flags
and cache contract. Timing output reports packages over 60 seconds of aggregate
suite wall time; that is a splitting signal, not a CPU measurement.
