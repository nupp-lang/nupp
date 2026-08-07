# Agent guidance

Nupp provides language-aware CLI tools for working on `.nupp` source. Run
commands from the repository root with `./bin/nupp`.

## Making changes

Do changes in a worktree. When finished, rebase the originating branch,
typically main into your worktree, resolve conflicts, and then FF merge.
When complete, delete the worktree. Leave no attribution in commits,
do not use conventional commits, use imperative language, and keep commit
lines under 72 characters.

## Language tools

Source positions are 1-based byte line and column numbers. Prefer `--json`
when consuming results programmatically.

- `./bin/nupp check --strict [FILE...]` type-checks source.
- `./bin/nupp check --json [FILE...]` returns structured diagnostics and
  available fixes. Read `help` and `related` before editing, and apply a whole
  titled fix rather than selecting individual edits from it.
- `./bin/nupp lsp inspect --json FILE LINE COLUMN` describes the symbol at a
  position.
- `./bin/nupp lsp definition --json FILE LINE COLUMN` finds its definition.
- `./bin/nupp lsp references --json FILE LINE COLUMN` finds semantic
  references; add `--include-declaration` when needed.
- `./bin/nupp lsp symbols --json [--file FILE] [PATTERN]` searches workspace or
  document symbols.
- `./bin/nupp lsp rename FILE LINE COLUMN NEW_NAME` previews a semantic rename.
  Add `--write` only when the requested change should be applied.
- `./bin/nupp lsp actions --json FILE LINE COLUMN` lists code actions. Use
  `--only quickfix` or `--only refactor` to narrow the results.

## Verification

- `./bin/nupp test` runs the test suite.
- `./bin/nupp fixpoint` verifies that the compiler rebuilds byte-identically.
