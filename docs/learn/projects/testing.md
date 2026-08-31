---
order: 580
---

# Testing

`nupp test` builds the configured target, then runs the command the manifest
names, so a test never runs against stale output. New projects use Nupp's
bundled runner; another harness remains a manifest choice in `test.argv`.

```bash
nupp test
nupp test --json
nupp test --verbose
nupp test sometest        # extra arguments reach the test command
```

## Test configuration

`test` is a table in the manifest holding the command and what to build before
it:

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
      argv = { "nupp", "test-runner" },
      env = { NUPP_TEST_MODE = "ci" },
   },
}
```

| Key | Required | Means |
| --- | --- | --- |
| `argv` | yes | The command, as an argv array |
| `build` | no | The target to build first |
| `env` | no | Environment variables, as string to string |

`test` requires a `build` table to exist in the manifest, and a manifest
without one reports `test requires build configuration`. The command runs with
the project root as its working directory, and anything you pass after
`nupp test` is appended to `argv`. The rock tree the built target depends on is
added to `LUA_PATH` and `LUA_CPATH` for it, since the test command is a fresh
interpreter that has never heard of that tree. See [rock
dependencies](build.md#rock-dependencies) for where that tree comes from.

## Arguments

`nupp test` does not parse its arguments, because they belong to the test
command. The consequences:

- `-h` and `--help` are honored only as the *first* argument. Use `--` before
  a test argument literally named `--help`.
- `--json` is passed along rather than interpreted, so the test command decides
  what it means.
- `--verbose` asks the bundled runner to print output captured from every test.
  Without it, output is shown only for failures.

## Nupp's runner

`nupp test-runner` is the runner Nupp ships and uses in its project templates;
the compiler's own suite uses the same implementation. It loads every
`tests/*test.lua` and compiles every `tests/*test.nupp`, and both kinds return a
table of test functions. `nupp test --schema` describes its JSON report.

```bash
nupp test              # everything
nupp test checktest    # one suite
```

It puts the build output directory and `tests` on `package.path` first, which
is how a suite reaches both. While it runs it prints `.` for a pass, `S` for a
skip, and `E` for a failure, and its summary reports every outcome and elapsed
time. Output from passing tests is captured, and printed for failures or with
`--verbose`.

## Where the time went

Every run times every case and every suite, and prints the slowest of each
under its summary:

```text
1790 tests, 1790 passed, 0 skipped, 0 failed (94210.4ms)

Timing: 94.2s wall, 615.3s of suite work
  18 shards: busiest 61.4s, idlest 12.9s, mean 34.2s

  slowest suites                  wall     load    hooks    cases  tests
  soatest                       101.0s    202ms      0ms   100.8s     19
  explaintest                    89.7s     31ms      0ms    89.7s      6

  slowest tests                                             wall
  explaintest / everyWrongExampleReportsTheCodeItIsFile      46.1s
  explaintest / everyRightExampleReportsNothing              43.4s
```

A suite is more than the sum of its cases, so its cost is broken into the three
places time goes: `load` compiles a Nupp suite or runs a Lua one's top level,
`hooks` is `beforeAll` and `afterAll`, and `cases` is the rest. Wall clock is
what was waited for and suite work is what was spent, so the distance between
them is the parallelism a run actually achieved, and the busiest shard is the
floor no number of further shards moves.

`--timings` prints every row rather than the slowest fifteen, `--timings=N`
prints N of them, and `--timings=0` prints none. Under `--json` the same
measurements are `suites` and `shards` beside `tests`.

The `app`, `lib`, and `love` templates configure this runner and include a real
suite using `nupp.test`. Running `nupp test-runner` directly skips the build;
the normal project command is `nupp test`, which builds first and forwards its
remaining arguments to the runner.

::: deepdive
The runner is written in Lua rather than Nupp because it loads the compiler
that the build produced and calls it to compile the Nupp suites. A runner
written in Nupp would be a build product of the code under test, so the change
that broke compilation would take the report of that breakage with it.
Compiling a suite is therefore work the runner does at run time, and a suite
that fails to compile is reported as a failing test rather than a missing
runner.
:::

### Writing a test

A test is a function on the table a suite returns:

```lua
local test = require("nupp.test")
local M = {}

function M.narrowsOnIs()
   local got = checkOf("local s: string | number = 'x' if s is string then end")
   test.equal(got, "")
end

return M
```

`nupp.test` is a shipped module, not a file copied from Nupp's own tests.
`test.assert`, `test.equal`, `test.notEqual`, `test.matches`, and `test.raises`
include the relevant values in failures; table values are rendered to make
structural differences visible. `test.skip("reason")` records a skipped test.
The runner also upgrades the ordinary global `assert` to report the falsy value
it received, so existing suites get better failures without being rewritten.

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

A `beforeAll` failure prevents the suite's cases from running and is reported
as `beforeAll`; `afterAll` still runs. A failing `afterEach` is reported with
the case failure, if there was one, so cleanup failures do not hide the
original problem. The same four names work as exports from a declared Nupp
suite.

### Suites in Nupp

A suite named `tests/*test.nupp` is a suite like any other. The runner compiles
it when it loads it and keeps the project's runtime loader installed while its
cases run, so it can require project modules the same way the code under test
does:

```nupp:playground
module tests.arithmetictest

local fixture = require("tests.nuppfixture")
local test = require("nupp.test")

export function addsNumbers(): nil
    test.equal(20 + 22, 42)
end

export function requiresNuppProjectModules(): nil
    test.equal(fixture.answer, 42)
end
```

Cases and lifecycle hooks need a `: nil` return annotation, since a `.nupp`
file is held to the strict floor and its exports are typed. See
[strictness.md](../language/gradual-typing.md) for what that floor asks for, and
[modules.md](../language/modules.md) for what `export` publishes. The
compiler's own suite carries `tests/nupptest.nupp`, `tests/ioscalarstest.nupp`,
and `tests/processcompat_test.nupp`, which is what keeps discovery,
compilation, and runtime loading of Nupp suites covered by the ordinary run.

## Parallel runs

A run of more than one suite splits itself across processes. The parent packs
the suites into groups, starts a child per group with
`--shard=name[,name...]`, and adds the reports up; the merged result is put
back into the order a serial run would have reported, so which shard finished
first changes nothing. A shard that cannot start, or that writes no report, is
counted as a failure of its own rather than quietly removing its suites from
the total.

```bash
nupp test --jobs=4        # four shards
nupp test --jobs=1        # one process
nupp test checktest       # one named suite, one process
```

Work is ordered from measurement rather than guesswork: nothing about a suite
says in advance how long it takes, so a run writes what every suite and every
case cost to `build/.nupp-test-times.json` and the next one puts the longest
first. A first run with no record is guessed evenly and is slower for it. A
suite costing more than a fair share is asked to run in slices, written
`name#index/count`, because one suite longer than the share is the floor for the
whole run however many workers there are. A slice takes the cases packed into it
by the same longest-first rule, so a suite holding one heavy case and a hundred
cheap ones puts the heavy one in a slice by itself.

Who runs what is decided while the run is happening: the order is a queue and
every worker takes the next piece when it has finished the last. That matters
because the record is what the last run measured *under its own load*, and a
suite that lands beside four heavy ones measures two or three times what it does
beside nothing. Packed in advance from a number that wrong, the busiest worker
came out near twice the mean and the run waited on it; taken from a queue, an
estimate that was wrong costs the difference rather than the whole imbalance.

The run stays in one process for a single named suite, for `--jobs=1`, inside
a shard, and while [coverage](#coverage) is collected, where the shards would
race each other for the one counter file `NUPP_COVERAGE_FILE` names.

::: deepdive
The default is one worker per processor. `--jobs=N` is explicit because the
useful count depends on the machine and on whether the suites spend their time
computing, compiling, or waiting on subprocesses.

What neither the count nor the queue fixes is a single test case longer than a
fair share. A case is the smallest thing that can be handed out, so the longest
one is the floor: on the compiler's own suite that is a `soatest` case at about
a minute and a half under load, and no arrangement of workers goes under it.
:::

## JSON output

`nupp test --schema` prints the schema the bundled runner writes. The shape is
a summary plus a record per test:

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
  ],
  "suites": [
    {"suite": "checktest", "durationMs": 431.2, "loadMs": 18.6,
     "hooksMs": 0, "casesMs": 412.6, "tests": 37,
     "slowestCase": "narrowsOnIs", "slowestCaseMs": 12.4, "shard": 3}
  ],
  "shards": [
    {"index": 3, "specs": ["checktest", "lexertest"], "durationMs": 1204.7,
     "tests": 61}
  ]
}
```

A failing record carries the message and the file and line the error came from,
plus its captured `output.stdout` and `output.stderr`. Lines are 1-based, as
everywhere else; a Lua error carries no column, so none is invented. With
`--json`, progress is written to stderr and the one JSON document remains clean
on stdout.

`suites` is where a run's time actually goes, which `tests` alone cannot say:
loading a suite and its `beforeAll` belong to no case. `shards` is empty for a
serial run, and otherwise one record per worker process.

## Bringing your own harness

`test.argv` is the whole interface, so busted, a shell script, or a bare Lua
file is configured the same way as the runner above:

```lua
test = {
   build = "app",
   argv = { "busted", "--output", "utfTerminal" },
}
```

What moves to the harness with it:

- **The meaning of `--json` and `--verbose`.** Both are appended rather than
  interpreted, and `nupp test --schema` still prints what the bundled runner
  writes, so a project answering `--json` differently is the one documenting
  it.
- **Splitting the run.** Nothing in `nupp test` divides work across processes;
  the sharding above belongs to `nupp test-runner`.
- **The coverage protocol.** A custom runner must load the build directory
  `NUPP_COVERAGE_BUILD` names ahead of its ordinary output and flush the
  generated global `__nuppCoverage.hits` to the file named by
  `NUPP_COVERAGE_FILE`.

What stays: the build, the working directory, `test.env`, and the rock paths.

## Coverage

`nupp coverage` builds a separate instrumented artifact under `build/coverage`,
runs the configured test command, and writes a static report to
`build/reports/coverage/index.html` by default:

```bash
nupp coverage
nupp coverage --out reports/coverage
nupp coverage checktest
```

Normal builds and their cache never contain coverage probes. The output
directory also holds `coverage.json`, `summary.json`, and `lcov.info` for CI or
editor integrations.

The HTML report has a collapsible source tree, root and per-directory totals,
sortable file metrics, and syntax-highlighted Nupp and generated-Lua views.
The index, each directory summary, and each source file are separate HTML pages,
so opening the report does not load the source for the whole project. Green
means executed, red means executable but missed, amber means a partial branch,
and gray is non-executable source such as a type-only line.

The bundled runner reads `NUPP_COVERAGE_BUILD` and writes the coverage shard
automatically. A runner that does not follow that protocol leaves
`nupp coverage` reporting incomplete data rather than treating it as zero
coverage. Coverage probes add runtime work by design, so time a run with
ordinary `nupp test` instead. See [profiling.md](../performance/profiling.md) for where that
time went.

### Reading an existing report

`--report-json` writes the complete `coverage.json` document to stdout, which
is how an agent or another tool reads the existing report:

```bash
nupp coverage --report-json
nupp coverage --report-json --out reports/coverage
```

It carries per-file metrics, missed locations, and counted coverage sites.
Source text and generated Lua remain in the HTML report.

## Fixpoint verification

`nupp fixpoint` builds a stage-1 compiler, has stage 1 build stage 2, and
compares the declared artifacts byte for byte:

```bash
nupp fixpoint
```

The working compiler is updated only after a match. This is the standing check
that a change to the compiler does not quietly change its output. See
[distribution.md](../../reference/distribution.md) for the packaged variant,
`nupp fixpoint --binary`.

## FAQ

### Why did `nupp test --json` print no JSON?

`--json` is appended to `test.argv` rather than interpreted, so a harness that
ignores it prints what it always prints. The bundled runner answers it, and
`nupp test --schema` prints the shape that runner writes.

### Why is the first parallel run slower than the next one?

Packing needs per-suite times, and nothing about a suite says in advance how
long it takes. A run with no `build/.nupp-test-times.json` guesses evenly and
writes the real times for the run after it. See [parallel
runs](#parallel-runs) for what it does with them.

### Does `nupp coverage` replace `nupp test`?

No. It builds a separate instrumented artifact under `build/coverage`, and the
probes cost runtime, so it answers what ran rather than how fast. Run
`nupp test` for the ordinary run, and see [profiling.md](../performance/profiling.md) for
timing one.

::: seealso
- [cli.md](../../reference/cli.md#test) for every option `nupp test`,
  `nupp coverage`, and `nupp fixpoint` take
- [build.md](build.md) for the targets `test.build` can name
- [tasks.md](project-tasks.md) for running a command that is not the test command
:::
