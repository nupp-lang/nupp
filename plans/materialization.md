# Comptime materialization

## Implementation status

M0 through M7 are implemented. The specialized PEG backend cleared the frozen
1.50x gate at a 3.04x geometric mean, and the second provider is a reflected,
typed keyed field codec. M8 now persists canonical blueprints and rendered
backend expressions, versions provider/helper/emitter/runtime-expression ABIs,
reports bounded observations from JSON builds, and enforces evaluator, call,
wall-clock, result, protocol, IR and provider limits.

The later anchored-recognition comparison with Rust `regex` now also clears
every named workload. On the recorded LuaJIT run, PEG reached 1.09x for short
identifiers, 1.59x for long identifiers, 1.61x for fixed dates and 1.20x for
HTTP routes, for a 1.35x geometric mean. The benchmark remains
`bench/peg-vs-rust-regex.nupp` rather than replacing the semantic LPeg suite.

The remaining work is deliberately outside the closed materialization core:
add declaration annotations and fine-grained cross-module invalidation to the
now structural C2a reflection graph, replace the synchronous LSP wait with
cancellable process suspension, and run the field-codec provider against the
external tecs acceptance corpus.

## Decision

Nupp will let a `comptime do ... end` block return a compiler-owned opaque
value when the block has an explicit expected runtime type. That type selects a
materializer from a closed, compiler-owned table. The materializer serializes
the opaque value as one runtime expression.

The rule is:

> A comptime block may return a compiler-owned opaque value. An explicitly
> declared expected runtime type at the block's position selects a materializer
> from a closed, compiler-owned table, and that materializer emits the runtime
> value represented by the opaque result.

Comptime still evaluates ordinary Nupp and returns a value. It cannot name a
declaration to add, inspect the source program, construct a syntax tree, paste
text, or choose an emitter. The materializer is a second serializer for a value
the compiler owns, beside the canonical literal serializer already used for
numbers, strings and tables.

The first materialized value will be a statically compiled PEG matcher. It is
the proving case, not the shape of the mechanism. The framework is not complete
until a second provider driven by semantic type information lands without a
change to the evaluator, worker protocol, expected-type rule, cache model or
emission interface.

## Why this is an extension of values, not a macro system

Ordinary comptime has this boundary:

```text
ordinary Nupp evaluation -> quotable value -> canonical literal source
```

Materialization adds one parallel exit:

```text
ordinary Nupp evaluation -> compiler-owned opaque value
                         -> expected-type materializer
                         -> runtime expression source
```

The distinction from a macro rests on four invariants.

1. **The provider table is closed and compiler-owned.** User code, packages,
   plugins and manifests cannot register a materializer. Adding one is a
   language change: it adds a prelude surface, a semantic specification,
   compiler implementation, diagnostics and acceptance tests.
2. **The boundary is an explicitly declared runtime type.** A materializer is
   not selected by inference from a distant call, overload or inferred return.
   Removing the declaration reports that an opaque comptime result needs an
   explicit materializable type; it never silently selects different code.
3. **The value cannot observe the program.** It is assembled through a sealed,
   typed constructor API. It cannot read a CST or AST, enumerate names or
   scopes, capture a runtime binding, access a file, or decide where generated
   code lands.
4. **The output has semantics independent of its spelling.** A PEG matcher, a
   field codec or a command parser has a specified runtime contract. The
   materializer may choose a comparison chain, lookup table or helper call
   without changing that contract, as the ordinary generator already chooses
   how a typed construct lowers to Lua.

The provider emits an expression that constructs the declared value. It does
not add a declaration or module, so comptime's existing exclusion of
declaration and module generation remains unchanged. It also does not
specialize an existing runtime function automatically: the author explicitly
constructs a compiler-owned value whose public contract includes compilation.

## What this is for

Materialization is for static descriptions whose useful runtime form is
executable and whose semantics are narrow enough for the compiler to own.

The initial and acceptance cases are:

