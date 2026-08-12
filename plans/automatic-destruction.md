# Automatic destruction for ordinary owners

> **Status: implemented.** Locally droppable ordinary owners auto-destroy at
> lexical scope exit. The standalone resource `with` syntax discussed in the
> historical stages below was subsequently removed because `do` plus an
> ordinary owner provides the same cleanup boundary with one ownership model.

## Decision

An ordinary binding that still holds a locally droppable ownership obligation
at lexical scope exit is destroyed automatically. Moving, explicitly dropping,
returning, or otherwise transferring the value removes that scope's cleanup
responsibility exactly as it does today.

```nupp
local file = openFile(path)
use(file)
-- file is destroyed here
```

Automatic destruction uses the exact ordered cleanup capability carried by the
value. It does not infer a method from a name, replace producer-specific
cleanup with a type-level destructor, attach an `ffi.gc` finalizer, or choose a
terminal action for an opaque owner.

`with` remains a distinct and useful construct:

```nupp
with file = openFile(path) do
    use(file)
end
```

It moves the owner into an inaccessible cleanup slot and exposes only a borrow
for one exact region. The visible binding cannot move, escape, be returned, or
be dropped early. An ordinary automatic owner remains movable, returnable,
and explicitly droppable. `with` therefore means *bounded borrowed extent*,
not merely *please remember cleanup*.

The implementation will not add a second cleanup runtime. Automatic locals and
explicit `with` lower through one cleanup-region planner. Equivalent source
must produce equivalent generated Lua, and ordinary code with no owner must be
byte-identical to the compiler output before this feature.

## Why change the existing decision

Nupp originally kept ordinary ownership completely erased and made `with` the
only source-visible opt-in to protected cleanup. That made the cost of emulating
`finally` on LuaJIT visible, and the checker still made forgetting cleanup a
compile error.

This proposal starts from the implemented baseline in
[ownership-hardening.md](ownership-hardening.md). Automatic destruction
requires the compiler to know, for every value slot:

- whether an obligation is live, moved, discharged, retained, or opaque;
- the producer-specific ordered cleanup operations;
- every borrow root and invalidating exclusive operation;
- capability transport through generics, packs, narrowing, fields, modules,
  and foreign results; and
- which suspension and boundary operations can abandon the continuation.

Those facts are prerequisites, not work that this plan silently recreates.
Current `main` supplies them through the hardening plan's semantic
`Capability` / `ValueSlot` model and its completed transport and boundary
stages. A port of this plan to a compiler version without that hardening must
land the dependencies below first; it must not substitute payload-type or
syntax-based cleanup inference.

Requiring the programmer to restate the final cleanup no longer supplies proof
the compiler lacks. It supplies only cleanup timing. The Rust mental model is
the more useful default: the binding that owns a value destroys it at the end
of its lexical scope unless responsibility moved elsewhere.

This matters especially for generated or agent-written FFI code. A compiler
diagnostic is a good backstop, but a safe default removes a repair iteration
and makes the shortest accepted program the error-safe one. Explicit syntax
should remain for early release, exact extents, transfer, and meaningful
protocol transitions rather than for the ordinary case.

## Goals

1. Make a locally droppable owner safe on fallthrough, structured control
   flow, raised errors, and handled cancellation without an explicit
   `drop` or `with`.
2. Preserve the existing ownership theorem: each obligation is discharged or
   transferred exactly once, use after move remains impossible, and no borrow
   root is destroyed while a dependent capability is live.
3. Give ordinary owners the predictable rule “lexical scope, not last use.”
4. Reuse `with` acquisition ordering, cleanup ordering, error aggregation,
   private cleanup linkage, and optimized lowering.
5. Fuse compatible automatic owners into the minimum protected regions rather
   than introducing one protected call per owner.
6. Elide protected regions when effect and control-flow analysis proves direct
   cleanup sufficient.
7. Keep ownership-free code and foreign ABIs unchanged.
8. Keep the generated cost inspectable even though the common source no longer
   spells `with`.

## Non-goals

- Inferring ownership or cleanup from `new`, `close`, `free`, `destroy`, or a
  structural interface.
