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
[performance guide](../guides/performance.md).

## Diagnostic index

This page is the canonical index of diagnostic summaries. Feature pages
explain their rules in context; use `nupp explain CODE` for a failing and
corrected program.

### [Calling C safely](../concepts/c-interop.md)

- **NUPP2201**: a struct field is not reifiable, which a `T[?]` field reports
  because a struct whose size depends on a runtime count has none.
- **NUPP2402**: `layoutof` was asked about something with no layout, such as a
  `record`, which is a table rather than C memory.
- **NUPP2403**: [structure-of-arrays storage](
  ../concepts/structure-of-arrays.md) was asked to store a non-reified or
  unsupported element, or a field projection did not resolve one stored struct
  field.

### [Named and plucked arguments](../concepts/calls.md)

- **NUPP2004**: a plucked name is not a field of the operand.
- **NUPP2006**: an argument does not fit the parameter it fills.
- **NUPP2125**: no overload accepts the call the arguments build.

### [Comptime](../concepts/comptime.md)

- **NUPP2410** / **NUPP2411** / **NUPP2412**: the block cannot be evaluated at
  compile time.
- **NUPP2413**: a result table is reachable by two paths, so it has no literal
  spelling.
- **NUPP2414**: an opaque provider result reached a binding that cannot
  materialize it.
- **NUPP2415**: a declared type has no registered materialization for the
  opaque result, or a worker payload failed the provider's checks.
- **NUPP2416** / **NUPP2419**: a provider rejected the request.
- **NUPP2420**: a comptime type function deliberately rejected its application
  through `nupp.types.error`.
- **NUPP2421**: a type-position comptime call has an invalid callee, signature,
  argument, result kind, or result bound.

### [Declared modules](../concepts/declarations.md)

- **NUPP1002** reports invalid module declarations, non-canonical names,
  duplicate canonical modules, reserved compiler-name collisions, and
  parent-export/child-module collisions.
- **NUPP2004** reports a missing selected field or exported member.
- **NUPP2101** reports an unknown type.
- **NUPP2105** reports an unknown value in strict source.
- **NUPP2119** reports a typed declaration with no visibility in a legacy
  module. In a declared module, use `local` or `export`.

### [Effect contracts](../concepts/effects.md)

- **NUPP2710**: a `noalloc` region can reach a modeled allocation.
- **NUPP2711**: a `noraise` region can reach a catchable error path.

- **NUPP2112**: an effect annotation member is not one the contract accepts, or
  a boolean member is not literally `true` or `false`.

### [Metamethod contracts](../concepts/metamethods.md)

The principal diagnostics are:

- `NUPP2003`: no applicable primitive operation or metamethod contract.
- `NUPP2005`: a value has no callable type or `__call` contract.
- `NUPP2006` / `NUPP2007`: contract argument or arity mismatch.
- `NUPP2116`: a generic argument violates its `is` bound.
- `NUPP2117`: an invalid contract parent after `is`.
- `NUPP2118`: an invalid, duplicate, misspelled, or unsupported metamethod or
  inline method declaration.

### [Reflection](../concepts/reflection.md)

- **NUPP2414**: an opaque reflection result reached a binding that cannot
  materialize it.
- **NUPP2415**: a declared materialization boundary or provider result failed
  validation.
- **NUPP2416** / **NUPP2418**: reflection or its provider rejected the request.

### [Gradual typing](../concepts/strictness.md)

- **NUPP1006**: the typed layer appears in a `.lua` file, which is plain Lua.
- **NUPP2105**: an unknown variable, in a strict file only.
- **NUPP2106**: an exported declaration needs a type annotation.

### [Structure-of-arrays storage](../concepts/structure-of-arrays.md)

- **NUPP2009**: code writes through a shared SoA row view.
- **NUPP2403**: an allocation element is not SoA-eligible, or `field` does not
  name one resolved stored field.

### [Suspension](../concepts/suspension.md)

- **NUPP2701** reports a call in a `nosuspend` region or cleanup contract that
  may suspend.
- **NUPP2702** reports a suspending callback invoked through a non-yieldable C
  boundary.
