# `nupp` command

One executable holds every tool. `nupp help <command>` prints the same
reference each command's `-h` does.

```
 Command    Does
 ─────────  ────────────────────────────────────────────────
 ast        Dump a Nupp file's parsed syntax tree
 check      Type-check source without emitting Lua
 fmt        Format Nupp source
 build      Build source files or a configured project target
 clean      Remove build outputs configured in nupp.lua
 tasks      List or inspect project tasks from nupp.lua
 lints      List the lints and the level each runs at
 explain    Describe a diagnostic code, with an example either way
 reference  Print the language reference, or eject it as an agent skill
 test       Build and run the configured test command
 doc        Generate API documentation from source comments
 fixpoint   Verify a byte-identical self-hosting rebuild
 run        Compile and run a Nupp or Lua program
 import-c   Generate typed Nupp bindings from a C header
 lsp        Language-server and semantic source operations
 help       Show general or command-specific help
```

## Options every command takes

```
 Option           Means
 ───────────────  ─────────────────────────────────────────────
 --color[=WHEN]   always, never, or auto (the default)
 --no-color       The same as --color=never
 -h, --help       Show this help
```

`--color` never consumes the next argument. Write `--color=never`; a bare
`--color` means `always`. Passing both `--color` and `--no-color` is an error
rather than last-wins.

Colour is decided by `NO_COLOR`, then `CLICOLOR_FORCE`, then `TERM=dumb`, then
whether the stream is a terminal. JSON output is never coloured.

`nupp test` and the `nupp lsp` group forward their arguments, so they take only
`-h`.

## JSON and schemas

Every command that produces data takes `--format json` — spelled `--json` — and
also `--schema`, which prints the JSON Schema of that output:

```bash
nupp check --json
nupp check --schema
```

That covers `ast`, `check`, `fmt`, `build`, `clean`, `tasks`, `lints`,
`explain`, `test`, `fixpoint`, `import-c`, and every `lsp` operation. `doc` and
`run` produce no structured result and take neither.

A test runs each command for real and validates its output against its own
`--schema`, so the schema cannot drift from what the command emits.

`--format`, `--json`, and `--text` share one setting; giving two of them is an
error. No option repeats unless it says so, and only `-Zno-opt` does.

## Exit codes

```
 Code  Means
 ────  ────────────────────────────────────────────────────────
 0     Success
 1     The work was attempted and failed
 2     Usage error: unknown option, wrong argument count, ...
```

A usage error prints `nupp: <message>` on stderr and points at
`nupp help <command>`.

## Command reference

### `check`

```
nupp check [--strict] [--target NAME] [--format text|json] [file...]
```

With no files, checks the default target from `nupp.lua`. `--strict` adds
unknown-variable errors, requires annotations on module exports, and enables
the `lossy-narrowing` lint. `--target` cannot be combined with explicit files.

### `build`

```
nupp build [--strict] [-O<n>] [--target NAME] [--out-dir DIR]
nupp build [--strict] [-O<n>] [-o DIR] <file...>
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

`--json` reports the diagnostics, the target, and every path written, so one
call says both what failed and what landed.

See [the build system](build.md).

### `run`

```
nupp run [--strict] [-O<n>] [--profile[=MS]] [--profile-out PATH]
         [--jit-aborts[=PATH]] <file> [args...]
```

The first non-option argument is the program; everything after it goes to the
program, options included. Arguments arrive as the chunk's varargs.

`--profile` and `--jit-aborts` take an attached value or none —
`--profile=2`, not `--profile 2`. Defaults are 10 ms and `profile.out`, and
`jit-aborts.csv`. See [profiling](profiling.md).

A `.nupp` file is compiled first; anything else is loaded as Lua directly.

### `fmt`

```
nupp fmt [-w|--write] [--check] [file...]
```

See [the formatter](fmt.md).

### `test`

```
nupp test [args...]
```

Extra arguments are appended to `test.argv` from `nupp.lua`. The CLI does not
parse them; use `--` before an argument named `--help`. See
[testing](testing.md).

### `lints`

```
nupp lints
```

Prints each lint's name, category, effective level, and summary, marking any
the project has moved. The text table has no code column; `--json` includes
`code`, `default`, and `moved`. See [lints](../lints.md).

### `explain`

```
nupp explain <CODE>
```

Prints the rule behind a diagnostic code, a program that reports it, the same
program corrected, related codes, and a documentation reference.

```bash
nupp explain NUPP2119
```

### `reference`

```
nupp reference [--format markdown|skill|json] [-o PATH]
```

Prints the whole language: every construct, the shortest program that uses it,
and the diagnostic codes that report getting it wrong. It is generated from the
compiler, so it cannot describe a construct the compiler does not have.

Around four thousand tokens, which is small enough to put in a prompt whole:

```bash
nupp reference > docs/reference.md
nupp reference --format skill -o .claude/skills/nupp/SKILL.md
```

The [language reference](../reference.md) on this site is its committed output,
and a test fails if the two drift.

### `tasks` and `clean`

```
nupp tasks [name] [--format text|json]
nupp clean [--target NAME] [--dry-run]
```

`tasks` lists the manifest's build targets, the configured test action, and the
self-host action, marking the default. Naming one prints its effective
configuration including inherited defaults.

`clean` removes configured output directories. It rejects absolute paths,
parent traversal, and the project root before removing anything. `--dry-run`
prints what it would remove.

### `doc`

```
nupp doc [site|markdown|both] [-o PATH] [--title TITLE] [--all] [path...]
```

The format is a positional word rather than a flag; `md` is accepted for
`markdown`. With none, the manifest's configured format is used, and `site` if
it has none. See [the documentation generator](doc.md).

### `import-c`

```
nupp import-c [-o FILE] [-l NAME|--lib NAME] <header.h>
```

Writes a committed, hand-editable module of `cdef` declarations. Without `-o`
it writes `<header basename>.nupp` into the current directory. See
[C interop](../c-interop.md).

### `ast`

```
nupp ast [--format text|json] <file>
```

Dumps the parsed tree. It prints the tree even when parsing fails — a recovered
tree is intentional output — and then exits 1.

### `fixpoint`

```
nupp fixpoint [--update-bootstrap]
nupp fixpoint --binary
```

Builds a stage-1 compiler, has it build stage 2, and compares them byte for
byte. `--binary` does the same for the packaged binary. See
[distribution](../distribution.md).

### `lsp`

```
nupp lsp [root]
nupp lsp serve [root]
nupp lsp inspect     [options] <file> <line> <column>
nupp lsp definition  [options] <file> <line> <column>
nupp lsp references  [options] [--include-declaration] <file> <line> <column>
nupp lsp symbols     [options] [--file FILE] [pattern]
nupp lsp rename      [options] [-w|--write] <file> <line> <column> <new-name>
nupp lsp actions     [options] [--only quickfix|refactor] <file> <line> <column>
```

With no operation, or with only a root, `nupp lsp` runs the language server
over stdio. Positions are 1-based byte line and column numbers, matching
compiler diagnostics. See [the language server](lsp.md).

`nupp help lsp` shows a merged option list; each of `--include-declaration`,
`--file`, `--only`, and `--write` belongs to exactly one operation.