- Choosing among terminal operations such as `submit` and `cancel`.
- Making cleanup asynchronous or permitting cleanup to suspend.
- Destruction after last use. Cleanup timing is lexical and observable.
- Automatically accepting a binding that is live on one side of a control-flow
  join and moved on the other. The first version preserves the current
  compatible-obligation join rule and therefore needs no general drop flags.
- Automatically destroying an old owner when an assignment overwrites it.
  Replacing a live owner remains an error; drop or transfer it first.
- Silently destroying an ignored owning result as a temporary. Ignoring a
  fresh obligation remains an error.
- Guaranteeing cleanup after process abort, power loss, an uncatchable VM or
  native crash, or deliberate `intoRaw` abandonment.
- Making arbitrary typestate a destructor problem. Ownership tokens continue
  to represent token-shaped protocol states only.
- Inferring a producer-specific cleanup witness for a visible `takes`
  parameter. The erased parameter ABI carries responsibility but not which of
  several producers supplied the value; such parameters remain explicit
  terminal consumers unless their contract is extended with a witness.

## Dependency on ownership hardening

Stage labels in this file use the `AD-` prefix. References such as `OH-S5`
mean the correspondingly numbered section of
[ownership-hardening.md](ownership-hardening.md). This avoids treating two
different plans' bare `S2` labels as the same milestone.

The hardening plan is marked implemented on current `main`, so these are
satisfied prerequisites rather than pending work in this rollout:

| Automatic-destruction work | Required hardening baseline | Why |
| --- | --- | --- |
| `AD-S1` shared cleanup plan | `OH-S1` capability / `ValueSlot` model | Cleanup entries must carry semantic capability identity and the exact producer-specific discharge list. |
| `AD-S2` ordinary cleanup facts | `OH-S1`, `OH-S2`, and `OH-S3` | Moves, generic forwarding, narrowing, packs, projections, and module transport must preserve the same obligation. |
| `AD-S2` aggregate cleanup | `OH-S5` | Optional and partially moved aggregate exits need path-sensitive affine-field state. |
| `AD-S3` handled cancellation | the proof-closure kernel of `OH-S8` | A parked continuation needs checked eventual resume or cancellation before lexical cleanup can be promised. |
| Final integration regressions | `OH-S6` and `OH-S12` | `resources.Set.adopt` and deterministic ownership-audit output must compose with automatic cleanup. |

The deferred `OH-S8` structured-child capability is not a prerequisite.
Automatic destruction cleans a continuation when the implemented handler
resumes or cancels it; it does not make an unjoined child borrowing a parent
scope safe. Likewise, `resources.Set` is needed for the final composition test,
not for the erased representation or common lowering of an ordinary owner.

If any prerequisite is absent on another branch, the dependent `AD-` stage is
blocked there. Do not partially enable automatic destruction with a local
fallback representation or omit the corresponding transport path.

## Surface semantics

### Lexical scope, never last use

Cleanup happens at the end of the binding's lexical scope. The compiler does
not move it to the last apparent use:

```nupp
do
    local guard = lock(mutex)
    readSharedState(guard)
    unrelatedWork()
end -- unlock here, not after readSharedState
```

Use a nested block or explicit drop for earlier release:

```nupp
local file = openFile(path)
readHeader(file)
nupp.drop(file)
doUnrelatedWork()
```

An explicit drop consumes the obligation, so no automatic cleanup remains
at the block exit.

### Moves and owning returns

A move transfers cleanup responsibility:

```nupp
local file = openFile(path)
registry:add(file) -- takes file
-- this scope has nothing to destroy
```

An owning return does the same:

```nupp
@owned
local function openConfigured(path: string): File
    local file = openFile(path)
    configure(file)
    return file
end
```

If `configure` raises, this function destroys `file`. If it succeeds, the
return transfers the exact capability to the caller. Returning a non-owning
view of `file` remains rejected.

A `takes` parameter is an owner activated at function entry, but its erased
payload does not carry the producer-specific cleanup witness needed for an
automatic fallback. A visible Nupp body must therefore consume, transfer,
return under an owning contract, or explicitly drop it through a cleanup
known to that body. A bodyless `takes` declaration continues to state that the
foreign implementation consumes the argument during the call. Automatically
destroying untouched `takes` parameters would require a future hidden witness
ABI or a type-level destructor and is deliberately not guessed here.

