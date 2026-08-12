# Ownership hardening

Status: implemented, except that the resource `with` construct this plan was
written around was removed. An ordinary owner is destroyed at its lexical scope
boundary instead, so `do ... end` is the cleanup boundary everywhere `with`
appears below. See [automatic-destruction.md](automatic-destruction.md).

The proof-closure kernels, safe boundary abstractions, diagnostics, audit
surface, and regression gates below landed together. The
remaining refusals listed under Deliberate limits are part of the theorem, not
unfinished implicit weakening.

The detailed records for existing features remain authoritative for their
feature-specific shape; this plan adds the stronger cross-cutting completion
criteria they must all satisfy:

- [with.md](with.md) for the resource-scope design this was written around,
  which records a construct that was removed;
- [automatic-destruction.md](automatic-destruction.md) for the lexical
  boundary that replaced it;
- [type-packs.md](type-packs.md) for affine value sequences and correlated
  results;
- [intersections.md](intersections.md) for overload selection and effect
  application;
- [suspension.md](suspension.md) for handled suspension and cancellation; and
- [workers.md](workers.md) for isolated worker ownership.

This plan owns the cross-cutting invariants, closes the gaps between those
features, and supplies one ordered completion gate.

## Implementation outcome

The implementation keeps the erased wrapper representation but exposes one
semantic `Capability` / `ValueSlot` API for payload-preserving transport. It
adds exact `preserves` result relations, stable expression provenance, borrowed
nominal fields, path-sensitive affine field moves, scoped callback effects,
non-suspending cleanup checks, bounds-checked C arrays and byte spans, reified
`resources.Set` discharge witnesses, foreign-boundary hardening, function-field
owning producers, and the `ownership-audit` command.

The safety-first limits are explicit:

- arbitrary anonymous table storage remains rejected; ordinary copyable
  closures borrow captured owners, while `takes (...)` creates an affine
  closure that owns and discharges its named captures;
- raw or variable-length pointer indexing requires a checked span or `unsafe`;
- structured children may not borrow a parent until a future structured task
  API supplies a statically unavoidable join/cancel obligation; and
- ownership tokens model token-shaped protocol state, not arbitrary typestate.

Those rejections preserve the guarantee without adding runtime cost to normal
owners. Only `resources.Set` and checked span objects reify dynamic metadata.

## Decision

Nupp will keep ownership as non-forgettable capability metadata over a payload
type, not as an ordinary interface, structural intersection, destructor method
name, or user-written lifetime parameter.

The existing surface remains the default:

```nupp
@owned(closeFile)
local function openFile(path: string): File

local function inspect(borrows file: File)
local function resize(exclusive buffer: Buffer, size: integer)
local function adopt(takes file: File)

local function first(borrows pool: Pool): Item borrows pool

do
    local file = openFile(path)
    inspect(file)
end
```

`owned<T>`, `borrowed<T>`, and `pinned<T>` remain storage qualifiers. Parameter
modes describe what a call does, and result clauses describe a relationship to
the call's inputs. Ordinary intersections remain structural and cannot contain
an ownership capability whose removal would erase an obligation.

The checker will infer capability relationships from visible Nupp bodies. A
bodyless declaration must state any relationship that cannot be recovered. The
only planned addition to the common surface is a result relation for exact
capability transport:

```nupp
local assert: function<T>(value: T?, message: any?): T preserves value
```

A visible identity or narrowing helper infers that relation without writing it:

```nupp
local function require<T>(value: T?): T
    if value == nil then error("required") end
    return value
end
```

The compiler treats this schematically as `(T? @ C) -> (T @ C)`, where `C` is
not a source-level generic argument. It is the exact owner cleanup contract,
borrow roots, pin state, and retention state arriving through `value`.

## Guarantee

For a strictly checked program whose trusted declarations and unsafe assertions
are truthful, every safe Nupp execution must satisfy all of these properties:

1. A fresh ownership obligation is discharged or transferred exactly once on
   every reachable exit.
2. A moved or discharged value cannot be used, moved, or discharged again.
3. An obligation cannot disappear through narrowing, widening, a cast, a
   generic, a value pack, an overload, a table, a closure, a module boundary,
   an untyped call, or generated code.
4. A borrow cannot outlive any of its roots, and no root can move, discharge,
   reallocate, or otherwise perform an exclusive operation while an
   incompatible borrow is live.
5. A pointer retained after a call keeps its required Lua anchor alive until a
   matching release, and retention cannot be duplicated or abandoned.
6. A raw pointer is not dereferenced, indexed, retained, or passed through an
   uncontracted foreign boundary in safe code.
