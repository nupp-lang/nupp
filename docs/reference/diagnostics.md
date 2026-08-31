# Diagnostics

A diagnostic is a stable code, a severity, a source range, and a message, and
every one the compiler reports carries all four whether a person or a program
is reading. This is what one looks like on standard error:

```text
src/main.nupp:8:13: error: NUPP2004: no field "horizonal" in Point
 8 | print(point.horizonal)
   |             ^~~~~~~~~
help: use the suggested field spelling
```

## Text report

The first line keeps the conventional compiler form, so a build tool that
already reads `file:line:column: severity: message` needs no adapter for Nupp.
Under it come the quoted source line and a caret run marking the primary range,
then one `note` line per related location, then `help`.

Lines, columns, and offsets are 1-based byte positions. They are `0` when the
file could not be read at all.

### Lint names

A lint carries its name after the code, so the thing a project would configure
is visible in the line it printed:

```text
src/main.nupp:4:5: warning: NUPP2107 exhaustiveness: every branch returns, so this handles "blue" | "green" | "red" and leaves "red" unhandled
help: add branches for "red" or add an else clause
```

That name is what an `@allow` suppression or a `nupp.lua` entry writes. See
[lints.md](lints.md) for the built-in lints, their categories, and their default
levels.

### Color

Written to a terminal the same report is colored: the severity and the caret run
share a color, the code and lint name are dimmed, the file position and the
message have their own, and so does the rail beside the quoted source. Written
anywhere else it is exactly the text above, byte for byte.

`--color=always` and `--color=never` answer without looking at the stream.
Failing an explicit flag, `NO_COLOR` refuses escapes, `CLICOLOR_FORCE` demands
them, and failing both the stream is asked whether it is a terminal that
understands them, which `TERM=dumb` answers no for.

::: deepdive
Color never changes the bytes. A styled report is the plain report with escapes
wrapped around spans of it, so a tool that reads compiler output has nothing to
strip and no second format to learn, and a person who pipes a failing build into
a file gets the same thing they saw.

That constraint is why `NO_COLOR` is one-way. The convention gives a user a way
to refuse escapes and no way to ask for them, so the variable that forces them
on is a separate one, and a terminal that has announced itself as incapable
through `TERM=dumb` is still asked last rather than first.
:::

## Diagnostic fields

Every diagnostic carries `severity`, `message`, and `range`, plus `fixes`,
`notes`, and `related`, which are always present and may be empty. The rest
appear when there is something to say:

- `file` and `code`, on anything with a source position and a code of its own.
- `help`: a concrete repair direction, in one sentence.
- `related`: labeled secondary ranges, including ranges in other files.
- `fixes`: titled edit sets a tool can apply without reading the prose.
- `notes`: context that points at no source, such as the trace classification a
  [JIT trace check](../learn/performance/jit-trace-checking.md) attaches to its finding.
- `lint`: the lint name, when the code names one.
- `docs`: the reference section covering the code, as a path and an anchor.

The language server converts the same data to UTF-16 LSP ranges,
`relatedInformation`, diagnostic `data`, and code actions, so an editor and a
terminal disagree about presentation and about nothing else.

## Explaining a code

`nupp explain` prints the rule behind a code, a program that reports it, the
same program corrected, related codes, and a reference into these documents:

```bash
nupp explain NUPP2119
```