### Cleanup choice

Only a capability with a known local cleanup list is automatic:

```nupp
@owned(closeFile)
local function openFile(path: string): File

local file = openFile(path) -- eligible
```

The exact cleanup list comes from the producing operation and travels with the
value. Two producers returning the same payload type may therefore still
destroy differently.

An opaque owner has no automatic action:

```nupp
@owned(opaque = true)
cdef function beginRequest(): Request

local request = beginRequest()
-- still an error: submit(request) or cancel(request) must take it
```

The compiler must never guess which terminal operation the application meant.
A `resources.Set` may continue to adopt an opaque owner only with an explicit
matching terminal consumer.

### Destruction is not successful finalization

`@drop` or an `@owned(cleanup...)` list describes the safe fallback that may
run automatically. An operation whose successful result matters stays an
explicit consuming transition:

```nupp
local transaction = beginTransaction()
apply(transaction)
transaction:commit() -- takes transaction and reports commit failure
```

If `apply` raises, automatic destruction may roll the transaction back. It
must not silently commit. The same distinction applies to `finish`, `flush`,
`submit`, and asynchronous shutdown.

Nupp does not assign meaning to a cleanup function's ordinary return values.
As today, an API whose close result matters supplies an adapter that raises on
failure or exposes an explicit consuming finalizer. Raised cleanup failures use
the resource-scope policy below.

### Optional owners

An optional owning result carries a conditional obligation. Scope exit checks
the payload and destroys only a present owner:

```nupp
local file = maybeOpen(path)
if file then
    inspect(file)
end
-- close file when non-nil
```

Narrowing preserves the same capability; it does not create a second cleanup
entry. Moving the non-nil value discharges the conditional obligation only on
paths where that move is established before the scope exit. A path that moves
the value joining a path that leaves it live remains rejected by the existing
compatible-obligation rule. This is the ownership equivalent of destroying
`Option<T>` when it contains `T`, not a general live/moved join feature.

### Ordering

Owners activated in one lexical scope are destroyed in reverse activation
order. Within one owner, cleanup operations retain their declared order:

```nupp
local socket = openSocket()
local tls = openTls(socket)
```

destroys the TLS cleanup list first and the socket cleanup list second. This
also satisfies the borrow that keeps the socket rooted while TLS is live.

Shadowing creates distinct bindings. The later binding activates later and is
destroyed first. A loop-local owner is destroyed at the end of each iteration,
including `continue`; `break` destroys it before leaving the loop.

The current assignment rule remains unchanged:

```nupp
local file = openFile("first")
file = openFile("second") -- error: would abandon the first owner
```

The programmer drops the old value or uses a new binding. Automatic
destruction at assignment can be evaluated separately after the scope model is
stable.

### Temporaries

An ignored owning expression remains an error:

```nupp
openFile(path) -- error, not a statement-end temporary drop
```

Important resource lifetime should not depend on Lua expression-temporary
rules that do not otherwise exist. Bind it, transfer it, or put it directly in
an explicit `with` acquisition.

### `with` after automatic destruction

`with` continues to provide guarantees an ordinary local does not:

- the owner itself is inaccessible inside the body;
- the visible name is a borrow with the exact block as its maximum extent;
- early drop and transfer are impossible;
- several acquisitions form one explicit failure and ordering group; and
- the protected extent and its likely cost remain visible in source.

Existing `with` programs keep their semantics and, after the common lowering
is extracted, their generated Lua. The “wrap in `with`” refactor remains useful
to shorten or freeze an extent, but it is no longer the fix for merely reaching
ordinary scope exit with a droppable owner.

### Control flow and errors

Automatic cleanup covers:

- block and function fallthrough;
- `return` after transferring every returned owner;
- `break` and `continue`;
- a `goto` leaving the binding's scope;
- an error raised by acquisition or the body; and
- handled cancellation that unwinds the continuation.

A `goto` still cannot enter a scope past an owner activation. An acquisition
creates no obligation until it succeeds. If a later acquisition raises, every
earlier successful acquisition in the cleanup region is destroyed.

