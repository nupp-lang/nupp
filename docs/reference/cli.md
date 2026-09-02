---
order: 650
---

# `nupp` command

One executable holds every tool. Each command carries its own `--help`, which is
the text `nupp help <command>` prints, and this page shows that text beside the
output the command writes.

```bash
nupp check
nupp build
nupp run src/main.nupp
```

The commands, in the order `nupp help` lists them:

- [`init`](#init): create a project from a template
- [`ast`](#ast): dump a Nupp file's parsed syntax tree
- [`aot`](#aot): show what the `@aot` functions in a file compile to
- [`bc`](#bc): show the bytecode a Nupp file compiles to
- [`check`](#check): type-check source without emitting Lua
- [`fmt`](#fmt): format Nupp source
- [`build`](#build): build source files or a configured project target
- [`backend`](#backend): run checked backend conformance suites
- [`clean`](#clean): remove build outputs configured in `nupp.lua`
- [`tasks`](#tasks): list or inspect project tasks from `nupp.lua`
- [`lints`](#lints): list the lints and the level each runs at
- [`ownership-audit`](#ownership-audit): list foreign pointer contracts and
  unsafe assertion sites
- [`explain`](#explain): describe a diagnostic code, with an example either way
- [`reference`](#reference): list or print a focused Nupp reference chapter
- [`completions`](#completions): print a shell completion script
- [`test`](#test): build and run the configured test command
- [`test-runner`](#test-runner): run test suites with the bundled runner
- [`coverage`](#coverage): run tests and write a source coverage report
- [`task`](#task): build, then run a named task from `nupp.lua`
- [`doc`](#doc): generate API documentation from source comments
- [`fixpoint`](#fixpoint): verify a byte-identical self-hosting rebuild
- [`run`](#run): compile and run a Nupp or Lua program
- [`import-c`](#import-c): generate typed Nupp bindings from a C header
- [`migrate`](#migrate): migrate typed foreign source into gradual Nupp
- [`export-c`](#export-c): export canonical C declarations for Nupp structs
- [`rock`](#rock): create and package typed LuaRocks libraries
- [`lsp`](#lsp): language-server and semantic source operations
- [`help`](#help): show general or command-specific help

## Universal options

Three options are appended to every command's grammar, so no command can be the
one that forgot them:

- `--color[=WHEN]`: always, never, or auto, the default
- `--no-color`: the same as `--color=never`
- `-h`, `--help`: show that command's help

`--color` never consumes the next argument. A bare `--color` means `always`, and
a value is attached with `=`, which is what keeps the argument after it from
being read as the value:

```bash
nupp check --color=never src/greet.nupp
```

`--color` and `--no-color` land on one key, so asking for color and refusing it
on the same command line is an error rather than last-wins.

A given `--color` decides on its own. With none, `NO_COLOR` refuses escapes,
`CLICOLOR_FORCE` asks for them, and what is left is whether the stream is a
terminal that understands them, which `TERM=dumb` says it is not. JSON output is
never colored.

[`test`](#test), [`test-runner`](#test-runner), [`task`](#task), [`rock`](#rock)
and the [`lsp`](#lsp) group
hand their arguments to another program or parse them per operation, so the
three are not appended to them. Each takes `-h`, and `lsp` declares
a grammar of its own.

## JSON and schemas

Every command that produces structured data takes `--format json`, shortened to
`--json`, and `--schema`, which prints the JSON Schema of that output:

```bash
nupp check --json
nupp check --schema
```

`init`, `ast`, `aot`, `bc`, `check`, `fmt`, `build`, `backend`, `clean`, `tasks`, `lints`,
`ownership-audit`, `explain`, `doc`, `fixpoint`, `import-c` and `export-c` take
all three, and so does every `lsp` operation. `reference` names its
formats `markdown`, `skill` and `json` instead. `coverage`, `test`, `test-runner` and `run`
take `--json` and `--schema` with no `--format`, because the JSON each writes is
one particular artifact rather than a rendering of the whole result.
`completions`, `task` and `rock` produce no structured result and take neither.

A test runs each command for real and validates its output against that
command's own `--schema`, so a schema cannot drift from what the command emits.

`--format`, `--json` and `--text` share one setting, and giving two of them is
an error. No option repeats unless it says so, and three do: `--set` on `init`,
and `--relax` and `-Zno-opt` on `build` and `run`.

A command writes its JSON as one line with no ordering guarantee across keys.
The `json` blocks on this page are indented so they can be read; the `text`
blocks are the bytes the command wrote.

## Exit codes

Every command answers with one of three statuses:

- `0`: success
- `1`: the work was attempted and failed
- `2`: usage error, such as an unknown option or the wrong argument count

A usage error is settled before any work starts, names the argument it could not
use, and points at that command's help:

```text [nupp check --colour]
nupp: unknown option --colour
Try 'nupp help check' for more information.
```

## Example project

Every example below runs in this project, except where a section says it runs
in Nupp's own repository because it needs a test suite or a compiler to build:

```text
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

```nupp [src/main.nupp]
local greet = require("greet")

print(greet.greet("world"))
```

## Command reference

### `init`

```text [nupp init --help]
Create a project from a template

Usage:
  nupp init [TEMPLATE] [DIRECTORY]
  nupp init --from PATH [DIRECTORY]
  nupp init --list

Options:
  --name NAME      Project name; defaults to the directory basename
  --set KEY=VALUE  Set a template variable; may be given more than once
  --from PATH      Use a template directory on disk
  --rev REV        Commit, tag or branch for a repository template
  --list           List the built-in templates and exit
  --yes            Do not ask before writing a repository template
  --dry-run        Print what would be written and write nothing
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help

With no TEMPLATE, the built-in `app`. A name with no slash is a built-in,
a path beginning with `.`, `/` or `~` is a directory, and `owner/repo`, optionally
followed by a path within it and by `@rev`, is a repository on GitHub; a full URL is
used as given.

A repository template is fetched with git, named by the commit it resolved to, and
confirmed before anything is written. Its post-init steps are reduced to `git init`:
`check`, `build` and `test` all load the scaffolded `nupp.lua`, which is ordinary
unrestricted Lua, so running them would execute code that was just downloaded.
```

The built-in templates travel inside the compiler, so this works with no network
and no checkout:

```text [nupp init --list]
Built-in templates:
  app  A runnable program, with a test and a task to start it
  lib  A typed library packaged as a LuaRocks rock
```

`nupp init` with no arguments writes the `app` template into a directory named
for it. Naming the directory names the project:

```text [nupp init app greeter]
Created greeter from built-in template app

Next:
  cd greeter
  nupp check
  nupp test
```

```text
 greeter/
 ├── .gitignore
 ├── README.md
 ├── nupp.lua
 ├── src/
 │   ├── greeting.nupp
 │   └── main.nupp
 └── tests/
     └── run.lua
```

That project checks, builds, tests and runs as it stands, which is what the
template is for.

#### Template sources

A `TEMPLATE` argument is read as text, never by looking at the filesystem, so
the same argument means the same thing in every directory.

| Argument | Resolves to |
| --- | --- |
| `app` | a built-in template of that name |
| `./x`, `../x`, `/x`, `~/x` | a directory on disk |
| `owner/repo` | `https://github.com/owner/repo` |
| `owner/repo@v1.2.0` | the same, at that revision |
| `owner/repo/games/topdown` | that repository's `games/topdown` directory |
| `https://...`, `git@...` | used as given, with `--rev` for a revision |

`--from PATH` forces a directory, for the case where a local path looks like a
repository name. A name with no slash that matches no built-in is
refused by name rather than guessed at as a repository.

#### Writing a template

A template is a directory tree with one `template.lua` at its root, which is not
copied. Every other file is carried, `.git` at any depth is not, and `${name}`
is replaced in both file contents and path components, so
`src/${moduleName}.nupp` becomes a file named for the project. Write `$${` for a
literal `${`.

```lua [template.lua]
return {
   description = "A runnable program",
   variables = {
      name = {pattern = "^[a-z0-9][a-z0-9_-]*$", invalid = "lowercase, please"},
      author = {description = "Author", default = "unknown"},
   },
   raw = { "assets/**" },
   after = { "git" },
}
```

`name`, `moduleName` (the name with its hyphens and underscores removed)
and `directory` are always defined. A template may declare `name` to constrain
it, but its value comes from `--name` or the directory. Anything else is
declared here or it cannot be used, and is supplied with `--set KEY=VALUE`.

`raw` names globs copied byte for byte, for assets that are not text. `after`
names post-init steps from a closed set: `git`, `check`, `build` and `test`.

#### Fetched template limits

A repository template is confirmed before anything is written, and a run with
nothing at the terminal to answer is refused rather than assumed. `--yes`
accepts it unread, and either way its `after` steps are reduced to `git init`,
so the scaffolded project is read before any of it runs.

```bash
nupp init owner/repo@v1.2.0 game --yes
```

::: deepdive
The reduced step list is not caution about `template.lua`, which is loaded in a
sandbox with no `io`, `os`, `require` or `load` in it. It is that `check`,
`build` and `test` all load the `nupp.lua` that was just scaffolded, and a
manifest is ordinary unrestricted Lua. A template allowed to ask for `check`
could put its payload in the manifest instead, and the sandbox would be
decoration.
:::

::: seealso
- [tour.md](../getting-started/tour.md) for a walk through the scaffolded
  project
- [build.md](../learn/projects/build.md) for the `nupp.lua` a template writes
- [LuaRocks](../learn/projects/integrations/luarocks.md) for the layout the `lib` template
  scaffolds
:::

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
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help

The parser produces a lossless concrete syntax tree. Text output is an indented
outline with quoted tokens; JSON includes structural children, tokens, trivia,
locations, and parse errors. A recovered tree is still printed when parsing
fails.
```

The tree is the one [grammar.md](grammar.md) defines, kept lossless down to
trivia. A file that does not parse still prints the tree recovery reached, and
then exits 1.

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

### `aot`

```text [nupp aot --help]
Show what the @aot functions in a file compile to

Usage:
  nupp aot [--emit ir|c|spirv|wgsl|asm|binding] [--check] [--function NAME] [--target TRIPLE] [--features TIER] <file>

Reports what the ahead-of-time backend produces for one file, without writing it. A native build emits the same artifacts under `aot = "emit-c"` or `aot = "require"`; Lua 5.1 Wasm applications use `emit-wasm` or `require-wasm`.

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --emit ARTIFACT  Print one artifact: ir, c, spirv, wgsl, asm, or binding
  --function NAME  Show only this function, named as the source or the symbol
                   spells it
  --check          Exit non-zero for a map loop that wanted lanes and ran one
                   iteration at a time
  --target TRIPLE  The target triple to compile for; the host's by default
  --features TIER  The CPU feature tier to promise: baseline, avx2, avx512f,
                   neon, scalar, or simd128
  --library PATH   Where the compiled object will be found, for the generated
                   binding
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help
```

The bare command says what the backend decided for every `@aot` function in the
file: how much arithmetic each loop does per byte it touches, and which
[gang](../learn/performance/ahead-of-time/index.md) it was lowered to, if any.

```text [nupp aot bench/kernel-subset-spike/mandelbrot.nupp]
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, 5.19 operations per byte (83 over 16), f64x4, 4 lanes
```

`--emit` prints one artifact. `ir` is the verified IR with the lane body beside
the scalar one it was rewritten from, `c` is the generated C, `asm` is the
instructions that C became, and `binding` is the Nupp module that stands in
front of it.

`--emit asm` compiles the generated C with the flags a build compiles this
tier's translation unit with, and stops one step before the assembler encodes
it. It is the answer to what the C compiler did, which is the last thing between
a lowering decision and the machine and the one thing nothing else in the tree
reports. Each symbol is headed by what it is -- the compiled body, the
forced-scalar oracle it is differentially tested against, a Lua wrapper, the
registrar, a layout reporter, or a helper the compiler declined to inline -- and
by a count of the listing under it:

```text [nupp aot --emit asm --function scale src/kernel.nupp]
-- src/kernel.nupp, aarch64-apple-darwin, neon, Apple clang version 21.0.0
-- ks_scale (scale), kernel: 50 instructions, 11 vector, 4 loads, 4 stores, 11 branches, 0 calls, 0 stack
      cbz     x2, LBB1_14
LBB1_6:
      ldp     q1, q2, [x9, #-32]
      fmul.4s v1, v1, v0[0]
      stp     q1, q2, [x10, #-32]
      subs    x11, x11, #16
      b.ne    LBB1_6
```

`total` is exact. The other counts are a rule per architecture over the mnemonic
and the operand shape, coarse on purpose: what they support is comparing two
runs of one kernel, not modelling the machine. Scalar floating point is
deliberately not counted as vector on either architecture, since a loop that
fell back to one element at a time is what a vector count is usually being read
to detect, and `stack` counts instructions whose memory operand is the frame,
which is the closest thing to a spill count that reading instructions can give.

`--function` narrows that to one body, named either as the source spells it or
as the symbol does. With `--features`, which selects the tier the C is both
lowered and compiled for, that is a repeatable command for one function at one
tier -- so what a change did to the emitted instructions can be compared across
runs rather than re-derived by hand. Two runs are comparable when the compiler
is: `--json` reports it, alongside the flags it was given and the per-symbol
counts. There are instruction rules for aarch64 and x86-64; another
architecture is refused rather than reported with empty counts.

`--check` covers the same category [`bc --check`](#bc) does: a performance
property no answer depends on, which an ordinary edit can quietly take away. It
distinguishes three outcomes and fails on one. A loop that lowered is fine, and
so is a loop that declined, whether because the arithmetic per byte says lanes
will not pay or because the source wrote `@aot(lanes = false)`. A loop that
wanted lanes and ran one iteration at a time exits 1, naming the construct that
stopped it:

```text [nupp aot --check src/particles.nupp]
nupp: advance ran one iteration at a time
  src/particles.nupp:39:5: aot: a nested numeric loop is not lane-controlled yet
```

When a loop declines because it does too little arithmetic and its traffic is
through fields of consecutive structs, the text report also suggests projecting
the hot fields from `nupp.mem.soa` column storage. This is guidance rather than
a failed check: the scalar body remains the selected implementation.

See [vectorization.md](../learn/performance/ahead-of-time/vectorization.md#targets-and-feature-tiers)
for how a gang is chosen and for the tiers `--features` names.

### `bc`

```text [nupp bc --help]
Show the bytecode a Nupp file compiles to

Usage:
  nupp bc [--check] [--prologue] [--format text|json] <file>

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --check          Report bytecode a loop cannot compile, and exit non-zero for
                   it
  --prologue       Include the generated runtime preamble, folded away by
                   default
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help

Source lines are shown against the instructions they produced. The generated
runtime preamble all lands on line 1 and is folded away unless `--prologue`
asks for it.

`--check` marks every instruction LuaJIT cannot record that sits inside a loop.
It exits 1 when every repeatable path reaches one, because that loop cannot
complete a root trace. A blocker reached on only some paths remains visible as
advice without claiming every path stays interpreted.
```

Generated Lua keeps source line numbers one to one, so the listing shows the
file that was written rather than the file that was generated:

```text [nupp bc src/greet.nupp]
-- chunk, lines 0-6
     ... 44 instructions of runtime preamble
    3 | end
      0044  FNEW     4   7      ; greet.nupp:1
    5 | return {greet = greet}
      0045  TDUP     5   8
      0046  TSETS    4   5   9  ; "greet"
      0047  UCLO     0 => 0048
      0048  RET1     5   2

  -- function, lines 1-3
      1 | local function greet(name: string): string
        0000  FUNCF    3 
      2 |     return "Hello, " .. name
        0001  KSTR     1   0      ; "Hello, "
        0002  MOV      2   0
        0003  CAT      1   1   2
        0004  RET1     1   2
```

Building a function is the usual thing `--check` finds. LuaJIT has no recording
for it, so the loop holding one aborts recording, is blacklisted after enough
attempts, and then runs interpreted however hot it gets. Nothing else reports
that, because the program's answers do not change.

It reads further than the two source lints, which see what was written rather
than what was generated:
[`loop-invariant-closure`](lints.md#loop-invariant-closure) reports a function
that could be lifted out of its loop unchanged, and
[`jit-loop-closure`](lints.md#jit-loop-closure), off until a project asks for
it, reports one that reads the iteration and so cannot be. Neither says
anything about a closure the compiler's own lowerings put in a loop, which is
what this reads.

::: seealso
- [jit-trace-checking.md](../learn/performance/jit-trace-checking.md) for reading a
  `--check` report and acting on it
- [performance.md](../learn/performance/index.md) for where bytecode checking sits
  among the other measurements
:::

### `check`

```text [nupp check --help]
Type-check source without emitting Lua

Usage:
  nupp check [--strict] [--dialect DIALECT] [--target NAME] [--platform NAME|all] [--format text|json] [file...]

Options:
  --strict           Treat strict checker rules as errors
  --dialect DIALECT  Source-lowering dialect: luajit (default), luajit-compat
                     or lua51
  --target NAME      Check a named manifest target
  --platform NAME    Check one configured binary platform, or all
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help

With no files, checks the default target from nupp.lua. Also reports a `timing` object naming how many modules were reused from the cache versus rechecked, and which modules cost the most of the wall-clock time either way -- see docs/reference/diagnostics.md.
```

A file's extension decides the floor it is held to, with `.nupp` strict and
`.g.nupp`, `.d.nupp` and `.lua` gradual. `--strict` overrides that, holding
every file to the strict floor whatever it is called: unknown variables are
errors, and module exports need annotations. `--target` names a manifest target
and cannot be combined with explicit files. `--dialect` overrides the target's
source-lowering dialect, or selects one for explicitly named files.

A clean project writes nothing and exits 0. With
`local shout: number = greet("world")` added to `src/greet.nupp`:

```text [nupp check]
src/greet.nupp:6:23: error: NUPP2001: cannot initialize shout: string is not a number
 6 | local shout: number = greet("world")
   |                       ^~~~~
```

See [strictness.md](../learn/language/gradual-typing.md#strict-floor-rules) for what the
strict floor holds a file to, and
[strictness.md](../learn/language/gradual-typing.md#file-extensions) for which extension
carries it.

#### Diagnostics as JSON

Every diagnostic carries the position, the code, the severity, and the `docs`
anchor that [`explain`](#explain) and the reference share:

```json [nupp check --json]
{
  "ok": false,
  "dialect": "luajit",
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
      "docs": "docs/reference/diagnostics.md#code-families"
    }
  ]
}
```

A lint carries its `lint` name and a `help` line as well, and a fix carries the
edits that apply it. See [diagnostics.md](diagnostics.md#code-families) for what
a diagnostic holds and [lints.md](lints.md#severity-levels) for the levels.

`ok` says whether the check ran and found nothing wrong. It is false both for a
project that reported an error and for a run that never got as far as checking:
a manifest the command could not use ends the run before any file is read, and
an empty `diagnostics` cannot tell that apart from a clean project on its own.

#### Check timing

With no files named, `--json` also carries a `timing` object, so a repeat check
that feels slow can be read rather than waited out. It is the shape
[`build`](#build) publishes, minus the parts only generation charges time to:

```json [nupp check --json]
{
  "ok": true,
  "dialect": "luajit",
  "diagnostics": [],
  "timing": {
    "totalMs": 8.4,
    "compiledModules": 0,
    "reusedModules": 2,
    "phases": [{"name": "check", "durationMs": 3.1}],
    "slowest": []
  }
}
```

`compiledModules` is how many modules this run actually reparsed and rechecked,
and `reusedModules` is how many it answered from the last run's cache without
looking at again. `compiledModules = 0` is the answer to trust that nothing was
redone.

`slowest` ranks modules by wall-clock time spent either way, longest first.
Confirming a reused module's cache entry is still valid costs time too, so a
check that stayed slow on an unchanged project still names a module to look at
rather than asking to be trusted. `timing` is absent when a diagnostic stopped
the check, the same as it is for `build`, since a run that did not finish has
no account of itself to give.

::: seealso
- [lints.md](lints.md#project-configuration) for moving a lint's level in
  `nupp.lua`
- [build.md](../learn/projects/build.md#cache-and-failure-behavior) for what the build
  cache holds between runs
:::

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
  --color[=WHEN]      When to color output: always, never, or auto (default)
  --no-color          Never color output; the same as --color=never
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

```nupp [src/messy.nupp]
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

See [fmt.md](../learn/tooling/formatter.md) for the rules the formatter applies and for the
`fmt` table in `nupp.lua`.

### `build`

```text [nupp build --help]
Build source files or a configured project target

Usage:
  nupp build [--strict] [--dialect DIALECT] [-O<n>] [--target NAME] [--platform NAME|all] [--standalone] [--out-dir DIR] [-q] [--format text|json]
  nupp build [--strict] [--dialect DIALECT] [-O<n>] [-o DIR] [-q] [--format text|json] <file...>

Options:
  --target NAME      Build a named manifest target
  --platform NAME    Build one configured binary platform, or all
  --standalone       Link native FFI and AOT code into the binary host
  --out-dir DIR      Override the manifest target's output directory
  -o DIR             Output directory for explicit source-file builds
  --strict           Treat strict checker rules as errors
  --dialect DIALECT  Source-lowering dialect: luajit (default), luajit-compat
                     or lua51
  -O0, -O1, -O2      Optimization level; ad-hoc builds default to -O0,
                     deliverable targets to -O2
  --remarks          Report what the optimizer did and what it declined to do
  --relax=GUARANTEE  Allow optimizations to change one named observable
                     guarantee
  -Zno-opt=CODE      Turn off one pass, named by its stable code, to bisect a
                     miscompile. Unstable: the spelling may change or go away
  --progress[=WHEN]  When to report progress and timing on standard error:
                     always, never, or auto (default), which reports only to a
                     terminal
  -q, --quiet        Report no progress or timing; the same as --progress=never
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help

Manifest target options cannot be combined with explicit source files.
Use 'nupp tasks' to discover target names and configuration.

The level is part of the build key, so changing it rebuilds rather than
mixing artifacts compiled at two different levels. See docs/learn/performance/index.md.

--json reports the same diagnostics as 'nupp check --json' alongside what the
build wrote, so one call answers both what went wrong and what landed. It also
reports bounded materialization facts: provider, schema, fingerprint, backend,
sizes, runtime features and ABI versions, and a timing object saying where the
build's wall-clock time went and which modules cost the most of it.

To a terminal, a build says which module it is on while it compiles and then
how long it took, what it spent that on, and its slowest modules. To anything
else it stays quiet, so a script reading the output sees what it always saw.
NUPP_PROGRESS says what --progress says, for the builds nothing passes a flag
to -- including the rebuild bin/nupp runs before every other command.
```

#### Output directories

`-o` is for explicit source-file builds and `--out-dir` overrides a manifest
target's output directory. They are different options, and using one in the
other's mode is an error:

```bash
nupp build --target app --out-dir dist
nupp build -o dist src/greet.nupp
```

#### Optimization levels

The default depends on what is being built. An ad-hoc file build stays at
`-O0`, which performs no rewrite at all and maps output one-to-one to source.
A `binary`, `bundle`, or `component` target is a release artifact and builds
at `-O2` unless its manifest entry declares its own level with
`optimize = 0|1|2`; an explicit `-O` on the command line wins over both. The
compiler builds itself optimized the same way, through `optimize = 2` on its
own target. `-O1` and `-O2` currently run the same eight passes, `OPT-1`
through `OPT-8`.

```bash
nupp build -O1 --remarks
nupp build -O1 -Zno-opt=OPT-3
```

`--remarks` reports what the optimizer did and what it declined to do.
`-Zno-opt=CODE` turns off one pass by its stable code, and the `-Z` prefix marks
it as unstable: the option's name may change or go away. `--relax=GUARANTEE`
opts in to a named observable tradeoff and may be given more than once; no
current pass requires one. See
[performance.md](../learn/performance/index.md#optimization-passes) for what each
pass rewrites and what it measured.

::: deepdive
`-Zno-opt` and `--relax` reach the build key as well, not only `-O`. That is
what makes `-Zno-opt=CODE` a usable bisection tool: turning a pass off and
building again produces a tree compiled entirely without it, rather than one
where whichever modules happened to be cached still carry it.
:::

#### Progress and timing

To a terminal, a build says which module it is on, on one line it rewrites in
place, and then how long the whole thing took, which activities that time went
to, and the modules that cost the most of it:

```text
built compiler in 18.9s: 164 compiled, 0 reused
  check 16.1s  generate 952ms
  slowest
    nupp.compiler.gen            1.9s
    nupp.mem.heap                699ms
    nupp.compiler.check.calls    664ms
```

One activity is current at a time, so the second line's parts add up to the
whole rather than overlapping. A module is charged for its own checking and
generation and not for the dependencies its check pulled in, so the list names
where the time went rather than whichever module happened to be reached first.

To anything that is not a terminal a successful build still writes nothing, so a
script reading its output sees what it always saw. `--progress=always` asks for
the report anyway, `-q` refuses it, and `NUPP_PROGRESS` says the same thing for
the builds nothing passes a flag to, including the rebuild `bin/nupp` runs
before every other command.

#### JSON report

`--json` says both what failed and what landed, and carries the same timing as
data rather than as a report:

```json [nupp build --json]
{
  "ok": true,
  "target": "app",
  "dialect": "luajit",
  "written": ["build/greet.lua", "build/main.lua"],
  "diagnostics": [],
  "materializations": [],
  "timing": {
    "totalMs": 412.7,
    "compiledModules": 2,
    "reusedModules": 0,
    "phases": [{"name": "check", "durationMs": 331.2}],
    "slowest": [{"module": "main", "durationMs": 208.4}]
  }
}
```

It also reports bounded materialization facts under `materializations`:
provider, schema, fingerprint, backend, sizes, runtime features, and ABI
versions.

::: seealso
- [build.md](../learn/projects/build.md) for `nupp.lua`'s targets, dependencies, and
  cache
- [build.md](../learn/projects/build.md#build-progress-and-timing) for reading the
  progress report
- [distribution.md](distribution.md) for turning a built target into something
  to ship
:::

### `backend`

```text [nupp backend --help]
Run checked backend conformance suites

Usage:
  nupp backend test <module> [--dialect luajit|luajit-compat|lua51] [--runtime LUA] [--seam NAME] [--json]

Options:
  -h, --help  Show this help
  --schema    Print the JSON Schema of --json output and exit

The command checks and compiles the backend without executing it, then runs all or one of its compiler-owned seam suites. --runtime writes the checked modules as real Lua files and executes them with that interpreter; without it the isolated CLI process is used. It reports resolution evidence, not a cached certification claim.
```

The backend module and every seam suite are checked source. Passing
`--runtime` compiles that source into an isolated Lua module tree before the
named executable runs it, so a Lua 5.1 compatibility result does not come from
the compiler's LuaJIT process:

```bash
nupp backend test acme.portable --dialect lua51 --runtime lua5.1
```

The command reports evidence from that run. It does not modify a manifest,
discover providers, or record a certification for later builds.

See [portable-libraries.md](../learn/projects/portability/libraries.md#backend-conformance)
for backend source, dependency providers, and a multi-runtime test matrix.

### `clean`

```text [nupp clean --help]
Remove build outputs configured in nupp.lua

Usage:
  nupp clean [--target NAME] [--platform NAME|all] [--dry-run] [--format text|json]

Options:
  --target NAME    Clean only the named build target
  --platform NAME  Clean one configured binary platform, or all
  --dry-run        Print output paths without removing them
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help

With no target, cleans every configured target output. Paths outside the
project and paths that resolve to the project root are always rejected.
```

`--dry-run` names the paths and removes nothing, which is how to see what a
clean is about to reach:

```text [nupp clean --dry-run]
would remove build
```

```text [nupp clean]
removed build
```

`--platform` narrows one target's outputs and so requires `--target`; giving it
alone is a usage error. See
[build.md](../learn/projects/build.md#cache-and-failure-behavior) for what a build
leaves in the output directory.

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
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
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

See [tasks.md](../learn/projects/project-tasks.md) for the manifest shape, and [`task`](#task)
for running one.

### `lints`

```text [nupp lints --help]
List the lints and the level each runs at

Usage:
  nupp lints [--format text|json]

Levels are off, note, warning and error; only an error stops a build. A
project moves one in nupp.lua by name or by category:

  lints = { ["missing-require"] = "warning", style = "off" }

A statement waves one away with @allow("missing-require"). See
docs/reference/lints.md.

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
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
jit-boundary                    suspicious   warning  an FFI boundary cannot safely run on a compiled trace
jit-callback                    suspicious   warning  a C callback left on the JIT
jit-loop-closure                performance  off      a loop builds a function and so never compiles
loop-invariant-closure          suspicious   warning  a loop builds the same function every iteration
missing-require                 correctness  error    a project module is used without being required
positional-record-construction  style        warning  a record built by field order rather than by naming its fields
reifiable-record                performance  off      a record whose fields would all live in C memory
string-pointer                  suspicious   warning  a pointer taken from a Lua string
undocumented-raise              suspicious   warning  a documented function raises without saying so
unused-binding                  suspicious   warning  a local is declared and nothing reads it
```

See [lints.md](lints.md#project-configuration) for moving one in `nupp.lua`,
and [lints.md](lints.md#local-suppressions) for waving one away at a statement.

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
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
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

cdef function blockCreate(size: integer): block*

cdef function blockFree(takes b: block*)

local function blockNew(size: integer): affine(block*, blockFree)
    return blockCreate(size)
end

local function sizeOf(borrows b: block*): integer
    unsafe do
        return b.size
    end
end

return {new = blockNew, free = blockFree, sizeOf = sizeOf}
```

```text [nupp ownership-audit src/block.nupp]
Foreign ownership contracts
  src/block.nupp:5  blockCreate
    result 1: block*
  src/block.nupp:8  blockFree
    parameter 1 b: block*  takes
Unsafe assertion sites
  src/block.nupp:15:5  unsafe assertion region
```

The audit reports what the *foreign* boundary states. `blockCreate` returns a
plain `block*` because a `cdef` declaration cannot say it produces an owner; the
obligation begins at `blockNew`, which is ordinary Nupp and so is not a foreign
contract to enumerate.

::: seealso
- [type-system/ownership.md](../learn/runtime/ownership/borrowing.md) for the contract each
  `cdef` declaration states
- [concepts/ownership.md](../learn/runtime/ownership/index.md) for the annotations a caller
  writes
- [c-interop.md](../learn/runtime/c-interop/index.md) for what the foreign side of the
  boundary promises
:::

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
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
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

Reference: docs/reference/diagnostics.md#diagnostic-index
```

### `reference`

```text [nupp reference --help]
List or print a focused Nupp reference chapter

Usage:
  nupp reference [language|cli|performance|all] [--format markdown|skill|json] [-o PATH]
  nupp reference --section NAME | --for CODE

With no chapter, lists the available focused references and the sections
inside them. `all` is the complete Nupp reference, meant to be pasted whole.

A chapter is thousands of words. `--section` prints one section, named by its
heading or by any `docs` pointer at it, and `--for` prints whichever sections
explain a diagnostic code -- which is what a reader holding one actually has.

  nupp reference cli
  nupp reference language
  nupp reference --section affine-resources
  nupp reference --section docs/learn/language/modules.md#modules
  nupp reference --for NUPP2004
  nupp reference cli --format skill -o .claude/skills/nupp-cli/SKILL.md
  nupp reference performance --format skill -o .claude/skills/nupp-performance/SKILL.md
  nupp reference --format skill -o .claude/skills/nupp/SKILL.md

Options:
  --format FORMAT    Output format: markdown (default), skill, or json
  --skill            Shorthand for --format skill
  --json             Shorthand for --format json
  --section NAME     Print one section, by heading or by a docs pointer at it
  --for CODE         Print whichever sections explain that diagnostic code
  -o, --output PATH  Write to this file rather than to standard output
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help

The skill's description is what a harness keeps in context permanently;
the body loads when something is actually being written. The documentation site
instead presents the same subjects as focused pages for human browsing.
```

With no chapter, it lists what there is to print:

```text [nupp reference]
Nupp reference chapters

  language    Nupp syntax, types, runtime constructs, lints, and diagnostics.
  cli         Nupp commands, JSON contracts, testing, and coverage workflows.
  performance Nupp trace checking, sampling, abort analysis, zones, and benchmark workflow.

Language sections
  gradual-typing-over-luajit
  declaring-things
  types
  functions
  …

CLI sections
  …

Performance sections
  …

Run `nupp reference <chapter>` for one chapter, `nupp reference all` for the complete reference,
`nupp reference --section <name>` for one section, or `nupp reference --for <CODE>` for
whichever sections explain a diagnostic.
```

#### Printing one section

A chapter is thousands of words, and `language` is over thirteen thousand, so a
reader who knows which construct they are asking about should not have to load
the rest of it. `--section` prints one:

```bash
nupp reference --section types
nupp reference --section affine-resources
```

A section is named by its heading or by any `docs` pointer at it, and everything
before the `#` is ignored, so the anchor a diagnostic already carries can be
followed straight through:

```bash
nupp reference --section docs/learn/language/modules.md#modules
```

That prints the same section as `--section modules`. `--for CODE` goes the other
way and prints whichever sections explain a diagnostic, which is what a reader
holding one actually has:

```bash
nupp reference --for NUPP2004
```

A code that no section covers says so and points at [`explain`](#explain), which
is where every code answers. The listing above names every section, so nothing
has to be guessed at.

#### Chapter guarantees

The chapters are generated from the compiler, so they cannot describe a
construct the compiler does not have. Their examples compile in the test suite,
and every cited diagnostic code resolves through `nupp explain`.

::: deepdive
The reference is compiled into the binary rather than fetched, which is the
reason it is a command and not only a page on a website. A reader holding a
reference from a different version is worse off than one holding none, because
nothing in what they are reading tells them it does not match the compiler they
are running. Printing it from the binary makes the two the same artifact.
:::

::: seealso
- [diagnostics.md](diagnostics.md) for the codes `--for` resolves
- [tour.md](../getting-started/tour.md) for the same material written for a
  first read rather than for pasting
:::

### `completions`

```text [nupp completions --help]
Print a shell completion script

Usage:
  nupp completions <bash|zsh|fish>

Options:
  --color[=WHEN]  When to color output: always, never, or auto (default)
  --no-color      Never color output; the same as --color=never
  -h, --help      Show this help
```

The script is generated from the same command grammar that parses arguments and
renders help, so a new command and its options appear in it without a second
edit. Install it for the shell that runs `nupp`:

```bash
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
    COMPREPLY=( $(compgen -W 'init ast aot bc check fmt build backend clean tasks lints ownership-audit explain reference completions test test-runner coverage task doc fixpoint run import-c migrate export-c rock lsp help' -- "$cur") )
    return 0
  fi
  command="${COMP_WORDS[1]}"
  case "$command" in
  init)
```

### `test`

```text [nupp test --help]
Build and run the configured test command

Usage:
  nupp test [args...]

Options:
  --json          Ask the test command for one JSON document instead of
                  progress text
  --verbose       Ask the test command to show output from passing tests
  --color[=WHEN]  Color both compiler and test output: always, never, or auto
  --no-color      Never color compiler or test output
  --timings       Ask the test command for its whole timing report rather than
                  the slowest few. `--timings=N` asks for N rows, and
                  `--timings=0` for none
  -h, --help      Show this help
  --schema        Print the JSON Schema of --json output and exit

Additional arguments are appended to test.argv from nupp.lua. Use '--' before
a test argument named --help.

--json is passed along to the test command rather than interpreted here, since
the arguments past this point are that command's. --schema describes what the
bundled runner writes for it.
```

The example project configures no test command, so these two run in Nupp's own
repository, whose runner takes a suite name. Progress prints `.` when a unit
passes, `S` when all of it is skipped, and `E` when it contains a failure. A
parallel unit is a suite slice rather than one test, which keeps large runs
compact; the failure report still names every failing test:

```text [nupp test elseiftest]
........

8 tests, 8 passed, 0 skipped, 0 failed (1972.3ms)

Timing: 2.0s wall, 2.0s of suite work

  slowest suites                  wall     load    hooks    cases  tests
  elseiftest                      2.0s     24ms      0ms     1.9s      8

  slowest tests                                             wall
  elseiftest / canBeAllowedByNameOrCode                    427ms
  elseiftest / allowsAdjacentConditionsThatCouldBothHol    411ms
  elseiftest / offersAMachineApplicableFix                 276ms
  elseiftest / flagsAdjacentMutuallyExclusiveConditions    273ms
  elseiftest / allowsAdditionalStatementsInTheElse         154ms
  elseiftest / allowsAnAnnotatedNestedIf                   137ms
  elseiftest / canBeTurnedOff                              135ms
  elseiftest / flagsAnElseContainingOnlyAnIf               134ms
```

The timing report is the slowest fifteen of each by default; `--timings` asks
for all of them, `--timings=N` for N, and `--timings=0` for none.

With `--json` the progress marks go to stderr and one document stays on stdout:

```json [nupp test elseiftest --json]
{
  "ok": true,
  "total": 8,
  "passed": 8,
  "skipped": 0,
  "failed": 0,
  "durationMs": 1830.0378417969,
  "tests": [
    {"suite": "elseiftest", "name": "allowsAnAnnotatedNestedIf",
     "file": "tests/elseiftest.lua", "line": 130,
     "status": "passed", "durationMs": 142.4580078125}
  ],
  "suites": [
    {"suite": "elseiftest", "durationMs": 1830.037841796875,
     "loadMs": 24.1259765625, "hooksMs": 0.394775390625,
     "casesMs": 1805.449462890625, "tests": 8,
     "slowestCase": "canBeAllowedByNameOrCode",
     "slowestCaseMs": 384.158935546875}
  ],
  "shards": []
}
```

A failing record carries the message and the file and line the error came from.
`suites` says what a suite cost beyond its cases -- compiling or loading it, and
its `beforeAll` -- and `shards` is one record per worker process, empty here
because a single named suite runs in one.

::: seealso
- [testing.md](../learn/projects/testing.md#test-configuration) for the `test` table in
  `nupp.lua`
- [testing.md](../learn/projects/testing.md#bringing-your-own-harness) for what a runner
  other than Nupp's has to write
- [coverage](#coverage) for running the same suites under instrumentation
:::

### `test-runner`

```text [nupp test-runner --help]
Run test suites with the bundled runner

Usage:
  nupp test-runner [suite...] [options]

Options:
  --json          Write one JSON test report instead of progress text
  --verbose       Show output captured from passing tests
  --jobs N        Use N parallel workers
  --timings[=N]   Show every timing, or only the N slowest suites and cases
  --color[=WHEN]  Color output: always, never, or auto
  --no-color      Never color output
  -h, --help      Show this help
  --schema        Print the JSON Schema of --json output and exit

Discovers tests/*test.lua and tests/*test.nupp. Each suite returns a
table of test functions and may define beforeAll, afterAll, beforeEach, and
afterEach hooks. A suite name selects one or more files without their extension.
```

Run `nupp test` for the normal build-then-test path. `test-runner` is the
manifest command Nupp's templates select, and is useful directly when the
artifact under test is already current.

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
  --color[=WHEN]  When to color output: always, never, or auto (default)
  --no-color      Never color output; the same as --color=never
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

See [testing.md](../learn/projects/testing.md#coverage) for the report's contents and
for what a custom runner has to do.

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

The exit code is the task command's own. See
[tasks.md](../learn/projects/project-tasks.md) for declaring a task and for the build it runs
first.

### `doc`

```text [nupp doc --help]
Generate API documentation from source comments

Usage:
  nupp doc [site|markdown|json|both] [-o PATH] [--target NAME] [--title TITLE] [--all] [--format text|json] [path...]

Options:
  -o, --output PATH  Output file or directory
  --target NAME      Document a named manifest target
  --title TITLE      Documentation title
  --all              Include private declarations
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
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

See [doc.md](../learn/tooling/documentation.md) for the docblock tags it reads and for
configuring a documentation target.

### `fixpoint`

```text [nupp fixpoint --help]
Verify a byte-identical self-hosting rebuild

Usage:
  nupp fixpoint [--update-bootstrap] [--format text|json]
  nupp fixpoint --binary [--format text|json]

By default the compiler compiles itself twice, the two must agree,
and the tracked stage-zero bundle must match the verified compiler. Use
--update-bootstrap to refresh that bundle when it is intentionally stale.

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
  --color[=WHEN]      When to color output: always, never, or auto (default)
  --no-color          Never color output; the same as --color=never
  -h, --help          Show this help
```

The two stages are built into separate directories and compared file by file.
Run in Nupp's own repository:

```text [nupp fixpoint]
fixpoint ok: compiler rebuilds itself byte-identically
```

The tracked stage-zero bundle is held to the same claim. It is a compiler
artifact too, so `fixpoint` regenerates it and requires the committed
`bootstrap/nupp.lua` to match, which is what stops it retaining an old
declaration surface or an old lowering pass until something unrelated finally
forces a refresh. A bundle that has legitimately moved is stale rather than
wrong, and the failure says which command accepts it:

```text
nupp: tracked bootstrap is stale; run nupp fixpoint --update-bootstrap
```

`--update-bootstrap` writes the regenerated bundle instead of comparing it, and
is how an intentional bootstrap change lands. See
[build.md](../learn/projects/build.md#self-hosting) for what `selfHost` configures.

`--binary` names the target it stamped and the size the two runs agreed on. A
mismatch keeps both stages for inspection and exits 1. See
[distribution.md](distribution.md) for the payload format whose determinism
this verifies.

### `run`

```text [nupp run --help]
Compile and run a Nupp or Lua program

Usage:
  nupp run [--strict] [-O<n>] [--watch] [--profile[=MS]] [--profile-out PATH]
           [--jit-aborts[=PATH]] [--json] <file> [args...]

Options:
  --strict             Treat strict checker rules as errors
  -O0, -O1, -O2        Optimization level; ad-hoc builds default to -O0,
                       deliverable targets to -O2
  --remarks            Report what the optimizer did and what it declined to do
  --relax=GUARANTEE    Allow optimizations to change one named observable
                       guarantee
  -Zno-opt=CODE        Turn off one pass, named by its stable code, to bisect a
                       miscompile. Unstable: the spelling may change or go away
  --watch              Keep named function identities patchable at cooperative
                       poll points
  --profile[=MS]       Sample the program every MS milliseconds (default 10)
  --profile-out PATH   Where the samples go (default profile.out)
  --jit-aborts[=PATH]  Record where the JIT gave up (default jit-aborts.csv)
  --json               Write --jit-aborts as structured JSON instead of CSV
  --schema             Print the JSON Schema of --json output and exit
  --color[=WHEN]       When to color output: always, never, or auto (default)
  --no-color           Never color output; the same as --color=never
  -h, --help           Show this help

Program arguments are passed to the loaded chunk. Use '--' before a file name
that starts with a dash.

--profile writes collapsed-stack text: one line per stack, frames separated by
semicolons, then the sample count. speedscope.app, FlameGraph.pl and inferno
all read it directly. Frames are prefixed by the zone path that was open, so a
program that calls nupp.profile.zone reports itself in its own terms, and the leaf
carries the VM state most of its samples were in: N compiled, I interpreted,
C in a C function, G collecting, J compiling.

--jit-aborts answers the question a sampler cannot: whether the hot code was
compiled at all. It writes CSV, one row per place the compiler gave up, with a
blacklisted trace, permanently demoted to the interpreter, ranked first.

Both cover the program only: the session opens once the file has compiled and
closes when it returns, so the compiler's own work stays out of the report. A
program that fails still writes what was collected before it did. Each reports
a summary line on stderr.

--watch is development-only and always uses -O0. A long-running program calls
nupp.hotreload.poll() at a safe loop or request boundary.
The poll scans inputs, stages a valid changed-body patch, commits it,
and leaves the last good generation running after diagnostics or a required
restart. Programs that never return to such a boundary cannot reload
cooperatively.
```

The first non-option argument is the program; everything after it goes to the
program, options included. Arguments arrive as the chunk's varargs. A `.nupp`
file is compiled first; anything else is loaded as Lua directly.

```text [nupp run src/main.nupp]
Hello, world
```

#### Profiling a run

`--profile` and `--jit-aborts` take an attached value or none, never the next
argument, so a program name after either is still the program:

```bash
nupp run --profile=2 --profile-out hot.txt src/main.nupp
nupp run --jit-aborts src/main.nupp
```

The defaults are 10 ms, `profile.out`, and `jit-aborts.csv`. With `--json` the
abort default becomes `jit-aborts.json`, and every site carries both the raw VM
detail and its stable normalized reason identity.

::: seealso
- [profiling.md](../learn/performance/profiling.md) for reading a collapsed-stack profile
  and an abort report
- [performance.md](../learn/performance/index.md) for what to measure before
  changing anything
- [hot-reload.md](../learn/projects/hot-reload.md) for `--watch` and the poll points a
  program has to reach
:::

### `import-c`

```text [nupp import-c --help]
Generate typed Nupp bindings from a C header

Usage:
  nupp import-c [-o FILE] [-l NAME|--lib NAME] [--bridge-out FILE] [--inspect] [--format text|json] <header.h>

Options:
  -o FILE            Write the generated module to FILE
  -l, --lib NAME     Name the native library loaded by the bindings
  --bridge-out FILE  Emit C wrappers for eligible static inline functions
  --inspect          Report declaration dispositions without writing output
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help
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

```nupp [src/mini.nupp]
-- generated by nupp import-c from mini.h
-- committed and hand-editable: fix or extend freely, re-import
-- only when the header changes.

cdef struct mini_point
   x: number
   y: number
end

cdef function mini_length(point: const mini_point*?): number from "mini"
cdef function mini_version(): int32 from "mini"

return { mini_point = mini_point, mini_length = mini_length, mini_version = mini_version }
```

Every imported pointer is nullable unless you edit the generated module to add
a stronger reviewed contract. Fixed arrays retain their bounds, function
pointers remain typed in fields, parameters, results and pointer nesting, and a
typedef-named anonymous aggregate keeps its typedef identity. A declaration the
importer cannot type is left out with a readable `-- import-c: skipped` comment.

#### Inspecting a header

`--inspect` reports what each declaration would lower to and writes nothing,
neither the default module nor an `-o` path:

```bash
nupp import-c native/image.h --inspect
nupp import-c native/image.h --inspect --json
nupp import-c --schema
```

Text inspection prints `direct N, bridged N, skipped N`. JSON also carries the
warning strings and structured `dispositions`, where `direct`, `type-only`,
`bridge-inline`, `bridge-macro` and `skipped` distinguish the lowering
available. A skipped `static inline` function carries
`reason: "bridge-required"`.

#### Bridging static inline functions

A `static inline` definition has no symbol for FFI to load, so ask for wrappers
beside the editable module:

```bash
nupp import-c native/image.h \
  --lib build/lib/libimage.so \
  --bridge-out build/generated/image_bridge.c \
  -o src/native/image.nupp
```

On success, text mode prints the Nupp output path. JSON reports this shape:

```json
{
  "ok": true,
  "output": "src/native/image.nupp",
  "bridgeOutput": "build/generated/image_bridge.c",
  "warnings": [],
  "direct": 1,
  "bridged": 2,
  "skipped": 0,
  "dispositions": [
    {"name": "image_version", "kind": "direct"},
    {
      "name": "image_triple",
      "kind": "bridge-inline",
      "symbol": "__nupp_bridge_..."
    }
  ]
}
```

The command emits C but does not compile it. Build that file into the exact
library named by `--lib`, with the header's include paths, definitions and C
flags. Function-like macros cannot be typed on this command line; configure
their explicit signatures under a C dependency's `bindings.macros`. Combining
`--bridge-out` with `--inspect` previews which inline functions would bridge but
still writes no file.

See [c-interop.md](../learn/runtime/c-interop/index.md#header-only-functions) for complete
direct and bridge headers, a runnable header-only manifest, macro recipe types,
emitted C, ownership refinements, and supported limits.

### `migrate`

```text [nupp migrate --help]
Migrate typed foreign source into gradual Nupp

Usage:
  nupp migrate [--check] [--json] [--dialect auto|luacats|emmy|luadoc] FILE...

Options:
  --check            Print the migration plan without changing files
  --dialect DIALECT  Resolve ambiguous comment spellings for this migration
                     (default auto)
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help

The file extension selects the migrator. Annotated `.lua` becomes the
same module at `.g.nupp`; unsupported extensions are refused rather than guessed.

Without --check, the destination is written atomically and checked before the source
is removed. An existing destination is never replaced.
```

The annotated-Lua guide describes [always-on comment
ingestion](../learn/projects/integrations/luacats.md) and the shared command/editor migration
planner. `--check` reports the complete plan without writing or removing files.

### `export-c`

```text [nupp export-c --help]
Export canonical C declarations for Nupp structs

Usage:
  nupp export-c -o FILE [--target NAME] [--format text|json] <source.nupp>... <module.Declaration>...

Options:
  -o, --output FILE  Write the generated header to FILE
  --target NAME      Use a named manifest build target
  --format FORMAT    Output format: text (default) or json
  --json             Shorthand for --format json
  --text             Shorthand for --format text
  --schema           Print the JSON Schema of --json output and exit
  --color[=WHEN]     When to color output: always, never, or auto (default)
  --no-color         Never color output; the same as --color=never
  -h, --help         Show this help

The selected build target supplies layoutTarget. When it has none, the
compiler host is used. Header generation itself invokes no C compiler.
```

The command writes one target-specific header from selected exported structs
and `cdef` functions. It includes transitive layout dependencies, stable C
names, layout assertions, and the typed declarations used by native wrappers.
See [c-interop.md](../learn/runtime/c-interop/index.md#export-ordinary-structs-to-c) for
what a struct has to be for a header to be exportable from it.

### `rock`

```text [nupp rock --help]
Package and check typed LuaRocks libraries

Usage:
  nupp rock pack [rockspec]
  nupp rock test [rockspec]

Options:
  -h, --help  Show this help

A Nupp rock installs runtime Lua normally and carries matching public
declarations in its versioned `nupp/` directory. `pack` validates and builds that
layout; `test` installs the result into a fresh tree and checks a fresh consumer.
`nupp init lib <name>` writes a project already in that shape.
```

Starting one is [`init`](#init) with the built-in `lib` template:

```text [nupp init lib string-tools]
Created string-tools from built-in template lib

Next:
  cd string-tools
  nupp check
  nupp test
```

The rock keeps its hyphens and the module drops them, since the module name is
what `require` is given:

```text
 string-tools/
 ├── nupp.lua
 ├── string-tools-dev-1.rockspec
 ├── src/
 │   └── stringtools.nupp
 ├── nupp/
 │   └── stringtools.d.nupp
 └── tests/
     └── run.lua
```

See [LuaRocks](../learn/projects/integrations/luarocks.md) for the declaration's contents and for
publishing one.

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
  nupp lsp trace-check [options] <file> <line> <column>

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

`symbols` searches the workspace, or one document with `--file`. Each line is
the kind, the name, and where it was declared:

```text [nupp lsp symbols greet]
function greet src/greet.nupp:2:16
```

`trace-check` asks the same question for one function that
[`bc --check`](#bc) asks for a file, reporting the LuaJIT trace blockers and
risks the reason catalog knows about it:

```bash
nupp lsp trace-check --json src/greet.nupp 2 16
```

`nupp help lsp` shows a merged option list; each of `--include-declaration`,
`--file`, `--only` and `--write` belongs to exactly one operation. Every
operation answers `--schema` with its own.

::: seealso
- [lsp.md](../learn/tooling/language-server.md) for what the resident server supports
- [editors.md](../learn/tooling/editors.md) for wiring it into an editor
- [diagnostics.md](diagnostics.md) for the codes a quickfix answers
- [jit-trace-checking.md](../learn/performance/jit-trace-checking.md) for what
  `trace-check` reports
:::

### `help`

```text [nupp help --help]
Show general or command-specific help

Usage:
  nupp help [command]

Options:
  --color[=WHEN]  When to color output: always, never, or auto (default)
  --no-color      Never color output; the same as --color=never
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
  init             Create a project from a template
  ast              Dump a Nupp file's parsed syntax tree
  aot              Show what the @aot functions in a file compile to
  bc               Show the bytecode a Nupp file compiles to
  check            Type-check source without emitting Lua
  fmt              Format Nupp source
  build            Build source files or a configured project target
  backend          Run checked backend conformance suites
  clean            Remove build outputs configured in nupp.lua
  tasks            List or inspect project tasks from nupp.lua
  lints            List the lints and the level each runs at
  ownership-audit  List foreign pointer contracts and unsafe assertion sites
  explain          Describe a diagnostic code, with an example either way
  reference        List or print a focused Nupp reference chapter
  completions      Print a shell completion script
  test             Build and run the configured test command
  test-runner      Run test suites with the bundled runner
  coverage         Run tests and write a source coverage report
  task             Build, then run a named task from nupp.lua
  doc              Generate API documentation from source comments
  fixpoint         Verify a byte-identical self-hosting rebuild
  run              Compile and run a Nupp or Lua program
  import-c         Generate typed Nupp bindings from a C header
  migrate          Migrate typed foreign source into gradual Nupp
  export-c         Export canonical C declarations for Nupp structs
  rock             Package and check typed LuaRocks libraries
  lsp              Language-server and semantic source operations
  help             Show general or command-specific help

Run 'nupp help <command>' for command-specific options.
```
