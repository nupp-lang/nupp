# AOT candidate advisor

Status: proposed — follows `plans/038-aot-functions.md` and
`plans/052-trace-aware-checking.md`

## Decision

Add an advisory analysis which finds unannotated functions that the checked AOT
backend can compile and explains why they are worth benchmarking. Present its
strongest static findings as editor CodeLens entries, expose the complete result
through `nupp aot --suggest` and `nupp lsp aot-candidate`, and optionally join it
with the sampling and trace-abort profiles from one representative run.

The advisor does not add `@aot`, compile a native library, change generated Lua,
or participate in whether source checks. It answers three separate questions and
never combines them into a promise it cannot make:

1. **Eligibility:** can this checked body lower to verified AOT IR for the
   selected target?
2. **Static opportunity:** does the admitted body have a bulk-loop, fixed-width,
   lane, span or LuaJIT property which makes a native comparison worthwhile?
3. **Observed importance:** did a supplied profile see the body consuming enough
   time, interpreted execution or trace aborts to prioritize it?

Only the first answer is a proof. The second is a deterministic cost-model
judgement. The third is evidence from one workload. None predicts a speedup.
`@aot` remains the durable source contract a programmer adds after inspection or
measurement: a required build must compile it, and a regression may not quietly
fall back to LuaJIT.

The first editor text is deliberately modest:

```text
AOT candidate · f64x4 · 4.2 operations/byte
```

With matching profile evidence it may become:

```text
Hot AOT candidate · 14.8% of samples · interpreted
```

It never says “faster”, “15x”, or “add `@aot`” in the lens. The detailed result
offers “benchmark with AOT” before the mechanical “add `@aot`” refactoring.

## Why

The current discovery loop starts with a fact the compiler makes the programmer
state:

1. find a hot function by hand;
2. add `@aot`;
3. discover whether the AOT subset admits it;
4. run `nupp aot` to see whether lanes were selected; and
5. compare `aot = "off"` with `aot = "require"`.

The annotation is serving as a query in steps 2–4 even though its actual meaning
is a required execution contract. That reverses the useful order. The compiler
already owns the parser, checked types, AOT lowering, verified IR, arithmetic-
intensity estimator, lane rewrite, trace catalog, bytecode checker and sampling
profiler. It can find plausible bodies without asking the source to promise
anything first.

Static analysis still cannot answer whether native code pays. It does not know:

- whether the function runs at all or becomes hot;
- its representative span counts or loop trip counts;
- how frequently one native wrapper is entered;
- the distribution which governs data-dependent inner loops;
- whether LuaJIT inlines the surrounding call path;
- the target machine which will run a baseline-compatible artifact; or
- whether latency, throughput, startup, code size or portability is the user's
  objective.

Those are reasons to report evidence, not reasons to hide eligibility. A
function that lowers to a four-lane numeric span loop is worth making visible;
the editor must stop short of claiming that visibility is a benchmark.

## Governing invariants

1. **Advisory means non-semantic.** Enabling, disabling, refreshing or losing the
   advisor changes no diagnostic, generated Lua, AOT artifact or build answer.
2. **Checking never runs a program.** Profile evidence may rank a result, but is
   not an input to type checking, AOT eligibility or `@aot` enforcement.
3. **No speculative mutation.** Candidate analysis does not attach annotation
   facts to the CST, rewrite source or leave a body marked `aotRequired`.
4. **The real backend decides eligibility.** Do not maintain a second syntactic
   list of AOT-compatible constructs for hints. Speculative lowering invokes the
   same checked lowering and verifier as a required build.
5. **One body may fail without hiding the next.** An unsupported function yields
   one structured refusal and candidate scanning continues through the file.
6. **Eligibility is target-relative.** Target triple, feature tier, AOT IR
   version and numeric-contract version travel with every result.
7. **Opportunity is not profitability.** Arithmetic intensity, lane width and
   trace state are reported as facts. No result contains a synthetic speedup.
8. **Absence of samples is not coldness.** Sampling can miss short runs and
   LuaJIT can inline frames out of the walked stack. A body unseen in a profile
   retains its static result and receives no negative runtime conclusion.
9. **Stale profiles are inert.** Runtime evidence joins only when its source
   fingerprint, optimization level, trace profile and target match the editor's
   checked document and selected target.