Cleanup order and failure reporting are exactly those of `with`:

1. Attempt every applicable cleanup even when one raises.
2. Preserve an acquisition or body failure as primary.
3. Attach cleanup failures in attempted order.
4. If the body succeeded, make the first cleanup failure primary and later
   failures suppressed.
5. Preserve a single raised error unchanged; use the existing resource-scope
   failure object only for several failures.

### Suspension

An automatically destroyed owner remains a live temporal obligation until it
moves or its scope exits. Raw or unknown suspension is therefore still
rejected: automatic cleanup cannot run if an arbitrary coroutine is abandoned
forever.

Checked handled suspension may cross the owner under the existing contract.
Handler shutdown must cancel and unwind the continuation, at which point the
same automatic cleanup path runs. Cleanup itself remains transitively
non-suspending.

## One cleanup-region model

The checker and generator need one semantic plan shared by explicit and
automatic cleanup. The names below describe responsibilities, not required
source-level compiler types:

```text
CleanupRegion
  protected extent
  ordered cleanup entries
  activation point for each entry
  lexical cleanup boundary for each entry
  transfer/drop points
  structured and exceptional exits

CleanupEntry
  capability identity
  payload slot
  ordered cleanup operations
  roots and dependent entries
  activation state needed on an exceptional exit
```

`with` contributes entries whose owners are hidden and active for the whole
body. Ordinary bindings contribute entries that may be consumed before their
lexical boundary. Both use the same cleanup-call emission, private function
registration, failure aggregation, and line-count accounting.

The common representation must be semantic rather than a rewrite of automatic
locals into `with` CST nodes. An ordinary owner can move and a `with` binding
cannot; erasing that distinction before ownership checking would either reject
valid transfers or let a scoped borrow escape.

## Region formation and fusion

### Protection interval

For each automatic owner, the exceptional protection interval begins after a
successful acquisition and ends at its transfer, explicit drop, or lexical
cleanup boundary. A potentially raising operation inside that interval needs a
path that destroys the still-live owner.

Intervals that overlap and have compatible failure semantics form one region.
The region registers each owner immediately after successful acquisition, so a
later acquisition failure sees only owners that actually became live.

The implementation should reuse the existing multi-acquisition `with` state
rather than allocate a general-purpose runtime cleanup stack. A small acquired
count is sufficient for a straight-line group. Branch-specific groups use
control-flow-specific cleanup blocks while the current compatible-join rule
remains in force.

### Lexical boundaries remain observable

Fusion may share error protection without extending an owner's lifetime:

```nupp
local outer = openOuter()
do
    local inner = openInner()
    use(inner)
end -- inner is destroyed here
use(outer)
```

The inner cleanup still runs at the inner block boundary. The shared region, if
one is profitable, records that the inner entry is no longer active so a later
error cannot destroy it twice.

Nested explicit scopes may be fused only when the raised error object and
primary/suppressed ordering remain observably identical. If flattening would
change nested failure context, keep the region boundary. Runtime call count is
not a license to change error semantics.

### Elision

No protected call is required when the compiler proves that no error can cross
the live interval. Structured exits receive direct cleanup blocks. A visible
Nupp body with a non-raising effect summary can therefore compile to the same
straight-line cleanup as manual `drop`.

Unknown, indirect, untyped, or foreign calls are conservatively may-raise
unless their declaration supplies the existing checked effect contract. The
optimizer must not infer away protection from observed test behavior or a
function name.

An owner acquired and transferred before any may-raise operation needs no
region at all. Ownership-free source remains byte-identical.

### Shared lowering

The existing optimized `with` paths remain the performance baseline:

- a non-capturing region may use one shared protected body rather than allocate
  a closure per execution;
- a capturing region keeps the general correct lowering;
- cleanup calls are individually protected so one failure does not skip the
  rest; and
- compiler-owned helper names remain collision-proof and line-count neutral.

Automatic cleanup must select those same paths from the region plan. A new
automatic-only runtime helper is evidence that the lowering was split at the
wrong layer.

## Checker changes

1. At every lexical boundary, classify each live obligation as:
   transferable only, locally droppable, retained/pinned with a required
   release, or invalidly borrowed.
