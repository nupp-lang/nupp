# Coverage reports and source explorer

Status: implemented. `nupp coverage` runs an instrumented build, merges the
data, and writes the static source-first report; see `docs/tooling/cli.md`.

## Decision

Add a first-class `nupp coverage` command that runs a project in a
coverage-instrumented build, merges the resulting data, and writes a portable,
static report. It is deliberately separate from `nupp test`: the latter builds
and launches an arbitrary command from `nupp.lua`; it is not entitled to assume
that command understands Nupp's built-in test runner or coverage protocol.

The report is source-first. It presents Nupp source as the primary program and
offers the generated Lua as a synchronized secondary view. No source map is
needed for line attribution: `nupp.compiler.gen` already emits code on the source line
it came from and never changes a module's line count. Coverage metadata is
still needed for columns, functions, branch arms, lowered forms, and erased
syntax; it is not a replacement for the line-attribution invariant.

Normal compilation must remain byte-identical and effectively the same speed.
Coverage is a distinct generator mode selected once per module. With coverage
off, code generation takes today's path: it does not enumerate coverage sites,
allocate metadata, emit a runtime import, or add a per-node conditional.

## Goals

1. `nupp coverage` produces reliable line, function, and structural-branch
   coverage for `.nupp` modules reached by a test run.
2. The normal `nupp build`, `nupp check`, `nupp test`, and their generated Lua
   preserve current bytes, cache behavior, line attribution, and performance.
3. A static HTML report works by opening `coverage/index.html` from disk; it
   does not need a server, Node, or a browser extension.
4. The report has a navigable source tree, a useful root and directory roll-up,
   syntax-highlighted Nupp and Lua, and an explanation of what is not runtime
   code rather than painting type-only syntax red.
5. JSON and LCOV outputs make the same data usable by CI, editor coverage
   gutters, and other report tools.

## Non-goals

- Measuring time, allocations, or JIT quality. `nupp run --profile` and
  `--jit-aborts` already answer those different questions.
- Instrumenting handwritten `.lua` by rewriting it. The first release reports
  Nupp modules; a future Lua adapter may contribute external coverage data.
- Statement-perfect coverage for every expression inside a line in the first
  release. Line, function, and control-flow-arm coverage are the useful,
  explainable base.
- Pretending coverage proves behaviour or test quality. It reports execution,
  not assertions or input diversity.
- Making a coverage run performance-representative. Instrumented code is
  intentionally slower and can change LuaJIT trace formation.

## Command and configuration

Introduce a CLI group rather than making `nupp test --coverage` ambiguous:

```text
nupp coverage [test arguments...]
nupp coverage --out coverage [test arguments...]
nupp coverage --format html,json,lcov
nupp coverage --open [test arguments...]
nupp coverage --fail-under-lines 90 --fail-under-branches 80
```

`[test arguments...]` are appended to the configured test command exactly as
they are for `nupp test`. `--open` is a later convenience and must never be
needed to create or read the report.

Add an optional `coverage` manifest table:

```lua
coverage = {
   outDir = "coverage",
   include = {"src/**/*.nupp"},
   exclude = {"src/generated/**"},
   formats = {"html", "json", "lcov"},
   failUnder = {lines = 90, branches = 80, functions = 90},
}
```

The command-line values override the manifest. The defaults should include all
project source files under the configured `include` roots, not merely modules
that happened to load. A never-loaded source file is a real zero-coverage file;
a declaration-only or all-erased file is reported as non-executable instead.

The first integration target is Nupp's documented `tests/run.lua`-style
runner. A custom test command can participate by inheriting the coverage
environment and calling the public `nupp.compiler.coverage.flush()` before it exits.
Document that contract rather than silently producing a partial report. Add a
small wrapper later only if it can reliably cover normal and error exits across
supported LuaJIT hosts.

## Coverage semantics

The report must distinguish these states:

| State | Meaning | UI treatment |
| --- | --- | --- |
| covered | An executable site on the line ran. | Green, with hit count. |
| uncovered | An executable site is known but never ran. | Red. |
| partial | A line has covered and uncovered executable sites or branch arms. | Amber. |
| non-executable | Comment, blank line, type-only syntax, or an erased declaration. | Neutral gray. |
| unknown | Instrumentation/source fingerprints disagree or a process did not flush. | Purple warning; never silently count as uncovered. |

Line coverage is a line's executable-site count. A source line with several
statements may have several IDs but is covered if any site ran and partial if
some did not. Function coverage records entry into named and anonymous runtime
functions. The first branch definition covers the arms of `if`/`elseif`/`else`
and the true/false outcomes of `while` and `repeat ... until`; it reports both
the number and list of missed arms. Add `?:`, `and`, `or`, and optional chaining
only after their lowering has equally clear arm semantics.

