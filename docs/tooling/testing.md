# Testing

`nupp test` builds the configured target, then runs the command the manifest
names, so a test never runs against a stale compiler. The harness is your
choice: the compiler's own suite runs on `tests/run.lua`, a runner that
discovers suites and spreads them across processes, and any other harness is
configured by naming it in `test.argv`.

```bash
nupp test
nupp test --json
nupp test --verbose
nupp test sometest        # extra arguments reach the test command
```

## Test configuration

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

| Key | Required | Means |
| --- | --- | --- |
| `argv` | yes | The command, as an argv array |
| `build` | no | The target to build first |
| `env` | no | Environment variables, as string to string |

`test` requires a `build` table to exist in the manifest. The command runs with
the project root as its working directory, and anything you pass after
`nupp test` is appended to `argv`. The rock tree the built target depends on is
added to `LUA_PATH` and `LUA_CPATH` for it, since the test command is a fresh
interpreter that has never heard of that tree.

## Arguments

`nupp test` does not parse its arguments, because they belong to the test
command. Two consequences:

- `-h` and `--help` are honoured only as the *first* argument. Use `--` before
  a test argument literally named `--help`.
- `--json` is passed along rather than interpreted, so the test command decides
  what it means.
- `--verbose` asks `tests/run.lua` to print output captured from every test.
  Without it, output is shown only for failures.

## Nupp's runner

`tests/run.lua` is the runner the compiler's own suite uses, and the one
`nupp test --schema` describes. It loads every `tests/*test.lua` and compiles
every `tests/*test.nupp`; both kinds return a table of test functions, and Nupp
suites run with the project's runtime loader, so they can require project
modules. It puts the build output directory and `tests` on `package.path`
first, which is how a suite reaches both.

```bash
./bin/nupp test              # everything
./bin/nupp test checktest    # one suite
```

It is not installed for you. `nupp rock init` writes a manifest whose
`test.argv` names `tests/run.lua`, and puts a two-line assertion script at that
path to replace; a project that wants this runner copies it and
`tests/assert.lua` out of the Nupp repository.

The runner prints `.` for a pass, `S` for a skip, and `E` for a failure while
it runs, and its summary reports every outcome and elapsed time. Output from
passing tests is captured; it is printed for failures or with `--verbose`.

Writing a test is defining a function on the returned table:

```lua
local test = require("assert")
local M = {}

function M.narrowsOnIs()
   local got = checkOf("local s: string | number = 'x' if s is string then end")
   test.equal(got, "")
end

return M
```

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
value it received, so existing tests get better failures without being
rewritten.

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
problem. The same four names work in Nupp; a hook in a `.nupp` file needs a `:
nil` return annotation, since that is a strict file and its exports are typed.

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

The default is two shards per online processor. Suites are nothing like equal,
so one shard per core leaves cores idle behind whichever shard drew the heavy
suites, while twice as many gives the slack a work-stealing scheduler would.
Measured on eight cores: 71s at one per core, 63s at two, and no further gain
at three.

Packing is from measurement rather than guesswork. Nothing about a suite says
in advance how long it takes, so a parallel run writes per-suite times to
`build/.nupp-test-times.json` and the next one packs longest-first from that
record. A first run with no record is guessed evenly and is slower for it. A
suite costing more than a fair share is asked to run in slices, spelled
`name#index/count`, because one suite longer than the share is the floor for
the whole run however many shards there are.

The run stays in one process for a single named suite, for `--jobs=1`, inside
a shard, and while [coverage](#coverage) is collected, where the shards would
race each other for the one counter file `NUPP_COVERAGE_FILE` names.

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
everywhere else; a Lua error carries no column, so none is invented. With
`--json`, progress is written to stderr and the one JSON document remains clean
on stdout.

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
  interpreted, and `nupp test --schema` still prints what `tests/run.lua`
  writes, so a project answering `--json` differently is the one documenting
  it.
- **Splitting the run.** Nothing in `nupp test` divides work across processes;
  the sharding above belongs to `tests/run.lua`.
- **The coverage protocol.** A custom runner must load the build directory
  `NUPP_COVERAGE_BUILD` names ahead of its ordinary output and flush the
  generated global `__nuppCoverage.hits` to the file named by
  `NUPP_COVERAGE_FILE`.

What stays: the build, the working directory, `test.env`, and the rock paths.

## Coverage

```bash
nupp coverage
nupp coverage --out reports/coverage
nupp coverage checktest
```

`nupp coverage` builds a separate instrumented artifact under `build/coverage`,
runs the configured test command, and writes a static report to
`build/reports/coverage/index.html` by default. Normal builds and their cache
never contain coverage probes. The output directory also holds `coverage.json`,
`summary.json`, and `lcov.info` for CI or editor integrations.

Agents and other tools can read the full existing report without rerunning
tests:

```bash
nupp coverage --report-json
nupp coverage --report-json --out reports/coverage
```

It writes the complete `coverage.json` document to stdout: per-file metrics,
missed locations, and counted coverage sites. Source text and generated Lua
remain in the HTML report.

The HTML report has a collapsible source tree, root and per-directory totals,
sortable file metrics, and syntax-highlighted Nupp and generated-Lua views.
Green means executed, red means executable but missed, amber means a partial
branch, and gray is non-executable source such as a type-only line.

`tests/run.lua` reads `NUPP_COVERAGE_BUILD` and writes the coverage shard
automatically. A runner that does not follow that protocol leaves
`nupp coverage` reporting incomplete data rather than treating it as zero
coverage. Coverage probes intentionally add runtime work, so use ordinary
`nupp test` or the profiler for timing.

## Verifying the compiler itself

```bash
./bin/nupp fixpoint
```

builds a stage-1 compiler, has stage 1 build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.
This is the standing check that a change to the compiler does not quietly
change its output. See [distribution](../distribution.md) for the packaged
variant, `nupp fixpoint --binary`.
