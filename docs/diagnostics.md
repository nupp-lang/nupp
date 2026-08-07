# Diagnostics

Nupp diagnostics are designed for terminals, editors, and automated repair
agents without requiring prose parsing. Every diagnostic has a stable code,
severity, complete primary token range, and message. It may also carry:

- `help`: a concrete repair direction;
- `notes`: context that does not point at source;
- `related`: labeled secondary source ranges, including other files;
- `fixes`: titled, machine-applicable edit sets.

The first text line keeps the conventional compiler form understood by build
tools. Source and guidance follow it:

```text
src/main.nupp:8:13: error: NUPP2004: no field "horizonal" in Point
 8 | print(point.horizonal)
   |             ^~~~~~~~~
help: use the suggested field spelling
```

Use `nupp check --json` when consuming diagnostics programmatically. Lines,
columns, and offsets in this CLI format are 1-based byte positions. Each
diagnostic contains `file`, `severity`, `code`, `lint`, `message`, `range`,
`help`, `notes`, `related`, and `fixes`. A fix is all-or-nothing and contains
one or more byte-ranged edits. The language server converts the same data to
UTF-16 LSP ranges, `relatedInformation`, diagnostic `data`, and code actions.

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
| `OPT-n` | An optimization pass reporting what it did or declined to do. |

`OPT-n` is the one family that does not describe a problem. A pass emits it to
say that it rewrote something, or that it looked at something and could not,
which is the answer a language owes its user when a declared intention did not
reach the generated code. The severity is always `note`, so a remark is reported
and stepped over and never fails a build.

Remarks are off unless `--remarks` is passed, and they come from `nupp build`
and `nupp run` rather than `nupp check`, which does not optimize. The code is
stable across a pass being renamed, split, or merged, so it can be cited in a
bug report or passed to `-Zno-opt`. See the
[optimization guide](guides/optimization.md).

The domain references describe `NUPP2xxx` diagnostics in context:

- [modules and project names](MODULES.md#diagnostics);
- [metamethods and contracts](METAMETHODS.md#diagnostics);
- [ownership and unsafe operations](OWNERSHIP.md);
- [`with` resource scopes](WITH.md#diagnostics);
- [lints, configuration, and suppression](LINTS.md).

## Repairs

Checker-provided fixes cover misspelled variables, type names, fields,
methods, and metamethods; missing module qualifications and `require`
statements; declaration visibility; and explicit casts for intended lossy
narrowing. The LSP also offers safe `with` wrap/unwrap transformations.

A diagnostic gives help rather than an edit when the compiler cannot choose a
program on the author's behalf. Enum exhaustiveness cannot invent branch
bodies, an ambiguous global cannot decide which public declaration should
change visibility, and a resource without cleanup metadata cannot guess which
function owns that responsibility.

## Suggested agent workflow

1. Run `./bin/nupp check --json --strict`.
2. Apply a complete fix from `diagnostics[].fixes` when its title matches the
   intended repair.
3. Inspect `related` locations before changing cross-file declarations or
   ownership transfers.
4. Use `./bin/nupp lsp inspect`, `definition`, and `references` when more
   semantic context is needed.
5. Re-run the check after each edit group and `./bin/nupp test` before commit.