Type annotations, generic parameters, casts, interfaces, type aliases, and
other erased nodes are excluded from both numerator and denominator. A line
that contains only erased syntax must not damage a percentage.

## Compiler and runtime architecture

### 1. Preserve the uninstrumented path

Extend compile settings and build cache keys with an explicit coverage mode.
`compile.module` calls either the existing normal generator or the coverage
generator configuration. Keep the normal generator's emitted bytes protected
by the existing fixpoint corpus and add a direct test that normal output is
unchanged when the coverage feature exists.

Coverage artifacts must not occupy ordinary build cache entries. Put generated
Lua and module metadata under a coverage-specific output/cache namespace, such
as `build/coverage/`, keyed by compiler version, source digest, build options,
and coverage schema version.

### 2. Build a coverage-site manifest while emitting

Teach `nupp.compiler.gen` to construct a per-module manifest only in coverage mode. Each
site has a stable ID, kind, source span, generated span, and optional enclosing
function/branch ID:

```json
{
  "version": 1,
  "source": "src/app/player.nupp",
  "sourceHash": "...",
  "generated": "build/coverage/app/player.lua",
  "sites": [
    {"id": 17, "kind": "statement", "start": [23, 4], "end": [23, 18]},
    {"id": 18, "kind": "branch-arm", "branch": 7, "arm": "then",
     "start": [24, 1], "end": [26, 3]},
    {"id": 19, "kind": "erased", "start": [7, 1], "end": [7, 26]}
  ]
}
```

IDs are deterministic in source order within a source-hash-identified module;
the merger never accepts hits whose module fingerprint does not match the
manifest. The manifest provides the complete executable denominator before
tests run, which is what makes unvisited files visible.

Use the generator's existing `e(text, line)` cursor to put injected text on its
own source line. A counter may make that generated line longer, but it must not
insert a new line or claim a different line. The normal generator retains its
current cursor unchanged.

### 3. Instrument safe runtime boundaries

Do not rewrite generated Lua as text after compilation. Instrument while
emitting known CST node kinds:

```nupp
if valid(user) then
   save(user)
else
   reject(user)
end
```

Conceptually becomes, only in the coverage build:

```lua
if __nuppCoverage.branch(7, valid(user)) then
   __nuppCoverage.hit(18); save(user)
else
   __nuppCoverage.hit(19); reject(user)
end
```

`branch` must return the exact value it was passed, not merely a boolean. This
preserves Lua truthiness and condition evaluation. The implementation review
must prove evaluation order, multiple-result adjustment, short-circuiting,
`return`, `break`, `continue`, `goto`, loop back edges, coroutine yields,
errors, and error locations remain correct. Prefer statements placed before a
known statement body; do not wrap arbitrary expressions merely to chase a
percentage.

Function-entry hits belong immediately inside emitted runtime functions. Branch
hits belong in arm bodies; decisions receive a true/false outcome recorder.
Instrumentation imports or binds one private coverage runtime local on the
generator's existing hoisted first line. It is coverage-only and uses names
reserved through the same collision-avoidance mechanism as other generated
helpers.

### 4. Recorder and process protocol

Add `nupp.compiler.coverage` as a small runtime module. It receives the run directory,
run ID, and module manifest identity from environment/configuration, maintains
per-module counters, and writes one shard per process at `flush()`.

The shard format is compact JSON initially; use a stable, documented schema so
it can be changed to a binary counter vector later without changing reports.
It contains process ID, run ID, module hash, counter values, and a completion
marker. The merger rejects incomplete shards rather than treating them as zero.

Update the built-in runner to flush in its normal completion path and its
top-level protected-error path. Cover `beforeAll`/`afterAll` lifecycle failures
as well as case failures. Dynamic Nupp test suites compiled by the runner must
read the same coverage setting, so they use the coverage generator too.

`nupp coverage` creates an isolated run directory, passes its identifying
environment variables through `project.test`, waits for the test command, then
merges shards even when tests failed. It exits nonzero for either test failures,
coverage protocol failures, or configured thresholds, while still writing the
report whenever enough data exists to make it honest.

## Aggregate data and standard outputs

Build one normalized aggregate model; HTML, JSON, LCOV, terminal summary, and
threshold evaluation consume it rather than independently recounting files.

For every file and directory retain:

```text
lines:      covered / executable / percent / missing line numbers
functions:  covered / total / percent / missing names and spans
branches:   covered arms / total arms / percent / missing arms and spans
status:     covered | partial | uncovered | non-executable | unknown
```

