# Comptime type-function implementation results

This is the living evidence record for [`comptime-types.md`](028-comptime-types.md).
Counts and timings are from the implementation worktree on 2026-08-11 unless a
later entry says otherwise.

## CT0 baseline

### User inventory

The production declaration surface has two users:

| Source | Current operation | Migration |
| --- | --- | --- |
| `src/nupp/compiler/decls/prelude.d.nupp` | recursive template parser for `string.format` | ordinary comptime scanner returning `typepack` |
| `src/nupp/compiler/decls/lpeg.d.nupp` | tuple and pack inference for optional captures and match results | comptime pack inspection and construction |

The format implementation occupies 254 lines, from the error alias through
`__NuppFormatArguments`. Before the implementation branch added its own format
calls, `src` contained 717 textual `format(` call sites. The query benchmark
must report canonical unique literal inputs in addition to this upper-bound
source count.

The proving acceptance file `tests/acceptance/typelevel/apis.g.nupp` contains
the recursive route and deep-element aliases. The remaining authored syntax is
test or documentation coverage:

- `tests/typeleveltest.lua` owns parsing, resolution, matching, recursion,
  diagnostics, reduction budgets, templates, function packs and removal
  coverage;
- `tests/packtest.lua` owns nominal pack-pattern extraction;
- `tests/associatedcomposetest.lua` owns a finite match used through an
  associated type;
- `tests/doctest.lua` owns rendered type-match documentation;
- `docs/type-system/type-level-computation.md`, `generics.md`, and `packs.md`
  teach the syntax; and
- `src/nupp/compiler/reference.nupp` generates the checked reference text and
  `docs/reference.md` is its rendered output.

Production PEG typing does not depend on a source-level type interpreter. Its
existing analyzer remains an exact-typing parity fixture and will return its
pack through the shared validated boundary.

### Compiler removal inventory

The implementation vocabulary is concentrated in:

- `parser.nupp` and `cst.nupp`: `tmatch`, match arms, `tinfer`, and
  `ttypeerror`;
- `check/resolve.nupp`: pattern compilation, recursive-arm admission, alias
  shells and source diagnostics;
- `types.nupp`: `MatchPattern`, `MatchArm`, `AliasHeader`, match/type-error and
  alias-call neutral terms;
- `generics.nupp`: pattern substitution and unification, template splitting,
  distribution, recursive alias execution and budgets;
- `reflection.nupp`, `build/modules.nupp`, and `incremental.nupp`: graph and
  fingerprint cases;
- `neutralpolicy.nupp`, `relations.nupp`, `members.nupp`, and
  `methodslots.nupp`: blocked-term boundary behavior; and
- formatter, highlighter, reference, explain and LSP modules for source-facing
  tooling.

Removal remains inventory-driven: a textual occurrence is not sufficient
evidence because ordinary value matching and generic inference use the same
English words.

### Constructor and inspector coverage matrix

CT1 must turn every row from `missing` to `round trip` before CT2 source calls
are admitted. “Reference only” means a result may point at an existing nominal
identity but cannot allocate one.

| Semantic family | Inspect | Construct or reference | CT1 baseline |
| --- | --- | --- | --- |
| primitives and literal types | kind, base and literal value | primitive handles and literal builder | prototype |
| arrays | element | array builder | prototype |
| tuples | ordered elements | tuple builder | prototype |
| maps and indexers | read/write key and value capabilities | capability-preserving indexer builder | missing |
| structural shapes | ordered fields, optionality, read/write capabilities and indexers | structural shape builder | missing |
| unions and intersections | canonical members | union and intersection builders | union prototype; intersection missing |
| pointers and C arrays | element, exact count and const count term | pointer and C-array builders | missing |
| ownership wrappers | inner type, access and cleanup capability | checked owned/borrowed/pinned/const wrappers | missing |
| functions | parameter/result packs, names, modes, effects and ownership relations | function builder from packs | missing |
| packs | fixed head, modes, homogeneous/generic/computed tail and alternatives | fixed and homogeneous pack builder | prototype |
| generic nominal applications | origin, parameter kinds and type/pack/const arguments | apply an existing generic nominal | missing |
| records, structs and interfaces | stable identity and public semantic descriptor | reference only | missing |
| associated types | head, requirement identity, bound and resolved answer | projection of an existing requirement | missing |
| const binders and terms | domain, literal, binder and closed operation | closed const argument and term support | missing |
| metatable, ctype and protocol-thread types | contained types and packs | structural/reference builders where source-spellable | missing |
| gradual and bottom types | exact primitive identity | existing handles | prototype |

The worker graph never includes an allocator for a nominal declaration. A
record or interface computed from a schema is generated as reviewable source;
a derive augments one written declaration through `DeriveResult`.

### Performance and behavior baseline

- `./bin/nupp test typeleveltest`: 27 passed in 323.5 ms.
- Full `./bin/nupp test`: 1,915 tests, 1,906 passed, 9 skipped, 0
  failed in 120.289 seconds; outer wall time 121.58 seconds.
- The admitted T5 implementation previously recorded about 120 ms for its
  focused language suite, about 0.5 seconds for a fresh LSP inspection, about
  14 seconds per self-host pass after an exported type edit, and 0.3 seconds
  for an unchanged build in
  [`type-level-computation-results.md`](020-type-level-computation-results.md).

These are replacement baselines, not historical decoration. CT5 must explain
any regression in exact answers, diagnostics, warm incremental behavior or LSP
latency.

## CT-1 format spike

The first worker-side slice provides opaque primitive, literal, array, tuple,
union and pack handles plus a parent-side graph validator. A focused test
expresses format scanning with ordinary loops, string operations and pack
construction. It has no format-specific checker branch and distinguishes
authored type rejection from evaluator failure.

The expressiveness half of the gate is therefore proven provisionally. The
persistent-worker cold/warm/cache measurements remain open; production prelude
migration cannot begin until those numbers are recorded here.

## CT1 and CT2 implementation result

The compiler now has opaque evaluator `type` and `typepack` handles, a
versioned `TypeBlueprint` graph with parent-side validation, structural
builders and inspectors, permitted references back to existing nominal inputs,
and no nominal allocator. Closed private comptime functions can be called
with ordinary parentheses in type position. Type and const arguments execute
ordinary evaluator control flow, authored `nupp.types.error` failures report
NUPP2420, invalid applications report NUPP2421, and successful queries are
memoized per checker run.

The first CT3 slice is active too: open calls are interned type terms,
substitute through generic type and const inference, and execute through the
checker-owned query callback once closed. `type<Bound>` exposes the bound while
open and validates the concrete result. Generated `typepack` results expand
through retained `unpackof`, including after generic inference. Semantic
fingerprints and reflection carry the new terms without live checker objects.

Focused evidence after this slice:

- 36/36 `typeleveltest` cases pass in 684 ms, including nine new type-function
  cases;
- direct blueprint coverage passes for structures, packs, field/indexer
  capabilities, wrappers, C arrays, intersections, functions, authored errors,
  and malformed graph rejection; and
- a complete compiler build succeeds from the tracked bootstrap.