10. **No new profiler.** Runtime prioritization reuses `profile.sample` and
    `profile.trace`; it does not instrument every call, loop iteration or span
    access and does not introduce a third VM hook.
11. **No editor warning.** A valid ordinary implementation is not wrong. The
    advisor publishes CodeLens and inspection data, never a warning squiggle or
    lint enabled by default.
12. **The annotation remains intentional.** The only source edit is an explicit
    refactoring selected by the user. No build or editor silently adds `@aot`.

## Analysis representation

Add `src/nupp/compiler/aot/advisor.nupp`. It consumes a checked module, one
selected AOT target and optional runtime evidence. It returns source-ordered
records and performs no I/O.

```text
AotCandidate {
    id
    name
    file
    declarationRange
    bodyFingerprint
    target
    status              contracted | candidate | eligible | ineligible
    recommendation      inspect | benchmark | prioritize | none
    eligibility
    opportunity
    profile
}
```

`id` is a compiler-owned identity derived from the canonical source key and the
declaration's byte offset. It is for joining one build's source, profile and LSP
answer; it is not a public symbol name and does not survive moving a declaration.
`bodyFingerprint` covers the checked source body, selected optimization level and
facts which affect lowering. A comment outside the declaration does not stale a
profile; changing its body, signature or relevant declaration does.

`status` distinguishes four useful states:

- `contracted`: the source already carries `@aot`; show its current lowering in
  inspection but do not suggest the annotation it already has;
- `candidate`: unannotated, eligible and carrying enough static or runtime
  evidence for an editor lens;
- `eligible`: verified AOT IR exists, but the first cost model has no affirmative
  reason to interrupt the editor; retain it in explicit CLI inspection;
- `ineligible`: lowering declined, with the first stable reason and source site.

The recommendation is separate from status. A `candidate` without profile data
asks for `benchmark`; matching hot evidence upgrades it to `prioritize`. An
eligible body may remain `inspect`. An ineligible body is `none` unless an
explicit cursor query asks why.

### Structured evidence

Do not build prose in the analyzer. Each reason has a stable identity, values and
a renderer shared by the CLI and LSP:

```text
AotEvidence {
    id
    class       eligibility | opportunity | profile | caution
    site
    values
}
```

The initial opportunity identities are:

- `aot/span-loop`: one checked native call covers a complete loop over spans;
- `aot/lane-lowered`: the verified rewrite selected a lane shape and width;
- `aot/lane-declined-thin`: the loop is eligible but below the lane intensity
  threshold;
- `aot/lane-refused`: the body wanted lanes and the rewrite named what stopped
  it;
- `aot/fixed-width-work`: repeated explicit `f32`, `i32` or `u32` operations can
  stay in native registers instead of using ordinary FFI-backed round trips;
- `aot/struct-span-plumbing`: repeated span and reified-field operations lower
  directly in AOT IR;
- `aot/scalar-only`: the complete body compiles, but no lane opportunity was
  selected;
- `aot/low-work`: the admitted body contains too little counted work for a lens
  without runtime evidence.

The initial profile identities are:

- `aot/profile-hot`: samples attribute a documented share of the captured window
  to the function;
- `aot/profile-interpreted`: attributed samples spent time in the interpreter;
- `aot/profile-compiled`: attributed samples spent time in compiled traces;
- `aot/profile-trace-abort`: a normalized abort belongs to the body;
- `aot/profile-blacklisted`: the body was permanently demoted in the observed
  run.

`compiled` is context, not evidence against AOT. The committed Mandelbrot result
shows scalar C beating a clean LuaJIT trace, so the advisor must not suppress a
lane or fixed-width opportunity merely because the JIT compiled it.

Keep the identity catalog beside the advisor rather than adding NUPP diagnostic
codes. These are inspection results, not language misuse.

## Speculative AOT lowering

Refactor `aot/lower.nupp` so discovery of declarations is independent from
discovery of `@aot` applications. The existing `lower.scan` already collects
visible local helpers and structs; extend its result with every visible function
shape the released AOT backend could accept.

Introduce one explicit input describing how a body reached lowering:

```text
Request {
    function
    mode        contract | inspection
    contract    written @aot/@relax settings, or inspection defaults
}
```

Contract mode retains every current rule. Inspection mode supplies the neutral
defaults—no floating-point relaxation, lane selection left to the existing cost
model—and does not pretend an annotation was written. Both modes enter the same
signature lowering, helper resolution, scalar IR verifier, intensity estimator
and lane rewrite.

