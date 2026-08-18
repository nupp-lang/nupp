# Diagnostics

Nupp diagnostics are designed for terminals, editors, and automated repair
agents without requiring prose parsing. Every diagnostic has a stable code,
severity, complete primary token range, and message. It may also carry:

- `help`: a concrete repair direction;
- `related`: labeled secondary source ranges, including other files;
- `fixes`: titled, machine-applicable edit sets;
- `notes`: context that points at no source. The field is carried end to end
  and is part of the JSON shape, but nothing in the compiler sets it yet, so it
  arrives empty.

The first text line keeps the conventional compiler form understood by build
tools. Source and guidance follow it:

```text
src/main.nupp:8:13: error: NUPP2004: no field "horizonal" in Point
 8 | print(point.horizonal)
   |             ^~~~~~~~~
help: use the suggested field spelling
```

A lint carries its name after the code, so the thing a project would configure
is visible in the line it printed:

```text
src/main.nupp:4:5: warning: NUPP2107 exhaustiveness: every branch
returns, so this handles "blue" | "green" | "red" and leaves "blue" unhandled
help: add branches for "blue" or add an else clause
```

Written to a terminal, the same report is colored: the severity and the caret
run share a color, the code is dimmed, and the rail beside the quoted source is
its own. Written anywhere else it is exactly the text above, byte for byte, so
nothing that reads compiler output has to strip anything. `--color=always`
forces the escapes on for a pager that wants them, `--no-color` (or
`--color=never`) forces them off, and `NO_COLOR`, `CLICOLOR_FORCE` and
`TERM=dumb` are honoured in that order before the terminal is asked.

Use `nupp check --json` when consuming diagnostics programmatically, and
`nupp check --schema` for the JSON Schema of that output. Lines, columns, and
offsets in this CLI format are 1-based byte positions, and are `0` when the
file could not be read at all.

Each diagnostic contains `file`, `severity`, `code`, `message`, `range`,
`fixes`, `notes`, and `related`. `lint` is present only when the code names a
lint, and `help` only when there is one; the other fields are always there and
may be empty. A fix is all-or-nothing and contains one or more byte-ranged
edits. The language server converts the same data to UTF-16 LSP ranges,
`relatedInformation`, diagnostic `data`, and code actions.

## Explaining a code

```bash
nupp explain NUPP2119
```

prints the rule behind a code, a program that reports it, the same program
corrected, related codes, and a reference into these documents. Every
diagnostic code that has an entry can be looked up this way, which is usually
faster than searching for the number.

## Code families

| Codes | Meaning |
| --- | --- |
| `NUPP0001` | Source input could not be read. |
| `NUPP1001` | Invalid or unterminated lexical input. |
| `NUPP1002` | A required token is missing. |
| `NUPP1003` | A required name is missing. |
| `NUPP1004` | A required expression is missing. |
| `NUPP1005` | Another syntax or recovery constraint failed. |
| `NUPP2xxx` | Type, declaration, lint, FFI, or ownership diagnostics. |
| `NUPP3xxx` | Code generation cannot represent a checked construct. |
| `NUPP4001` | Formatting could not safely produce the requested result. |
| `NUPP5xxx` | A development-time change requires a restart. |
| OPT-n | An optimization pass reporting what it did or declined to do. |

`OPT-n` is the one family that does not describe a problem. A pass emits it to
say that it rewrote something, or that it looked at something and could not,
which is the answer a language owes its user when a declared intention did not
reach the generated code. The severity is always `note`, so a remark is reported
and stepped over and never fails a build.

Remarks are off unless `--remarks` is passed, and they come from `nupp build`
and `nupp run` rather than `nupp check`, which does not optimize. The code is
stable across a pass being renamed, split, or merged, so it can be cited in a
bug report or passed to `-Zno-opt`. See the
[performance guide](tooling/performance.md).

The domain references describe `NUPP2xxx` diagnostics in context:

- [modules and project names](modules.md#diagnostics);
- [metamethods and contracts](metamethods.md#diagnostics);
- [ownership and unsafe operations](ownership.md);
- [lints, configuration, and suppression](lints.md).

Switch-expression diagnostics distinguish pattern shape, coverage, control
flow, and lowering placement:

| Code | Meaning |
| --- | --- |
| `NUPP2137` | A static value, type binding, or destructured field is invalid. |
| `NUPP2138` | Two static cases normalize to the same scalar value. |
| `NUPP2139` | A case is incompatible with or unreachable from the remaining selector type. |
| `NUPP2140` | A switch is not exhaustive. |
| `NUPP2141` | A block arm can fall through, or `yield` is invalid here. |
| `NUPP2142` | Lifting the switch here would change conditional evaluation. |
| `NUPP3001` | A checked type case has no runtime identity. |

See [switch expressions](switch-expressions.md) for worked examples and
`nupp explain CODE` for an isolated failing and corrected program.

The capability-specific codes distinguish the repair the checker needs:

| Code | Meaning |
| --- | --- |
| `NUPP2607` | Two capability regions overlap. |
| `NUPP2608` | A rooted value escapes its permitted lifetime. |
| `NUPP2609` | A loop back edge changes capability state. |
| `NUPP2610` | A public capability contract leaves its mode or relation implicit. |
| `NUPP2611` | A dynamic boundary would erase a live capability. |
| `NUPP2612` | A dynamic store cannot safely discharge the supplied capability. |
| `NUPP2613` | An erased dynamic handle is recovered with the wrong type policy. |
| `NUPP2614` | A dynamic handle is stale or names a destroyed store. |

Run `nupp explain CODE` for a checked example and the matching repair. Runtime
handle failures use the same `NUPP2613` and `NUPP2614` codes in
`nupp.dynamic.Error` values.

Region conflicts relate the earlier live borrow, loop back-edge failures relate the
repeatable loop, and borrow escapes relate their root where one is nameable. A static
`NUPP2613` recovery mismatch offers the exact recorded representation as a fix.

## Repairs

Checker-provided fixes cover misspelled variables, type names, fields,
methods, and metamethods; missing module qualifications and `require`
statements; declaration visibility; and explicit casts for intended lossy
narrowing.

A diagnostic gives help rather than an edit when the compiler cannot choose a
program on the author's behalf. Enum exhaustiveness cannot invent branch
bodies, an ambiguous global cannot decide which public declaration should
change visibility, and a resource without cleanup metadata cannot guess which
function owns that responsibility.

## Machine-readable output

Every command whose result is data rather than a side effect takes
`--format json` (or `--json`), and every command that takes it also takes
`--schema`, which prints the JSON Schema of what `--json` writes and exits. The
schema is declared beside the code that writes it and a test validates real
output against it, so the two cannot drift.

| Command | --json reports |
| --- | --- |
| `check` | diagnostics |
| `build` | diagnostics, the target, and every path written |
| `fmt` | unformatted, written, and failed, kept apart |
| `test` | totals and a record per test, with file and line |
| `lints` | every lint, its level here, and its default |
| `tasks` | the task list, or one task's configuration |
| `ast` | the lossless syntax tree |
| `clean` | the paths removed, or that would be |
| `fixpoint` | whether it reproduced, and why not |
| import-c | the module written and any warnings |
| `explain` | a code's rule and worked examples |
| `lsp` | per operation; each has its own schema |

`nupp run` is absent because the program's own output is the output, and
`nupp doc` because it writes a site rather than an answer.

## Suggested agent workflow

1. Run `./bin/nupp check --json --strict`.
2. Apply a complete fix from `diagnostics[].fixes` when its title matches the
   intended repair.
3. Read `docs` on a diagnostic, or run `./bin/nupp explain <code> --json`, when
   the message alone does not say what the rule is. `explain` gives the rule, a
   program that reports the code, and the same program corrected.
4. Inspect `related` locations before changing cross-file declarations or
   ownership transfers.
5. Use `./bin/nupp lsp inspect`, `definition`, and `references` when more
   semantic context is needed.
6. Re-run the check after each edit group, then `./bin/nupp test --json` before
   commit, which reports the failing test's name, message, file and line rather
   than a wall of progress text.
7. When a check of an unchanged project is not answering as fast as expected,
   read `timing.compiledModules` and `timing.slowest` in the same `--json`
   answer rather than waiting the next one out: `compiledModules = 0` means
   nothing was actually redone, and `slowest` names whichever modules cost
   the most wall-clock time regardless -- confirming a cache entry is still
   valid costs time too, just less of it on a project this size.

## Next

- [lints.md](lints.md): the configurable half, and how to move one.
- [lsp.md](tooling/lsp.md): the same diagnostics in an editor.
