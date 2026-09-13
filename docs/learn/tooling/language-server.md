---
order: 550
---

# Language server

`nupp lsp serve` speaks LSP over stdio and drives the same checker and
incremental engine a build does, so an editor and `nupp check` agree about what
your code means.

```bash
nupp lsp serve [root]
```

`nupp lsp` with no arguments serves the current directory, and `nupp lsp
<path>` is a legacy form kept for editor clients that already send it. See
[editors.md](editors.md) for the clients that start it.

## LSP features

| Capability | Notes |
| --- | --- |
| Diagnostics | Push-based, republished on change |
| Hover | Signature, then the doc comment |
| Completion | Members after `.` and `:`, plus scope and keywords |
| Signature help | One signature; no overloads exist |
| Go to definition | Single location |
| References | Honors `includeDeclaration` |
| Rename | With prepare support |
| Document symbols | Hierarchical, with children |
| Workspace symbols | Case-insensitive substring over the index |
| Semantic tokens | Full, delta, and range |
| Document highlight | Occurrences of the symbol under the cursor |
| Folding ranges | Any multi-line node |
| Selection ranges | The enclosing node chain |
| Formatting | Whole document and range |
| Code actions | Quick fixes and refactorings |
| Code lenses | One `Inspect` lens over every checked function, for a client that asked |
| Go to implementation | Registered service members |

Document sync is full text. Inlay hints, call hierarchy and type hierarchy have
no handler, and an unknown request is answered `method not found` (-32601).

## Cancellation

The server reads its input while it is working, so news of a request can reach
it before that request is finished. A `$/cancelRequest` read before the request
it names is dispatched answers that request `RequestCancelled` without doing
the work:

```json
{"jsonrpc": "2.0", "id": 7,
 "error": {"code": -32800, "message": "request cancelled"}}
```

One read while the request is being answered stops the work at the next point
it offers. Every module checked and every file header read on the way to the
answer is such a point, as is each poll of an isolated comptime evaluation.
Work abandoned that way leaves nothing memoized, so the next request recomputes
from where the project actually stands.

## Stale answers

A request is answered from a version of the document, and an edit that arrives
while the answer is being worked out replaces the text its positions are
measured against. That answer is discarded and the request is answered
`ContentModified` instead, which is the client's cue to ask again against the
text it now has:

```json
{"jsonrpc": "2.0", "id": 9,
 "error": {"code": -32801, "message": "document changed while answering"}}
```

An edit the server had already read when it took the request up is not that:
the client sent both, in that order, and the answer it asked for is the one it
gets. `textDocument/publishDiagnostics` carries the `version` of the document
its diagnostics were found in, so an editor that has typed on since drops them
rather than showing them against text it no longer has.

## Workspace folders

A project is a `nupp.lua`. Each one is read under its own manifest, with its own
dependencies, lint levels, strictness, language mode and target, so a file is
checked the same way whichever window opened it and whichever folder the server
was launched against. A project still searches its neighbors for modules, so a
`require` that crosses projects resolves as it always did. See
[modules.md](../language/modules.md) for how a module name maps to a file.

A folder the client opened is usually one project, and does not have to be. One
checkout can hold several. A workspace of packages does, and so does a template
beside the compiler that builds it. A file is read under the nearest `nupp.lua`
at or above it, stopping at the folder that owns it, so each of those projects
is read under its own manifest. A directory with no manifest of its own belongs
to the project above it.

Each project has its own incremental graph, built the first time something asks
that project a question. Buffers the editor has open are overlays in all of
them: a file open in one folder is the module another folder requires, and both
read what you are typing rather than what is saved.

