# Testing

```bash
nupp test
nupp test --json
nupp test --verbose
nupp test sometest        # extra arguments reach the test command
```

`nupp test` builds the configured target, then runs the command the manifest
names. Nupp does not supply a test framework — it supplies the step that builds
first, so a test never runs against a stale compiler.

## Coverage

```bash
nupp coverage
nupp coverage --out reports/coverage
nupp coverage checktest
```

`nupp coverage` builds a separate instrumented artifact under `build/coverage`,
runs the configured test command, and writes a static report to
`build/reports/coverage/index.html` by default. Normal builds and their cache never contain
coverage probes. The output directory also holds `coverage.json`, `summary.json`,
and `lcov.info` for CI or editor integrations.

Agents and other tools can read the full existing report without rerunning tests:

```bash
nupp coverage --report-json
nupp coverage --report-json --out reports/coverage
```

It writes the complete `coverage.json` document to stdout: per-file metrics,
missed locations, and counted coverage sites. Source text and generated Lua remain
in the HTML report.

The HTML report has a collapsible source tree, root and per-directory totals,
sortable file metrics, and syntax-highlighted Nupp and generated-Lua views.
Green means executed, red means executable but missed, amber means a partial
branch, and gray is non-executable source such as a type-only line.

The included `tests/run.lua` runner reads `NUPP_COVERAGE_BUILD` and writes the
coverage shard automatically. Custom runners must load that build directory
ahead of their ordinary output and flush the generated global
`__nuppCoverage.hits` to the file named by `NUPP_COVERAGE_FILE`; otherwise
`nupp coverage` reports incomplete data rather than treating it as zero
coverage. Coverage probes intentionally add runtime work, so use ordinary
`nupp test` or the profiler for timing.

## Configuring it

```lua
return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = { app = { kind = "modules", entries = { "app.main" } } },
   },

   test = {
      build = "app",
      argv = { "luajit", "tests/run.lua" },
      env = { NUPP_TEST_MODE = "ci" },
   },
}
```

```
 Key    Required  Means
 ─────  ────────  ────────────────────────────────────────────
 argv   yes       The command, as an argv array
 build  no        The target to build first
 env    no        Environment variables, as string to string
```

`test` requires a `build` table to exist in the manifest. The command runs with
the project root as its working directory, and anything you pass after
`nupp test` is appended to `argv`.

## Arguments

`nupp test` does not parse its arguments — they belong to the test command. Two
consequences:

- `-h` and `--help` are honoured only as the *first* argument. Use `--` before
  a test argument literally named `--help`.
- `--json` is passed along rather than interpreted, so the test command decides
  what it means.
- `--verbose` asks this repository's runner to print output captured from every
  test. Without it, output is shown only for failures.

## JSON output

`nupp test --schema` prints the schema the runner in `tests/run.lua` writes
for. The shape is a summary plus a record per test:

```json
{
  "ok": true,
  "total": 724,
  "passed": 724,
  "skipped": 0,
  "failed": 0,
  "durationMs": 41230.5,
  "tests": [
    {"suite": "checktest", "name": "narrowsOnIs", "status": "passed",
     "durationMs": 12.4}
  ]
}
```

A failing record carries the message and the file and line the error came from,
plus its captured `output.stdout` and `output.stderr`. Lines are 1-based, as
everywhere else; a Lua error carries no column, so none is invented.

## This repository's suite

The compiler's own tests use a small runner: `tests/run.lua` loads every
`tests/*test.lua` and compiles every `tests/*test.nupp`. Both kinds return a
table of test functions. Nupp suites run with the project's runtime loader, so
they can require project modules. The runner prints `.` for a pass, `S` for a
skip, and `E` for a failure while it runs. Its summary reports every outcome
and elapsed time. With `--json`, progress is written to stderr and the one JSON
document remains clean on stdout. Output from passing tests is captured; it is
printed for failures or with `--verbose`.

```bash
./bin/nupp test              # everything
./bin/nupp test checktest    # one suite
```

Writing one is defining a function on the returned table:

```lua
local test = require("assert")
local M = {}

function M.narrowsOnIs()
   local got = checkOf("local s: string | number = 'x' if s is string then end")
   test.equal(got, "")
end

return M
```

### Lifecycle hooks

A suite may define JUnit-style lifecycle functions. They are not ordinary test
cases; a failing hook becomes an explicit synthetic failure:

```lua
local M = {}

function M.beforeAll()
   -- once, before this suite's cases
end

function M.beforeEach()
   -- before every case
end

function M.afterEach()
   -- after every case, including a failed setup or case
end

function M.afterAll()
   -- once, even when beforeAll fails
end

function M.opensAConnection()
   -- test body
end

return M
```

`beforeAll` failure prevents the suite's cases from running and is reported as
`beforeAll`; `afterAll` still runs. A failing `afterEach` is reported with the
case failure, if there was one, so cleanup failures do not hide the original
problem. The same four names work in Nupp; a hook in a `.nupp` file needs a `: nil`
return annotation, since that is a strict file and its exports are typed.

The same shape works in Nupp; save this as `tests/mathstest.nupp`:

```nupp
local M = {}

function M.addsNumbers(): nil
   assert(20 + 22 == 42)
end

return M
```

`test.equal`, `test.notEqual`, `test.matches`, and `test.raises` include their
expected and actual values in failures. `test.skip("reason")` records a skipped
test. The ordinary `assert` is also upgraded by the runner to say which falsy
value it received, so existing tests get better failures without being rewritten.

## Verifying the compiler itself

```bash
./bin/nupp fixpoint
```

builds a stage-1 compiler, has stage 1 build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.
This is the standing check that a change to the compiler does not quietly
change its output. See [distribution](../distribution.md) for the packaged
variant, `nupp fixpoint --binary`.