- **NUPP2706** reports a jump into a `handle suspension` region.
- **NUPP2603** reports a raw coroutine yield that would strand a live ownership
  or borrowing obligation.

### [Switch expressions](../concepts/switch-expressions.md)

- `NUPP2137`: invalid static case, field, or binding.
- `NUPP2138`: duplicate static value after normalization.
- `NUPP2139`: unreachable or selector-incompatible case.
- `NUPP2140`: non-exhaustive switch.
- `NUPP2141`: invalid block-arm completion or switch yield.
- `NUPP2142`: placement would change conditional evaluation.
- `NUPP3001`: a type case has no runtime identity.

### [Tour of Nupp](../getting-started/tour.md)

- **NUPP2107**: the `exhaustiveness` lint, where a dispatch leaves members of a
  closed set unhandled.
- **NUPP2119**: a declaration says neither `local`, `global`, nor a table to
  attach to.

### [Ahead-of-time compilation](../guides/ahead-of-time.md)

| Code | Meaning |
| --- | --- |
| NUPP2901 | `@aot` stacked with `@jit`, promising one body to two compilers |
| NUPP2902 | `@aot` on something that is not a whole function |
| NUPP2903 | A construct in an `@aot` body with no AOT IR form |

A closure, interpolated string, vararg, `goto`, dynamic call or unsafe operation
inside an `@aot` body reports NUPP2903 at the construct. Fresh table
construction is admitted; unsupported table reads or mutations are refused by
the value-level AOT lowering with a source position.

### [Formatter](../guides/fmt.md)

- **NUPP4001**: formatting could not safely produce a result, so the input is
  left untouched. The formatter refuses whatever it cannot prove it would
  preserve.

### [LuaJIT trace checking](../guides/jit-trace-checking.md)

- **NUPP2707**: an `@jit` body, or a checked callee it reaches, holds a
  catalogued unconditional recorder blocker.
- **NUPP2515** / **NUPP2505**: a loop builds a function, capturing the
  iteration or not.
- **NUPP2514**: a variadic FFI call cannot run on a compiled trace.
- **NUPP2502**: a Lua function passed to C becomes an FFI callback.

### [`nupp.io.files`](../modules/nupp/io/files.md)

- **NUPP2701**: a non-suspending region can reach suspension, which a
  filesystem call inside `nosuspend` reports at compile time.

### [`nupp.log`](../modules/nupp/log.md)

- **NUPP2006**: a logging call's arguments do not fit the format it names,
  which an omitted argument supplying nil also reports.

### [`nupp.math`](../modules/nupp/math.md)

- **NUPP2011**: a `float`, `int32`, or `uint32` claim lacks an establishing
  literal, load, conversion, or fixed-width source.
- **NUPP2012**: a physical storage width is used where an ordinary value type is
  required.

See [the standard-library overview](../concepts/standard-library.md) for
selection and lazy-loading rules.

### [`nupp.mem.span`](../modules/nupp/mem/span.md)

- **NUPP2001**: an element, count, or result does not fit the span's declared
  type.
- **NUPP2004**: a requested operation is not present on the shared or writable
  view being used.
- **NUPP2602**: an ownership or exclusive-access operation is invalid for the
  live span regions.
- **NUPP2604**: raw pointer arithmetic, indexing, or a region assertion lacks
  the required proof or `unsafe` boundary.

### [Annotations](annotations.md)

- **NUPP2108**: an `@allow` names a lint that does not exist, and the error it
  was meant to suppress still stands.
- **NUPP2112**: an annotation argument is outside the closed set the annotation
  accepts, which is what a misspelled `@relax` guarantee reports.
- **NUPP2113**: a reserved annotation parsed and resolved, and is not yet
  implemented.
- **NUPP2707**: an `@jit` function crosses a variadic or callback FFI boundary.
- **NUPP2119**: a declaration does not say where it lives.
- **NUPP2901**: a declaration carries both `@aot` and `@jit`.
- **NUPP2902**: `@aot` decorates a constructor or an inline requirement,
  neither of which is a whole function to compile.
