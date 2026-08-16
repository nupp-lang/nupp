# Agent guidance

Nupp provides language-aware CLI tools for working on `.nupp` source. Run
commands from the repository root with `./bin/nupp`.

## Making changes

Do changes in a worktree. When finished, rebase the originating branch,
typically main into your worktree, resolve conflicts, and then FF merge.
When complete, delete the worktree. Leave no attribution in commits,
do not use conventional commits, use imperative language, and keep commit
lines under 72 characters.

### Worktree setup

Use the repository helper so a new worktree links the ignored `.rocks`
dependencies, seeds the content-validated compiler cache and test timings, and
reuses the repository-wide native Cargo target:

```sh
./scripts/worktree example-task /private/tmp/nupp-example-task main
```

Use task-specific branch and directory names. Never replace an existing
cache or `.rocks` path; inspect it instead. Run subsequent Nupp commands from
the task worktree. Removing the completed worktree removes its `.rocks`
symlink and local seeded caches, not the originating checkout's dependencies or
the repository-wide native cache.

## Responding to prompts

Answer directly and keep the bottom line up front. Do not label it explicitly
as "BLUF" or bottom line up front. Just say the answer, then give details.

## Language tools

Source positions are 1-based byte line and column numbers. Prefer `--json`
when consuming results programmatically; every command that takes it also
takes `--schema`, which prints the JSON Schema of that output. Colour is off
whenever output is not a terminal, so piped output never carries escapes.

- `./bin/nupp reference language` prints the whole language in about fifteen
  thousand tokens: every construct, a compiled example of each, and the codes that
  report misuse. Read it before writing `.nupp` if you have not already.
  `--format skill` ejects it as an agent skill.
- `./bin/nupp check [FILE...]` type-checks source. A `.nupp` file is checked
  strictly; `.g.nupp` opts a file out of the strict floor without giving up the
  typed syntax, and `.lua` is plain Lua the typed layer is refused in.
  `--strict` holds every file to the floor whatever it is called.
- `./bin/nupp check --json [FILE...]` returns structured diagnostics and
  available fixes. Read `help` and `related` before editing, and apply a whole
  titled fix rather than selecting individual edits from it.
- `./bin/nupp build --json [FILE...]` returns the same diagnostics alongside
  what the build wrote, so one call says both what failed and what landed.
- `./bin/nupp explain CODE [--json]` describes a diagnostic code: the rule, a
  program that reports it, and the same program corrected. Every diagnostic
  carries a `docs` anchor pointing at the same reference.
- `./bin/nupp bc [--check] FILE` prints the bytecode a file compiles to, beside
  the source line each instruction came from. `--check` marks work LuaJIT cannot
  record inside a loop and exits 1 for it: a loop that builds a function aborts
  trace recording and is blacklisted, so it runs interpreted however hot it
  gets, and nothing else reports that because the answers do not change. It
  reads bytecode rather than timing anything, so it needs no quiet machine and
  answers the same every run.
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

- `./bin/nupp test` runs the test suite. `--json` reports a record per test —
  name, status, duration, and the failure's message, file and line.
- CSS or styling-only changes do not require the test suite. Verify the
  affected generated site or assets instead.
- `./bin/nupp fixpoint` verifies that the compiler rebuilds byte-identically.

## Speed

Commands reuse what the last one worked out, so a check of an unchanged
project answers in about the time it takes to start. The cache lives in the
build directory, is plain data, and is never load-bearing: deleting it, or
finding it corrupt, costs one slow command and changes no answer. `nupp
clean` removes it with everything else.

This means a slow command is worth reading rather than waiting out. A check
that takes a second is one that had to redo the project, and the usual reason
is an edit to an exported type declaration — that invalidates every module,
where an edit to a function body invalidates one.

The first full test run in a helper-created worktree also starts with the
originating checkout's suite timings, so its parallel shards are balanced from
the outset. Run focused suites while editing and the full suite before
committing. Run `fixpoint` near completion when compiler sources changed; it is
a self-hosting verification, not part of the inner edit/check loop.