2. Convert a locally droppable live owner into an automatic cleanup fact
   instead of reporting the current live-owner diagnostic.
3. Keep the diagnostic for opaque owners, owners whose cleanup cannot be
   resolved, retained pins that have not reached release, and obligations on a
   continuation that may be abandoned.
4. Attach cleanup facts to fallthrough and every structured exit from the
   binding's scope.
5. Make raised edges consult the callable effect summary. Unknown calls are
   may-raise.
6. Preserve capability identity through the cleanup fact; do not reconstruct a
   cleanup list from the payload type at the exit.
7. Treat a successful move, `takes` call, owning return, `drop`, or
   `intoRaw` as deactivation of that exact cleanup entry.
8. Preserve the existing rule that incompatible live/moved obligations do not
   join. General conditional drop state is deferred.
9. Reuse affine-field state: automatic destruction of a partially moved record
   destroys exactly the fields statically live at that exit.
10. Keep raw suspension diagnostics unchanged while recognizing handled
    cancellation as an exit that runs the plan.

The feature applies wherever Nupp recognizes an ownership capability, not only
under `--strict`. Gradual typing may decline to originate a capability, but it
may not weaken one after an `@owned` boundary created it.

## Generator changes

1. Extract the existing `with` exit and failure machinery behind the semantic
   cleanup plan.
2. Lower current `with` through it first and hold generated fixtures byte-for-
   byte before accepting automatic owners.
3. Emit direct reverse cleanup on structured exits.
4. Emit one protected body for each fused may-raise region.
5. Activate an entry only after its acquisition succeeded.
6. Deactivate it at explicit drop or transfer, and at an inner lexical
   cleanup boundary shared by a larger region.
7. Reuse the existing primary/suppressed failure construction.
8. Preserve the line-count invariant and stack-trace positions.
9. Emit no finalizer and no generic runtime cleanup stack.
10. Allow optimizer remarks to name whether a region was shared, general,
    fused, or elided.

## Diagnostics and tooling

The current end-of-scope live-owner error changes meaning. Reaching scope exit
with a droppable owner is no longer an error. The same code remains useful
for an obligation automatic cleanup cannot discharge, with related information
that distinguishes:

- transfer-only owner needs a `takes` terminal operation;
- cleanup contract is unresolved or invalid;
- retained pin needs its matching release;
- raw suspension may abandon the automatic cleanup; and
- one branch moved the owner while another left it live.

Tooling must make the implicit behavior inspectable:

- hover on an owner says where automatic cleanup occurs and lists its cleanup
  operations in order;
- `lsp inspect` reports the cleanup boundary and whether the binding moved
  before it;
- go-to-definition on cleanup metadata still reaches private or public cleanup
  declarations;
- a refactor turns an automatic owner into an exact `with` extent;
- a quick fix inserts explicit `nupp.drop` at an earlier valid point when
  requested, but never guesses a protocol terminal;
- `ownership-audit --json --regions` opt-in output adds automatic cleanup
  sites and reports their region identity and lowering class (`direct`,
  `shared`, `general`, or `fused`); and
- optimization remarks explain protected-region fusion and elision without
  making ordinary builds noisy.

The audit schema must use deterministic semantic capability and region
identifiers rather than generated Lua local names. Source locations remain
separate presentation data and may naturally change after an edit.

## Compatibility

Previously valid programs that explicitly drop, transfer, return, or use
`with` keep their source meaning. A manual program may gain cleanup on an error
that formerly escaped before its trailing `drop`; that is the intended
safety improvement and must be called out as a behavior change.

Previously invalid programs that merely left a droppable owner live become
valid. Programs leaving opaque, retained, or otherwise non-dischargeable
obligations remain invalid.

No C ABI, ownership annotation, module interface, or generated cleanup
registration key changes. A local automatic region is body-only incremental
state. Changing a producer's cleanup list already changes its exported
interface fingerprint and continues to recheck consumers.

The compiler bootstrap must carry identical semantics. Incremental, cold,
warm, and bootstrap checks must form the same cleanup regions for the same
source.

## Implementation stages

