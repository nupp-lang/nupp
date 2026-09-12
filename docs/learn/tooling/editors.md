---
order: 560
---

# Editors

The repository carries a Visual Studio Code extension and a Claude Code plugin,
and both are clients for one server that any other LSP client can start the
same way:

```bash
nupp lsp serve
```

See [lsp.md](language-server.md#lsp-features) for the capabilities that server answers.

## Visual Studio Code

The extension lives in `editors/vscode`. It contributes the `nupp` language for
`.nupp` files, a TextMate grammar for the no-server case, and a client for the
server.

To run it from a checkout:

```bash
cd editors/vscode
npm install
```

Then open the repository root in VS Code and run the **Run Nupp extension**
launch configuration. The development extension finds `bin/nupp` in the
workspace automatically. For other workspaces, install `nupp` on `PATH` or
point the extension at it.

### Inspecting compiled output

Every checked function carries an **Inspect** code lens, and the command palette
carries the same entries:

| Command | What opens |
| --- | --- |
| **Nupp: Inspect Compiled Output** | A pick of what is available here |
| **Nupp: Open Generated Lua** | The Lua this file erases to |
| **Nupp: Open Bytecode** | The folded listing `nupp bc` prints |
| **Nupp: Compare Generated Artifacts** | Two levels of one artifact, in a diff |

Artifacts open beside the source as ordinary read-only editors under the
`nupp-generated:` scheme, so search, folding, diff and every other editor
command keep working on them. They are made from the buffer rather than from the
file, so an unsaved edit is what you are reading.

Selecting in either view reveals the matching line in the other. For generated
Lua that is the line itself, because the emitter never changes a file's line
count; for a bytecode listing it is whichever line the server's mapping names,
and a line standing for compiler-owned work -- the runtime preamble -- reveals
nothing rather than pointing somewhere arbitrary.

The bytecode view does not repeat the source, because the source is in the pane
beside it. Row N is what line N compiled to, and it opens folded so that a line
compiling to several instructions still occupies one row and the two panes stay
in step. Expanding a row shows the rest of that line's instructions.

One lens per function rather than one per artifact kind is deliberate. Most
kinds do not apply to most functions, and a row of six buttons over every
function would be five dead links.

### Tests and coverage

The extension registers a test controller per workspace folder, listing the
suites `nupp test --list-suites` reports. Its **Coverage** profile runs `nupp
test --coverage` and publishes the result through VS Code's own coverage UI: the gutter
overlay, the hover counts, and the Test Coverage tree. Branches show both
outcomes separately, so a condition that ran a hundred times and never once went
the other way reads as half a branch rather than as a covered line.

Coverage is computed when a coverage run is asked for, not on every edit.

The gutter itself is behind VS Code's **Test: Toggle Inline Coverage** (`⌘; ⌘⇧I`),
which is a toggle with no state an extension can read, so the first coverage run
of a session offers it rather than flipping it blind.

### Settings

Five settings configure the extension. The four naming the process restart the
server when changed:

- `nupp.serverPath`: empty, which resolves to this repository's `bin/nupp` when
  the workspace is the checkout and to `nupp` on `PATH` otherwise.
- `nupp.serverArgs`: `["lsp", "serve", "${workspaceFolder}"]`.
- `nupp.serverCwd`: `${workspaceFolder}`.
- `nupp.serverEnvironment`: `{}`.
- `nupp.artifactOptimizationLevel`: `0`, the level generated artifacts are
  resolved at. Zero is the promise that nothing is rewritten.

The four naming the process expand `${workspaceFolder}` and `${env:NAME}`, and arguments are
passed without shell interpretation. The extension runs one client per
workspace folder, each watching `**/*.nupp` so an edit from Git, a generator,
or another editor invalidates the incremental graph.

### Highlighting without the server

The TextMate grammar covers the shebang line, `---` doc comments as their own
scope, with nested ```` ```nupp ```` fences inside them highlighted as Nupp,
block comments, every string form including backtick interpolation with `${...}`
regions, numerics with `_` separators and `ULL`/`i` suffixes, and the
declaration forms. It is hand-scoped rather than generated from the ABNF in
[grammar.md](../../reference/grammar.md), because ABNF defines syntax and a
grammar file defines editor scope intent.

Semantic highlighting from the server layers on top of it.

## Claude Code

`editors/claude-code` is a plugin marketplace registering the same server for
`.nupp`, so Claude Code's LSP tool reads the language rather than the text:

```bash
claude plugin marketplace add ./editors/claude-code
claude plugin install nupp-lsp@nupp
```

`nupp` has to be on `PATH`, and Claude Code has to be restarted afterwards,
because it builds its file-type-to-server table when a session starts.

## Other editors

Any LSP client works. Point it at `nupp lsp serve` over stdio for files with
the `.nupp` extension. The repository carries no Vim, Neovim, Emacs, Sublime,
Helix, or Zed configuration.

## Command-line forms

Every navigation and refactoring operation also runs from a shell, in the same
in-process session an editor gets, which is what makes them scriptable:

```bash
nupp lsp inspect --json src/app/main.nupp 12 9
nupp lsp artifact --kind lua src/app/main.nupp
```

::: seealso
- [lsp.md](language-server.md#command-line-operations) for every operation and the
  positions it takes
- [tooling.md](index.md) for the rest of the tools a
  project uses day to day
- [fmt.md](formatter.md) for the formatter behind the editor's format command
:::
