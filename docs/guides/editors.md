# Editors

The repository carries a Visual Studio Code extension and a Claude Code plugin,
and both are clients for one server that any other LSP client can start the
same way:

```bash
nupp lsp serve
```

See [lsp.md](lsp.md#lsp-features) for the capabilities that server answers.

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

### Settings

Four settings configure the process, and all four restart the server when
changed:

- `nupp.serverPath`: empty, which resolves to this repository's `bin/nupp` when
  the workspace is the checkout and to `nupp` on `PATH` otherwise.
- `nupp.serverArgs`: `["lsp", "serve", "${workspaceFolder}"]`.
- `nupp.serverCwd`: `${workspaceFolder}`.
- `nupp.serverEnvironment`: `{}`.

All four expand `${workspaceFolder}` and `${env:NAME}`, and arguments are
passed without shell interpretation. The extension runs one client per
workspace folder, each watching `**/*.nupp` so an edit from Git, a generator,
or another editor invalidates the incremental graph.

### Highlighting without the server

The TextMate grammar covers the shebang line, `---` doc comments as their own
scope, with nested ```` ```nupp ```` fences inside them highlighted as Nupp,
block comments, every string form including backtick interpolation with `${...}`
regions, numerics with `_` separators and `ULL`/`i` suffixes, and the
declaration forms. It is hand-scoped rather than generated from the ABNF in
[grammar.md](../reference/grammar.md), because ABNF defines syntax and a
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
```

::: seealso
- [lsp.md](lsp.md#command-line-operations) for every operation and the
  positions it takes
- [tooling.md](../getting-started/tooling.md) for the rest of the tools a
  project uses day to day
- [fmt.md](fmt.md) for the formatter behind the editor's format command
:::