7. A resource scope runs all applicable cleanup in deterministic order on
   fallthrough, structured control flow, an error, or handled cancellation.
8. A continuation cannot be abandoned with a live temporal obligation unless
   responsibility has transferred to a checked handled-suspension contract.
9. Incremental checking, imports, declaration files, overloads, and code
   generation preserve the same capability facts as a whole-project check.

The owned *value* is affine: one binding cannot be used after it moves. The
outstanding *obligation* is linear: safe control flow must account for it once.
Calling the entire model affine must not weaken the second rule.

## Trust boundary

The guarantee deliberately begins after these claims. They are trusted because
their truth is not observable from Lua values or a C header:

- An external `@owned` producer returned a fresh, exclusive resource.
- Its ordered cleanup list is the correct protocol and allocator pairing.
- A bodyless `takes`, `borrows`, `exclusive`, `retains`, `releases`,
  `@borrowed`, or `@owned` declaration describes the foreign implementation.
- A foreign borrowed output actually derives from every named input.
- A cleanup body, cancellation callback, or handler shutdown implementation
  performs what its contract says.
- `nupp.fromRaw`, `nupp.borrowFrom`, `nupp.pin`, and other assertions inside
  `unsafe do` are true for the concrete addresses involved.
- The LuaJIT VM, FFI ABI, allocator, and called native libraries honor their
  own documented memory model.
- An untyped Lua module that receives a raw value behaves according to the
  explicit unsafe adapter that handed it that value.

`unsafe do` grants permission only for the unproved operation it contains. It
does not suppress affine accounting, allow a borrow to escape, or make an
owner storable in an untracked table. Safe code on both sides of an unsafe block
continues to receive the full guarantee.

The following remain outside the promised proof:

- semantic correctness of cleanup or foreign code;
- process abort, power failure, or an uncatchable VM/native crash;
- general data-race freedom across native threads;
- arbitrary typestate such as authenticated or committed;
- liveness, fairness, or proof that cleanup eventually returns; and
- memory safety of arbitrary raw pointer arithmetic inside `unsafe`.

The documentation must present this boundary as the theorem's assumptions, not
as caveats scattered after stronger claims.

## Capability model

The implementation currently represents part of this information in ownership
wrapper types, part on bindings, and part on pack slots. Hardening starts by
giving every value slot one semantic capability record:

```text
Capability
  obligation    none | cleanup(ordered references) | opaque | pin
  roots         set of binding/projection identities
  retention     unretained | retained(contract identity)
  access        ordinary | shared-borrow | exclusive-borrow
```

This is a product, not a tagged union. A TLS session, for example, can own its
own cleanup and borrow its socket at the same time. A pinned pointer owns its
anchor relation and may additionally be retained by C.

The payload and capability travel together through expression inference, pack
adjustment, generic substitution, narrowing, overload resolution, assignment,
returns, imports, and interface hashing:

```text
ValueSlot
  payload       Type
  capability    Capability
```

The representation must preserve the different algebra of its members:

- cleanup is an ordered, non-commutative sequence;
- roots are an identity-deduplicated set;
- retention is a state transition tied to one foreign contract; and
- payload intersections and unions use ordinary type relations without
  weakening the capability beside them.

`unwrapOwnership` may expose a payload for an operation that explicitly asks
for one. It must not be the default path through generic unification, relation
checking, a cast, or pack reconstruction.

## Current baseline

The following are implemented and are not redesigned here:

- producer-specific ordered `@owned` cleanup, including private cross-module
  cleanup references;
- unique inherited `@drop` and explicit transfer-only owners;
- `takes`, inferred/declared `borrows`, and call-duration `exclusive`;
- lexical borrows, multi-root result provenance, and owners that also borrow;
- lexical cleanup on all structured exits and cleanup-failure aggregation;
- affine nominal records and reverse field cleanup;
- owned and borrowed C output parameters;
- raw adoption/abandonment, provenance assertions, pins, and C
  retention/release contracts;
- per-slot ownership and provenance in concrete and generic type packs;
- correlated `pcall` ownership and refusal to truncate affine results;
- use-after-move, double consumption, live-obligation, and raw-pointer
  diagnostics; and
- interface hashing and cross-module transport for the ownership contracts
  already represented.

The remaining work is split below into soundness closure, expressiveness that
is safe only because it is currently rejected, and proof/tooling work.

The priorities are different:

- **Proof closure:** S0, S1, the rootless-provenance cases in S3, raw versus
  handled suspension in S8, and the boundary audits in S9 and S10. A failure
  here can make an accepted program weaker than the documented guarantee.
- **Safe expressiveness:** S2 and S4-S7. These programs are rejected today;
  implementing them removes unsafe adapters or awkward wrappers without
  repairing an accepted unsound program.