Building one resolves the project's pinned [type
dependencies](../projects/integrations/luacats.md#pin-the-source), so a `kind = "types"`
tree an editor has never fetched is fetched once and the project types the way
its build does.

Which project answered travels with the answer. `$/nupp/inspect` names it in
`root`, and a `workspace/symbol` result carries the folder its declaration is
in as `data.root`:

```json
{"name": "greet", "kind": "function",
 "detail": "function(name: string): string",
 "root": "/home/you/app"}
```

## Diagnostics in an editor

Diagnostics carry `source: "nupp"`, a code, related information, and a `data`
bag holding `help`, `notes`, and the lint name:

```json
{"range": {"start": {"line": 3, "character": 10},
           "end": {"line": 3, "character": 15}},
 "severity": 1, "code": "NUPP2105", "source": "nupp",
 "message": "unknown variable \"gret\"\n\nhelp: use the suggested visible name",
 "data": {"help": "use the suggested visible name"}}
```

`help` and `notes` are appended to the message text as well, so an editor that
ignores `data` still shows them. Severity maps `error` to Error, `warning` to
Warning, and `note` to Information.

One diagnostic is deliberately quieter in an editor than in a build:
`missing-require` is an error in a build and a warning here. A file
you are typing into is half-written by definition, and the `require` is usually
the next thing you add. See [lints.md](../../reference/lints.md) for the levels a
project sets for the rest of them.

## Code actions

Quick fixes come from the checker, so an editor offers exactly what
`nupp check --json` reports in `fixes`. They are offered anywhere within the
token carrying the diagnostic rather than only at its first byte.

| Title | Reported by |
| --- | --- |
| ``change to `name` `` | a misspelled name within edit distance |
| ``convert with `nupp.math.f32.narrow` `` | establishing a binary32 value |
| ``convert with `nupp.math.i32.wrap` `` | establishing a signed 32-bit integer |
| ``convert with `nupp.math.u32.wrap` `` | establishing an unsigned 32-bit integer |
| ``change the type to `number` `` | preserving an unestablished Lua value |
| `require("module")` | an unbound module, one fix per candidate module |
| `use bound.name` | the module is already bound in this file |
| `require("m") and use m.name` | the module is not bound yet |
| ``drop `local` `` | a qualified name that also states visibility |
| `mark it local`, `mark it global` | a declaration with no visibility |
| `attach it to <moduleLocal>` | a declaration where the module returns a table |

A spelling fix refuses on a tie rather than picking one, and a missing require
offers one fix per candidate module rather than guessing between them.

## Compiled artifacts

What a file compiles to, answered for the buffer rather than for the file on
disk. Two requests, because the two questions cost different amounts:

| Request | Cost |
| --- | --- |
| `$/nupp/artifacts` | The check already done, so a client may ask per function |
| `$/nupp/artifact` | Lowers the buffer, so a client asks once something is opened |

A lens carries a command the *client* runs, so the server advertises
`codeLensProvider` only for a client whose `initializationOptions` name one:

```json
{"artifacts": {"inspectCommand": "nupp.inspectCompiledFunction"}}
```

A client that names none is offered no lenses, which is what keeps an editor on
an older extension from showing a button over every function that nothing it has
can run. The command on each lens is the one the client gave, so the server never
needs to know what any particular editor calls it.

`$/nupp/artifacts` takes a document and an optional position and answers with
the kinds available and the innermost function the position is in.
`$/nupp/artifact` takes a document, a `kind` and an optional `optLevel`, and
answers with the artifact or with why there is not one. The kinds the server can
produce are advertised under `capabilities.experimental.nuppArtifacts`, so a
client can tell what it may ask for without asking for it.

| Kind | Language | Mapping |
| --- | --- | --- |
| `lua` | `lua` | `line-identity` |
| `bytecode` | `nupp-bytecode` | `lines-collapsible` |

Generated Lua carries no table of mappings, because it does not need one: the
emitter holds the lowering to the source's own line numbering, which is what
makes a stack trace correct with no sourcemap, and `line-identity` says exactly
that. Generated line N is source line N, for every N.

A bytecode listing is a rendering rather than a lowering, so it carries one
entry per line that stands for source.

It is laid out *against* the file rather than beside it. The editor already has
the source in the next pane, so the listing does not repeat it: row N holds what
line N compiled to, and a line that compiled to nothing is blank. Bytecode order
is not source order -- a chunk builds each function with an `FNEW` attributed to
the line the function ends on and assigns it on the line it starts on -- so
instructions are gathered by the line they came from rather than left in the
order the interpreter will meet them. Program counters are printed, so execution
order is still there to be read.

A source line that compiled to several instructions keeps the first on its own
row and indents the rest beneath it, which is a folding region. Collapsed, every
source line is one row again and the two panes scroll together; that is what
`lines-collapsible` names, and a client opening one should fold it. The
generated preamble is not part of that shape at all -- it is attributed to line
1 only because it has nowhere else to go -- so it follows the file rather than
displacing it.

`nupp bc` keeps the older layout, which echoes each source line above the
instructions it produced and nests a function's body under the line that
declares it. A terminal has no second pane to lay anything against.

| Role | What that line is |
| --- | --- |
| `exact` | One instruction, at the line it was lowered from |
| `source` | The echoed source line |
| `derived` | A line about a span rather than a point: a function header |
| `synthetic` | The compiler's own: the folded runtime preamble |

Lines with no entry stand for nothing anyone wrote. A client synchronizing a
cursor reveals nothing for those rather than guessing.

An artifact that could not be produced answers `available: false` with an
`unavailable` reason and detail, rather than with an empty document. A file that
checks can still fail to lower, and which of those happened is the whole answer.

## Command-line operations

Every navigation and refactoring operation has a command-line form. Each runs
the same in-process session, with no subprocess, which is what makes them
usable from a script or an agent:

```bash
nupp lsp inspect     --json FILE LINE COLUMN
nupp lsp definition  --json FILE LINE COLUMN
nupp lsp references  --json [--include-declaration] FILE LINE COLUMN
nupp lsp symbols     --json [--file FILE] [PATTERN]
nupp lsp rename            FILE LINE COLUMN NEW_NAME
nupp lsp actions     --json [--only quickfix|refactor] FILE LINE COLUMN
nupp lsp trace-check --json FILE LINE COLUMN
nupp lsp artifacts   --json FILE LINE COLUMN
nupp lsp artifact    --json --kind lua|bytecode [-O 0|1|2] FILE
```

Every operation takes `--root DIR` (default `.`), the format group, and
`--schema`. Positions are 1-based byte line and column numbers, matching
compiler diagnostics, and a column pointing into the middle of a multibyte
character is an error rather than a guess.

`rename` previews its project-wide edits and changes files only with
`--write`. It refuses a new name that is not an identifier or is a keyword, and
refuses a symbol not declared in a project file. `--only refactor` selects the
`refactor.rewrite` kind.

`trace-check` selects the smallest enclosing checked function and returns the
same normalized blocker and risk identities used by `@jit`, including resolved
callee paths. It reads the language server's unsaved document overlay, runs no
program, and does not add an annotation or persist a contract.

`artifact` prints the artifact itself, so `nupp lsp artifact --kind lua FILE`
pipes generated Lua like any other command, and `--json` adds the mapping and
the metadata beside it. An artifact that could not be produced is a failure with
the reason on stderr. Both read the same overlay `trace-check` does, so an
editor and a terminal answer for the same bytes.

## Agent workflow

An agent editing Nupp reads the checker first and reaches for the semantic
operations only where a diagnostic does not say enough:

1. Run `nupp check --json --strict`.
2. Apply a whole titled fix from `diagnostics[].fixes` when its title matches
   the intended repair, rather than selecting individual edits from it.
3. Read `related` before changing a cross-file declaration or an ownership
   transfer.
4. Use `nupp lsp inspect`, `definition`, and `references` when more semantic
   context is needed.
5. Re-check after each edit group, and run `nupp test` before committing.

::: seealso
- [editors.md](editors.md) for the Visual Studio Code and Claude Code clients
  that start this server
- [cli.md](../../reference/cli.md#lsp) for every option and a worked example of
  each operation
- [diagnostics.md](../../reference/diagnostics.md) for the codes an editor shows
  and what each one means
- [jit-trace-checking.md](../performance/jit-trace-checking.md) for what `trace-check` reports
- [cli.md](../../reference/cli.md#bc) for `nupp bc`, which renders the same
  listing the `bytecode` artifact carries
:::
