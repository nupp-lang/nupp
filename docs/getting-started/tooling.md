---
order: 200
---

# Tooling

One executable holds the checker, formatter, build system, documentation
generator, language server, profiler, and C importer. They share a parse, a
type checker, and an incremental engine, so the editor and the build agree
about what your code means.

```bash
nupp check
nupp build
nupp test
```

Every command takes `-h`, and `nupp help <command>` prints the same reference.

| Command | Purpose | More |
| --- | --- | --- |
| `check` | Type-check the project | [cli.md](../reference/cli.md) |
| `build` | Compile to Lua, incrementally | [build.md](../guides/build.md) |
| `run` | Compile and run; profile behind a flag | [profiling.md](../guides/profiling.md) |
| `bc --check` | Find deterministic LuaJIT recorder blockers | [jit-trace-checking.md](../guides/jit-trace-checking.md) |
| `test` | Build, then run the configured suite | [testing.md](../guides/testing.md) |
| `fmt` | Format; fixed style | [fmt.md](../guides/fmt.md) |
| `doc` | Generate an API site from the parse | [doc.md](../guides/doc.md) |
| `lsp` | Language server, and CLI equivalents | [lsp.md](../guides/lsp.md) |
| `explain` | Describe a diagnostic code | [diagnostics.md](../reference/diagnostics.md) |
| `lints` | List the lints and their levels | [lints.md](../reference/lints.md) |
| `import-c` | Turn a C header into declarations | [c-interop.md](../concepts/c-interop.md) |
| `rock` | Create and package typed Lua rocks | [luarocks.md](../guides/luarocks.md) |
| `tasks` | List or inspect manifest targets | [build.md](../guides/build.md) |
| `clean` | Remove configured build outputs | [build.md](../guides/build.md) |
| `fixpoint` | Verify the self-hosting rebuild | [distribution.md](../reference/distribution.md) |
| `ast` | Dump a parsed syntax tree | [cli.md](../reference/cli.md) |

## Checking

```bash
nupp check              # the whole configured project
nupp check --strict     # hold every file to the strict floor, .g.nupp included
nupp check src/app.nupp # one file
```

Check the whole project rather than the file you changed. That is what lets Nupp
verify module boundaries, ownership contracts, and project lint settings
together. See [gradual typing](../concepts/strictness.md) for what the strict
floor adds, and [modules](../concepts/modules.md) for the boundaries it checks.

## Machine-readable output

Every command that produces data takes `--format json` (written `--json`), and
each one also takes `--schema`, which prints the JSON Schema of that output. A
test runs each command for real and validates its output against its own schema,
so the two cannot drift.

```bash
nupp check --json
nupp check --schema
nupp build --json      # diagnostics, the target, and every path written
nupp test --json       # a record per test: name, status, duration, failure
```

Color is off whenever output is not a terminal, so a pipe never carries escape
codes. `--color=always` forces it back on; `NO_COLOR`, `CLICOLOR_FORCE`, and
`TERM=dumb` are honored. See [JSON and
schemas](../reference/cli.md#json-and-schemas) for the options every command
shares.

## Diagnostics

Every diagnostic has a stable code, a source span, and often a
machine-applicable fix. `nupp explain` turns the code into the rule, a program
that reports it, and the same program corrected:

```bash
nupp explain NUPP2119
```

See [diagnostics](../reference/diagnostics.md) for the format and the JSON
shape, and [lints](../reference/lints.md) for the ones a project can configure
or suppress.

## Editors

`nupp lsp serve` speaks LSP over stdio. It provides diagnostics, hover,
completion, signature help, go-to-definition, references, rename, document and
workspace symbols, semantic tokens, folding, selection ranges, formatting, and
the checker's code-action quick fixes.

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

::: seealso
- [editors.md](../guides/editors.md) for the VS Code extension and the Claude
  Code plugin in `editors/`
- [lsp.md](../guides/lsp.md#lsp-features) for every capability the server
  advertises
- [lsp.md](../guides/lsp.md#command-line-operations) for the same operations
  from a script
:::

## Formatting

```bash
nupp fmt              # list what is unformatted, project-wide
nupp fmt --write      # rewrite in place
nupp fmt --check      # report only; exits 1 if anything is unformatted
nupp fmt src/x.nupp   # format one file to stdout
```

There is nothing to configure. The formatter guarantees the output re-lexes to
an identical token sequence, so it cannot change a quote style, a numeric
literal, or a trailing comma even if it wanted to. See
[formatter](../guides/fmt.md#formatter-modes) for what each way of calling it
does with its result.

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
changes. See [build system](../guides/build.md) for the manifest, targets,
caching, and native dependencies.

## Profiling

```bash
nupp run --profile app.nupp      # where the time went   -> profile.out
nupp run --jit-aborts app.nupp   # what the JIT refused  -> jit-aborts.csv
```

The second answers a question a sampling profiler structurally cannot: whether
the hot code was compiled at all.

::: seealso
- [jit-trace-checking.md](../guides/jit-trace-checking.md) for every static and
  runtime reason a trace aborts, with its repair
- [profiling.md](../guides/profiling.md) for both measurement channels and for
  zones
- [performance.md](../guides/performance.md) for `-O` levels and remarks
:::

## Hot reload

```bash
nupp run --watch app.nupp
```

At a safe loop boundary, call `nupp.hotreload.poll()`. Compatible named-function
body edits commit without recreating application state; broken or structural
edits leave the last good generation running. Watch is an `-O0` development
target, not a release-performance build. See [hot
reload](../guides/hot-reload.md#accepted-edits) for which edits commit and which
need a restart.

## Documentation

```bash
nupp doc site -o build/docs src
nupp doc markdown -o docs/api.md src
```

`nupp doc` reads the parser's lossless CST and never invokes the checker or the
code generator, so a documentation build costs parsing and rendering alone. This
site is built by it. See [documentation
generator](../guides/doc.md) for the doc-comment tags, the public surface rule,
and how handwritten pages join the generated ones.