Directory totals are recursive and include direct files plus descendants. A
root summary also carries test run status, elapsed time, source-file count,
generated timestamp, compiler version, and warnings. Never sum percentages;
sum covered and total units, then calculate the percentage.

Write:

- `coverage/coverage.json`: the complete, versioned aggregate for automation
  and future report viewers;
- `coverage/lcov.info`: `DA` records for executable lines and `BRDA` records
  for branch arms, with Nupp paths as `SF` paths;
- `coverage/summary.json`: a small CI-friendly summary;
- `coverage/index.html` and related static assets/pages.

Functions have no portable LCOV representation that is equally reliable across
consumers; emit `FN`/`FNDA` where representable, while treating Nupp JSON as the
authoritative detailed format.

## Static report UX

### Information architecture

Generate a page hierarchy mirroring the project tree:

```text
coverage/
  index.html                    root summary
  src/index.html                directory summary
  src/app/index.html            nested directory summary
  src/app/player.nupp.html      source detail page
  assets/coverage.css
  assets/coverage.js
  coverage.json
  lcov.info
```

The report does not depend on client-side routing. Every index and detail page
is useful with JavaScript disabled; JavaScript adds sorting, filtering, tree
state persistence, view toggles, and synchronized scrolling.

### Root and directory index pages

Every root/directory page begins with compact totals for lines, functions, and
branches: covered, total, percentage, and missed count. It then offers a table
of immediate directories and files, so a directory report is useful without
being a duplicate of the full recursive file list.

Columns are:

```text
Name | Lines | Missed lines | Functions | Missed functions |
Branches | Missed arms | Status
```

Each metric column is sortable numerically; name sorts naturally with
directories before files. The default order is worst coverage first, then
alphabetical, because it makes the report actionable. Provide sort indicators,
a text filter, and toggles for `all`, `partial`, `uncovered`, and `unknown`.
Use a compact bar plus exact `covered / total` text; colour never carries the
only meaning.

### Persistent file tree

Every report page has a left panel containing the complete source hierarchy.
Use semantic nested lists and buttons/`aria-expanded` disclosure controls, not
a faux tree made of generic divs. Directories open and close independently;
their icon and coverage badge summarize recursive status. Files show an icon,
name, coverage percentage, and status dot. The active page has a clear current
state.

Expand ancestors of the active file by default. Persist expanded directories,
selected filter, and theme with `localStorage`, keyed by report schema and root
digest, so a new run does not inherit invalid paths. The panel remains
keyboard-navigable and collapses into an accessible drawer on narrow screens.

### File detail page

The header identifies the file and shows line/function/branch totals, missed
items, and links to its parent directory report. Under it, present two views:

- **Nupp source** is the default. Each line has a stable anchor, line number,
  coverage gutter, hit count, and branch-arm chips. Clicking a missed summary
  jumps to its line.
- **Generated Lua** is a toggle and an optional side-by-side split view. It
  preserves source-line anchors and shows inserted coverage probes with a
  subtle annotation. A highlighted source span and its generated counterpart
  cross-highlight on hover/focus.

On each source line explain `not executable` where appropriate: “type alias
erased”, “annotation erased”, or “comment/blank line”. For a lowered construct,
the generated pane can label the fragment “lowered from line 42”; do not imply
a one-to-one token mapping where there is none.

The line gutter must not make enormous files unusable. Render static HTML for
correctness first, then consider windowing only after measuring a real large
report.

### Syntax highlighting and assets

Reuse `nupp.compiler.doc.highlight` rather than introducing a browser-only highlighter:

- Nupp source uses the compiler's lexer/highlighter, which already gives the
  language-authoritative tokenization.
- Generated Lua uses the existing Scintillua-backed Lua highlighter when it is
  available, with escaped plain text as the documented fallback.

Extract or share the token CSS variables/classes already used by the
documentation site. Coverage-specific CSS adds gutters, hit-state colours,
tree controls, tables, responsive layout, and light/dark themes. The generated
report contains highlighted HTML, so it works from `file://` and does not load
third-party scripts, fonts, or network assets.

## Implementation stages

### Stage 0: settle schema and semantics

1. Add this plan's coverage schema as a small module/type definition with
   fixture examples before generators write it.
2. Specify the initial executable node and branch set, including how failed
   setup/teardown, errors, and loop zero-iterations count.
3. Choose a stable path policy: project-relative slash-separated paths in all
   artifacts, regardless of host platform.
