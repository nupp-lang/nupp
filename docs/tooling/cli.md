# `nupp` command

One executable holds every tool. Each command below carries its own `--help`,
which is the text `nupp help <command>` prints, and the output it writes when
it has any.

- [`ast`](#ast): dump a Nupp file's parsed syntax tree
- [`check`](#check): type-check source without emitting Lua
- [`fmt`](#fmt): format Nupp source
- [`build`](#build): build source files or a configured project target
- [`clean`](#clean): remove build outputs configured in `nupp.lua`
- [`tasks`](#tasks): list or inspect project tasks from `nupp.lua`
- [`lints`](#lints): list the lints and the level each runs at
- [`ownership-audit`](#ownership-audit): list foreign pointer contracts and
  unsafe assertion sites
- [`explain`](#explain): describe a diagnostic code, with an example either way
- [`reference`](#reference): list or print a focused Nupp reference chapter
- [`completions`](#completions): print a shell completion script
- [`test`](#test): build and run the configured test command
- [`coverage`](#coverage): run tests and write a source coverage report
- [`task`](#task): build, then run a named task from `nupp.lua`
- [`doc`](#doc): generate API documentation from source comments
- [`fixpoint`](#fixpoint): verify a byte-identical self-hosting rebuild
- [`run`](#run): compile and run a Nupp or Lua program
- [`import-c`](#import-c): generate typed Nupp bindings from a C header
- [`rock`](#rock): create and package typed LuaRocks libraries
- [`lsp`](#lsp): language-server and semantic source operations
- [`help`](#help): show general or command-specific help

## Options every command takes

- `--color[=WHEN]`: always, never, or auto, the default
- `--no-color`: the same as `--color=never`
- `-h`, `--help`: show that command's help

`--color` never consumes the next argument. Write `--color=never`; a bare
`--color` means `always`. Passing both `--color` and `--no-color` is an error
rather than last-wins.

Color is decided by `NO_COLOR`, then `CLICOLOR_FORCE`, then `TERM=dumb`, then
whether the stream is a terminal. JSON output is never colored.

`nupp test` and the `nupp lsp` group forward their arguments, so they take only
`-h`.

## JSON and schemas

Every command that produces data takes `--format json`, spelled `--json`, and
also `--schema`, which prints the JSON Schema of that output:

```bash
nupp check --json
nupp check --schema
```

That covers `ast`, `check`, `fmt`, `build`, `clean`, `tasks`, `lints`,
`ownership-audit`, `explain`, `test`, `coverage`, `fixpoint`, `import-c`, and
every `lsp` operation. `doc` reports what it wrote; `run`, `task`, `rock` and
`completions` produce no structured result and take neither.

A test runs each command for real and validates its output against its own
`--schema`, so the schema cannot drift from what the command emits.

`--format`, `--json`, and `--text` share one setting; giving two of them is an
error. No option repeats unless it says so, and only `-Zno-opt` does.

A command writes its JSON as one line with no ordering guarantee across keys.
The `json` blocks on this page are indented so they can be read; the `text`
blocks are the bytes the command wrote.

## Exit codes

- `0`: success
- `1`: the work was attempted and failed
- `2`: usage error, such as an unknown option or the wrong argument count

A usage error prints `nupp: <message>` on stderr and points at
`nupp help <command>`.

## Example project

Every example below runs in this project, except where a section says it runs
in Nupp's own repository because it needs a test suite or a compiler to build:

```
 greeter/
 ├── nupp.lua
 └── src/
     ├── greet.nupp
     └── main.nupp
```

```lua [nupp.lua]
return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "modules",
            description = "Build the greeter",
            entries = { "main" },
         },
      },
   },

   tasks = {
      greet = {
         description = "Print a greeting",
         argv = { "nupp", "run", "src/main.nupp" },
      },
   },
}
```

```nupp [src/greet.nupp]
--- Greets someone by name.
local function greet(name: string): string
    return "Hello, " .. name
end

return {greet = greet}
```

```nupp:static [src/main.nupp]
local greet = require("greet")

print(greet.greet("world"))
```

## Command reference

### `ast`

```text [nupp ast --help]
Dump a Nupp file's parsed syntax tree

Usage:
  nupp ast [--format text|json] <file>

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

The parser produces a lossless concrete syntax tree. Text output is an indented
outline with quoted tokens; JSON includes structural children, tokens, trivia,
locations, and parse errors. A recovered tree is still printed when parsing
fails.
```

A file that does not parse still prints the tree recovery reached, and then
exits 1.

```text [nupp ast src/greet.nupp]
chunk
  block
    localFuncStmt
      local "local"
      function "function"
      name "greet"
      funcbody
        ( "("
        param
          name "name"
          : ":"
          tname
            name "string"
        ) ")"
        : ":"
        tname
          name "string"
        block
          returnStmt
            return "return"
            binop
              string
                string "\"Hello, \""
              .. ".."
              name
                name "name"
        end "end"
    returnStmt
      return "return"
      tableExpr
        { "{"
        fieldNamed
          name "greet"
          = "="
          name
            name "greet"
        } "}"
  eof ""
```

### `check`

```text [nupp check --help]
Type-check source without emitting Lua

Usage:
  nupp check [--strict] [--target NAME] [--format text|json] [file...]

Options:
  --strict         Treat strict checker rules as errors
  --target NAME    Check a named manifest target
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

With no files, checks the default target from nupp.lua.
```

A file's extension decides the floor it is held to, with `.nupp` strict and
`.g.nupp`, `.d.nupp` and `.lua` gradual. `--strict` overrides that, holding
every file to the strict floor whatever it is called: unknown-variable errors,
annotations required on module exports, and the `lossy-narrowing` lint.
`--target` cannot be combined with explicit files.

A clean project writes nothing and exits 0. With `local shout: number =
greet("world")` added to `src/greet.nupp`:

```text [nupp check]
src/greet.nupp:6:23: error: NUPP2001: cannot initialize shout: string is not a number
 6 | local shout: number = greet("world")
   |                       ^~~~~
```

Every diagnostic carries the position, the code, the severity, and the
`docs` anchor that [`nupp explain`](#explain) and the reference share:

```json [nupp check --json]
{
  "diagnostics": [
    {
      "code": "NUPP2001",
      "severity": "error",
      "message": "cannot initialize shout: string is not a number",
      "file": "src/greet.nupp",
      "range": {
        "start": {"line": 6, "column": 23, "offset": 128},
        "end": {"line": 6, "column": 28, "offset": 133}
      },
      "notes": [],
      "related": [],
      "fixes": [],
      "docs": "docs/diagnostics.md#code-families"
    }
  ]
}
```

A lint carries its `lint` name and a `help` line as well, and a fix carries the
edits that apply it. See [diagnostics.md](../diagnostics.md) for what a
diagnostic holds and [lints.md](../lints.md) for the levels.

### `fmt`

```text [nupp fmt --help]
Format Nupp source

Usage:
  nupp fmt [-w|--write] [--check] [--no-method-parens] [--width N] [--format text|json] [file...]

With files named, each is formatted to stdout, or rewritten with --write.

With none, the project is the subject: every .nupp and .d.nupp under the
manifest's include roots, minus the build output. The files that are not
formatted are listed and the exit status is 1, so a build can gate on it;
--write formats them and lists what it changed.

--check asks that question of whatever it was given, so a build can gate on
the files a change touched. Nothing is written and nothing goes to stdout but
the list; the exit status is 1 if it is not empty.

Options:
  -w, --write         Rewrite files in place instead of writing to stdout
  --check             Report which files are not formatted; write nothing
  --no-method-parens  Leave obj:m{...} and obj:m"..." written without
                      parentheses, instead of adding them
  --width N           Code column past which a line breaks, at least 20
                      (default 120)
  --format FORMAT     Output format: text (default) or json
  --json              Shorthand for --format json
  --text              Shorthand for --format text
  --schema            Print the JSON Schema of --json output and exit
  --color[=WHEN]      When to colour output: always, never, or auto (default)
  --no-color          Never colour output; the same as --color=never
  -h, --help          Show this help

--json always reports the list, whichever form was asked for, and separates a
file that could not be formatted from one that merely is not.

A method call left in its sugar form, obj:m{...} or obj:m"...", is given its
parentheses back, obj:m({...}) and obj:m("..."). --no-method-parens leaves it
as written, and so does a manifest with fmt = { methodParens = false }; the
flag wins if both are given.

--width sets the code column past which a line breaks; the default is 120,
unchanged from before this was a flag. Docblock text keeps wrapping at 88
columns regardless.
```

With a file named, the formatted source goes to stdout. Given an unformatted
`src/messy.nupp`:

```nupp:static [src/messy.nupp]
local function greet( name:string ):string
  return  "Hello, "..name
end
return {greet=greet}
```

```text [nupp fmt src/messy.nupp]
local function greet(name: string): string
    return "Hello, " .. name
end

return {greet = greet}
```

With none, the project is the subject and the answer is the list of files that
are not formatted, which is what a build gates on:

```text [nupp fmt --check]
src/messy.nupp
```

```json [nupp fmt --check --json]
{
  "ok": false,
  "written": false,
  "unformatted": ["src/messy.nupp"],
  "failed": []
}
```

See [the formatter](fmt.md) for the rules it applies.

### `build`

```text [nupp build --help]
Build source files or a configured project target

Usage:
  nupp build [--strict] [-O<n>] [--target NAME] [--out-dir DIR] [--format text|json]
  nupp build [--strict] [-O<n>] [-o DIR] [--format text|json] <file...>

Options:
  --target NAME      Build a named manifest target
  --out-dir DIR      Override the manifest target's output directory
  -o DIR             Output directory for explicit source-file builds
  --strict           Treat strict checker rules as errors
  -O0, -O1, -O2      Optimization level (default -O0, which rewrites nothing)
  --remarks          Report what the optimizer did and what it declined to do
  --relax=GUARANTEE  Allow optimizations to change one named observable
                     guarantee
  -Zno-opt=CODE      Turn off one pass, named by its stable code, to bisect a
                     miscompile. Unstable: the spelling may change or go away
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to colour output: always, never, or auto (default)
  --no-color         Never colour output; the same as --color=never
  -h, --help         Show this help

Manifest target options cannot be combined with explicit source files.
Use 'nupp tasks' to discover target names and configuration.

The level is part of the build key, so changing it rebuilds rather than
mixing artifacts compiled at two different levels. See plans/optimizations.md.

--json reports the same diagnostics as 'nupp check --json' alongside what the
build wrote, so one call answers both what went wrong and what landed. It also
reports bounded materialization facts: provider, schema, fingerprint, backend,
sizes, runtime features and ABI versions.
```

`-o` is for explicit source-file builds; `--out-dir` overrides a manifest
target's output directory. They are different options, and using one in the
other's mode is an error.

`-O0` is the default and performs no rewrite at all. `-O1` and `-O2` currently
run the same two passes. `--remarks` reports what the optimizer did and what
it declined to do; `-Zno-opt=CODE` turns off one pass by its stable code, and
the `-Z` prefix marks that spelling as unstable. Repeatable
`--relax=GUARANTEE` flags opt in to a named observable tradeoff; no current
pass requires one.

A successful build writes nothing to the terminal. `--json` says both what
failed and what landed:

```json [nupp build --json]
{
  "ok": true,
  "target": "app",
  "written": ["build/greet.lua", "build/main.lua"],
  "diagnostics": [],
  "materializations": []
}
```

See [the build system](build.md).

### `clean`

```text [nupp clean --help]
Remove build outputs configured in nupp.lua

Usage:
  nupp clean [--target NAME] [--dry-run] [--format text|json]

Options:
  --target NAME    Clean only the named build target
  --dry-run        Print output paths without removing them
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

With no target, cleans every configured target output. Paths outside the
project and paths that resolve to the project root are always rejected.
```

```text [nupp clean --dry-run]
would remove build
```

```text [nupp clean]
removed build
```

### `tasks`

```text [nupp tasks --help]
List or inspect project tasks from nupp.lua

Usage:
  nupp tasks [--format text|json]
  nupp tasks <name> [--format text|json]

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

With no name, lists build targets plus configured test and self-host actions.
With a name, prints the task's effective configuration.
```

The list marks the default build target:

```text [nupp tasks]
app (default) - Build the greeter
greet - Print a greeting
```

Naming one prints its effective configuration, inherited manifest defaults
included:

```text [nupp tasks app]
Name: app
Default: yes
Description: Build the greeter
Kind: modules
Category: build
Command: nupp build --target app
Output directory: build
Entries:
  - main
Resources:
  (none)
Dependencies:
  (none)
```

See [tasks.md](tasks.md) for the manifest shape, and [`task`](#task) for
running one.

### `lints`

```text [nupp lints --help]
List the lints and the level each runs at

Usage:
  nupp lints [--format text|json]

Levels are off, note, warning and error; only an error stops a build. A
project moves one in nupp.lua by name or by category:

  lints = { ["missing-require"] = "warning", style = "off" }

A statement waves one away with @allow("missing-require"). See docs/lints.md.

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help
```

The text table has no code column; `--json` includes `code`, `default`, and
`moved`.

```text [nupp lints]
lint                            category     level    summary
customary-operator              style        warning  a customary operator where Lua has a word
deprecated                      suspicious   warning  use of an API marked deprecated
discarded-result                suspicious   warning  a call with nothing to do but return has its result dropped
else-if                         style        warning  a conditional chain written as separate ifs
exhaustiveness                  correctness  warning  a dispatch leaves members of a closed set unhandled
gradual-projection              suspicious   warning  an associated type was erased because inference did not reach its head
jit-callback                    suspicious   warning  a C callback left on the JIT
loop-invariant-closure          suspicious   warning  a loop builds the same function every iteration
lossy-narrowing                 suspicious   warning  lossy integer narrowing
missing-require                 correctness  error    a project module is used without being required
positional-record-construction  style        warning  a record built by field order rather than by naming its fields
reifiable-record                performance  off      a record whose fields would all live in C memory
string-pointer                  suspicious   warning  a pointer taken from a Lua string
undocumented-raise              suspicious   warning  a documented function raises without saying so
unused-binding                  suspicious   warning  a local is declared and nothing reads it
```

See [lints.md](../lints.md) for moving one and for waving one away.

### `ownership-audit`

```text [nupp ownership-audit --help]
List foreign pointer contracts and unsafe assertion sites

Usage:
  nupp ownership-audit [--format text|json] [--regions] [file...]

Options:
  --regions        Include automatic cleanup regions
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

With no files, scans Nupp sources under src. The report enumerates trusted C contracts and explicit unsafe regions; it does not verify foreign implementations.
```

The report is the list of places where the checker is trusting something it
cannot see: a foreign declaration's contract, and every `unsafe do` region.
Given `src/block.nupp`:

```nupp [src/block.nupp]
cdef struct block
   size: integer
end

@owned(blockFree)
cdef function blockNew(size: integer): block*

@drop
cdef function blockFree(takes b: block*)

local function sizeOf(borrows b: block*): integer
    unsafe do
        return b.size
    end
end

return {new = blockNew, free = blockFree, sizeOf = sizeOf}
```

```text [nupp ownership-audit src/block.nupp]
Foreign ownership contracts
  src/block.nupp:6  blockNew
    result 1: owned<block*>
  src/block.nupp:9  blockFree
    parameter 1 b: block*  takes
Unsafe assertion sites
  src/block.nupp:12:5  unsafe assertion region
```

See [ownership.md](../ownership.md) for the contracts this enumerates.

### `explain`

```text [nupp explain --help]
Describe a diagnostic code, with an example either way

Usage:
  nupp explain <code> [--format text|json]
  nupp explain --list

Options:
  --list           List the codes with a worked example
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help

Every diagnostic written by --json carries the same `docs` anchor this
reports, so a reader holding a diagnostic can reach the reference without
being told where it is.

A code with no worked example still resolves through its family, and says so
with `family: true`, rather than an example being invented to fit it.
```

```text [nupp explain NUPP2119]
NUPP2119  A declaration does not say where it lives

A declaration is file-local (`local`), a member of a table (`record m.R`), or a
project global (`global`). Plain Lua would have made it a global silently; Nupp
asks instead, because a name that means one thing here and another elsewhere is
worth one word to prevent.

Reports it:

    record Loose
        id: integer
    end

    return Loose

Does not:

    local record Loose
        id: integer
    end

    return Loose

Related: NUPP2106, NUPP2120

Reference: docs/modules.md#diagnostics
```

### `reference`

```text [nupp reference --help]
List or print a focused Nupp reference chapter

Usage:
  nupp reference [language|cli|all] [--format markdown|skill|json] [-o PATH]

With no chapter, lists the available focused references. `all` is the
complete language reference, around four thousand tokens, so it fits in a prompt
whole.

  nupp reference cli
  nupp reference cli --format skill -o .claude/skills/nupp-cli/SKILL.md
  nupp reference all > docs/reference.md
  nupp reference --format skill -o .claude/skills/nupp/SKILL.md

Options:
  --format FORMAT    Output format: markdown (default), skill, or json
  --skill            Shorthand for --format skill
  --json             Shorthand for --format json
  -o, --output PATH  Write to this file rather than to standard output
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to colour output: always, never, or auto (default)
  --no-color         Never colour output; the same as --color=never
  -h, --help         Show this help

The skill's description is what a harness keeps in context permanently;
the body loads when something is actually being written. See docs/reference.md
for the same document rendered into the site.
```

With no chapter, it lists what there is to print:

```text [nupp reference]
Nupp reference chapters

  language   Nupp syntax, types, runtime constructs, lints, and diagnostics.
  cli        Nupp commands, JSON contracts, testing, and coverage workflows.

Run `nupp reference <chapter>` for one chapter, or `nupp reference all` for the complete reference.
```

The chapters are generated from the compiler, so they cannot describe a
construct the compiler does not have. The
[language reference](../reference.md) on this site is the committed output of
`nupp reference all`, and a test fails if the two drift.

### `completions`

```text [nupp completions --help]
Print a shell completion script

Usage:
  nupp completions <bash|zsh|fish>

Options:
  --color[=WHEN]  When to colour output: always, never, or auto (default)
  --no-color      Never colour output; the same as --color=never
  -h, --help      Show this help
```

The script is generated from the same command grammar that parses arguments and
renders help, so a new command and its options appear in it without a second
edit. Install it for the shell that runs `nupp`:

```sh
# Bash: add this to ~/.bashrc.
eval "$(nupp completions bash)"

# Zsh: write _nupp into a directory on fpath.
nupp completions zsh > "${fpath[1]}/_nupp"

# Fish
nupp completions fish > ~/.config/fish/completions/nupp.fish
```

```text [nupp completions bash | head -12]
# Bash completion for nupp; generated from nupp.compiler.cli.spec.
_nupp() {
  local cur prev command options
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  if (( COMP_CWORD == 1 )); then
    COMPREPLY=( $(compgen -W 'ast check fmt build clean tasks lints ownership-audit explain reference completions test coverage task doc fixpoint run import-c rock lsp help' -- "$cur") )
    return 0
  fi
  command="${COMP_WORDS[1]}"
  case "$command" in
  ast)
```

### `test`

```text [nupp test --help]
Build and run the configured test command

Usage:
  nupp test [args...]

Options:
  --json      Ask the test command for one JSON document instead of progress
              text
  --verbose   Ask the test command to show output from passing tests
  -h, --help  Show this help
  --schema    Print the JSON Schema of --json output and exit

Additional arguments are appended to test.argv from nupp.lua. Use '--' before
a test argument named --help.

--json is passed along to the test command rather than interpreted here, since
the arguments past this point are that command's. --schema describes what the
runner in tests/run.lua writes for it.
```

The example project configures no test command, so these two run in Nupp's own
repository, whose runner takes a suite name. It prints `.` for a pass, `S` for
a skip, and `E` for a failure while it runs:

```text [nupp test elseiftest]
........

8 tests, 8 passed, 0 skipped, 0 failed (11560.0ms)
```

With `--json` the progress marks go to stderr and one document stays on stdout:

```json [nupp test elseiftest --json]
{
  "ok": true,
  "total": 8,
  "passed": 8,
  "skipped": 0,
  "failed": 0,
  "durationMs": 13749.147949219,
  "tests": [
    {"suite": "elseiftest", "name": "allowsAnAnnotatedNestedIf",
     "file": "tests/elseiftest.lua", "line": 130,
     "status": "passed", "durationMs": 975.18994140625}
  ]
}
```

A failing record carries the message and the file and line the error came from.
See [testing](testing.md).

### `coverage`

```text [nupp coverage --help]
Run tests and write a source coverage report

Usage:
  nupp coverage [--out DIR] [--json] [test arguments...]
  nupp coverage --report-json [--out DIR]

Options:
  --out DIR       Directory for the HTML, JSON, and LCOV report
  --json          Write the aggregate summary as JSON
  --report-json   Print an existing full JSON report; do not run tests
  --schema        Print the JSON Schema of --json output and exit
  --color[=WHEN]  When to colour output: always, never, or auto (default)
  --no-color      Never colour output; the same as --color=never
  -h, --help      Show this help

Coverage uses a separate build/coverage artifact, so normal generated
Lua and its cache are never instrumented. The static report opens at
build/reports/coverage/index.html and also writes coverage.json and lcov.info.

`--report-json` prints the complete machine-readable coverage.json already in
the report directory, without rebuilding or rerunning tests.
```

Run in Nupp's own repository, over one suite:

```text [nupp coverage elseiftest]
........

8 tests, 8 passed, 0 skipped, 0 failed (23389.0ms)
coverage: lines 16.80%, functions 16.38%, branches 10.19%
coverage: report written to build/reports/coverage/index.html
```

See [testing](testing.md#coverage) for the report's contents and for what a
custom runner has to do.

### `task`

```text [nupp task --help]
Build, then run a named task from nupp.lua

Usage:
  nupp task <name> [args...]

Options:
  -h, --help  Show this help

Runs tasks.<name> from nupp.lua: builds tasks.<name>.build first if it names
one, then execs tasks.<name>.argv with any arguments after <name> appended.
See `nupp tasks` for the configured list.
```

```text [nupp task greet]
Hello, world
```

The exit code is the task command's own. See [tasks.md](tasks.md).

### `doc`

```text [nupp doc --help]
Generate API documentation from source comments

Usage:
  nupp doc [site|markdown|json|both] [-o PATH] [--title TITLE] [--all] [--format text|json] [path...]

Options:
  -o, --output PATH  Output file or directory
  --title TITLE      Documentation title
  --all              Include private declarations
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to colour output: always, never, or auto (default)
  --no-color         Never colour output; the same as --color=never
  -h, --help         Show this help

The first argument may name the format: site, markdown (or md), json, or both.
With none, the manifest's configured format is used, and site if it has none.

--format names the shape of this command's own report and is unrelated to the
documentation format, which is the positional word.
```

A successful run writes nothing to the terminal. `--json` names what it wrote:

```json [nupp doc markdown -o docs/api.md --json]
{
  "ok": true,
  "format": "markdown",
  "output": "docs/api.md",
  "files": ["docs/api.md"]
}
```

See [the documentation generator](doc.md).

### `fixpoint`

```text [nupp fixpoint --help]
Verify a byte-identical self-hosting rebuild

Usage:
  nupp fixpoint [--update-bootstrap] [--format text|json]
  nupp fixpoint --binary [--format text|json]

By default the compiler compiles itself twice and the two must agree.

--binary makes the same claim about packaging: the target named by
selfHost.binary is stamped, and the binary that comes out stamps another
identical to itself. It is what the payload format's determinism rests on.

Options:
  --update-bootstrap  Refresh the tracked stage-0 bundle after verification
  --binary            Verify the packaged binary instead of the compiler
  --format FORMAT     Output format: text (default) or json
  --json              Shorthand for --format json
  --text              Shorthand for --format text
  --schema            Print the JSON Schema of --json output and exit
  --color[=WHEN]      When to colour output: always, never, or auto (default)
  --no-color          Never colour output; the same as --color=never
  -h, --help          Show this help
```

The two stages are built into separate directories and compared file by file.
Run in Nupp's own repository:

```text [nupp fixpoint]
fixpoint ok: compiler rebuilds itself byte-identically
```

`--binary` names the target it stamped and the size the two runs agreed on. A
mismatch keeps both stages for inspection and exits 1. See
[distribution](../distribution.md).

### `run`

```text [nupp run --help]
Compile and run a Nupp or Lua program

Usage:
  nupp run [--strict] [-O<n>] [--profile[=MS]] [--profile-out PATH]
           [--jit-aborts[=PATH]] <file> [args...]

Options:
  --strict             Treat strict checker rules as errors
  -O0, -O1, -O2        Optimization level (default -O0, which rewrites nothing)
  --remarks            Report what the optimizer did and what it declined to do
  --relax=GUARANTEE    Allow optimizations to change one named observable
                       guarantee
  -Zno-opt=CODE        Turn off one pass, named by its stable code, to bisect a
                       miscompile. Unstable: the spelling may change or go away
  --profile[=MS]       Sample the program every MS milliseconds (default 10)
  --profile-out PATH   Where the samples go (default profile.out)
  --jit-aborts[=PATH]  Record where the JIT gave up (default jit-aborts.csv)
  --color[=WHEN]       When to colour output: always, never, or auto (default)
  --no-color           Never colour output; the same as --color=never
  -h, --help           Show this help

Program arguments are passed to the loaded chunk. Use '--' before a file name
that starts with a dash.

--profile writes collapsed-stack text: one line per stack, frames separated by
semicolons, then the sample count. speedscope.app, FlameGraph.pl and inferno
all read it directly. Frames are prefixed by the zone path that was open, so a
program that calls nupp.zone reports itself in its own terms, and the leaf
carries the VM state most of its samples were in: N compiled, I interpreted,
C in a C function, G collecting, J compiling.

--jit-aborts answers the question a sampler cannot: whether the hot code was
compiled at all. It writes CSV, one row per place the compiler gave up, with a
blacklisted trace — permanently demoted to the interpreter — ranked first.

Both cover the program only: the session opens once the file has compiled and
closes when it returns, so the compiler's own work stays out of the report. A
program that fails still writes what was collected before it did. Each reports
a summary line on stderr.
```

The first non-option argument is the program; everything after it goes to the
program, options included. Arguments arrive as the chunk's varargs. A `.nupp`
file is compiled first; anything else is loaded as Lua directly.

```text [nupp run src/main.nupp]
Hello, world
```

`--profile` and `--jit-aborts` take an attached value or none, so `--profile=2`
rather than `--profile 2`. Defaults are 10 ms and `profile.out`, and
`jit-aborts.csv`. See [profiling](profiling.md).

### `import-c`

```text [nupp import-c --help]
Generate typed Nupp bindings from a C header

Usage:
  nupp import-c [-o FILE] [-l NAME|--lib NAME] [--format text|json] <header.h>

Options:
  -o FILE          Write the generated module to FILE
  -l, --lib NAME   Name the native library loaded by the bindings
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to colour output: always, never, or auto (default)
  --no-color       Never colour output; the same as --color=never
  -h, --help       Show this help
```

It writes a committed, hand-editable module of `cdef` declarations. Without
`-o` it writes `<header basename>.nupp` into the current directory. Given
`native/mini.h`:

```c
struct mini_point {
    double x;
    double y;
};

double mini_length(const struct mini_point *point);
int mini_version(void);
```

The command reports the path it wrote:

```text [nupp import-c native/mini.h --lib mini -o src/mini.nupp]
src/mini.nupp
```

```nupp:static [src/mini.nupp]
-- generated by nupp import-c from mini.h
-- committed and hand-editable: fix or extend freely, re-import
-- only when the header changes.

cdef struct mini_point
   x: number
   y: number
end

cdef function mini_length(point: mini_point*): number from "mini"
cdef function mini_version(): int32 from "mini"

return { mini_point = mini_point, mini_length = mini_length, mini_version = mini_version }
```

A declaration the importer cannot type is left out with a comment saying so,
and `--json` reports those as warnings. See [C interop](../c-interop.md).

### `rock`

```text [nupp rock --help]
Create and package typed LuaRocks libraries

Usage:
  nupp rock init <name> [directory]
  nupp rock pack [rockspec]
  nupp rock test [rockspec]

Options:
  -h, --help  Show this help

A Nupp rock installs runtime Lua normally and carries matching public
declarations in its versioned `nupp/` directory. `pack` validates and builds that
layout; `test` installs the result into a fresh tree and checks a fresh consumer.
```

`init` scaffolds the layout:

```text [nupp rock init string-tools]
Created string-tools
```

```text
 string-tools/
 ├── nupp.lua
 ├── string-tools-dev-1.rockspec
 ├── src/
 │   └── string_tools.nupp
 ├── nupp/
 │   └── string_tools.d.nupp
 └── tests/
     └── run.lua
```

See [Working with LuaRocks](luarocks.md) for the declaration's contents and
for publishing one.

### `lsp`

```text [nupp lsp --help]
Language-server and semantic source operations

Usage:
  nupp lsp [root]
  nupp lsp serve [root]
  nupp lsp inspect [options] <file> <line> <column>
  nupp lsp definition [options] <file> <line> <column>
  nupp lsp references [options] [--include-declaration] <file> <line> <column>
  nupp lsp symbols [options] [--file FILE] [pattern]
  nupp lsp rename [options] [-w|--write] <file> <line> <column> <new-name>
  nupp lsp actions [options] [--only quickfix|refactor] <file> <line> <column>

Options:
  --root DIR       Project root (default: current directory)
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --include-declaration
                   references only: include the declaration
  --file FILE      symbols only: search one document instead of the workspace
  --only KIND      actions only: narrow to quickfix or refactor
  -w, --write      rename only: apply the rename instead of previewing it
  --schema         Print the JSON Schema of an operation's --json output; each
                   operation answers with its own
  -h, --help       Show this help

With no operation, or with only a root, runs the language server over stdio for
compatibility. `serve` names that mode explicitly. Source positions are 1-based
byte line and column numbers, matching compiler diagnostics. Rename previews by
default and changes files only with --write.
```

`inspect` describes the symbol under a position:

```json [nupp lsp inspect --json src/main.nupp 3 13]
{
  "symbol": {
    "name": "greet",
    "kind": "variable",
    "type": "function(name: string): string",
    "range": {
      "start": {"line": 3, "column": 13, "offset": 45},
      "end": {"line": 3, "column": 18, "offset": 50}
    }
  }
}
```

`definition` answers with the site a name was bound at:

```json [nupp lsp definition --json src/main.nupp 3 7]
{
  "definition": {
    "file": "src/main.nupp",
    "range": {
      "start": {"line": 1, "column": 7, "offset": 7},
      "end": {"line": 1, "column": 12, "offset": 12}
    }
  }
}
```

`references` answers semantically rather than by name, and adds the declaration
with `--include-declaration`:

```json [nupp lsp references --json --include-declaration src/greet.nupp 2 16]
{
  "declarationIncluded": true,
  "references": [
    {"file": "src/greet.nupp",
     "range": {"start": {"line": 2, "column": 16, "offset": 44},
               "end": {"line": 2, "column": 21, "offset": 49}}},
    {"file": "src/greet.nupp",
     "range": {"start": {"line": 6, "column": 17, "offset": 122},
               "end": {"line": 6, "column": 22, "offset": 127}}}
  ]
}
```

`rename` previews as a diff and changes files only with `--write`:

```text [nupp lsp rename src/greet.nupp 2 16 hello]
--- src/greet.nupp
+++ src/greet.nupp
@@ 2:16 @@
-greet
+hello
@@ 6:17 @@
-greet
+hello
```

`actions` lists what can be applied at a position, and `--json` carries the
edits with each one. On the `else` of a file whose conditional the `else-if`
lint reports:

```text [nupp lsp actions src/scratch.nupp 4 5]
quickfix: write `elseif`
```

`nupp help lsp` shows a merged option list; each of `--include-declaration`,
`--file`, `--only`, and `--write` belongs to exactly one operation. Every
operation answers `--schema` with its own. See
[the language server](lsp.md).

### `help`

```text [nupp help --help]
Show general or command-specific help

Usage:
  nupp help [command]

Options:
  --color[=WHEN]  When to colour output: always, never, or auto (default)
  --no-color      Never colour output; the same as --color=never
  -h, --help      Show this help

With no command, prints the command list.
```

Bare `nupp` prints the same list:

```text [nupp help]
Nupp compiler and project tool

Usage:
  nupp <command> [options]
  nupp help [command]

Commands:
  ast              Dump a Nupp file's parsed syntax tree
  check            Type-check source without emitting Lua
  fmt              Format Nupp source
  build            Build source files or a configured project target
  clean            Remove build outputs configured in nupp.lua
  tasks            List or inspect project tasks from nupp.lua
  lints            List the lints and the level each runs at
  ownership-audit  List foreign pointer contracts and unsafe assertion sites
  explain          Describe a diagnostic code, with an example either way
  reference        List or print a focused Nupp reference chapter
  completions      Print a shell completion script
  test             Build and run the configured test command
  coverage         Run tests and write a source coverage report
  task             Build, then run a named task from nupp.lua
  doc              Generate API documentation from source comments
  fixpoint         Verify a byte-identical self-hosting rebuild
  run              Compile and run a Nupp or Lua program
  import-c         Generate typed Nupp bindings from a C header
  rock             Create and package typed LuaRocks libraries
  lsp              Language-server and semantic source operations
  help             Show general or command-specific help

Run 'nupp help <command>' for command-specific options.
```