- **PEG matchers.** A pattern graph becomes either a flat program consumed by a
  pure-Lua parsing machine or a specialized matcher closure. A bundle can use
  it without linking LPeg.
- **Type-directed codecs.** A descriptor built from `reflect(T)` becomes a
  typed encoder/decoder or field projection. The real acceptance workload is
  the keyed codec `fieldcodec.tl` builds through `load()` at run time from a
  table component's declared `fields`. It is not a C-layout codec and does not
  replace the struct size and fingerprint work in `plans/layout.md`.

Other plausible providers include finite state machines, declarative command
parsers, binary layouts and protocol validators. None is admitted merely
because the framework can host it; each owes the evidence and contract in
§Provider admission.

A materializer returns a value with a fixed, already declared interface. A
derive remains different: it adds methods, interfaces or constants to a
declaration. A module generator remains different too: it adds names another
module can import. Neither is reached by widening the materializer emission IR.
They may reuse reflection, fingerprints and provenance later, but retain their
separate phase and proposal.

This plan does not expose a general `Code<T>` builder. One closed provider able
to express arbitrary functions would make the provider table technically
closed while making the language semantically macro-capable. Typed staged
programming may be proposed later, but it is not smuggled in as the generic
case of this design.

## Surface rule

A materialized block needs a runtime type written on the declaration that owns
the expression:

```nupp
const Identifier: nupp.peg.Matcher<integer> = comptime do
    const head = nupp.peg.choice(
        nupp.peg.range("az", "AZ"),
        nupp.peg.literal("_")
    )
    const tail = nupp.peg.choice(head, nupp.peg.range("09"))
    return nupp.peg.compile(
        nupp.peg.sequence(head, nupp.peg.zeroOrMore(tail))
    )
end
```

The checker resolves `nupp.peg.Matcher<integer>` before evaluating the block.
The block itself returns a comptime-only `nupp.peg.Blueprint<integer>`. The
expression's runtime type is the written `Matcher<integer>`, and generated Lua
constructs that value directly. A blueprint with runtime inputs has the
distinct type `nupp.peg.FactoryBlueprint<R, S>`; `nil` is not used to mean an
empty slot set.

The expected type must be attached directly to the declaration or field whose
initializer is the block. These do not select a provider:

```nupp
local inferred = comptime do
    return nupp.peg.compile(pattern)
end -- opaque result needs an explicit materializable runtime type

consume(comptime do
    return nupp.peg.compile(pattern)
end) -- a call parameter is not an explicit materialization boundary
```

A return annotation on an enclosing runtime function is likewise too far away.
This local rule makes the generated behavior discoverable at the expression
and keeps overload resolution independent of evaluation.

### Runtime inputs through factories

Generated behavior sometimes needs runtime callbacks or resources. Comptime
does not capture those bindings. The materialized value is instead a factory
whose argument is an ordinary declared record:

```nupp
local record NumberActions
    number: function(text: string): number
end

const buildNumber:
        function(NumberActions): nupp.peg.Matcher<number> = comptime do
    const digits = nupp.peg.capture(
        nupp.peg.oneOrMore(nupp.peg.range("09"))
    )
    return nupp.peg.compile(digits:action("number"))
end

const Number = buildNumber(new NumberActions {
    number = function(text: string): number
        return assert(tonumber(text))
    end,
})
```

### The materialization relation

The checker learns one new kind of type relation. It is a provider-owned,
partial type-level function over a closed opaque result type `O` and the
directly declared expected runtime type `E`:

```text
materialization(O, E) -> accepted bindings | mismatch
```

It is not subtyping and does not add a general conversion. After typechecking
the block and resolving the written expected type, the checker asks the one
provider registered for the resolved nominal roots of `O` and `E`. Acceptance
makes the comptime expression's runtime type exactly `E`; mismatch is reported
at that explicit boundary. Provider selection and this relation run before
evaluation only as far as needed to establish that an opaque result family is
possible, then validate its finalized result and slot schema afterward.

PEG declares exactly these relations initially:

```text
Blueprint<R> -> Matcher<R>

FactoryBlueprint<R, S> -> function(A): Matcher<R>
    when A is a resolved nominal record
    and fields(A) are exactly slots(S), by name and function type
```

`S` is the blueprint's immutable slot schema, not a runtime table. Result type
arguments must be identical after ordinary type resolution; this relation does
not widen `R` or infer it from `E`. Slot compatibility uses the normal function
assignment rule, including parameter and result packs, after exact field-name
equality has established which declarations correspond.

The generated factory binds action fields to locals once and closes over those
locals. Matching pays the callback call, not a table lookup on every action.
There is no compiler-side function identity, binding name, closure capture or
link step.

Exact slot equality is deliberate in the first version. A missing field is an
unfulfilled input, and an extra field usually means a misspelled or dead action.
Allowing a larger reusable environment record can be considered after a real
consumer wants it.

### Results are typed

A provider declares the relationship between the opaque blueprint's result and
the runtime value's type parameters. PEG does not inherit LPeg's untyped
multiple-return surface by accident. Its first version produces one declared
result:

```text
Matcher<integer>       recognition position
Matcher<string>        one substring capture
Matcher<User>          one action-produced value
Matcher<{Token}>       an explicit collection
```

Providers may deliberately expose a gradual result where their domain needs
one, but materialization itself does not erase result types.

## Compiler-owned opaque values

An opaque comptime value has:

- a nominal compiler-owned type;
- a provider identifier and schema version;
- provider-owned payload reachable only by its intrinsic constructor API;
- structural provenance for every constructed node;
- no runtime representation and no canonical literal spelling.

The evaluator may hold identity, sharing and cycles inside the value. Recursive
grammars therefore remain graphs while they are assembled. They do not weaken
the ordinary rule that a quoted table cannot contain sharing or cycles.

Only direct intrinsic operations can observe or combine an opaque value. For a
PEG pattern those initially include constructors and methods. An arbitrary
table cannot forge one, and `tostring`, `pairs`, equality against an unrelated
handle, serialization and runtime escape are unavailable unless the provider
specifies them.

The implementation keeps opaque payloads in a private evaluator registry keyed
by fresh handle identity. The handle's Lua table, if a table is used as the
implementation box, carries neither the payload nor a public tag; only registry
membership makes it opaque. Every evaluator operation and result path tests
that membership before ordinary Lua dispatch, table traversal, metatable checks
or quotability. Returning a handle without a selected materialization boundary
therefore reports an opaque-value/materialization diagnostic, never NUPP2413's
complaint about a table with a metatable. User code cannot reach the registry or
manufacture an existing identity.

Operator sugar is not part of the opaque-value floor. M4 may add PEG's `+`,
`*`, `^` and unary operators only after the checker declares their typed
contracts and the evaluator dispatches the resolved compiler-owned operation
directly. It does not enable general Lua metamethod dispatch at comptime, and
ordinary quoted tables with metatables remain NUPP2413.

Reusable `@comptime` functions may accept and return opaque values. File-local
helpers are enough for the first implementation; cross-module comptime helpers
later transport the same provider and schema identities in their checked
interface.

## Finalization and the worker boundary

Materialization depends on comptime's minimum isolated-worker floor. The
landed evaluator is budgeted but still direct; a public opaque provider does
not ship while a live host graph could be retained by the checker or LSP. A
live graph or host object cannot cross the eventual process boundary, so each
provider owns a `finalize` operation:

```text
live opaque graph -> validate -> canonical blueprint payload
```

Finalization happens inside the worker before a successful result is returned.
It must:

- resolve cycles to stable rule or node indices;
- reject invalid graphs with provenance-bearing diagnostics;
- order maps and otherwise canonicalize equivalent construction histories;
- remove evaluator identity and addresses;
- produce a bounded, acyclic protocol value;
- attach the provider id, schema version, output relation and provenance table;
- compute a content fingerprint independent of process and construction order.