- **Protocol and usability closure:** S11 and S12. These establish what the
  ownership theorem does and make its refusals reviewable.

Do proof-closure work first even when an expressiveness feature looks smaller.
The ordering is phase-granular: when one numbered section contains both a
proof-closure kernel and a later expressiveness tail, land the kernel early and
return to finish the section after its dependencies exist. The Ordering section
names those splits explicitly.

## S0: Freeze the proof with laundering tests

Before adding expressiveness, make the current guarantee executable. Build a
table-driven suite in which the same owner, borrow, pin, and dependent owner is
attempted through every language transport:

- local declaration and reassignment;
- optional narrowing and branch joins;
- loops, `break`, `continue`, `goto`, return, and error paths;
- scalar and pack generics;
- unions, intersections, aliases, metatables, and type predicates;
- overload selection, failed overload selection, and method adjustment;
- scalar projection, expansion, parenthesized calls, varargs, `select`,
  `unpack`, `pcall`, and coroutine packs;
- arrays, maps, tuples, anonymous tables, nominal records, and field writes;
- closures, callbacks, raw coroutines, and handled suspension;
- casts, `any`, `unknown`, declaration files, plain Lua modules, and C calls;
- qualified declarations, imports, re-exports, incremental cache reloads, and
  generated declarations; and
- safe/unsafe entry and exit in both directions.

Each transport needs every applicable case: safe forwarding succeeds;
discarding fails; duplication fails; and weakening to a raw/plain value fails.
For a deliberately unsupported transport such as arbitrary table storage, the
positive result is rejection at the first boundary rather than accidental
acceptance followed by a later error. Add mutation tests that delete one
capability copy or one check at a time and require a negative test to fail.

Record a capability-flow fixture format used by tests rather than relying only
on diagnostics. It should expose payload, obligation identity, ordered cleanup,
roots, and retention state for compiler tests without becoming a public
reflection API.

Exit criteria:

- every row has a positive and negative regression;
- no owner or borrow crosses an `any`, cast, generic, or module boundary by
  accidental wrapper removal; and
- test results are identical under a clean build, warm incremental build, and
  imported declaration summary.

## S1: One non-forgettable capability representation

Replace ad hoc reconstruction of ownership wrappers and side metadata with the
`ValueSlot` model. Packs already provide the right carrier; scalar inference
must use the same abstraction instead of re-deriving facts from expression
nodes.

`ValueSlot` is a semantic requirement, not a demand for gratuitous allocation
or a rewrite of every interned type. Existing wrapper types and pack records may
remain physical storage where they satisfy the same invariant behind one API.

Required changes:

1. Intern capability records by cleanup identities, root identities, pin
   contract, and retention state.
2. Make substitution rewrite payload types while retaining symbolic
   capabilities.
3. Make narrowing change the payload inside a slot and preserve its capability.
4. Make joins require compatible outstanding obligations. A branch cannot
   merge "moved" and "live" into a usable owner.
5. Make relation checking compare payload compatibility and capability
   compatibility separately, with capability checked first.
6. Make casts incapable of weakening a capability. Only `intoRaw` in `unsafe`
   removes one deliberately.
7. Store slot capabilities in callable types and exported interface records;
   include them in canonical identity and incremental fingerprints.
8. Keep rejected overload candidates side-effect free. Apply moves, borrows,
   and retention only after one candidate is selected.

Do not encode capabilities as ordinary intersections. In particular,
`Bar & Owns<close>` must never become a subtype of plain `Bar` merely because
intersection elimination is valid for structural members.

Exit criteria:

- there is one source of truth for scalar and pack capabilities;
- `T.unwrapOwnership` calls are audited and documented at every remaining
  payload-only boundary; and
- the S0 laundering matrix passes without boundary-specific exceptions.

## S2: Capability-preserving scalar generics

Generic packs already preserve instantiated ownership and provenance. Scalar
generics must do the same.

Add the result relation:

```nupp
local id: function<T>(value: T): T preserves value
local require: function<T>(value: T?): T preserves value
```

For a visible body, infer it when every successful result path transfers the
same parameter capability exactly once. A raising or non-returning path does
not need a result. A bodyless declaration and an intentionally abstract public
contract state it explicitly.

`preserves value` transports all capability axes, not only ownership:

- exact ordered cleanup and opacity;
- exact borrow-root set;
- pin and anchor relation;
- retained/unretained state; and
- the affine identity used for move diagnostics.