The new acceptance rule must remain behind an internal feature gate until
exceptional exits work. Landing “fallthrough auto-drop” first would accept
programs that leak precisely when a body raises.

### AD-S0: Freeze semantics and cost

- Add paired fixtures for explicit `with` and equivalent automatic locals.
- Record generated output, cleanup order, failure shape, allocations, and
  trace behavior for the current `with` implementation.
- Add negative fixtures for opaque owners, ignored owning expressions,
  replacement assignment, raw suspension, incompatible branch joins, and
  incorrect terminal choice.
- Add the proposed audit schema before compiler work depends on ad hoc debug
  prints.

### AD-S1: Extract the shared cleanup plan

- Represent `with` acquisitions, activation, cleanup order, exits, and failure
  aggregation in one semantic plan.
- Lower existing `with` through it.
- Require byte-identical generated Lua for the existing `with` corpus and a
  clean full test suite before proceeding.

This stage changes architecture, not language behavior.

### AD-S2: Compute automatic cleanup facts

- Mark droppable owners at lexical boundaries instead of reporting them.
- Cover fallthrough, return, loop control, and outward `goto`. Keep function
  parameters received with `takes` explicit until their producer-specific
  cleanup witness has a representable ABI.
- Deactivate entries on every existing transfer operation.
- Support optional owners and partially moved affine records.
- Keep the feature gated until `AD-S3` handles raised edges.

### AD-S3: Protect raised exits

- Extend cleanup intervals across every may-raise call and expression.
- Register only successful acquisitions.
- Reuse `with` primary/suppressed cleanup failure behavior.
- Cover `pcall`/`xpcall` correlation and handled cancellation.
- Add bootstrap and generated-module regressions before enabling the syntax
  change.

At the end of `AD-S3`, ordinary automatic destruction may become the default.

### AD-S4: Fuse and elide regions

- Fuse overlapping compatible intervals.
- Preserve inner lexical cleanup boundaries and observable nested failure
  structure.
- Reuse shared non-capturing bodies.
- Elide protection for proven non-raising intervals and immediate transfers.
- Add optimizer remarks and audit output.

### AD-S5: Tooling, documentation, and migration

- Update the reference, ownership guide, `with` guide, diagnostics, and LSP
  actions.
- Mark the opposite decision in [with.md](with.md) as superseded rather than
  leaving two authoritative answers.
- Document the distinction between destruction and successful finalization.
- Update examples so ordinary ownership uses `local`, `with` demonstrates an
  exact borrowed extent, and explicit `drop` demonstrates early release.
- Run the ownership laundering matrix with automatic exits added as both
  source and destination transports.

### Deferred follow-up: conditional drop state

After the no-drop-flag model is measured, consider accepting a binding that is
moved on one branch and live on another. That requires a runtime active bit at
their join and Rust-like restrictions on subsequent use. It is not necessary
for automatic destruction and must not delay the zero-flag common path.

Owner replacement assignment is a separate follow-up. Its evaluation and
failure order is subtle: acquiring the replacement, destroying the old owner,
and handling a failure from either action can temporarily create two
obligations. Keep the explicit rule until that protocol has its own decision.

## Verification

### Semantic tests

- fallthrough, return, break, continue, outward `goto`, and raised error;
- acquisition failure after zero, one, and several successful acquisitions;
- reverse owner order and forward per-owner cleanup order;
- explicit drop, `takes`, owning return, `resources.Set.adopt`, and
  `intoRaw` suppress exactly one automatic cleanup;
- optional owner nil/present paths;
- partially moved affine records;
- owners that retain borrows of earlier owners;
- cleanup failure alone, body failure plus cleanup failure, and several
  cleanup failures;
- `pcall` ownership result correlation;
- raw suspension rejection and handled cancellation cleanup;
- shadowing and loop iteration boundaries;
- opaque owner and ignored owning result remain errors; and
- no cleanup after a move, including through a capability-preserving generic.

### Equivalence tests

For source pairs whose lifetime and transfer behavior match, assert:

- identical cleanup call sequence;
- identical primary and suppressed error values;
- identical generated Lua after normalization, and byte-identical output for
  the canonical single-owner and multi-owner cases;
- identical private cleanup linking and module load order; and
- identical incremental interface fingerprints.