The compiler treats the returned payload as untrusted input even though its own
worker produced it. The selected provider validates the schema, indices, sizes,
types and resource limits again before lowering. A crashed or compromised
worker cannot ask the generator to paste source or address an arbitrary local.

For PEG the finalized payload is not required to be the exact runtime VM
bytecode. Preserve the analysis needed by every backend:

```text
Pattern graph with provenance
    -> nullability, fixed length, FIRST sets, capture shape, rule validation
    -> normalized matcher blueprint
        -> flat parsing-machine program
        -> specialized runtime expression
```

The quoted interpreter program uses rule indices and flat tables because a
runtime table cannot carry the recursive graph directly. The specialized
backend should not have to recover high-level facts from bytecode after the
provider already proved them.

## Materializer registry

The registry is a static compiler table. A registration contains:

```text
provider id and schema version
opaque comptime result types
materialization-relation implementation
payload validator and fingerprint version
reference backend, when the provider has one
specialized backend, when justified
runtime helper and feature requirements
diagnostic and hover summarizers
```

Selection uses resolved nominal identity and checked type structure, never a
spelled type name. A project cannot shadow `nupp.peg.Matcher` with an unrelated
record and select the PEG provider. Generic arguments and a factory action
record are passed as immutable semantic descriptors, not mutable checker
tables.

There is no registration API in Nupp source, the manifest, a plugin, a build
provider or a compiler command line. A materializer added by a compiler fork is
part of that compiler's language in the same way as a new builtin lowering.

## Emission contract

A provider returns a structured internal runtime-expression IR, not Lua source.
The IR is private to the compiler and just large enough to express a value
constructor:

- literals, tables and field access;
- hygienic generated locals;
- closures and immediately invoked closures;
- conditionals, loops and returns inside those closures;
- calls to named compiler runtime helpers;
- calls through declared factory inputs;
- provider-owned immutable data tables.

It cannot express a module, top-level declaration, `require` chosen by user
data, access to a source binding, arbitrary global assignment, `load`, or a raw
source fragment. The ordinary generator validates and renders this IR.

Compiler helpers are also selected from a closed table. A provider may request
`nupp.peg.vm`, for example, but cannot derive a module name from its
payload. Helper requests participate in the target's semantic helper and
runtime-feature accounting. A pure generated-Lua helper records no native
feature; a future provider with a native backend would use the same conservative
feature detection as `nupp.regex`.

### Line numbers

The materialized expression renders on the physical line containing the
`comptime` token. Every remaining source line occupied by the block becomes a
blank generated line. Internal closures and statements use semicolons and do
not introduce a generated newline.

This preserves the line-count invariant and requires no source map. A runtime
failure in generated machinery points at the materialization expression;
callbacks passed through a factory retain their own ordinary source locations.

Every provider has generated-source and per-function bytecode limits below the
LuaJIT parser and bytecode ceilings. Generated functions also stay below
LuaJIT's hard limits of 200 local variables and 60 upvalues. The expression IR
renderer splits a large value among nested private closures before it reaches
any of those limits while keeping one logical source line. A value that still
exceeds a provider's lower declared cap is rejected with its blueprint size,
the limit it reached and the provider-specific way to divide it.

## Provenance and diagnostics

Every opaque constructor records:

- the source node that called it;
- the current bounded comptime call stack;
- the provider operation and the child handles it consumed.

Combining values preserves this provenance graph through finalization. It is a
semantic requirement, not tooling polish: generated descriptions assembled by
helpers and loops otherwise report failures against text that does not contain
the error.

A PEG error can consequently say both where the invalid operation was applied
and where a surprising child came from:

```text
NUPPxxxx: repetition can match the empty string
  grammar.nupp:9:38
      return nupp.peg.compile(head * tail^0)
                                     ^^^^^^
  the repeated pattern is empty when built by
  grammar.nupp:4:14  token(p) -- nupp.peg.space()^0
```

`NUPPxxxx` is illustrative. The provider reserves its real code through the
ordinary diagnostic registry when the diagnostic is implemented.