4. Add golden fixtures covering erasure, several statements per line, nested
   branches, lowered forms, anonymous functions, and generated helper lines.

### Stage 1: coverage compiler mode

1. Add coverage to compile/build settings, cache identity, and a separate
   output namespace.
2. Refactor only enough of `nupp.compiler.gen` to make a normal emitter and optional
   coverage emitter share the existing emission logic without adding normal
   per-node checks.
3. Generate per-module manifests and assert every runtime counter ID appears
   once in it.
4. Instrument statements, function entries, and the first structural branch
   set. Preserve line-count invariance in coverage output as a tested property.
5. Add semantic regression tests that execute normal and coverage variants and
   compare values, errors, side effects, and coroutine behaviour.

### Stage 2: runtime collection and command orchestration

1. Implement `nupp.compiler.coverage` counter storage, manifest registration, flush,
   and shard validation.
2. Add `nupp coverage`, isolated run directories, environment propagation,
   cleanup policy, and threshold evaluation.
3. Make the built-in test runner flush reliable partial data for passing,
   failing, skipped, and lifecycle-hook cases.
4. Compile dynamic `.nupp` suites and modules under the same mode.
5. Merge shards deterministically and surface missing/incompatible shards as
   `unknown` warnings and nonzero coverage-command exits.

### Stage 3: reports and CI formats

1. Implement aggregate roll-ups for files and directories.
2. Write JSON, summary JSON, and LCOV from the single aggregate model.
3. Add terminal summary rows sorted by lowest coverage, with clear threshold
   failure diagnostics.
4. Test paths, zero-executable files, partial lines, partial branches, and
   aggregation across processes.

### Stage 4: static HTML explorer

1. Build a coverage page/layout module, sharing only the established
   highlighter and token styles from `nupp.compiler.doc`.
2. Generate root, directory, and file pages plus a semantic left-hand tree.
3. Implement no-JavaScript tables/links first; add sorting, filters, toggles,
   persistent tree state, and synchronized source/Lua scrolling in the small
   report script.
4. Add source gutters, branch details, tooltips/explanations, and cross-links.
5. Add responsive, keyboard, screen-reader, light/dark, and visual regression
   coverage with fixture reports.

### Stage 5: hardening and documentation

1. Document command use, manifest configuration, LCOV/JSON consumption,
   custom-runner `flush()` integration, and what percentages mean.
2. Document why a coverage run is slower and must not be used for benchmarks.
3. Add `nupp coverage --schema`, matching the existing CLI JSON-schema style.
4. Run the full test suite, coverage self-test fixtures, byte-identical normal
   build/fixpoint checks, and a report-open smoke test from a `file://` URL.

## Validation matrix

| Area | Required proof |
| --- | --- |
| Normal build | Existing source produces byte-identical Lua with coverage unavailable/off. |
| Attribution | Every instrumented generated line equals its Nupp source line. |
| Semantics | Normal and coverage variants agree on results, error sites, side effects, yields, and control flow. |
| Counting | Lines, functions, and arms count correctly for positive, negative, partial, and zero-iteration cases. |
| Erasure | Type-only lines are non-executable and excluded from percentages. |
| Failures | Reports remain honest after failed tests and lifecycle hooks; missing flushes are warnings/errors, not false zeros. |
| Processes | Independent test subprocesses merge without collision or double-counting. |
| UI | Root/directory/file pages, tree, sort/filter, source/Lua toggle, and both highlighters work without network access. |
| Accessibility | Tree and tables work with keyboard and expose names/statuses to assistive technology. |

## Risks and decisions to revisit

- **Generic custom runners.** Reliable flush-on-crash is not something a
  generic subprocess wrapper can promise on every LuaJIT host. Keep the
  built-in runner first-class and make unflushed modules visibly unknown.
- **Instrumentation semantics.** Coverage must not “fix” a program by changing
  evaluation order. Add a node kind only after a fixture proves it safe.
- **JIT distortion.** Coverage counters can prevent trace formation. Make this
  explicit in output and never compare coverage-run timings to normal runs.
- **Report size.** Side-by-side syntax-highlighted source is larger than raw
  LCOV. Keep it opt-out (`--format json,lcov`), compressible in CI artifacts,
  and measure before adding client-side virtualization.
- **Highlighting dependency.** The docs renderer's Lua highlighting fallback
  must remain graceful if Scintillua is unavailable; lack of highlighting must
  not block coverage data or source display.
- **Future scope.** Once structural branches are stable, logical-expression
  arms and a coverage-to-test reverse index (“which tests hit this line?”) are
  strong extensions. Do not make either a prerequisite for the first report.