Analyze a generic body against symbolic capability use. If it forwards an
unknown capability once, borrows it temporarily, or returns it through a
matching `preserves` result, the function is capability-polymorphic. If it
duplicates, discards, or stores the value, infer that the corresponding actual
must be unrestricted; keep the generic declaration valid and reject only an
affine instantiation. It may never drop an unknown producer-specific cleanup
contract without a reified witness.

A bodyless generic parameter is conservatively unrestricted for an affine
actual unless a parameter mode or `preserves` relation states how the
obligation moves. This gives declaration files a safe default without exposing
kind variables. Inferred unrestricted requirements are serialized in interface
data; an ejected bodyless declaration needs no extra spelling because the same
default reconstructs them.

Examples that must work:

```nupp
local file = require(maybeOpen())
nupp.drop(file)
```

```nupp
local view = id(pool:first())
-- view still holds the pool root
```

```nupp
local function forward<T>(value: T): T
    return value
end
```

Examples that must remain rejected for an affine instantiation:

```nupp
local function duplicate<T>(value: T): (T, T)
    return value, value
end
```

```nupp
local function choose<T>(left: T, right: T, useLeft: boolean): T
    return useLeft and left or right -- the unchosen owner would be lost
end
```

Inference records one source per result in the first version. Choosing among
several affine inputs requires all unchosen obligations to be returned or
discharged and is not disguised as preservation.

Update `assert`, `setmetatable`, and any other standard declaration that
returns the same runtime value. Update hover, definition rendering, docs,
formatting, interface serialization, and fixpoint output.

Preservation is attached to the exact result slot, including a result inside a
fixed or generic pack. A bodyless producer must likewise be able to attach a
fresh owner contract to any result slot rather than relying on a first-result
special case.

Exit criteria:

- optional-owner narrowing through `assert` works without a wrapper producer;
- owner, borrow, dependent owner, pin, and plain-value calls share one generic
  implementation when the current state permits the required move;
- inferred and declared preservation produce identical exported types; and
- a generic body cannot become unsound only when instantiated with an affine
  value.

## S3: Provenance through expressions and projections

Close the known bare-name hole. Provenance must follow the value, not the
syntax shape that happened to produce it.

Introduce stable provenance identities for:

- local aliases and narrowed aliases;
- parenthesized and cast expressions;
- string concatenation, indexing, and calls returning managed storage;
- record and tuple projections;
- pointer arithmetic and slices whose bounds remain known;
- generic scalar and pack forwarding; and
- multi-root expressions.

A derived address records both its roots and the operation that can invalidate
it. A string-derived pointer therefore keeps the string binding alive. A
buffer-derived pointer additionally blocks resize, detach, or other declared
exclusive operations while live.

When a managed root is an expression rather than a named binding, lowering
must keep it in a hidden local for the full proven borrow extent. Static
provenance metadata alone cannot keep a Lua object alive. If no bounded extent
can be established, reject the expression and require the programmer to bind
the root explicitly.

Do not infer roots through opaque arithmetic or an untyped call. Require the
existing narrow assertion:

```nupp
unsafe do
    return nupp.borrowFrom(raw, source)
end
```

Projection identities must distinguish independent fields where the language
can prove independence and conservatively share a root otherwise. Reassignment
to a root or projection with a live dependent borrow remains rejected.

Exit criteria:

- every string-to-pointer expression either carries a live root or requires
  `unsafe`;
- aliasing and narrowing cannot produce a borrowed type with no owner;
- provenance survives calls, packs, module summaries, and projections; and
- an invalidating operation names the live derived view that blocks it.

## S4: Bounds-carrying spans

Proven lifetime is not proven bounds. Add a checked span abstraction only after
S3 can retain provenance through its projections.

The initial span carries:

```text
span<T>
  pointer
  runtime element count
  roots
  access: shared | exclusive
```

It supports checked indexing, checked slicing, and conversion from known
pointer-plus-count APIs. An exclusive write span prevents its source from
moving, closing, resizing, or detaching until the span is committed or leaves
scope. Conversion to a raw pointer, unchecked indexing, and bulk operations
whose size cannot be proven remain `unsafe`.

Do not infer a bound from allocation folklore or a sentinel unless the foreign
contract says so. Do not conflate `cstring` termination with an arbitrary byte
span's length.

Use owned growable buffers, retained immutable views, exclusive write ranges,
mapped memory, compression, process I/O, and pointer-plus-length C APIs as the
acceptance corpus.

Exit criteria:

- safe pointer indexing always has a proven live root and runtime bound;
- slicing preserves or narrows both facts;
- exclusive spans block invalidation; and
- unchecked conversion is visible in the smallest `unsafe` block.

## S5: Borrowed fields and aggregate state

Borrowed fields are currently rejected, which is safe but prevents checked
composites that retain a view. Add them first to nominal records, where field
identity and construction are visible.