Provider diagnostics reserve codes through the ordinary registry rather than
claiming a range in advance. The common layer needs codes for:

- opaque result without an explicit materializable runtime type;
- no provider for the declared type and opaque result;
- provider payload rejected at the worker boundary;
- action-slot shape or signature mismatch;
- materialized output over its size or complexity limit;
- backend unavailable for the selected target.

Provider-specific diagnostics point into the provenance graph and carry their
normal `help`, `related`, `docs` and whole-fix structure.

## Checking, building and tooling

`nupp check` evaluates, finalizes, validates and lowers a materializable block
under the selected target and optimization context because emission validity is
part of whether that program checks. It discards the rendered output. `nupp
build` uses the same query and may reuse its cached lowering, so a clean check
cannot later fail merely because build first discovered an unavailable backend,
an oversized generated function or invalid expression IR. A different target
or optimization policy is a different query, as it already is for other
target-sensitive checks.

The LSP uses the same isolated evaluation and lowering query for its active
build context and never materializes on the protocol loop. Hover shows:

- the declared runtime type;
- provider name and backend-independent blueprint summary;
- bounded facts useful to the domain, such as PEG rule and capture counts;
- the canonical fingerprint when verbose tooling is requested.

Definition, references and rename operate only on written declarations and
runtime factory callbacks. There are no synthetic declarations to navigate.
Completion inside a block exposes only comptime functions and the sealed
provider APIs available there.

`nupp build --json` and build records include materialization observations:

```text
source position, provider, schema, fingerprint, backend,
blueprint size, generated size, runtime features
```

These are build facts, not new manifest inputs.

## Backend selection and semantic equality

A provider can offer a general backend and a specialized backend. The build
derives the choice from the existing optimization policy and backend
availability; there is no provider-specific manifest flag. Source code and
checked interfaces do not change. PEG's general backend is a compact pure-Lua
bytecode VM. Specialized PEG source ships only after its benchmark gate.

Both backends implement the same provider specification. Differential tests
run the same finalized payloads and inputs through both and compare successes,
positions, captures, callbacks and failures. Fuzzed small descriptions compare
against the provider's reference semantics where practical.

Backend selection belongs in the materialization query key but not the
evaluation key. Changing it regenerates output without re-running a block whose
canonical blueprint is unchanged.

## Incremental and persistent cache model

The evaluation result key includes:

- the lowered and checked comptime body and helper bodies;
- captured known values and opaque provider versions;
- semantic type fingerprints the block observed;
- comptime environment and API versions;
- selected target facts the provider was explicitly allowed to observe.

The finalized blueprint key adds its canonical payload and expected runtime
type fingerprint. The lowering key adds:

- provider emitter version;
- selected backend and optimization settings;
- target runtime feature and ABI versions;
- internal runtime-expression IR version.

An equal blueprint fingerprint cuts off dependents even when the block re-ran.
A backend change reuses the blueprint. A callback body edit does not rerun a
pure factory blueprint because the action record is a runtime argument; its
declared signature change invalidates the expected type and therefore the
materialization relation.

Canonical finalized payloads are suitable for the future persistent build
cache. Live opaque handles and evaluator heap identities are never serialized.

## Provider admission

A new provider is accepted only with all of the following:

1. A runtime-value contract documented independently of generated source.
2. A nominal compiler-owned comptime API and runtime result type.
3. A deterministic, canonical finalized payload and versioned validator.
4. Structural provenance and domain diagnostics.
5. A typed plan for runtime inputs through a declared factory, or proof that it
   needs none.
6. Resource bounds for evaluation, payload, generated source, per-function
   bytecode, locals, upvalues and runtime recursion or storage.
7. A reference implementation or independent semantic oracle used in tests.
8. A real repository or validation-target workload.
9. A benchmark before any specialized backend, with an explicit pass/fail bar.
10. No change to the common evaluator, worker protocol or emission contract
    beyond registering the provider. A provider that needs one first proposes
    the general missing capability.