- **NUPP2903**: an `@aot` body uses a construct the backend has no IR for --
  a closure, table, interpolated string, vararg, `goto`, dynamic call, or
  unsafe operation.

### [Derives](derives.md)

- **NUPP2810**: a derive provider failed or returned an invalid blueprint,
  and named no code of its own.

### [Affine types](../type-system/affine-types.md)

- **NUPP2606**: a result has two possible `T` components, so conservation is
  ambiguous.

### [Associated types](../type-system/associated-types.md)

- **NUPP2127**: a declaration does not answer an associated type it owes, or
  answers otherwise than a `==` fixes it, or two contracts default it
  differently.
- **NUPP2128**: an associated type member cannot mean anything where it is
  written. Answering a name no contract declares, restating a bound, or stating
  a requirement outside an interface.
- **NUPP2129**: an associated type collides with a nested alias or declaration.
- **NUPP2134**: a projection names something that cannot be projected.
- **NUPP2135**: an associated type answers through itself, reported once per
  component.
- **NUPP2511**: the `gradual-projection` lint, where inference did not reach a
  projection's head and it was erased to `any`.

### [Generics](../type-system/generics.md)

- **NUPP2003**: an operator is applied to types it does not accept, which an
  unbounded type parameter reports before a bound admits the operation.
- **NUPP2116**: a type argument violates its bound, checked where the generic is
  instantiated.
- **NUPP2122**: a refinement cannot be enforced.

### [Interfaces](../type-system/interfaces.md)

- **NUPP2116**: a generic argument violates its bound.
- **NUPP2117**: `is` names something that is not an interface.
- **NUPP2118**: an invalid, duplicate, or unsupported metamethod contract, or
  an interface method given a body.
- **NUPP2136**: a sealed interface is implemented outside its owning module.
- **NUPP3001**: `is` used against a type with no runtime identity.

### [Intersection types and overloads](../type-system/intersections.md)

- **NUPP2124**: an intersection is provably uninhabited, so no value could
  satisfy it.
- **NUPP2125**: no overload accepts the call's adjusted argument pack.
- **NUPP2126**: several overloads accept it, and source order does not break
  the tie.
- **NUPP2208**: a constructor does not hold up its declaration, which duplicate
  parameter-pack contracts also report.

### [Narrowing](../type-system/narrowing.md)

- **NUPP2002**: a returned value does not fit the declared result, which is
  what a union that was never narrowed reports.
- **NUPP2109**: a narrowing test cannot hold, because the type tested for is
  not one the subject could be.
- **NUPP2110**: a parameter could not hold the type a test narrows it to.

### [Overloads and overrides](../type-system/overloads.md)

- **NUPP2125**: no callable-intersection member accepts the argument pack.
- **NUPP2126**: several members accept it, or an overloaded method was read as
  one field value.
- **NUPP2118**: a method parameter pack is duplicated, an interface entry is
  missing or incompatible, or `@override` does not match exactly one inherited
  default.
- **NUPP2208**: constructor overloads duplicate a parameter pack or violate
  constructor integrity.

For the underlying intersection relation, including capability composition and
provable emptiness, see [Intersection types](../type-system/intersections.md).
For general interface inheritance and runtime defaults, see
[Interfaces](../type-system/interfaces.md).

### [Type system](../type-system/overview.md)

- **NUPP2001**: a value does not fit the type it is bound to.
- **NUPP2004**: the field does not exist on that type.
- **NUPP2011**: a fixed-width value was claimed without being established.
- **NUPP2012**: a physical storage width was used as an ordinary value type.
- **NUPP2105**: an unknown variable, in a strict file only.
- **NUPP2106**: an exported declaration needs a type annotation.

### [Ownership and affine types](../type-system/ownership.md)

- **NUPP2601**: use after an affine value or field was moved.
- **NUPP2602**: an ownership operation is invalid, such as dropping a
  terminal-less value.
- **NUPP2603**: an affine obligation leaves a path without being consumed or
  transferred.
- **NUPP2606**: a preservation relation loses, duplicates, or names the wrong
  capability source.