Proposed field relation:

```nupp
local record Cursor
    source: borrowed<Buffer>
    bytes: ByteView borrows source
end

local function cursor(borrows source: Buffer): Cursor borrows source
```

For a record owning its root:

```nupp
local record ParsedFile
    file: owned<File>
    view: Bytes borrows file
end
```

Construction must prove every borrowed field from its declared source field.
Field order cannot stand in for lifetime: the relation is explicit. The whole
record carries the union of its external roots. It becomes affine when a field
owns, pins, or carries an exclusive token; a shared borrowed field remains
non-escaping without being needlessly linear. Moving the whole record preserves
internal roots.

Initially reject:

- borrowed fields on anonymous table shapes;
- cycles among borrowed fields;
- a field borrowing an outer local not stored as a declared root;
- replacing or moving a root field while a dependent field is live; and
- returning a projection whose enclosing record will be discharged.

Then add path-sensitive affine field state for post-construction assignment and
partial moves:

```text
uninitialized -> live -> moved/discharged -> reinitialized
```

A partially moved record may access independent live fields but cannot use a
method requiring the whole record. Every exit must account for every live
field, and synthesized drop skips fields already moved only when the flow
state proves that fact.

Exit criteria:

- declared composites retain views without unsafe storage;
- whole-record moves preserve internal provenance;
- partial initialization, overwrite, move, and cleanup are path-complete; and
- anonymous or dynamically keyed storage cannot launder the same capability.

## S6: Dynamic owner collections and discharge reification

Static affine fields cannot represent a runtime number of heterogeneous
owners. Today rejection is safe, but real resource scopes, registries, and
retirement queues otherwise need an unsafe implementation.

Provide one audited owning container rather than permitting arbitrary tables
of owners. Its conceptual API is:

```nupp
do
    local resources = resources.Set("request")
    local input = resources:adopt(openFile("in"))
    local output = resources:adopt(openFile("out"))
    copy(input, output)
end
```

`adopt` moves the owner into the set, reifies its resolved ordered cleanup
references in the set's runtime registration, and returns a borrow tied to the
set. Dropping the set runs every registration in reverse order, attempts all
cleanup steps, and uses the same primary/suppressed failure contract as
lexical cleanup.

An opaque transfer-only owner has no cleanup to reify. It enters the same set
only with an explicit terminal consumer:

```nupp
do
    local obligations = resources.Set("requests")
    local request = obligations:adopt(beginRequest(), submitRequest)
    prepare(request)
end
```

The checker requires the second argument to have a matching `takes` parameter.
The registration stores that resolved function as its discharge witness and
invokes it on set cleanup. Because the witness is per registration, one set may
hold heterogeneous cleanup owners and opaque owners with different terminal
consumers without guessing from their payload types.

This is the narrow place where a producer-specific discharge operation becomes
runtime data. Do not add a global side table, change pointer identity, attach
`ffi.gc`, or make every owner allocate. Static owners remain erased and
zero-cost.

The set must support transferring an owner back out only through an operation
that removes exactly one registration and returns its original capability.
Duplicate adoption, use of the moved input, use of a returned borrow after set
cleanup, and abandonment of the set are rejected. An opaque owner without an
explicit terminal consumer remains rejected. If no terminal operation is
appropriate on every exit, a scope-owned set is the wrong abstraction: keep
the owner in explicit flow or move it into a nominal transfer queue whose own
terminal `takes` contract is checked.

Generic code may forward an unknown capability after S2. It still may not call
`drop` on one unless it receives a reified discharge witness or moves it
into this owning container. This keeps ordinary generic calls erased.

Exit criteria:

- a dynamic number of homogeneous or heterogeneous owners has one checked
  aggregate obligation;
- cleanup owners and opaque owners with explicit terminal consumers can share
  the aggregate without unsafe storage;
- adoption and removal preserve exact cleanup and provenance;
- no ordinary owner pays a runtime metadata cost; and
- the implementation contains the only audited dynamic discharge erasure.

## S7: Closure capture

Status: implemented. [Closure capture](closure-capture.md) is the authoritative
design record.

An ordinary closure borrows every captured ownership value. It remains
copyable, but its callable capability is borrowed and its concrete roots travel
as value-flow provenance. It cannot outlive those roots, enter anonymous
storage, or be returned without a declared relation. `borrows (...)` spells
that relation in type position and can pin it on a closure expression; an
expression with no clause infers its borrow captures from the body.

`takes (...)` moves named owners into a closure, makes that closure affine and
single-shot, and carries the owners' cleanup witnesses. Calling the closure
consumes it. Lexical cleanup drops an uncalled closure and its captures.
Ordinary copyable closures may borrow owners but never own them.