The tenth item is tested by the second provider. PEG proves that
materialization works; the type-directed codec proves that the abstraction was
not merely LPeg's compiler renamed.

## PEG proving case

### API floor

The first PEG surface is static, byte-oriented and deliberately smaller than
LPeg:

- literal, any byte, range and set;
- sequence, ordered choice and difference;
- zero-or-more, one-or-more and optional repetition;
- and/not predicates;
- named recursive rules without left recursion;
- substring, position, group and explicit collection captures;
- named runtime action slots through a factory.

Match-time captures, locale-dependent classes, dynamic pattern inputs and
arbitrary Lua values are deferred. Match-time captures are last because their
callback can decide success and move the subject position; they are not merely
post-match value conversion.

The evaluator builds an opaque pattern graph. `nupp.peg.compile` validates and
finalizes it into a normalized blueprint with stable rule indices, byte sets,
literals, capture descriptions, action slots, FIRST sets, nullability and
fixed-length facts.

### General bytecode backend

The general runtime backend lowers the finalized graph to numeric instructions
and pooled strings and 256-byte class maps, then constructs a matcher through
the pure generated-Lua `nupp.peg.vm` helper. The VM uses an explicit combined
call/backtracking stack, a capture-free loop, and deferred capture/action
opcodes. Its recognizer tier detects fixed-width whole matches and bounded
prefix/class/suffix scans while lowering, then records compact superinstruction
operands beside the fallback bytecode. Fixed checks are unrolled at the common
ten-byte width; short prefix choices use length-tagged packed keys; byte classes
use 256-byte maps; and the nine-byte route suffix tier packs its fixed bytes
into two comparisons. Shared subgraphs above the inline budget become
subroutines so source growth remains bounded. It exists even if specialization
never wins:

- bundles need no native LPeg dependency;
- it validates the public semantics and finalized IR;
- it supplies the semantic baseline for specialization;
- it is the real table-building workload comptime's implementation plan asks
  for.

Its choice, commit, partial-commit, back-commit, call and return instructions
follow LPeg's parsing-machine design. Nupp still owns its typed result, capture,
action and diagnostic contracts. The original recursive runtime AST interpreter
was retired after the VM won recognition, captures, action, and recursive
grammar benchmarks while passing the same semantic suite.

### Specialized backend gate

M0 has no implementation prerequisite and runs now, before the materialization
framework. Hand-write both the Lua that a specialized backend would emit and a
small reference-machine prototype for representative real patterns, then
compare them with LPeg 1.1.0. Record separately:

- construction and first-match time;
- warm capture-free throughput;
- warm capture-heavy throughput;
- recursive grammar behavior and maximum depth;
- allocation per match;
- generated source and LuaJIT bytecode size;
- bundled artifact dependencies and size.

The primary acceptance condition for the reference machine is useful pure-Lua
bundle performance with no LPeg linked, not a universal win over LPeg's tuned C
VM. The specialized prototype has a separate, numeric improvement margin over
that machine for named workloads, with source-size, bytecode-size and
trace-compiler caps. The benchmark records workloads and every threshold before
results are measured. If the handwritten specializer misses that margin, M6 is
deleted from this plan rather than deferred.

Likely specializations include literal fusion, byte-class comparison or lookup
selection, FIRST-byte choice dispatch, tight spans, tail-rule elimination and
omission of capture state from capture-free rules. These are hypotheses until
the benchmark records them.

The shipped span specializer uses precomputed 256-byte membership maps and
fuses matcher validation with its hot recognition loop. That avoids both
pattern-table dispatch and an extra Lua call per match while retaining the same
`:match(subject, init)` and callable matcher contracts.

## Second proving case: type-directed field codecs

The second provider consumes immutable `TypeInfo` rather than a PEG graph. Its
acceptance case is the keyed table-component codec `fieldcodec.tl` builds with
runtime `load()` from each component's declared `fields`, as described in
`plans/layout.md`.