Do not implement inspection by inserting synthetic annotation tokens or setting
`Funcbody.aotRequired`. Synthetic source sites corrupt fixes and diagnostics, and
mutating a checked tree would let a later request observe an annotation that was
never in the document.

Candidate lowering is isolated per function. Today one sentinel rejection can
unwind compilation of an annotated file; the advisor catches that rejection for
one request, records its stable message and source site, then tries the next.
Unexpected errors and IR-verifier failures still raise as compiler defects.

The CLI advisor and LSP pass checked trees. They do not use the parse-only spike
path as evidence about a real project. That ensures aliases, effects, ownership,
associated types and selected target layouts are the same facts a required build
would consume.

The first release scans only the declaration forms the production AOT backend can
replace where written. Nested closures, constructors, bodyless declarations,
arbitrary function-valued bindings and dynamically installed methods remain
ineligible rather than receiving an approximate hint. Widen discovery only when
the backend can dispatch that form under `aot = "require"`.

## Static opportunity model

Eligibility alone is too broad for an editor lens, while the existing
operations-per-byte threshold answers only whether lane assembly pays relative
to scalar C. It does not answer whether crossing from LuaJIT to scalar C pays.
Keep these two models separate.

The first AOT opportunity model is deliberately categorical. A body becomes a
static `candidate` when it is eligible and at least one of these holds:

1. lane rewriting succeeds and the existing intensity model selected it;
2. the loop contains repeated explicit fixed-width work whose ordinary lowering
   uses FFI storage or helpers;
3. the body contains enough repeated span or reified-struct operations for the
   wrapper to replace per-element plumbing with one native boundary; or
4. the body is scalar AOT but a normalized trace analysis identifies an
   unconditional recorder blocker which AOT IR does not contain.

The last case is intentionally narrow. Do not infer that an arbitrary LuaJIT
blocker makes an ineligible body a candidate, and do not share the `@jit` and
`@aot` contract catalogs. The advisor merely joins two independent analyses over
one body.

A scalar-only eligible function with none of these remains visible under
`--suggest --all` and an explicit cursor query, but receives no CodeLens. A
threshold must not make a tiny helper noisy merely because it technically
lowered. Conversely, a below-threshold lane decision does not erase fixed-width
or profile evidence.

Centralize every count and threshold in `advisor.nupp`, include it in the JSON
result, and gate it with repository benchmarks before enabling lenses by
default. The threshold is an editor-noise policy, not part of AOT compatibility.

Never estimate a percentage speedup. The current benchmark demonstrates that
span plumbing, control-flow divergence and numeric width can dominate the same
operation count in different directions. The model reports the facts it counted
and asks for a comparison.

## Command-line inspection

Extend the existing command rather than introduce another top-level noun:

```bash
nupp aot --suggest FILE
nupp aot --suggest --all --json FILE
nupp aot --suggest --profile build/aot-profile.json FILE
nupp aot --suggest --function integrate --emit ir FILE
```

Without `--suggest`, `nupp aot` retains its exact current meaning and requires
written `@aot` functions. With it, the command checks the project file, analyzes
every supported visible function and emits no C unless `--emit` explicitly asks
for the candidate selected by `--function`. A missing or ambiguous name is an
error rather than permission to choose one.

Human output leads with the recommendation and evidence:

```text
src/physics.nupp:42: integrate: benchmark AOT
  verified for aarch64-apple-darwin/neon
  4.20 operations per byte (84 over 20), f64x4
  repeated span and reified-struct work

src/vector.nupp:18: length: eligible, not suggested
  scalar only; no static evidence that one native call pays

src/parser.nupp:91: advance: not eligible
  src/parser.nupp:96:14: aot: dynamic table access has no AOT IR form
```

Default `--suggest` prints `candidate` and `contracted` entries. `--all` includes
quietly eligible and ineligible bodies so the command also answers “why did the
editor not show anything?”

Extend the JSON schema with:

- schema and advisor-catalog versions;
- target triple, architecture and feature tier;
- source identity, range and body fingerprint;
- status and recommendation;
- structured eligibility refusal, when present;
- operations, touched bytes, intensity, selected lanes and refusals;
- structured opportunity and caution identities;
- matching profile evidence and the profile identity used; and
- an optional exact edit which adds `@aot` at the declaration indentation.

