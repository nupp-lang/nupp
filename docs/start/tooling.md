# Tooling

One executable holds the checker, formatter, build system, documentation
generator, language server, profiler, and C importer. They share a parse, a
type checker, and an incremental engine, so the editor and the build agree
about what your code means.

```
 Command       What it does                            More
 ────────────  ──────────────────────────────────────  ─────────────────────
 check         Type-check the project                  cli.md
 build         Compile to Lua, incrementally           build.md
 run           Compile and run; profile behind a flag  profiling.md
 test          Build, then run the configured suite    testing.md
 fmt           Format; fixed style                     fmt.md
 doc           Generate an API site from the parse     doc.md
 lsp           Language server, and CLI equivalents    lsp.md
 explain       Describe a diagnostic code              ../diagnostics.md
 lints         List the lints and their levels         ../lints.md
 import-c      Turn a C header into declarations       ../c-interop.md
 tasks         List or inspect manifest targets        build.md
 clean         Remove configured build outputs         build.md
 fixpoint      Verify the self-hosting rebuild         ../distribution.md
 ast           Dump a parsed syntax tree               cli.md
```

Every command takes `-h`, and `nupp help <command>` prints the same reference.

## Checking

```bash
nupp check              # the whole configured project
nupp check --strict     # plus unknown variables and untyped exports
nupp check src/app.nupp # one file
```

Check the whole project rather than the file you changed. That is what lets
Nupp verify module boundaries, ownership contracts, and project lint settings
together.

## Machine-readable output

Every command that produces data takes `--format json` (spelled `--json`), and
each one also takes `--schema`, which prints the JSON Schema of that output. A
test runs each command for real and validates its output against its own
schema, so the two cannot drift.

```bash
nupp check --json
nupp check --schema
nupp build --json      # diagnostics, the target, and every path written
nupp test --json       # a record per test: name, status, duration, failure
```

Colour is off whenever output is not a terminal, so a pipe never carries escape
codes. `--color=always` forces it back on; `NO_COLOR`, `CLICOLOR_FORCE`, and
`TERM=dumb` are honoured.

## Diagnostics you can act on

Every diagnostic has a stable code, a source span, and often a
machine-applicable fix. `nupp explain` turns the code into the rule, a program
that reports it, and the same program corrected:

```bash
nupp explain NUPP2119
```

[Diagnostics](../diagnostics.md) describes the format and the JSON shape.
[Lints](../lints.md) covers the ones a project can configure or suppress.

## Editors

`nupp lsp serve` speaks LSP over stdio. It provides diagnostics, hover,
completion, signature help, go-to-definition, references, rename, document and
workspace symbols, semantic tokens, folding, selection ranges, formatting, and
code actions — the checker's own quick fixes plus `with` wrap and unwrap
refactorings.

The same operations are available without an editor, which is what makes them
usable from a script or an agent:

```bash
nupp lsp inspect --json FILE LINE COLUMN
nupp lsp definition --json FILE LINE COLUMN
nupp lsp references --json --include-declaration FILE LINE COLUMN
nupp lsp symbols --json [--file FILE] [PATTERN]
nupp lsp rename FILE LINE COLUMN NEW_NAME    # previews; --write applies
nupp lsp actions --json --only quickfix FILE LINE COLUMN
```

Positions are 1-based byte line and column numbers, matching the compiler's
diagnostics.

A VS Code extension and a Claude Code plugin live in `editors/`. See
[editors](../tooling/editors.md).

## Formatting

```bash
nupp fmt              # list what is unformatted, project-wide
nupp fmt --write      # rewrite in place
nupp fmt --check      # report only; exits 1 if anything is unformatted
nupp fmt src/x.nupp   # format one file to stdout
```

There is nothing to configure. The formatter guarantees the output re-lexes to
an identical token sequence, so it cannot change a quote style, a numeric
literal, or a trailing comma even if it wanted to.

## Building

```bash
nupp build                    # the default manifest target
nupp build --target docs      # a named target
nupp build -O2                # optimize
nupp tasks                    # what targets exist
nupp clean --dry-run          # what clean would remove
```

Builds are incremental across processes. A source edit rechecks and regenerates
that module; dependents are only invalidated when its exported interface
changes. [Build system](../tooling/build.md) covers the manifest, targets,
caching, and native dependencies.

## Profiling

```bash
nupp run --profile app.nupp      # where the time went   -> profile.out
nupp run --jit-aborts app.nupp   # what the JIT refused  -> jit-aborts.csv
```

The second answers a question a sampling profiler structurally cannot: whether
the hot code was compiled at all. [Profiling](../tooling/profiling.md) explains
both channels, and [optimization](../tooling/optimization.md) covers `-O`
levels and remarks.

## Documentation

```bash
nupp doc site -o build/docs src
nupp doc markdown -o docs/api.md src
```

`nupp doc` reads the parser's lossless CST and skips the checker entirely, so a
documentation build costs parsing and rendering alone. This site is built by
it. See [the documentation generator](../tooling/doc.md).