A visible Nupp callee infers that a scoped callback parameter is invoked only
during the call and is neither stored, returned, retained, nor passed to an
unknown target. A bodyless or foreign declaration uses an explicit `scoped`
parameter contract. This lets a borrow-carrying closure cross a synchronous
call without erasing its provenance.

The implemented analysis covers:

- immediate and repeated synchronous invocation;
- callbacks forwarded through other proven scoped calls;
- errors and non-local exits;
- re-entrancy into code that can see another alias of a borrowed root;
- exclusive operations while a callback-held view is live;
- callback conversion to a C function pointer; and
- asynchronous/retained callbacks, which require `pin` plus matching
  `retains`/`releases` and are never scoped by inference.

Exit criteria, completed:

- common iterator and protected-scope callbacks may capture a borrow without
  unsafe code;
- invalid storage, return, coroutine capture, or unknown forwarding rejects the
  borrow at its escape point;
- an owner moved into a closure is discharged exactly once by call or drop;
- re-entrant exclusivity remains sound; and
- a C-retained callback requires a pinned anchor and an explicit release.

## S8: Suspension and structured concurrency

Finish the ownership portion of [suspension.md](suspension.md). The checker
already has a lexical `handle suspension` region; make it load-bearing.

Required rules:

1. A direct raw `coroutine.yield` remains rejected with any live owner, borrow,
   pin, retained handle, resource set, or pending scope cleanup.
2. Function summaries distinguish the checked `suspend` operation from a raw
   coroutine yield or an unknown yielding call. A single undifferentiated
   `yields` bit is sufficient for `nosuspend` but not for ownership.
3. A checked `suspend` may cross a live obligation: with no handler it blocks
   and returns or raises before its call returns; with a handler, that handler
   owns the park and its cancellation. This lets one library acquire a
   resource internally and work both inside and outside a host scheduler.
4. A raw or unknown yielding call is rejected transitively while an obligation
   is live. Putting it lexically inside `handle suspension` does not turn it
   into the checked operation.
5. Inside `handle suspension with h`, a checked suspension may park because `h`
   accepts ownership of every parked continuation and its cancellation until
   it resumes or unwinds.
6. Handler shutdown cancels every park, resumes it with cancellation, drives
   cleanup, and refuses success while a source or park remains.
7. Coroutine handler inheritance and save/switch/restore preserve the lexical
   region's dynamic handler without leaking it between tasks.
8. A structured child may borrow a parent scope only when the parent owns a
   join/cancel obligation that cannot discharge until every child unwinds.
9. Bare `coroutine.create`, `resume`, and `wrap` do not become structured merely
   because their protocol packs are typed.
10. `return`, loop control, and errors leaving the handler region reuse the
    proven scope control protocol so handler release and resource cleanup both
    run.
11. Every cleanup step and `@drop` operation is checked as non-suspending.
    Cleanup runs while another obligation is being discharged and, during
    cancellation, while its handler may be shutting down; allowing it to park
    again makes completion circular. A bodyless cleanup contract is trusted to
    return without suspending.

The handler's eventual-resume/cancel behavior is part of the trust boundary;
all ownership state around its installation, shutdown, and one-shot transitions
is statically checked.

Exit criteria:

- transitive raw or unknown yielding cannot hide behind a function call;
- a checked suspension blocks safely without a handler and parks safely with
  one;
- a resource held across handled suspension cleans up on normal resumption,
  failure, and cancellation;
- an abandoned raw coroutine cannot strand an obligation; and
- structured children cannot outlive a borrowed parent resource.

## S9: FFI contract completeness

Audit every C-shaped value path against one vocabulary:

```text
fresh result       @owned
consumed input     takes
call-only input    borrows
invalidating input exclusive
stored input       retains
unregistered input releases
derived output     @borrowed(... from ...)
fresh output       @owned(out = ...)
```

Complete the following gaps:

- mark every C-derived function and callback type;
- transport contracts through function pointers, aliases, imports, header
  translation, and overloads;
- reject variadic or indirect C calls whose pointer effects are unknown;
- preserve per-output ownership and roots for all logical outputs;
- verify success predicates before creating obligations;
- keep allocator/context state explicit in a nominal owner;
- match each retention with the same pinned identity and release contract;
- reject pointer arithmetic without root and, after S4, bounds; and
- reject `ffi.gc` on an owned, borrowed, pinned, or retained value in safe
  code, because a finalizer would create an untracked second cleanup path; and
- make generated C declarations round-trip these facts byte-identically.

Provide an audit command or structured report that lists every foreign pointer
parameter/result with its contract and every raw use that requires `unsafe`.
This does not prove C; it makes the trusted surface enumerable and reviewable.

