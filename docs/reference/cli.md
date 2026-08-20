# `nupp` command

One executable holds every tool. Each command below carries its own `--help`,
which is the text `nupp help <command>` prints, and the output it writes when
it has any.

- [`ast`](#ast): dump a Nupp file's parsed syntax tree
- [`aot`](#aot): show what the `@aot` functions in a file compile to
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
- [`export-c`](#export-c): export canonical C declarations for Nupp structs
- [`rock`](#rock): create and package typed LuaRocks libraries
- [`lsp`](#lsp): language-server and semantic source operations
- [`help`](#help): show general or command-specific help

```bash
nupp check
nupp build
nupp run src/main.nupp
```

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
`ownership-audit`, `explain`, `test`, `coverage`, `fixpoint`, `import-c`,
`export-c`, and every `lsp` operation. `doc` reports what it wrote; `run`,
`task`, `rock` and `completions` produce no structured result and take neither.

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

### `aot`

```text [nupp aot --help]
Show what the @aot functions in a file compile to

Usage:
  nupp aot [--emit ir|c|binding] [--check] [--target TRIPLE] [--features TIER] <file>

Production `nupp build` still emits the ordinary Lua body; this reports what the ahead-of-time backend would produce for the file.

Options:
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --emit ARTIFACT  Print one artifact: ir, c, or binding
  --check          Exit non-zero for a map loop that wanted lanes and ran one
                   iteration at a time
  --target TRIPLE  The target triple to compile for; the host's by default
  --features TIER  The CPU feature tier to promise: baseline, avx2, or neon
  --library PATH   Where the compiled object will be found, for the generated
                   binding
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help
```

The bare command says what the backend decided for every `@aot` function in the
file: how much arithmetic each loop does per byte it touches, and which gang it
was lowered to, if any.

```text [nupp aot bench/kernel-subset-spike/mandelbrot.nupp]
bench/kernel-subset-spike/mandelbrot.nupp: mandelbrot, 5.19 operations per byte (83 over 16), f64x4, 4 lanes
```

`--emit` prints one artifact. `ir` is the verified IR with the lane body beside
the scalar one it was rewritten from, `c` is the generated C, and `binding` is
the Nupp module that stands in front of it.

`--check` is for the same category `nupp bc --check` covers: a performance
property no answer depends on, which an ordinary edit can quietly take away. It
distinguishes three outcomes and fails on one. A loop that lowered is fine. A
loop that declined is fine too, whether because the arithmetic per byte says
lanes will not pay or because the source wrote `@aot(lanes = false)`. A loop
that wanted lanes and ran one iteration at a time exits 1, naming the construct
that stopped it.

```text [nupp aot --check src/particles.nupp]
nupp: advance ran one iteration at a time
  src/particles.nupp:39:5: aot: a nested numeric loop is not lane-controlled yet
```

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
file that was written rather than the file that was generated. The runtime
preamble all lands on line 1 and is folded away; `--prologue` keeps it.

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

`--check` reads the bytecode for work LuaJIT cannot record inside a loop, and
exits 1 when it finds any. Building a function is the usual cause: LuaJIT has
no recording for it, so the loop holding one aborts recording, is blacklisted
after enough attempts, and then runs interpreted however hot it gets. Nothing
else reports that, because the program's answers do not change.

It reads further than the two source lints, which see what was written rather
than what was generated: [`loop-invariant-closure`](lints.md) reports a
function that could be lifted out of its loop unchanged, and
[`jit-loop-closure`](lints.md), off until a project asks for it, reports one
that reads the iteration and so cannot be. Neither says anything about a closure
the compiler's own lowerings put in a loop, which is what this reads.

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

#### Where a template comes from

A `TEMPLATE` argument is read lexically, never by looking at the filesystem: the
same spelling means the same thing in every directory.

```text
 Spelling                     Resolves to
 ───────────────────────────  ──────────────────────────────────────────
 app                          a built-in template of that name
 ./x, ../x, /x, ~/x           a directory on disk
 owner/repo                   https://github.com/owner/repo
 owner/repo@v1.2.0            the same, at that revision
 owner/repo/games/topdown     the games/topdown directory of that repository
 https://…, git@…             used as given, with --rev for a revision
```

`--from PATH` forces a directory, for the case where a local path is spelled
like a repository name. A name with no slash that matches no built-in is
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

`name`, `moduleName` (the name in luacase, with hyphens and underscores removed)
and `directory` are always defined. A template may declare `name` to constrain
it, but its value comes from `--name` or the directory. Anything else is
declared here or it cannot be used, and is supplied with `--set KEY=VALUE`.

`raw` names globs copied byte for byte, for assets that are not text. `after`
names post-init steps from a closed set: `git`, `check`, `build` and `test`.

#### Fetched template limits

A repository template is cloned with git, reported by the commit it resolved to,
and confirmed before anything is written. A run with nothing at the terminal to
answer is refused rather than assumed; `--yes` accepts it unread.

Its `after` steps are reduced to `git init`. This is not caution about
`template.lua`, which is loaded in a sandbox with no `io`, `os`, `require` or
`load` in it. It is that `check`, `build` and `test` all load the `nupp.lua`
that was just scaffolded, and a manifest is ordinary unrestricted Lua: a
template allowed to ask for `check` could put its payload in the manifest
instead, and the sandbox would be decoration. Read the project, then run those
yourself.

### `check`

```text [nupp check --help]
Type-check source without emitting Lua

Usage:
  nupp check [--strict] [--target NAME] [--platform NAME|all] [--format text|json] [file...]

Options:
  --strict         Treat strict checker rules as errors
  --target NAME    Check a named manifest target
  --platform NAME  Check one configured binary platform, or all
  --format FORMAT  Output format: text (default) or json
  --json           Shorthand for --format json
  --text           Shorthand for --format text
  --schema         Print the JSON Schema of --json output and exit
  --color[=WHEN]   When to color output: always, never, or auto (default)
  --no-color       Never color output; the same as --color=never
  -h, --help       Show this help

With no files, checks the default target from nupp.lua. Also reports a `timing` object naming how many modules were reused from the cache versus rechecked, and which modules cost the most of the wall-clock time either way -- see docs/reference/diagnostics.md.
```

A file's extension decides the floor it is held to, with `.nupp` strict and
`.g.nupp`, `.d.nupp` and `.lua` gradual. `--strict` overrides that, holding
every file to the strict floor whatever it is called: unknown-variable errors,
and annotations required on module exports. `--target` cannot be combined with
explicit files.

A clean project writes nothing and exits 0. With
`local shout: number = greet("world")` added to `src/greet.nupp`:

```text [nupp check]
src/greet.nupp:6:23: error: NUPP2001: cannot initialize shout: string is not a number
 6 | local shout: number = greet("world")
   |                       ^~~~~
```

Every diagnostic carries the position, the code, the severity, and the
`docs` anchor that [`nupp explain`](#explain) and the reference share:

```json [nupp check --json]
{
  "ok": false,
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
edits that apply it. See [diagnostics.md](diagnostics.md) for what a
diagnostic holds and [lints.md](lints.md) for the levels.

`ok` says whether the check ran and found nothing wrong. It is false both for a
project that reported an error and for a run that never got as far as checking:
a manifest the command could not use ends the run before any file is read, and
an empty `diagnostics` cannot tell that apart from a clean project on its own.

With no files named, `--json` also carries a `timing` object -- the same shape
`build` publishes, minus the parts only generation charges time to -- so a
repeat check that feels slow can be read rather than waited out:

```json [nupp check --json]
{
  "ok": true,
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

`compiledModules` is how many modules this run actually reparsed and
rechecked; `reusedModules` is how many it answered from the last run's cache
without looking at again. `compiledModules = 0` is the answer to trust that
nothing was redone. `slowest` ranks modules by wall-clock time spent either
way, longest first -- confirming a reused module's cache entry is still valid
costs time too, just less of it, so a check that stayed slow on an unchanged
project still points at a module to look at rather than asking to be
trusted. `timing` is absent when a diagnostic stopped the check, the same as
it is for `build`, since a run that did not finish has no account of itself
to give.

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

See [the formatter](../guides/fmt.md) for the rules it applies.

### `build`

```text [nupp build --help]
Build source files or a configured project target

Usage:
  nupp build [--strict] [-O<n>] [--target NAME] [--platform NAME|all] [--out-dir DIR] [-q] [--format text|json]
  nupp build [--strict] [-O<n>] [-o DIR] [-q] [--format text|json] <file...>

Options:
  --target NAME      Build a named manifest target
  --platform NAME    Build one configured binary platform, or all
  --out-dir DIR      Override the manifest target's output directory
  -o DIR             Output directory for explicit source-file builds
  --strict           Treat strict checker rules as errors
  -O0, -O1, -O2      Optimization level (default -O0, which rewrites nothing)
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
mixing artifacts compiled at two different levels. See docs/neps/0011-performance-and-the-jit.md.

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

`-o` is for explicit source-file builds; `--out-dir` overrides a manifest
target's output directory. They are different options, and using one in the
other's mode is an error.

`-O0` is the default and performs no rewrite at all. `-O1` and `-O2` currently
run the same two passes. `--remarks` reports what the optimizer did and what
it declined to do; `-Zno-opt=CODE` turns off one pass by its stable code, and
the `-Z` prefix marks that spelling as unstable. Repeatable
`--relax=GUARANTEE` flags opt in to a named observable tradeoff; no current
pass requires one.

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

`--json` says both what failed and what landed, and carries the same timing as
data rather than as a report:

```json [nupp build --json]
{
  "ok": true,
  "target": "app",
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

See [the build system](../guides/build.md).

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

See [tasks.md](../guides/tasks.md) for the manifest shape, and [`task`](#task)
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

See [lints.md](lints.md) for moving one and for waving one away.

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

See [ownership.md](../type-system/ownership.md) for the contracts this
enumerates.

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

Reference: docs/concepts/declarations.md#diagnostics
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
  nupp reference --section docs/concepts/declarations.md#modules
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

A chapter is thousands of words -- `language` is over thirteen thousand -- and
a reader who knows which construct they are asking about should not have to
load the rest of it. `--section` prints one:

```bash
nupp reference --section types
nupp reference --section affine-resources
```

A section is named by its heading, or by any `docs` pointer at it, so the anchor
a diagnostic already carries is a thing that can be followed: `--section
docs/concepts/declarations.md#modules` prints the same section as `--section
modules`. `--for CODE` goes the other way and prints whichever sections explain
a diagnostic, which is what a reader holding one actually has:

```bash
nupp reference --for NUPP2004
```

A code that no section covers says so and points at `nupp explain`, which is
where every code answers. The catalogue above names every section, so nothing
has to be guessed at.

The chapters are generated from the compiler, so they cannot describe a
construct the compiler does not have. Their examples compile in the test suite,
and every cited diagnostic code must resolve through `nupp explain`.

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
See [testing](../guides/testing.md).

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

See [testing](../guides/testing.md#coverage) for the report's contents and for
what a custom runner has to do.

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

The exit code is the task command's own. See [tasks.md](../guides/tasks.md).

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

See [the documentation generator](../guides/doc.md).

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
  --color[=WHEN]      When to color output: always, never, or auto (default)
  --no-color          Never color output; the same as --color=never
  -h, --help          Show this help
```

The two stages are built into separate directories and compared file by file.
Run in Nupp's own repository:

```text [nupp fixpoint]
fixpoint ok: compiler rebuilds itself byte-identically
```

`--binary` names the target it stamped and the size the two runs agreed on. A
mismatch keeps both stages for inspection and exits 1. See
[distribution](distribution.md).

### `run`

```text [nupp run --help]
Compile and run a Nupp or Lua program

Usage:
  nupp run [--strict] [-O<n>] [--watch] [--profile[=MS]] [--profile-out PATH]
           [--jit-aborts[=PATH]] [--json] <file> [args...]

Options:
  --strict             Treat strict checker rules as errors
  -O0, -O1, -O2        Optimization level (default -O0, which rewrites nothing)
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

`--profile` and `--jit-aborts` take an attached value or none, so `--profile=2`
rather than `--profile 2`. The defaults are 10 ms, `profile.out`, and
`jit-aborts.csv`. See [profiling](../guides/profiling.md).
With `--json`, the default is `jit-aborts.json` and every site carries both the
raw VM detail and its stable normalized reason identity.

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

Inspect a header before writing anything:

```bash
nupp import-c native/image.h --inspect
nupp import-c native/image.h --inspect --json
nupp import-c --schema
```

Text inspection prints `direct N, bridged N, skipped N`. JSON also carries the
warning strings and structured `dispositions`; a skipped `static inline`
function, for example, has `reason: "bridge-required"`. `direct`, `type-only`,
`bridge-inline`, `bridge-macro`, and `skipped` distinguish the available
lowering. Inspection writes neither the default module nor an `-o` path.

A `static inline` definition has no symbol for FFI to load. Ask the standalone
command to emit wrappers beside the editable module:

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

See [C interop](../concepts/c-interop.md#header-only-functions) for complete
direct and bridge headers, a runnable header-only manifest, macro recipe types,
emitted C, ownership refinements, and supported limits.

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
See [C interop](../concepts/c-interop.md).

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

See [Working with LuaRocks](../guides/luarocks.md) for the declaration's
contents and for publishing one.

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

`nupp help lsp` shows a merged option list; each of `--include-declaration`,
`--file`, `--only`, and `--write` belongs to exactly one operation. Every
operation answers `--schema` with its own. See
[the language server](../guides/lsp.md).

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
  export-c         Export canonical C declarations for Nupp structs
  rock             Create and package typed LuaRocks libraries
  lsp              Language-server and semantic source operations
  help             Show general or command-specific help

Run 'nupp help <command>' for command-specific options.
```