`with` remains intentionally different when its borrow-only binding rejects a
move an ordinary owner permits.

### Performance tests

Extend `bench/ownership.lua` with reproducible rows for:

1. one non-capturing owner in a hot loop;
2. one capturing owner;
3. several owners acquired together;
4. staggered nested lexical scopes;
5. immediate transfer before a may-raise operation;
6. a proven non-raising direct cleanup;
7. partial acquisition failure;
8. cleanup failure aggregation;
9. optional owners; and
10. a handled suspension crossing an owner.

For an equivalent explicit `with`, automatic destruction should be byte-
identical in the canonical cases and otherwise within measurement noise for
time and allocation. Owner-free code must be byte-identical. A proven
non-raising automatic owner should match straight-line manual drop. Any
regression beyond two percent against the equivalent `with` row needs an
explained generated-code difference rather than a threshold waiver.

Run long enough to cross LuaJIT's trace threshold and record whether each row
traces. A fast interpreter-only result is not an acceptable substitute for a
hot loop that stopped compiling because automatic cleanup introduced `FNEW`.

### Project and build gates

- full test suite passes;
- compiler reaches byte-identical fixpoint;
- tracked bootstrap builds the current compiler;
- cold, warm, incremental, and whole-project checks agree;
- formatter and CST round-trip preserve every affected construct;
- generated code remains line-count invariant;
- ownership audit output is deterministic; and
- a Tecs-shaped fixture covers a device-rooted GPU owner, a mapped write span,
  an explicit submit/commit transition, and error cleanup without a broad
  `unsafe` block.

## Completion gate

Automatic destruction is complete only when all of these are true:

- the shortest ordinary locally droppable owner is error-safe without
  explicit cleanup syntax;
- moving, returning, dropping, or transferring it suppresses automatic
  cleanup exactly once;
- opaque and multi-terminal protocols still demand an explicit choice;
- cleanup order and failure behavior match `with`;
- equivalent automatic and explicit scopes share the same lowering and cost;
- no owner-free program gains runtime machinery;
- raw suspension still cannot strand an automatic owner;
- all implicit regions are visible through tooling and deterministic audit
  output;
- existing valid explicit-lifetime code retains its intended timing; and
- documentation has one unambiguous default model: ordinary droppable owners
  auto-destroy, `with` fixes an exact borrowed extent, and explicit terminal
  operations express early release or meaningful completion.

## Rejected alternatives

### Keep explicit cleanup as the permanent default

This remains safe but makes the common correct program longer after the
compiler already possesses the complete proof. It particularly taxes generated
and agent-written FFI code without improving auditability: the exact cleanup
contract already travels with the owner and can be inspected directly.

### Clean only on normal fallthrough

This is cheap and unsound as an RAII promise. It leaks on the error path users
most expect automatic destruction to cover. Do not enable the feature until
protected raised exits land.

### Add a second `using` or `defer` construct

`with` already expresses an explicit bounded cleanup region. Another opt-in
spelling does not answer why ordinary ownership should require an opt-in and
would split tooling and documentation across equivalent mechanisms.

### Attach `ffi.gc`

Finalization is nondeterministic, cannot report completion failure, can create
a second cleanup path, and does not model transfer. It remains a rejected
implementation technique.

### Destroy after last use

Cleanup is observable and may release locks, GPU objects, files, or native
registrations. Last-use placement would make small source edits change runtime
timing and would be difficult to explain in the debugger. Lexical scope is the
contract.

### Make auto-destruction a project option

Ownership semantics must not depend on a build flag. A module compiled under
one project cannot safely acquire a different cleanup meaning when imported by
another. The change is a language rule, with explicit operations for local
timing differences.

### Enable it only in strict files

A capability created by an `@owned` contract is non-forgettable regardless of
the gradual typing floor. Different destruction semantics across `.nupp` and
`.g.nupp` would make a file rename change resource behavior.

### Introduce general drop flags immediately

Rust-like conditional move joins are useful but not required for the common
case. They add runtime state and broaden the checker change. Preserve the
current compatible-join rule, prove zero-cost fusion first, then evaluate them
as a measured expressiveness feature.