The command needs no C compiler. It verifies and rewrites IR in memory; native
compilation remains a property of `aot = "require"`.

## Language-server surface

### Cursor query

Add the same one-shot pattern as trace inspection:

```bash
nupp lsp aot-candidate --json FILE LINE COLUMN
```

and the corresponding request:

```text
$/nupp/aotCandidate
```

It selects the smallest supported visible function containing the cursor and
returns its complete `AotCandidate`, including an ineligibility reason. It reads
the language server's unsaved overlay, selected workspace target and cached
checked result. It runs no program, writes no file and adds no annotation.

This query is the authoritative detail behind editor presentation and gives
agents and clients a stable interface without scraping CodeLens titles.

### CodeLens

Implement `textDocument/codeLens` and advertise `codeLensProvider`. Lenses are
computed lazily when a client asks for a document, not during diagnostic
publication. Return one lens above each unannotated `candidate`; do not return a
lens for every eligible or ineligible function.

The title contains the useful result without requiring a client extension:

```text
AOT candidate · f64x4 · 4.2 ops/byte
```

or, with valid runtime evidence:

```text
Hot AOT candidate · 14.8% samples · interpreted
```

Use one server command, `nupp.showAotCandidate`, carrying URI, document version,
function identity and target. Advertise it through
`workspace.executeCommandProvider` and handle `workspace/executeCommand` by
returning the structured cursor-query result. A Nupp-aware editor may render
that result in a panel. A generic LSP client still receives a readable lens and
can use the code actions below.

Candidate analysis must offer cancellation between bodies and discard results
when the document version changes, under the existing LSP stale-answer rules.
Cache it by checked document version, target and advisor-catalog version. Do not
emit C or render full IR merely to draw a lens.

### Code actions

At an eligible declaration offer `refactor.rewrite` actions:

- `Inspect AOT candidate` invokes the structured query;
- `Add @aot` inserts the annotation with the declaration's indentation; and
- `Add @aot(lanes = false)` is offered only when the user has inspected a scalar
  body for which explicit lane refusal is meaningful.

Do not title the first edit `Fix`, `Optimize`, or `Make faster`. The action is a
contract edit whose performance still needs measurement. Existing annotations
and an `@jit` contract suppress the edit; the ordinary NUPP2901 rule continues
to reject promising one body to two compilers.

Advertise `refactor.rewrite` beside the existing quick-fix kind. Advisor actions
are selected from the declaration under the requested range and do not depend on
a diagnostic being present.

No dismissal is written into source. Editors already allow CodeLens to be
disabled, and the high-confidence filter is the first noise control. Add a
project-level advisory setting only if real use shows a repeated need; do not
invent a suppression annotation before then.

## Runtime evidence

Static advice ships first. Runtime evidence is a prioritization layer over the
same candidates, not a prerequisite for editor support.

### One joined report

Add an AOT-advisor mode to `nupp run` which starts the existing sampling and
trace sessions together for the requested window and writes a structured joined
report after the program exits:

```bash
nupp run --aot-profile[=build/aot-profile.json] app.nupp
```

The default path is in the target's disposable build state rather than beside
source. A direct use of `profile.sample` and `profile.trace` remains supported;
the flag is orchestration and post-processing, not a third profiler.

Do not instrument function entries or loop iterations in the first release.
That would change the trace behavior being measured, add overhead proportional
to calls, and manufacture precise-looking call counts which the sampling
profiler never observed.

The joined report contains:

```text
AotProfile {
    version
    createdAt
    entry
    optimizationLevel
    traceProfile
    target
    intervalMs
    totalSamples
    sourceFingerprints
    candidates[] {
        id
        bodyFingerprint
        samples
        compiled
        interpreted
        cCode
        collecting
        compiling
        aborts[]
    }
}
```

Extend `SampleReport` with its already-built structured rows instead of parsing
the collapsed-stack rendering back into data. Collapsed text remains unchanged.
Join rows to the supported top-level functions by canonical source key and
debug function name, then confirm the body fingerprint from the build which ran.
Trace aborts already carry normalized locations and identities; attribute only
an abort whose mapped source range lies inside the declaration.

The join is conservative:

- samples attributed directly to the function count;
- an inlined function absent from the walked stack receives no samples and no
  `cold` conclusion;