- **NUPP2607**: shared and exclusive regions overlap incompatibly.
- **NUPP2608**: a rooted or scoped value escapes its permitted lifetime.
- **NUPP2609**: a loop back edge changes a live capability or region.
- **NUPP2610**: a capability-bearing public parameter omits its mode.
- **NUPP2611**: a nontrivial capability is implicitly erased.
- **NUPP2612**: a dynamic-store value is not self-contained and droppable.
- **NUPP2613**: dynamic recovery requests the wrong type policy.
- **NUPP2614**: a dynamic handle is stale or names a different or destroyed
  store.
- **NUPP2615**: a terminal is missing or does not exactly match its
  representation.

See also [C interop](../concepts/c-interop.md),
[effects](../concepts/effects.md), and [checked
spans](../modules/nupp/mem/span.md).

### [Type packs](../type-system/packs.md)

- **NUPP2007**: a call's results do not fit where they land, which a two-result
  call into a one-parameter function still reports.
- **NUPP2010**: a complete value pack does not fit the required sequence,
  covering incompatible heads, tails, alternatives and `select` indices.
- **NUPP2121**: a type pack is used where only one value type can appear.
- **NUPP2605**: adjusting a value pack would discard an affine value.

### [Primitive types](../type-system/primitives.md)

- **NUPP2001**: a value does not fit the type it is bound to, which is what a
  widening arithmetic result reports when it is bound back to `integer`.
- **NUPP2004**: the field does not exist on that type, which is what reading a
  field of `unknown` reports before it is narrowed.
- **NUPP2006**: a call's arguments are not arranged in a way it can be given,
  which is what an extra argument to a `never` variadic reports.
- **NUPP2002**: a returned value does not fit the declared result sequence.
- **NUPP2106**: a strict exported declaration is not fully annotated.
- **NUPP2115**: an alias is defined in terms of itself.

### [Property capabilities](../type-system/properties.md)

- **NUPP2009**: a property view does not grant the access asked of it, which a
  read through a write-only view and an assignment through a read-only one both
  report.
- **NUPP2118**: a duplicate capability, or an ordinary property combined with a
  separated one.

### [Records and structs](../type-system/records.md)

- **NUPP2201**: a struct field is not reifiable, or a struct nests a
  declaration.
- **NUPP2202**: a construction problem: an unknown field, a missing one, or a
  positional argument to a record.
- **NUPP2204** / **NUPP2205**: array-part problems.
- **NUPP2118**: a duplicate member, or a metamethod contract on a struct.

### [Refinements](../type-system/refinements.md)

- **NUPP2122**: a refinement cannot be enforced. It reads something other than
  `self`, always answers the same way, sits on a record or struct, or a
  declaration's own fields provably fail an interface it declares.

### [Comptime types](../type-system/type-level-computation.md)

- **NUPP2001**: two applications of one generic differ in a const argument.

### [Unions](../type-system/unions.md)

- **NUPP2001**: a value is not a member of the union it is bound to.
- **NUPP2107**: the `exhaustiveness` lint, where a dispatch leaves members of a
  closed set unhandled.
- **NUPP2138**: two switch case spellings normalize to the same scalar value.
- **NUPP2139**: a switch case cannot match the remaining selector type.
- **NUPP2140**: a value-producing switch does not cover its selector type.

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

## Agent workflow

1. Run `./bin/nupp check --json --strict`. Read `ok` before `diagnostics`: an
   empty list means the project is clean only when `ok` is true, since a run
   that could not use the manifest never reached a file and reports the same
   empty list.
2. Apply a complete fix from `diagnostics[].fixes` when its title matches the
   intended repair.
3. Read `docs` on a diagnostic, or run `./bin/nupp explain <code> --json`, when
   the message alone does not say what the rule is. `explain` gives the rule, a
   program that reports the code, and the same program corrected. For the
   surrounding prose rather than the rule, `./bin/nupp reference --for <code>`
   prints the sections that cover it, and `--section` takes the `docs` pointer
   itself — a few hundred words either way, where the chapter is thousands.
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