Exit criteria:

- no validity-dependent use of a typed C pointer occurs with an unknown
  lifetime operation;
- all retained Lua memory has a checked anchor and release transition;
- callback and output-parameter contracts survive every declaration path; and
- the project's trusted foreign surface can be reviewed from one report.

## S10: Gradual and module boundaries

Ownership must be stricter than ordinary gradual typing. `any`, plain Lua, and
an unresolved indirect call cannot erase a capability by convenience.

Rules:

- Passing an owner or borrow to `any`, `unknown`, an untyped call, or an
  uncontracted module field is rejected when the destination may retain,
  duplicate, or discard it.
- A safe adapter may expose only a borrow whose non-escape is proven.
- An ownership transfer to plain Lua requires `intoRaw` inside `unsafe`; a
  value returning from Lua requires a corresponding narrow assertion.
- Re-exported and aliased callable values carry their complete parameter,
  result, preservation, cleanup, provenance, retention, and suspension facts.
- Function-valued declaration fields can carry producer and result-slot
  ownership contracts; until that surface lands, a named annotated wrapper is
  required rather than silently treating the field as plain.
- Interface cache keys include every such fact. Loading an older or malformed
  cache discards it rather than weakening the answer.
- Comptime may inspect syntax and types but cannot execute or synthesize an
  untracked owner into the runtime program.

Add mixed `.nupp`, `.g.nupp`, `.lua`, generated declaration, and cyclic module
fixtures. Run them with producer-before-consumer and consumer-before-producer
load order, clean and incremental.

Exit criteria:

- gradual typing never acts as an implicit ownership escape hatch;
- every intentional crossing is a small, named unsafe adapter; and
- module order and cache state do not change capability diagnostics or cleanup
  behavior.

## S11: Typestate-shaped protocols without general typestate

Many protocols need no new typestate system when ownership and provenance are
used precisely:

```nupp
@owned(finishPass)
local function beginPass(borrows frame: Frame): Pass borrows frame

local function finishPass(takes pass: Pass)
```

The pass owner prevents submission or destruction of the borrowed frame until
it finishes. Distinct nominal states and consuming transitions can model
protocols whose payload operations genuinely differ:

```nupp
local function commit(takes write: WriteRange): CommittedRange
```

Copying an external resource is never inferred from `Copy`, table identity, or
a structural operation. A reference-counted or duplicable resource exposes an
explicit producer, and each call creates one independently checked obligation:

```nupp
@owned(release)
local function clone(borrows value: Resource): Resource
```

Add no arbitrary state predicates to the ownership checker. Instead, audit the
acceptance corpus for begin/end, map/unmap, reserve/commit, open/close,
register/unregister, and acquire/submit/cancel protocols. Use existing
ownership when one outstanding token can represent the state. Record any case
that still requires value-dependent reasoning before considering a separate
typestate plan.

Exit criteria:

- all token-shaped protocols are expressible through owners, dependent roots,
  `takes`, and nominal transitions; and
- no ownership diagnostic claims to prove arbitrary runtime state.

## S12: Diagnostics, tooling, and reference contract

Sound rejection must also be actionable.

Every ownership diagnostic should include, where applicable:

- the binding and operation that created the obligation;
- the exact move/discharge that consumed it;
- every root keeping an owner live;
- the projection or callback through which a borrow escaped;
- the cleanup contract and module where it was declared;
- the call-chain edge that may suspend;
- whether the missing fact needs a safe annotation or an unsafe assertion; and
- one whole machine-applicable fix when control flow can be preserved.

Add hovers that show inferred parameter effects and result preservation without
requiring source annotations. Definitions and references for cleanup and root
contracts must cross modules. Renames update structured references, never
strings. The formatter and grammar cover every added relation.

Complete the remaining resource-scope surface after the capability work makes
it mechanical:

- destructuring or multi-name acquisition retains every affine result rather
  than applying Lua truncation accidentally;
- an optional owner is bound as one only after an explicit narrowing, with
  capability-preserving `assert` providing the concise form;
- annotations on function-valued declaration fields represent owning
  producers without a wrapper; and
- no inline `using` or name-based `adopt` form invents ownership for an
  unannotated producer. Such adoption remains `fromRaw` in `unsafe`.

Update `./bin/nupp reference language`, `docs/ownership.md`, diagnostic
explanations, and FFI examples from the same final doctrine. Remove
stale statements as each milestone lands; an implemented guarantee and a plan
must not disagree about whether it exists.

Exit criteria:

- every new diagnostic has an explanation, corrected example, JSON help, and
  LSP coverage;