- a C sample inside the AOT wrapper is context, not proof about ordinary Lua;
- a source-name collision which cannot be resolved is retained as an unmatched
  row rather than guessed;
- profiles from a different optimization level, hot-reload generation, trace
  profile, body fingerprint or target do not decorate the lens.

Sample share ranks work inside the captured window; it is not an application-
wide percentage unless the whole application was deliberately profiled. Render
the interval, total samples and zone filter beside the percentage so a reader
can see what it means.

### Benchmark remains the decision

The profile finds where comparison effort should go. It does not replace the
comparison. Documentation directs the user to build and run the same
representative workload under `aot = "off"` and `aot = "require"`, validate
answers, alternate run order and compare distributions rather than one timing.

A later command may orchestrate those two builds when a project declares a
benchmark entry and correctness oracle. This plan does not invent a benchmark
from an arbitrary function signature or call it with fabricated values.

## Ranking and editor policy

The default ranking is deterministic:

1. matching blacklisted or interpreted hot candidates;
2. matching hot candidates with lane or fixed-width opportunity;
3. static lane candidates above the checked intensity threshold;
4. static fixed-width and struct/span candidates;
5. scalar-only eligible bodies, visible only under explicit inspection; and
6. ineligible bodies, visible only under `--all` or a cursor query.

Within a rank, matching sample count descends first, then source path and
declaration offset provide stable ties. Do not compare raw elapsed time from two
profiles or merge profiles with different sample intervals as though their
counts were one run.

The initial CodeLens budget is one lens per candidate and a configurable
implementation cap per document, with the highest-ranked results kept. Record a
structured `aot/lens-budget` omission in `--suggest --all` so a missing lens is
explainable. Select the cap from editor latency and noise tests, not aesthetics.

## Diagnostics and observability

No new source diagnostic is introduced. In particular:

- an eligible unannotated function is valid ordinary Nupp;
- an ineligible unannotated function has made no AOT promise;
- a stale or missing profile is normal;
- a low-confidence opportunity is not a warning; and
- declining a lens is not an optimization remark during an ordinary build.

`@aot` retains NUPP2901–NUPP2903 and the existing required-build behavior.
Explicit inspection uses `aot:` prose and stable advisor identities, not new
NUPP codes.

`--remarks` may report advisor decisions only when an advisor or profile mode was
requested. An ordinary `nupp check`, build or editor diagnostic publication must
not scan every function and narrate that most were ineligible.

## Documentation

Update `docs/tooling/aot.md` with a “Finding candidates” section before the
annotation workflow. It explains:

- eligibility, static opportunity and observed importance are different;
- why the advisor does not predict a speedup;
- why a clean LuaJIT trace can still lose to scalar or lane AOT;
- why a trace abort alone does not make an unsupported body eligible;
- how to read intensity and lane results;
- how CodeLens remains advisory and optional;
- how profile fingerprints prevent stale editor claims; and
- how to perform the final `off` versus `require` comparison.

Update `docs/tooling/profiling.md` with the joined AOT report and its sampling
limits. Update `docs/tooling/lsp.md`, `docs/tooling/cli.md`, generated reference
material and schemas for the new query, CodeLens capability and flags.

Include one end-to-end example with three functions:

1. an unannotated span kernel which receives a static candidate lens;
2. a tiny or scalar body which is eligible but quiet; and
3. a hot dynamic body which profiling makes worth inspecting but AOT rejects
   with an exact structural reason.

The third example matters: the tool finds AOT opportunities, not a pretext to
label every hot function native-compatible.

## Test matrix

### Candidate lowering

- an unannotated eligible function produces byte-identical verified IR to the
  same body under neutral `@aot` settings;
- inspection does not mutate `aotRequired`, lane flags, relaxed guarantees or
  annotation chains on the checked tree;
- one rejected body does not prevent later bodies from being analyzed;
- unexpected lowering and verifier failures remain compiler errors rather than
  ineligibility;
- helpers, structs, ownership regions and target layouts resolve from the real
  checked module;
- already contracted, eligible, candidate and ineligible statuses are distinct;
- nested functions and unsupported declaration forms are declined without
  approximate dispatch promises;
- source order and candidate identities are deterministic; and
- target triple, tier, IR version and numeric contract enter the cache key.

### Opportunity model

