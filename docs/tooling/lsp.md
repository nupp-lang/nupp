# Language server

```bash
nupp lsp serve [root]
```

LSP over stdio. `nupp lsp` with no arguments does the same thing rooted at the
current directory, and `nupp lsp <path>` is a legacy spelling kept for existing
editor clients.

The server drives the same checker and incremental engine the build does, so an
editor and `nupp check` agree about what your code means.

## LSP features

| Capability | Notes |
| --- | --- |
| `Diagnostics` | Push-based, republished on change |
| `Hover` | Signature, then the docblock |
| `Completion` | Members after . and :, plus scope and keywords |
| Signature help | One signature; no overloads exist |
| Go to definition | Single location |
| `References` | Honours includeDeclaration |
| `Rename` | With prepare support |
| Document symbols | Hierarchical, with children |
| Workspace symbols | Case-insensitive substring over the index |
| Semantic tokens | Full, delta, and range |
| Document highlight | Occurrences of the symbol under the cursor |
| Folding ranges | Any multi-line node |
| Selection ranges | The enclosing node chain |
| `Formatting` | Whole document and range |
| Code actions | Quick fixes and refactorings |

Document sync is full-text. Inlay hints, code lens, call hierarchy, type
hierarchy, and go-to-implementation have no handler; an unknown request gets
a `method not found` response.

## Cancellation and stale answers

The server reads its input while it is working, so news of a request can reach
it before that request is finished.

`$/cancelRequest` read before the request it names is dispatched answers that
request `RequestCancelled` (-32800) without doing the work. One read while the
request is being answered stops the work at the next point it offers: every
module checked and every file header read on the way to the answer is such a
point, as is each poll of an isolated comptime evaluation. Work abandoned that
way leaves nothing memoized, so the next request recomputes from where the
project actually stands.

A request is answered from a version of the document, and an edit that arrives
while the answer is being worked out replaces the text its positions are
measured against. That answer is discarded and the request is answered
`ContentModified` (-32801) instead, which is the client's cue to ask again
against the text it now has. An edit the server had already read when it took
the request up is not that: the client sent both, in that order, and the answer
it asked for is the one it gets.

`textDocument/publishDiagnostics` carries the `version` of the document its
diagnostics were found in, so an editor that has typed on since drops them
rather than showing them against text it no longer has.

## Workspace folders

A folder is a project. Each one a client opens is read under its own `nupp.lua`,
with its own lint levels, strictness, language mode and target, so a file is
checked the same way whichever window opened it and whichever folder the server
was launched against. A folder still searches its neighbours for modules, so a
`require` that crosses folders resolves as it always did.

Each folder has its own incremental graph, built the first time something asks
that folder a question. Buffers the editor has open are overlays in all of
them: a file open in one folder is the module another folder requires, and both
read what you are typing rather than what is saved.

Which folder answered travels with the answer: `$/nupp/inspect` names it in
`root`, and a `workspace/symbol` result carries the folder its declaration is
in as `data.root`.

## Diagnostics in an editor

Diagnostics carry `source: "nupp"`, a code, related information, and a `data`
bag holding `help`, `notes`, and the lint name. `help` and `notes` are also
appended to the message text so an editor that ignores `data` still shows them.

Severity maps `error` to Error, `warning` to Warning, and `note` to
Information.

One code is deliberately quieter in an editor than in a build:
`missing-require` (NUPP2120) is an error in a build and a warning here. A file
you are typing into is half-written by definition, and the `require` is usually
the next thing you add.

## Code actions

Quick fixes come from the checker, so an editor offers exactly what
`nupp check --json` reports in `fixes`. They are offered anywhere within the
token carrying the diagnostic rather than only at its first byte.

| Title | From |
| --- | --- |
| change to `name` | A misspelling, within edit distance |
| convert with `nupp.math.f32.narrow` | Establish a binary32 value |
| convert with `nupp.math.i32.wrap` | Establish a signed 32-bit integer |
| convert with `nupp.math.u32.wrap` | Establish an unsigned 32-bit integer |
| change the type to `number` / `integer` | Preserve an unestablished Lua value |
| `require("module")` | NUPP2120, one fix per candidate |
| use bound.name | The module is already required |
| require("m") and use m.name | It is not required yet |
| drop `local` / mark it local / global | NUPP2119 visibility |
| attach it to <moduleLocal> | NUPP2119, when a table is returned |

A spelling fix refuses on a tie rather than picking one. A missing require
offers one fix per candidate module rather than guessing between them.

## Command-line operations

Each runs the same in-process session, with no subprocess, which makes them
usable from a script or an agent.

```bash
nupp lsp inspect     --json FILE LINE COLUMN
nupp lsp definition  --json FILE LINE COLUMN
nupp lsp references  --json [--include-declaration] FILE LINE COLUMN
nupp lsp symbols     --json [--file FILE] [PATTERN]
nupp lsp rename            FILE LINE COLUMN NEW_NAME
nupp lsp actions     --json [--only quickfix|refactor] FILE LINE COLUMN
nupp lsp trace-check --json FILE LINE COLUMN
```

Every operation takes `--root DIR` (default `.`), the format group, and
`--schema`.

Positions are **1-based byte line and column numbers**, matching compiler
diagnostics. A column pointing into the middle of a multibyte character is an
error rather than a guess.

`rename` previews its project-wide edits and changes files only with
`--write`. It refuses a new name that is not an identifier or is a keyword, and
refuses a symbol not declared in a project file.

`--only refactor` selects the `refactor.rewrite` kind.

`trace-check` selects the smallest enclosing checked function and returns the
same normalized blocker and risk identities used by `@jit`, including resolved
callee paths. It reads the language server's unsaved document overlay, runs no
program, and does not add an annotation or persist a contract.

## Suggested workflow for an agent

1. `nupp check --json --strict`.
2. Apply a whole titled fix from `diagnostics[].fixes` when its title matches
   the intended repair, rather than selecting individual edits from it.
3. Read `related` before changing a cross-file declaration or an ownership
   transfer.
4. Use `nupp lsp inspect`, `definition`, and `references` when more semantic
   context is needed.
5. Re-check after each edit group, and `nupp test` before committing.