- inferred capabilities are visible in hover and exported declarations; and
- the reference states the guarantee and trust boundary in one place.

## Ordering

Implement in this order:

1. **S0 proof matrix.** Freeze what cannot regress.
2. **S1 capability representation.** One carrier before adding more facts.
3. **S3 provenance proof kernel.** Remove the known rootless-borrow hole for
   existing scalar expressions, generic packs, aliases, and projections. Its
   scalar-generic row deliberately waits for S2.
4. **S9 and S10 boundary proof.** Harden FFI, gradual typing, modules, and caches
   before expanding storage.
5. **S8 suspension proof kernel.** Distinguish checked suspension from raw or
   unknown yielding transitively, make cleanup non-suspending, and enforce the
   handler ownership contract. This needs S1 and transported suspend-kind
   summaries, not S6.
6. **S2 scalar preservation.** Add capability-polymorphic scalar transport and
   complete S3's scalar-generic provenance row.
7. **S4 spans.** Add bounds on top of reliable provenance.
8. **S5 aggregate state.** Add declared stored borrows and partial moves.
9. **S6 dynamic owner collections.** Reify cleanup and explicit terminal
   consumers at one audited abstraction.
10. **S7 closure capture.** Add provenance-tracked borrowed closures, scoped
    transport, and affine `takes (...)` captures after provenance is complete.
11. **S8 structured-concurrency tail.** Add resource-set regressions and
    structured children after their obligation and callback carriers exist.
12. **S11 protocol audit.** Prove whether any separate typestate work remains.
13. **S12 tooling throughout**, completed as the final gate.

The early S3 slice does not need scalar preservation to fix the rootless cases
accepted today; S2 later supplies and tests the missing scalar-generic carrier.
Likewise, S8's abandonment proof does not depend on `resources.Set`: ordinary
owners, borrows, pins, and scope obligations are enough to close it. S6 adds
its new aggregate obligation to that established matrix, and structured-child
expressiveness finishes afterward. C-derived callable marking lands with the
S9 boundary proof because S7 also consumes the same fact.

## Verification strategy

Each milestone adds four layers of verification:

### Checker tests

- one minimal positive example for every permitted transition;
- one diagnostic for every forbidden weakening, duplicate, discard, escape,
  invalidation, and abandonment;
- control-flow variants for every exit; and
- generic, pack, overload, import, and incremental variants.

### Runtime tests

- cleanup identity and order;
- partial acquisition and multiple cleanup failure;
- C success/failure output behavior;
- pin retain/release transitions;
- resource-set adoption/removal and reverse cleanup; and
- handled resumption, failure, cancellation, and shutdown.

### Corpus tests

Maintain strict fixtures for:

- files, sockets, processes, and layered TLS-style resources;
- allocator-context and arena allocations;
- owned buffers, immutable views, exclusive write ranges, and spans;
- begin/end GPU- or transaction-shaped tokens;
- callback registration and release;
- dynamic resource scopes and retirement queues;
- worker channels and message-copy boundaries; and
- suspended operations holding resources across cancellation.

TECS is a useful large acceptance corpus for several of these shapes, but the
language guarantee and tests must stand without it.

### Build invariants

Run:

```sh
./bin/nupp test
./bin/nupp fixpoint
```

Also compare clean and warm incremental diagnostics, generated line counts,
interface hashes after each capability-only change, and optimized versus
unoptimized output. Add targeted benchmarks for ordinary calls, generic
forwarding, scope cleanup, resource-set adoption, span indexing, and
suspension.

No common ownership operation may acquire a runtime side table or closure.
Only explicitly dynamic abstractions such as `resources.Set` may pay for reified
cleanup.

## Completion gate

Ownership hardening is complete when all of the following are true:

- the S0 laundering matrix has no untracked transport;
- scalar and pack generics preserve exact capabilities or reject the call;
- every safe derived pointer has roots and, when indexed, bounds;
- nominal composites can safely hold declared borrows and partially move
  affine fields;
- dynamic owners are confined to the checked owning-container abstraction;
- scoped callbacks cannot escape and retained callbacks are pinned;
- retention cannot be duplicated or abandoned, and every retained pin reaches
  its matching release before its anchor can end;
- raw and transitive suspension cannot abandon obligations, while handled
  cancellation unwinds them;
- C, untyped Lua, `any`, modules, and caches cannot silently weaken ownership;
- the trusted surface is enumerable and documented; and
- the full tests, fixpoint, strict corpus, and ownership benchmarks pass.

At that point remaining rejected programs are deliberate limits rather than
holes in the proof. Extending arbitrary typestate, native-thread data-race
freedom, or unsafe pointer verification would be a new language project, not
unfinished ownership work.