- lane-lowered, thin, refused, fixed-width, span/struct and scalar-only evidence;
- thresholds immediately below, at and above their boundaries;
- a clean trace does not erase an AOT opportunity;
- a trace blocker does not admit a body the AOT verifier rejects;
- no estimated speedup appears in text or JSON;
- profile evidence changes ranking, never eligibility or generated artifacts;
  and
- missing and stale profiles produce the same static answer.

### CLI

- `nupp aot` without `--suggest` retains its output and exit behavior;
- default suggestions, `--all`, JSON, schema and selected targets;
- a checked project overlay rather than parse-only source determines the result;
- no C compiler is searched for during suggestion;
- exact source ranges and add-annotation edits; and
- human output renders every stable evidence and refusal identity.

### LSP

- CodeLens capability advertisement and source-ordered lenses;
- no lens for contracted, quietly eligible or ineligible bodies;
- cursor inspection returns all four statuses;
- code actions insert at the right indentation and refuse an `@jit` conflict;
- unsaved overlays are analyzed rather than disk text;
- document edits and target changes invalidate cached answers;
- cancellation between bodies and `ContentModified` for stale requests;
- no candidate becomes a published diagnostic; and
- the per-document lens budget keeps the highest-ranked deterministic set.

### Runtime evidence

- the joined mode starts and stops the existing sample and trace sessions;
- structured sample rows render to the unchanged collapsed-stack text;
- compiled, interpreted, C, GC and compiler counts sum to each row's count;
- normalized aborts map only inside the declaration range;
- duplicate function names in separate modules do not collide;
- ambiguous and inlined-away frames do not become guessed or cold evidence;
- body, target, optimization, trace-profile and hot-reload mismatches reject the
  join; and
- a profile file is disposable evidence: deleting it changes no check or build.

### Repository verification

- focused AOT, CLI, LSP, profiler and schema suites;
- editor latency measurement on a source with many visible functions;
- advisor analysis allocates no native artifact and invokes no C toolchain;
- `./bin/nupp test`; and
- `./bin/nupp fixpoint` after compiler sources change.

## Non-goals

This plan does not add:

- a complete native Nupp runtime;
- whole-program automatic AOT compilation;
- an `aot = "auto"` build policy;
- silent per-function fallback in an AOT-required build;
- automatic insertion of `@aot`;
- a warning or lint for ordinary eligible code;
- a claimed or inferred numerical speedup;
- entry or loop instrumentation for exact call and trip counts;
- fabricated benchmark inputs for arbitrary functions;
- automatic acceptance of floating-point relaxation;
- support for declaration forms the production AOT dispatcher cannot replace;
- a second trace reason catalog or sampling implementation; or
- profile data as an input to checking, IR verification or reproducible builds.

Transparent region outlining remains a later optimizer. The advisor may provide
evidence for it, but this plan analyzes whole functions because that is the unit
the released AOT contract and wrapper compile.

## Delivery

1. Refactor AOT declaration discovery and lowering into explicit contract and
   inspection requests, with per-function structured refusals and no CST
   mutation.
2. Add `aot/advisor.nupp`, stable evidence identities, target-aware caching and
   focused tests while classifying every eligible body as quiet inspection.
3. Add the static opportunity model, checked-in benchmark fixtures and thresholds;
   keep CodeLens disabled until the default candidate set is useful and quiet.
4. Add `nupp aot --suggest`, `--all`, JSON/schema output and documentation. This
   is the first usable release and needs no profiler or editor support.
5. Add `nupp lsp aot-candidate`, `$/nupp/aotCandidate`, annotation refactorings
   and lazy CodeLens with cancellation, unsaved overlays and document-version
   caching.
6. Extend `SampleReport` with structured rows and add the joined
   `nupp run --aot-profile` report by composing the existing sampling and trace
   sessions.
7. Join valid runtime evidence into CLI ranking and editor lenses, retain stale
   evidence as inspectable metadata, and test every fingerprint boundary.
8. Update AOT, profiling, LSP, CLI and generated reference documentation; run the
   complete suite and compiler fixpoint.

The plan is complete when an unannotated eligible kernel can be discovered from
the CLI and an unsaved editor buffer, the result explains the verified lowering
and static evidence without claiming a speedup, a representative profile can
prioritize it without affecting checking, and adding `@aot` remains an explicit
measured decision whose required-build semantics are unchanged.
