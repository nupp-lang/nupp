# Tests

Tests live beside other tests of the same subject. Run a suite by its unique
file stem from the repository root:

```sh
./bin/nupp test doctest
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
