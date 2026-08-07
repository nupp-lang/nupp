# Testing

```bash
nupp test
nupp test --json
nupp test sometest        # extra arguments reach the test command
```

`nupp test` builds the configured target, then runs the command the manifest
names. Nupp does not supply a test framework — it supplies the step that builds
first, so a test never runs against a stale compiler.

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

## JSON output

`nupp test --schema` prints the schema the runner in `tests/run.lua` writes
for. The shape is a summary plus a record per test:

```json
{
  "ok": true,
  "total": 724,
  "passed": 724,
  "failed": 0,
  "durationMs": 41230.5,
  "tests": [
    {"suite": "checktest", "name": "narrowsOnIs", "status": "passed",
     "durationMs": 12.4}
  ]
}
```

A failing record carries the message and the file and line the error came from.
Lines are 1-based, as everywhere else; a Lua error carries no column, so none
is invented.

## This repository's suite

The compiler's own tests are a dependency-free runner: `tests/run.lua` loads
every `tests/*test.lua`, calls every function in the table each returns, and
reports failures with their assert message.

```bash
./bin/nupp test              # everything
./bin/nupp test checktest    # one suite
```

Writing one is defining a function on the returned table:

```lua
local M = {}

function M.narrowsOnIs()
   local got = checkOf("local s: string | number = 'x' if s is string then end")
   assert(got == "", got)
end

return M
```

## Verifying the compiler itself

```bash
./bin/nupp fixpoint
```

builds a stage-1 compiler, has stage 1 build stage 2, and compares the declared
artifacts byte for byte. The working compiler is updated only after a match.
This is the standing check that a change to the compiler does not quietly
change its output. See [distribution](../distribution.md) for the packaged
variant, `nupp fixpoint --binary`.
