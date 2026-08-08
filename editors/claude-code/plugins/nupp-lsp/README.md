# nupp-lsp

The Nupp language server for Claude Code, so its LSP tool can read `.nupp`
files the way it reads any other language.

## Supported extensions

`.nupp`

## Requirements

`nupp` has to be on `PATH`, the way `lua-lsp` needs `lua-language-server` and
`gopls-lsp` needs `gopls`. From a checkout:

```bash
ln -s "$PWD/bin/nupp" /usr/local/bin/nupp    # or anywhere on PATH
```

The server is started as `nupp lsp serve` with the workspace as its working
directory, so it takes the project root from there and reads `nupp.lua` for the
`include` roots. Nothing else is configured.

## What Claude Code gets

Of the operations Claude Code's LSP tool offers, the server answers
`goToDefinition`, `findReferences`, `hover`, `documentSymbol`, and
`workspaceSymbol`. References and workspace symbols run over the whole project
rather than the open documents.

`goToImplementation` and the call hierarchy have no handler and return a
method-not-found error; see
[plan.md](../../../../plans/plan.md#lsp-follow-up). The server also serves
diagnostics, completion, signature help, rename, semantic tokens, folding,
selection ranges, formatting, and code actions, which that tool does not expose
but an editor client does — see [editors/vscode](../../../vscode).

## Installing

From the repository root:

```bash
claude plugin marketplace add ./editors/claude-code
claude plugin install nupp-lsp@nupp
```

Restart Claude Code afterwards: the file-type-to-server table is built when a
session starts, so a newly installed server is not picked up by the session
that installed it.

To undo:

```bash
claude plugin uninstall nupp-lsp@nupp
claude plugin marketplace remove nupp
```
