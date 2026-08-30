# Agent guidance

Nupp provides language-aware CLI tools for working on `.nupp` source. Run
commands from the repository root with `./bin/nupp`.

## Making changes

Do changes in a worktree. When finished, rebase the originating branch,
typically main into your worktree, resolve conflicts, and then FF merge.
When complete, delete the worktree. Leave no attribution in commits,
do not use conventional commits, use imperative language, and keep commit
lines under 72 characters.

Before every commit, run `./bin/nupp fmt --write` on all changed code files.

Main moving underneath you while you integrate, and the rebase that follows,
is the expected, natural consequence of other agents working in parallel out
of their own worktrees. Do not report this or call it out as needing
attention: it is not an incident. Only report when integrating surfaces an
actual incident — one that changes the design or implementation in a way
the original work did not anticipate. Adjusting code to resolve a rebase
conflict does not on its own meet that bar.

### The development rock tree

`.rocks` holds the rocks this repository develops against -- lunamark and
scintillua for the documentation site, lunajson for the portable compiler, and
what those pull in. It is ignored, so a fresh checkout has none, and the suites
that need one fail rather than skip: twenty-eight of them, reading as missing
modules. Two builds write it, which is what CI runs:

```sh
./bin/nupp build --target bootstrapCompiler
./bin/nupp build --target docs
```

LuaRocks itself comes from `scripts/toolchain luarocks` and `bin/nupp` finds it
there, so nothing has to be installed on the machine first.

A worktree made by the helper below links the originating checkout's tree
instead of building its own, so provision the checkout rather than the worktree.

### Worktree setup

Use the repository helper so a new worktree links the ignored `.rocks`
dependencies, seeds the content-validated compiler cache and test timings, and
reuses the repository-wide toolchain cache:

```sh
./scripts/worktree example-task /private/tmp/nupp-example-task main
```

Use task-specific branch and directory names. Never replace an existing
cache or `.rocks` path; inspect it instead. Run subsequent Nupp commands from
the task worktree. Removing the completed worktree removes its `.rocks`
symlink and local seeded caches, not the originating checkout's dependencies or
the repository-wide native cache.

Remove your own worktree once its work has landed on `main`, and not before: a
worktree still holding unmerged work is the work. Leave every other worktree
alone, in whatever state it is in. One that looks abandoned may be a task
somebody else has open, and uncommitted changes in a tree that is not yours are
not yours to decide are finished.

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
- `./bin/nupp reference` with no chapter lists every section by name, and
  `--section NAME` prints one — a few hundred words rather than the chapter's
  thousands. A section is named by its heading or by any `docs` pointer at it,
  so the anchor a diagnostic carries can be followed directly. Reach for a
  section when the question is about one construct, and the chapter only when
  it is not.
- `./bin/nupp reference --for CODE` prints whichever sections explain a
  diagnostic code, which is what you have when a check reports one.
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

## Proposals are not documentation

`docs/neps/` holds Nupp Enhancement Proposals: numbered records of why a design
is the way it is. `docs/` says how Nupp behaves today and wins wherever the two
disagree. A proposal states its status in frontmatter — read it before believing
the body, which may describe something that was never built.

A proposal records reasoning, not behaviour. Never write a sentence describing
what the compiler does today into one; link to the page that owns it. Reasoning
about a decision made on a date stays true after the code moves.

When work lands, change the status in the same commit and leave the body alone.
[NEP 1](docs/neps/0001-nep-process.md) says how to write one; adding a proposal
is writing `docs/neps/NNNN-slug.md` and nothing else.

`TODO.md` is the backlog. It is not a design record and does not carry
reasoning.

## Verification

`.githooks/pre-push` refuses a push carrying source `nupp fmt` would rewrite,
asking only about the files that push adds or changes. `scripts/worktree` points
`core.hooksPath` at it; an existing checkout enables it once with

```sh
git config core.hooksPath .githooks
```

It is the one CI failure that never needs judgement — there is a single
formatted spelling and `nupp fmt --write` produces it — and the one most worth
catching here, because several worktrees push to one trunk and the run that
reports it is usually already testing somebody else's commit. `git push
--no-verify` skips it; CI still asks.

- `./bin/nupp test [SUITE...]` runs the test suite, or only the named suites:
  `./bin/nupp test doctest` finishes in seconds where the whole suite takes
  about nine minutes. `--json` reports a record per test — name, status,
  duration, and the failure's message, file and line.
- Run the suites that cover what changed, not the whole suite. Documentation
  generation is `doctest`, and the same holds elsewhere: match the suites to
  the area. The full suite is for changes that reach broadly — the checker, the
  compiler pipeline, the runtime — or when a focused run is not obviously
  enough. Running it on a change it cannot reach spends ten minutes to learn
  nothing, and its unrelated pre-existing failures then have to be sorted out
  from the ones the change caused.
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
where an edit to a function body invalidates one. `nupp check --json`'s
`timing.compiledModules` says how many modules a given run actually redid
rather than leaving that to be inferred from how long it took, and
`timing.slowest` says where the time went either way.

The first full test run in a helper-created worktree also starts with the
originating checkout's suite timings, so its parallel shards are balanced from
the outset. Run `fixpoint` near completion when compiler sources changed; it is
a self-hosting verification, not part of the inner edit/check loop.