The first reachable slice need not design a serialization framework. It can
materialize one narrow, typed field projection or keyed codec whose semantics
are already exercised by that workload. This does not replace the struct size
and fingerprint work in that plan. Struct raw-column encoding remains dependent
on its layout and ownership contract; keyed record-field traversal is
target-independent and can land with C2a reflection.

This provider must reuse, unchanged:

- explicit expected-type selection;
- opaque result finalization and worker transport;
- runtime factory actions;
- provenance;
- one-line runtime-expression emission;
- cache and build observation records.

If it requires PEG opcodes, rule concepts or pattern-shaped callbacks in the
common layer, the layer is wrong and is revised before the provider lands.

## Scheduling and prerequisites

M0 is unblocked today and runs independently of C2a, C3, C4 and every
materialization milestone. The implementation order is:

```text
C1 (landed)
    -> C4 worker floor -> M1 -> M2 -> M3
                                      -> M4 -> M5 -> M6, only if M0 earned it
C3 -----------------------------------^
C2a -------------------------------> M7
M3 --------------------------------> M7
```

C3 may proceed in parallel with M1 through M3, but both C3 and M3 are required
for M4. C2a need not block PEG; it and M3 are required for M7. M8 follows two
working providers. The rest of C4 may continue after its worker floor without
blocking provider work that already satisfies that floor.

## Milestones

### M0: evidence and two acceptance descriptions

- Add the handwritten PEG benchmark before a compiler feature.
- Choose the real PEG patterns and bundle target that define success.
- Write the exact first field-codec acceptance surface against the tecs
  workload, without implementing it.
- Record all pass margins and size caps before measuring either prototype.
- Record performance, allocation, generated-size and dependency baselines.

Exit test: the committed benchmark is runnable, names its real patterns and
bundle target, contains numeric thresholds written before its measurements and
records both prototypes' results. It makes an explicit keep/delete decision for
M6. If the specializer misses its recorded margin, this edit deletes M6. The
field-codec acceptance description names the runtime `load()` path to remove.

### M1: opaque values and explicit materialization boundaries

- Add nominal compiler-owned opaque values to the comptime evaluator.
- Permit intrinsic constructors and methods on them.
- Carry constructor call-site and comptime-frame provenance.
- Require a directly declared expected runtime type.
- Add the closed provider registry and materialization-relation checking.
- Reject runtime escape and every unregistered type/result pair.

Use a compiler-test-only provider to exercise the boundary before a public
namespace depends on it. This milestone may run against the direct evaluator;
it deliberately cannot expose a public provider yet.

Exit test: a block can construct, combine through methods and return a cyclic
opaque graph; a user table cannot forge a handle; ordinary quotable tables
retain their current rules; a missing or inferred boundary fails locally with
an opaque/materialization diagnostic rather than NUPP2413; no generated code
exists yet.

### M2: finalization, worker protocol and cache cutoff

- Land comptime's minimum isolated-worker protocol if C4 has not supplied it.
- Add provider finalization inside the isolated evaluator worker.
- Define and validate the versioned canonical blueprint envelope.
- Add payload, provenance and result-size limits.
- Fingerprint finalized values and prove equal-result invalidation cutoff.
- Expose blueprint summaries to diagnostics and hover.

Exit test: construction order and worker process do not change the fingerprint;
malformed returned payloads are rejected; a helper-built invalid graph reports
both the operation and its origin.

### M3: runtime-expression materializers

- Add the private structured runtime-expression IR.
- Render a materialized value on one logical source line.
- Add hygienic locals, IIFE closures, factory inputs and closed helper requests.
- Separate evaluation, finalization and backend-lowering query keys.
- Report materialization observations from JSON builds.

Exit test: a test provider emits both a direct value and a factory without a
source string or synthetic declaration; generated line count and stack
locations remain invariant; oversized output fails deterministically.

### M4: PEG general backend

- Add the compiler-owned `nupp.peg` comptime and runtime type surface.
- Implement the static pattern floor, graph validation and typed results.
- Add PEG operator sugar with checker-owned type contracts and direct evaluator
  dispatch for the resolved compiler intrinsic, without general metamethods.