Every code with an entry can be looked up this way, which is faster than
searching for the number. The [diagnostic index](#diagnostic-index) below is the
same content rendered as a page.

## Code families

The leading digit is the family, and every code falls in one, so a code with no
entry of its own can still be resolved this far.

| Codes | Meaning |
| --- | --- |
| `NUPP0001` | Source input could not be read. |
| `NUPP1001` | Invalid or unterminated lexical input. |
| `NUPP1002` | A required token is missing. |
| `NUPP1003` | A required name is missing. |
| `NUPP1004` | A required expression is missing. |
| `NUPP1005` | Another syntax or recovery constraint failed. |
| `NUPP1006` | Typed Nupp syntax appeared in plain Lua. |
| `NUPP1007` | A docblock names a parameter that does not exist. |
| `NUPP1008` | An annotated Lua type was recovered with reduced precision. |
| `NUPP2xxx` | Type, declaration, lint, FFI, or ownership diagnostics. |
| `NUPP3xxx` | Code generation cannot represent a checked construct. |
| `NUPP4001` | Formatting could not safely produce the requested result. |
| `NUPP5xxx` | A development-time change requires a restart. |
| `OPT-n` | An optimization pass reporting what it did or declined to do. |

`OPT-n` is the one family that does not describe a problem. A pass reports one
to say that it rewrote something, or that it looked at something and could not.
The severity is always `note`, so a remark is reported and stepped over and
never fails a build.

Remarks are off unless `--remarks` is passed, and they come from `nupp build`
and `nupp run` rather than `nupp check`, which does not optimize. The code is
stable across a pass being renamed, split, or merged, so it can be cited in a
bug report or passed to `-Zno-opt`. See the [performance
guide](../learn/performance/index.md) for what each pass reports.

::: deepdive
An optimizer is the one part of the compiler whose silence is ambiguous. A pass
that declined to inline a call and a pass that was never reached both produce a
program with the call still in it, and nothing in the output says which
happened. `OPT-n` is the answer a language owes its user when a declared
intention did not reach the generated code.

Giving remarks codes rather than free text is what makes them usable twice. The
same identifier that names a remark in a bug report turns the pass off through
`-Zno-opt`, and it survives the pass being renamed or split, so neither use
breaks when the optimizer is rearranged.
:::

## Codes by area

A code is explained in full by the [diagnostic index](#diagnostic-index) below,
and in context by the page that owns the rule. This is the map from an area to
that page:

| Area | Page | Codes |
| --- | --- | --- |
| Affine types | [affine-types.md](../learn/runtime/ownership/affine-types.md) | `NUPP2606` |
| Ahead-of-time compilation | [ahead-of-time.md](../learn/performance/ahead-of-time/index.md) | `NUPP2901`, `NUPP2902`, `NUPP2903` |
| Annotations | [annotations.md](annotations.md) | `NUPP2108`, `NUPP2112`, `NUPP2113`, `NUPP2119`, `NUPP2707`, `NUPP2901`, `NUPP2902`, `NUPP2903` |
| Associated types | [associated-types.md](../learn/language/types/associated-types.md) | `NUPP2127`, `NUPP2128`, `NUPP2129`, `NUPP2134`, `NUPP2135`, `NUPP2511` |
| C interop | [c-interop.md](../learn/runtime/c-interop/index.md) | `NUPP2201`, `NUPP2402`, `NUPP2403` |
| Checked spans | [](nupp.mem.span) | `NUPP2001`, `NUPP2004`, `NUPP2602`, `NUPP2604` |
| Comptime | [comptime.md](../learn/language/comptime.md) | `NUPP2410` through `NUPP2416`, `NUPP2419`, `NUPP2420`, `NUPP2421` |
| Comptime types | [type-level-computation.md](../learn/language/types/comptime-types.md) | `NUPP2001` |
| Derives | [derives.md](derives.md) | `NUPP2810` |
| Effect contracts | [effects.md](../learn/language/effects.md) | `NUPP2112`, `NUPP2710`, `NUPP2711` |
| Files | [](nupp.io.files) | `NUPP2701` |
| Formatter | [fmt.md](../learn/tooling/formatter.md) | `NUPP4001` |
| Generics | [generics.md](../learn/language/types/generics.md) | `NUPP2003`, `NUPP2116`, `NUPP2122` |
| Gradual typing | [strictness.md](../learn/language/gradual-typing.md) | `NUPP1006`, `NUPP1008`, `NUPP2105`, `NUPP2106` |
| Hot reload | [hot-reload.md](../learn/projects/hot-reload.md) | `NUPP5001` |
| Interfaces | [interfaces.md](../learn/language/types/interfaces.md) | `NUPP2116`, `NUPP2117`, `NUPP2118`, `NUPP2136`, `NUPP3001` |
| Intersections and overloads | [intersections.md](../learn/language/types/intersections.md) | `NUPP2124`, `NUPP2125`, `NUPP2126`, `NUPP2208` |
| Lints | [lints.md](lints.md) | `NUPP2107`, `NUPP2120`, `NUPP2501`, `NUPP2502`, `NUPP2504` through `NUPP2515` |
| Logging | [](nupp.log) | `NUPP2006` |
| LuaJIT trace checking | [jit-trace-checking.md](../learn/performance/jit-trace-checking.md) | `NUPP2502`, `NUPP2505`, `NUPP2514`, `NUPP2515`, `NUPP2707` |
| Math | [](nupp.math) | `NUPP2011`, `NUPP2012` |
| Metamethods | [metamethods.md](../learn/language/metamethods.md) | `NUPP2003`, `NUPP2005`, `NUPP2006`, `NUPP2007`, `NUPP2116`, `NUPP2117`, `NUPP2118` |
| Modules | [modules.md](../learn/language/modules.md) | `NUPP1002`, `NUPP2004`, `NUPP2101`, `NUPP2105`, `NUPP2119` |
| Named and plucked arguments | [calls.md](../learn/language/named-arguments.md) | `NUPP2004`, `NUPP2006`, `NUPP2125` |
| Narrowing | [narrowing.md](../learn/language/types/narrowing.md) | `NUPP2002`, `NUPP2109`, `NUPP2110` |
| Overloads and overrides | [overloads.md](../learn/language/types/overloads.md) | `NUPP2118`, `NUPP2125`, `NUPP2126`, `NUPP2208` |
| Ownership | [ownership.md](../learn/runtime/ownership/borrowing.md) | `NUPP2601`, `NUPP2602`, `NUPP2603`, `NUPP2606` through `NUPP2615`, `NUPP2620` |
| Primitive types | [primitives.md](../learn/language/types/primitives.md) | `NUPP2001`, `NUPP2002`, `NUPP2004`, `NUPP2006`, `NUPP2106`, `NUPP2115` |
| Property capabilities | [properties.md](../learn/language/types/properties.md) | `NUPP2009`, `NUPP2118` |
| Records and structs | [records.md](../learn/language/types/records-and-structs.md) | `NUPP2118`, `NUPP2201`, `NUPP2202`, `NUPP2204`, `NUPP2205` |
| Reflection | [reflection.md](../learn/language/reflection.md) | `NUPP2414`, `NUPP2415`, `NUPP2416`, `NUPP2418` |
| Refinements | [refinements.md](../learn/language/types/refinements.md) | `NUPP2122` |
| Structure-of-arrays storage | [structure-of-arrays.md](../learn/runtime/data/structure-of-arrays.md) | `NUPP2009`, `NUPP2403` |
| Suspension | [suspension.md](../learn/runtime/concurrency/suspension.md) | `NUPP2603`, `NUPP2701`, `NUPP2702`, `NUPP2706` |
| Switch expressions | [switch-expressions.md](../learn/language/switch-expressions.md) | `NUPP2137` through `NUPP2142`, `NUPP3001` |
| Type packs | [packs.md](../learn/language/types/packs.md) | `NUPP2007`, `NUPP2010`, `NUPP2121`, `NUPP2605` |
| Type system | [overview.md](../learn/language/types/index.md) | `NUPP2001`, `NUPP2004`, `NUPP2011`, `NUPP2012`, `NUPP2105`, `NUPP2106` |
| Unions | [unions.md](../learn/language/types/unions.md) | `NUPP2001`, `NUPP2107`, `NUPP2138`, `NUPP2139`, `NUPP2140` |

A code appears in several rows when several rules can report it. `NUPP2004` is
one code for "that field is not there", and which page explains it depends on
what was being reached for.

## Repairs

A fix is a title and a set of byte-ranged edits into one file, and applying it
is all-or-nothing. Only unambiguous rewrites qualify: where a message lists
alternatives, each alternative is its own fix rather than a guess between them.

The checker offers fixes for misspelled variables, type names, fields, methods,
and metamethods; missing module qualifications and `require` statements;
declaration visibility; a customary operator replaced with Lua's word; explicit
casts for intended lossy narrowing; and the conversion that establishes a
fixed-width value.

A diagnostic gives `help` rather than an edit when the compiler cannot choose a
program on the author's behalf. Enum exhaustiveness cannot invent branch bodies,
an ambiguous global cannot decide which public declaration should change
visibility, and a resource without cleanup metadata cannot guess which function
owns that responsibility.

## Machine-readable output

Every command whose result is data rather than a side effect takes
`--format json`, with `--json` as its shorthand, and every command that takes it
also takes `--schema`, which prints the JSON Schema of what `--json` writes and
exits. The schema is declared beside the code that writes it and a test
validates real output against it, so the two cannot drift.

| Command | `--json` reports |
| --- | --- |
| `aot` | what every `@aot` function in one file lowered to |
| `ast` | the lossless syntax tree |
| `bc` | the bytecode of one file, instruction by instruction |
| `build` | diagnostics, the target, and every path written |
| `check` | diagnostics, and where the check's time went |
| `clean` | the paths removed, or that would be |
| `coverage` | the aggregate coverage summary |
| `doc` | the resolved format, the output, and every path written |
| `explain` | a code's rule and worked examples |
| `export-c` | the header written and the declarations in it |
| `fixpoint` | whether it reproduced, and why not |
| `fmt` | unformatted, written, and failed, kept apart |
| `import-c` | the module written and any warnings |
| `init` | what the template resolved to and what it wrote |
| `lints` | every lint, its level here, and its default |
| `lsp` | per operation; each has its own schema |
| `ownership-audit` | foreign pointer contracts and unsafe assertion sites |
| `reference` | the reference, section by section |
| `tasks` | the task list, or one task's configuration |
| `test` | totals and a record per test, with file and line |

`nupp run` is the exception. Its `--json` writes the `--jit-aborts` record as
JSON instead of CSV, because the program's own output is the run's output.

Read `ok` before `diagnostics`. An empty list means the project is clean only
when `ok` is true, since a run that could not use the manifest never reached a
file and reports the same empty list.

## Agent workflow

1. Run `nupp check --json --strict`, and read `ok` first.
2. Apply a complete fix from `diagnostics[].fixes` when its title matches the
   intended repair. Never take individual edits out of one.
3. Read `docs` on a diagnostic, or run `nupp explain <code> --json`, when the
   message alone does not say what the rule is. For the surrounding prose rather
   than the rule, `nupp reference --for <code>` prints the sections that cover
   it, and `nupp reference --section <anchor>` takes the `docs` pointer itself.
   Either is a few hundred words where the chapter is thousands.
4. Inspect `related` locations before changing cross-file declarations or
   ownership transfers.
5. Use `nupp lsp inspect`, `nupp lsp definition`, and `nupp lsp references` when
   more semantic context is needed.
6. Re-run the check after each edit group, then `nupp test --json` before
   committing, which reports each failing test's name, message, file, and line
   rather than a wall of progress text.
7. Read `timing.compiledModules` and `timing.slowest` when a check of an
   unchanged project is slower than expected. `compiledModules = 0` is the
   authoritative answer that nothing was redone, and `slowest` ranks modules by
   time actually spent either way, since confirming that a cache entry is still
   valid costs time too.

## FAQ

### How do I stop the checker reporting a lint I do not want?

Set the lint to `off` by name or by category in the `lints` table in `nupp.lua`,
or decorate the one statement with `@allow("lint-name")`. See
[lints.md](lints.md) for the resolution order, which runs registry default, then
category, then name, then the `@allow`.

### Why did a diagnostic give me `help` and no fix?

Because more than one program would satisfy the rule and the compiler will not
pick one. An unhandled enum member needs a branch body only the author knows,
so the message says what is missing and stops. See [Repairs](#repairs) for the
repairs that are unambiguous enough to be offered as edits.

### Why is `diagnostics` empty when the command still failed?

The run never reached a file. A manifest that could not be used ends a check
before anything is parsed, and that answers with the same empty list a clean
project does, which is why `ok` is a separate field. See [Machine-readable
output](#machine-readable-output).

### Why did `@allow` not silence an error?

`@allow` reaches lints and nothing else, so naming a type error in one leaves
the error standing and reports `NUPP2108` for the name. See
[lints.md](lints.md) for what counts as a lint.

::: seealso
- [cli.md](cli.md) for every command, its options, and its exit codes
- [lsp.md](../learn/tooling/language-server.md) for the same diagnostics inside an editor
:::