- Finalize the analyzed graph to a canonical matcher blueprint.
- Emit compact bytecode and constant pools for the pure-Lua VM matcher.
- Differential-test the matcher against LPeg where the surfaces overlap.
- Integrate semantic runtime-feature detection and bundle tests.

Exit test: useful recursive grammars and captures run in a bundle with no LPeg;
check, build, LSP and fixpoint retain their invariants.

### M5: factories and action slots

- Add `function(A): Matcher<R>` selection over immutable record descriptors.
- Validate exact slot names and signatures.
- Bind action fields once when the factory runs.
- Add action failures, backtracking and capture rollback tests.

Exit test: the number example is ordinarily typechecked, comptime observes no
runtime binding, and both a missing and an extra action field fail before code
generation.

### M6: specialized PEG backend, only if earned

- Exist only when M0's handwritten prototype cleared its recorded margin.
- Keep the frozen benchmark and pass bar from M0.
- Lower the analyzed blueprint directly to specialized expression IR.
- Add only the optimizations with a measured case.
- Differential- and fuzz-test reference and specialized backends.
- Make backend changes regenerate without re-evaluating the grammar.

Exit test: the named workload clears the recorded bar, semantic results match
the general backend, and worst-case source/bytecode growth stays under the
declared cap.

### M7: second provider

- Land C2a reflection required by the chosen field-codec slice.
- Add the codec's sealed blueprint and runtime result types.
- Implement it using only provider registration and domain code.
- Run it against the real field-codec acceptance corpus.

Exit test: no common materialization file changes except the closed registry
entry; the provider removes one real runtime source-generation path; its output
is typechecked, deterministic and line-count invariant.

### M8: hardening and persistent integration

- Add adversarial opaque graphs, payloads, size bombs and cancellation tests.
- Persist canonical blueprints and backend outputs in the manifest build cache.
- Version provider, helper and runtime-expression ABIs independently.
- Document provider and backend observations in build tooling.

Exit test: a looping, crashing or memory-hungry builder cannot damage the
compiler or editor; cache entries never cross an incompatible provider or
runtime ABI; a cold and cached build are byte-identical.

## Deliberate exclusions

- User-defined or plugin-defined materializers.
- Public AST, CST or runtime-expression IR access.
- Quoting, splicing or parsing generated source.
- Generated declarations, modules, imports or globals.
- Capturing or naming runtime lexical bindings from comptime.
- Implicit call-site specialization or monomorphization.
- A general `Code<T>`, staged function or arbitrary residual program value.
- Backend-dependent public behavior or types.
- Filesystem, environment, process, clock, randomness or network access during
  evaluation.

These exclusions are architectural, not merely first-version staging. Any one
that later proves necessary reopens the macro boundary and receives its own
language proposal.

## Test matrix

Every materializer extends these common invariants:

- explicit-boundary positive and negative cases;
- every declared materialization relation and near-miss;
- provider selection by resolved identity rather than spelling;
- opaque-value forgery and runtime escape refusal before ordinary table checks;
- worker finalization and hostile-payload validation;
- canonical fingerprints across construction order and processes;
- provenance through loops, helpers and recursion;
- action-slot name, parameter, result and extra-field checks;
- check/build lowering agreement for each target and optimization context;
- line-count and generated-source loadability;
- backend-independent runtime behavior;
- generated-size, bytecode, local, upvalue, recursion and resource limits;
- query compute counters for body, type, blueprint and backend changes;
- LSP cancellation, diagnostics, hover and worker recovery;
- pure-Lua bundle execution with unavailable native features;
- self-hosted stage-one/stage-two byte-identical fixpoint.

Provider suites add an independent oracle and fuzz small canonical payloads.
PEG compares its overlapping floor with LPeg and its own reference machine.
The field codec compares generated behavior with the existing source-generating
implementation until that implementation can be removed.
