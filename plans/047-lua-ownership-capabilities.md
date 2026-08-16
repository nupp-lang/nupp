# Lua ownership capabilities

> Implemented. The checker stores per-value roots, access, regions, anchors, and
> retentions in canonical `CapabilityFacts`; obligation, move, and active-loan state
> have one query path. The old public ownership-policy aliases and borrowed/pinned
> wrapper spellings are gone.

## Decision

Nupp will finish its ownership model as garbage collection plus opt-in affine
capabilities. Ordinary Lua values remain freely aliased, mutable, and collected.
Only values that carry a cleanup obligation, a rooted view, an exclusive region,
or a pinned anchor participate in ownership checking.

The core Nupp-to-Nupp type and contract vocabulary is:

```nupp
affine(T, cleanup)
affine(T)

takes value: T
borrows value: T
exclusive value: T

T borrows (source)
T preserves source

borrows (capture)
takes (capture)
scoped callback
```

`affine(T, cleanup)` carries one exact cleanup-function identity.
`affine(T)` is deliberately transfer-only. `takes`, `borrows`, and `exclusive`
describe what a call does for its duration. `borrows (source)` records the roots
and region from which a result, field, or closure capture was derived.
`preserves source` conserves the source's complete capability through a generic
result: movable obligations and anchors move, while provenance is reproduced on the
result. `scoped` gives a callback a fresh nonescaping invocation scope.

The language will not expose named lifetimes, lifetime parameters, a reference-type
lattice, or read-only shared references. Relationships name ordinary values, and the
checker carries their roots invisibly.

[`042-affine-types.md`](042-affine-types.md) has largely landed: `affine(...)` is a
public type constructor. `Owned`, `Transfer`, and the structural `Drop` default
previously existed as ordinary prelude policy and are now removed. This plan keeps 042's affine constructor,
function identity, cleanup contract, origin proof, automatic destruction, comptime
construction, and erased runtime representation, but deliberately replaces that
prelude policy. It retires 042's completion criteria that require `Owned`, `Transfer`,
and `Drop` to remain in checked prelude source; its criteria for user-defined affine
types, the absence of compiler name checks, exact terminal identity, representation
compatibility, and fixpoint remain binding.

This plan also supersedes any remaining name-based or wrapper-based ownership
representation in
[`034-ownership-in-types.md`](034-ownership-in-types.md),
[`035-cleanup-registration.md`](035-cleanup-registration.md), and
[`015-ownership-hardening.md`](015-ownership-hardening.md).

## Goals

- Keep normal Lua programming outside the ownership system.
- Give every checked resource one statically accountable cleanup obligation.
- Prevent a view from outliving or invalidating any value that roots it.
- Give generic preservation and general regions one stable capability representation
  to extend in their own plans.
- Infer relationships inside private implementations while making public contracts
  explicit and stable.
- Make safe libraries express ownership without compiler recognition of their names.
- Keep checked Nupp-to-Nupp paths erased and allocation-free.
- Expose one capability query that dynamic-boundary checking can use without another
  ownership representation.

## Non-goals

- Reclaim ordinary tables without the Lua garbage collector.
- Make a shared borrow read-only.
- Prove all dynamic indexes or arithmetic ranges disjoint.
- Make arbitrary raw pointers safe without a root and bounds.
- Introduce a general concurrency capability lattice. A future parallel object model
  may add an isolated-transfer capability when a concrete worker use case requires it.
- Preserve source compatibility with `Owned`, `Transfer`, `Drop`, `Borrowed<T>`, or
  `Pinned<T>`.

## Why this model

Rust's ownership model gets its reach from making references, mutation, and lifetime
parameters part of nearly every API. Importing that model whole would make ordinary
Lua tables participate in borrow checking, turn shared access into read-only access,
and expose named lifetime plumbing in generic code that otherwise needs none of it.
That is the wrong default for a language whose ordinary values are garbage-collected
and freely aliased.

Reference counting and tracing already solve memory reachability, but do not prove
that a file closes once, a lock guard unlocks once, or a native view dies before its
backing allocation. Pure region or arena systems make bulk allocation simple but do
not cover independent handles, partial moves, or views into externally managed
storage. Uniqueness and isolated-object systems make transfer simple by restricting
the entire reachable object graph, which is a poor fit for Lua's shared table graphs.
Actor-capability systems solve a broader concurrency problem and would require a
runtime and object-model commitment that these resource proofs do not need.

Opt-in affine capabilities take the useful intersection: GC answers ordinary object
lifetime, exact cleanup identities answer resource obligations, hidden root sets
answer view lifetime, and regions answer invalidating access. The checker pays that
complexity only where an API introduces one of those facts. This is as strong as the
Rust subset Nupp needs for local resources and FFI views, while retaining Lua
mutation and omitting general reference-lifetime types. If future safe concurrency
needs isolated transfer, add that capability from a demonstrated worker API rather
than forcing it into the base ownership model now.

## Remove the policy aliases

Delete `Owned`, `Transfer`, and `Drop` from the global prelude. They are not distinct
language mechanisms:

```nupp
type Owned<T, const cleanup: function> = affine(T, cleanup)
type Transfer<T> = affine(T)
```

Keeping those names makes an alias look like a second ownership kind and makes APIs
appear to choose between `Owned` and some other affine type. Packages instead publish
the resource policy they mean:

```nupp
local record FileHandle
    descriptor: integer
end

local function closeFile(takes file: FileHandle): nil
    close(file.descriptor)
end

global type File = affine(FileHandle, closeFile)
```

A generic structural cleanup helper may live in an ordinary library, but it is not a
global prelude type and the compiler does not know its name. `drop value` remains
language syntax: it invokes the cleanup identity carried by the value's affine type,
not a method selected by a `Drop` marker.

Migrate every standard-library signature from `Owned<T>` or `Transfer<T>` to a named
resource type or a direct `affine(...)` application. Public resource aliases should
normally hide a private representation so callers name `File`, `Reader`, `Writer`, or
`LockGuard`, not a generic ownership wrapper.

At the `d8ac35a5` baseline, `Owned<` appears 62 times in `src`, 118 in `tests`, and 38
in `docs`; `Transfer<` appears 7, 8, and 7 times respectively. C0 refreshes and records
those counts, and C2 treats their migration as a mechanical deletion gate rather than
leaving an indefinite compatibility tail.

Delete `Borrowed<T>` from the user-visible type namespace. A borrow is a property of a
particular flow value, not a wrapper around its payload type. Two values of type
`ByteView` may have different roots without becoming different nominal or generic
types. The current `ownershipConstructors` table in
`src/nupp/compiler/check/resolve.nupp` makes both `Borrowed<T>` and `Pinned<T>`
user-writable constructors; C2 removes only the borrowed entry, while C5 replaces and
then removes the pinned entry.

## One canonical capability

Every value tracked by the checker has one capability value:

```text
Capability {
    obligation: none | ObligationTree
    loans: set<Loan>
    anchors: set<PinnedAnchor>
    retentions: set<ForeignRetention>
}

ObligationTree = cleanup(function identity)
               | transfer-only
               | aggregate([ObligationTree...])

Loan {
    roots: set<flow identity>
    access: shared | exclusive
    region: Region(root, path-or-range)
}
```

This is flow data associated with a value or place. It is not another runtime object,
not part of ordinary nominal identity, and not syntax users instantiate directly.

The type `affine(T, cleanup)` contributes the cleanup obligation. Aggregate records,
tuples, and closures compose the obligation trees of their live components. An
aggregate containing a `transfer-only` leaf is itself undroppable until that leaf is
moved out or released in `unsafe`; dropping its other cleanup leaves does not erase
the transfer obligation. Partial moves remove exactly the moved subtree.

`ordinary` means that the loan set is empty: no borrow contract currently restricts
the value or place. It does not mean unique; an ordinary Lua table may still have
arbitrary GC-managed aliases. A shared loan means a flow value is derived from named
roots and therefore blocks invalidation of its region while live. An exclusive loan
means the checker has sole access to that region for the stated call or derived
result. A set, rather than one access/region pair, lets an aggregate retain several
independent borrowed fields.

Pinned anchors and foreign retentions are separate sets for the same reason. Each
entry retains its component path and exact root or foreign contract, so projection
and partial movement select only the entries belonging to that subtree. These
definitions are the basis of diagnostics and joins.

`borrows (source)` contributes a loan. Borrowing an existing borrow flattens to its
ultimate live roots while retaining the intermediate affine owner when consuming that
intermediate value would invalidate the result. `exclusive` contributes an exclusive
loan for the call and for any result derived from it. `nupp.pin(value, root)`
contributes a strong anchor. A declared C `retains` operation contributes a foreign
retention token until its matching `releases` operation consumes it.

Make this capability the only answer used by:

- move and use-after-move checking;
- lexical destruction and explicit `drop`;
- call argument modes;
- result provenance;
- partial field moves;
- closure capture;
- suspension checks;
- C retain/release contracts;
- pinning;
- region overlap;
- reflection and diagnostics; and
- generic substitution.

Remove parallel truth stored in ownership wrapper tags, `affineResource`, borrowed
flags, exclusive booleans, span method names, or nominal declaration history. Type
wrappers may remain as interned implementation details only when they are a canonical
input to the capability calculation; checker decisions must query `Capability`.

## Affine identity and cleanup

Affine type identity remains:

```text
affine(canonical representation, cleanup declaration identity | transfer-only)
```

The alias name adds no identity. Equal cleanup signatures are insufficient; the same
function declaration must be named. A closed cleanup must be exactly compatible with:

```nupp
nosuspend function(takes Representation): nil
```

An open generic affine type carries the symbolic const-function identity until
substitution closes it. Validation then uses the ordinary function checker. No
resolver, checker, generator, LSP path, or documentation path may recognize a
resource alias by spelling.

Cleanup remains erased from each runtime value. Direct checked calls lower to the
resolved cleanup function or registry entry already selected by the type. Aggregate
cleanup attempts every independent obligation, preserves the first failure, and
attaches later failures as suppressed errors.

## Shared access remains Lua-like

`borrows` means shared, nonconsuming, call-scoped access. It does not mean `const`.
Ordinary Lua table mutation remains valid through a shared borrow when it cannot
invalidate a tracked view or move an affine component.

Require `exclusive` when an operation may:

- resize, replace, or free storage behind a live view;
- move, replace, or destroy an affine field;
- create a mutable child region;
- mutate identity-bearing state used by a provenance proof; or
- require sole access for a declared native contract.

This deliberately differs from a model in which every shared reference is read-only.
It preserves Lua's normal aliasing behavior while statically controlling operations
that can make another alias invalid.

## Compositional dependencies

Two independently gated plans build on the canonical record:

- [`049-compositional-capability-preservation.md`](049-compositional-capability-preservation.md)
  generalizes scalar `preserves`, defines one-to-one movement of obligations and
  anchors, fixes its `takes` parameter direction, and carries relationships through
  aggregates, packs, unions, closures, and module summaries.
- [`050-general-capability-regions.md`](050-general-capability-regions.md) defines
  place paths, overlap, audited splitting, exact loop-header invariants, back-edge rules, and
  the exact boundary between ownership-specific span logic and unrelated C, effect,
  storage, allocation, and AOT behavior.

Neither is required to migrate the existing ownership representations to one
canonical capability query. They begin only after C1 stabilizes that query and each
has its own compatibility, diagnostic, performance, and deletion gates.

## Higher-order calls and closures

Every invocation of a `scoped` callback receives a fresh hidden scope. Values rooted
in that invocation may be used by the callback and by nested scoped calls, but may not
appear in:

- the callback result unless the callable contract relates that result to an outer
  root;
- a retained callback;
- a global or longer-lived field;
- a coroutine that may outlive the invocation; or
- an `any` or untyped boundary.

Function types may state their own value relationships:

```nupp
function(borrows source: Buffer): ByteView borrows (source)
```

Those relationships survive storage in records, generic substitution, overload
selection, imports, and nested callable results. Function assignability performs the
safe parameter/result variance checks over hidden root sets and access modes. A
caller may shorten a borrow; it may not lengthen one or turn shared access into
exclusive access.

Closure captures use the same relationship machinery as function results. The forms
`borrows (capture)` and `takes (capture)` remain because they state an escaping
relationship at the closure boundary. A `takes` closure remains affine and
single-shot; dropping it destroys its still-live captures without running the body.

## Inference and public contracts

Infer ownership inside private functions and local closures:

- a parameter only observed during the call is `borrows`;
- a parameter used by an invalidating operation is `exclusive`;
- a parameter consumed, retained in an affine aggregate, or moved into a returned
  value is `takes`;
- result roots are inferred from returned expressions;
- borrows end at their last use, including branch-sensitive last use.

Explicit spelling remains legal on private code and is checked against the body.

Require an explicit mode or result relationship at a public boundary only when the
corresponding parameter, result, field, or callback can carry a nontrivial capability:
a cleanup or transfer-only obligation, roots, exclusive access, a pin, or foreign
retention. An exported function over strings, numbers, ordinary records, or ordinary
Lua tables remains unannotated. This condition is what keeps normal Lua outside the
ownership system.

Within that scope, require explicit contracts on:

- exported functions and methods whose affected values can carry a capability;
- interface and callable-record members;
- bodyless declarations;
- public record fields that retain a view;
- callbacks accepted beyond the immediate expression; and
- `cdef` parameters and results that carry ownership, provenance, exclusivity,
  pinning, or retention facts.

An unconstrained public generic type parameter is capability-bearing because callers
may instantiate it with an affine or rooted type. A bound that proves the type is
ordinary removes that requirement. A public declaration missing only ordinary
parameters receives no ownership diagnostic and no generated noise.

The inferred private contract must be available to optimization and diagnostics but
must not silently become a package ABI. A code action may write the inferred public
contract when a declaration is exported.

## Pinning

Replace the special generic spelling `Pinned<T>` with the type constructor:

```nupp
pinned(T)
```

`nupp.pin(pointer, root)` remains the sole public introduction operation. It is the
existing checked library intrinsic, not new `pin` syntax and not a bare global. It
produces `pinned(PointerType)`, strongly anchored in `root`. The type constructor is a
compiler primitive; the call keeps its stable `nupp.pin` declaration identity and the
checker validates it through the ordinary intrinsic table rather than its spelling.

Pinning does not itself select a cleanup policy. If the pinned handle must also be
affine, an ordinary alias states both policies through its representation and cleanup
rather than teaching the compiler a combined name.

A pinned value may cross a declared C `retains` call. The matching `releases`
contract updates the retained state. Moving or destroying the root is rejected while
any pin or foreign retention remains live.

Delete `Pinned<T>` and any name-based pointer-shape branch after migration. The
lowercase constructor is a compiler primitive for the same reason as `affine`: it
creates a capability descriptor, not a library nominal.

## Foreign contracts

Restrict `retains` and `releases` to `cdef` parameter grammar and documentation. They
must not appear as ordinary Nupp function parameter modes. Ordinary Nupp APIs express
storage by taking an affine value, borrowing a value, or accepting a `scoped`
callback.

A borrowed C output continues to name its roots:

```nupp
cdef function find(
    borrows owner: Handle,
    out view: Item* borrows (owner)
): Success<int32, 0>
```

Raw pointer indexing, pointer arithmetic without a checked region, and reconstructing
provenance remain `unsafe`. Bounds and lifetime are separate proofs: a root does not
prove an index valid, and a checked count does not keep storage alive.

## Dynamic-boundary dependency

Implicitly erasing a nontrivial capability into `.lua`, `any`, reflection data,
hot-reload storage, or opaque foreign memory is unsafe, but specifying the runtime
escape mechanism is independent work.
[`048-dynamic-capability-boundaries.md`](048-dynamic-capability-boundaries.md) owns
generation-checked handles, their type and API spelling, hot-reload integration, and
migration of existing `any`-backed resources.

This plan supplies the canonical capability query that 048 consumes and reserves the
rule that a nontrivial capability cannot disappear silently. It does not make dynamic
handles a completion dependency for canonical capabilities, compositional generics,
regions, higher-order relationships, pinning, or suspension. Ordinary rootless,
obligation-free values continue to cross `any` unchanged throughout this work.

## Suspension and cancellation

Apply the canonical capability query at every suspension point. A borrow may cross a
handled suspension only when its roots remain live in the suspended frame and the
handler's cancellation path discharges every obligation. An exclusive region may not
cross an unknown suspension that could reenter overlapping code. Raw suspension
cannot cross cleanup, pin, or retained-state obligations.

This replaces parallel checks for owned values, affine fields, closures, pinned
pointers, and borrowed views with one capability traversal. The cancellation cleanup
order and suppressed-error behavior remain those specified by
[`018-suspension.md`](018-suspension.md).

## Diagnostics and tooling

Diagnostics should describe the concrete capability conflict:

- which value owns the cleanup obligation;
- which result or field retains which root;
- the last use that keeps a borrow live;
- which callback scope a value attempted to escape; and
- which public value makes an explicit capability contract necessary.

Reserve one code for each new static failure class rather than routing them all
through the existing general ownership diagnostic:

| Code | Failure class |
| --- | --- |
| `NUPP2608` | a scoped or rooted value escapes its permitted lifetime |
| `NUPP2610` | a capability-bearing public contract omits a required mode or relation |

C0 verifies that these codes are still unallocated before implementation. Each code
lands together with its `explain` entry, example and correction, related locations,
generated reference entry, and row in `docs/diagnostics.md`. Plans 048, 049, and 050
own their dynamic, preservation, and region codes so the plans do not race for the
same diagnostic surface.

Every diagnostic carries related locations for the root, derivation, conflicting use,
and cleanup when those locations exist. Avoid messages that expose internal wrapper
tags or describe every capability as `Owned`.

Hover shows the ordinary type first and capability detail second. For example:

```text
ByteView
borrows buffer; shared region buffer.bytes
```

Go-to-definition on an affine cleanup reaches the exact function declaration.
References and rename treat that function identity semantically. Inlay hints may show
inferred private `takes`, `exclusive`, `borrows`, and result relationships, but remain
off by default. Code actions can make an inferred contract explicit.

Reflection reports capability kind, cleanup identity, roots when statically named,
access, pinning, and aggregate shape without inventing a runtime wrapper. Generated
documentation uses the same public vocabulary as source.

## Implementation order

### C0 — Inventory and freeze behavior

- Inventory every ownership flag, wrapper tag, name check, span special case, dynamic
  escape, and diagnostic.
- Add characterization tests for existing affine cleanup, field moves, borrows,
  exclusive span regions, callbacks, pins, C retention, and suspension.
- Verify and reserve the new diagnostic codes, including `explain` and documentation
  work for each failure class.
- Record unchanged-check, private-body invalidation, exported-type invalidation,
  module-summary size, and checker peak-memory baselines.
- Record generated Lua and C ABI baselines so the refactor cannot add wrappers.

### C1 — Canonical capability query

- Introduce the immutable capability value and one checker query over a type plus flow
  state.
- Translate existing affine, borrowed, exclusive, pinned, aggregate, and closure state
  into it without changing public behavior.
- Migrate consumers one subsystem at a time and delete the parallel answer after each
  migration.

### C2 — Remove policy aliases

- Add concrete standard-library resource aliases.
- Migrate all `Owned`, `Transfer`, and global `Drop` uses.
- Remove those prelude declarations and their documentation.
- Remove `Borrowed<T>` from the public namespace.
- Keep compatibility out of the compiler; packages that want aliases define them.

### C3 — Higher-order relationships

- Give each scoped invocation a fresh hidden root.
- Preserve function-type parameter/result relationships through storage, generics,
  imports, and overloads.
- Complete safe variance and borrow-shortening rules.
- Cover nested callbacks, returned closures, and coroutine capture.

### C4 — Inference and contract writing

- Infer private parameter modes, result roots, preservation, and last use.
- Require explicit public and foreign contracts only for values that can carry a
  nontrivial capability; leave ordinary exported APIs unannotated.
- Add semantic tokens, hover details, inlay hints, and contract-writing code actions.

### C5 — Pinning and foreign cleanup

- Add `pinned(T)` and migrate `Pinned<T>`.
- Keep `nupp.pin(pointer, root)` as the checked introduction intrinsic and rebase pin
  and retain/release checking on the canonical capability.
- Restrict retain/release syntax and docs to `cdef`.
- Update and regenerate `docs/grammar.abnf` for `pinned(T)` and removed constructors.
- Verify retained roots, release balance, C outputs, and ABI erasure.

### C6 — Suspension, documentation, and deletion

- Replace suspension-specific ownership walks with the capability traversal.
- Update the language reference, grammar, ownership guide, migration guide, and all
  examples.
- Delete superseded wrapper types, flags, special cases, compatibility code, and dead
  diagnostics.
- Run the full suite, fixpoint, generated-reference verification, and C ABI checks.

Each stage lands with its own migration and deletion. Temporary old and new
representations may coexist across the repository while a stage migrates consumers,
but no subsystem may leave that stage with two authoritative answers. Delete the old
field, wrapper, or query immediately after its final consumer in that stage moves.

## Checker performance gates

Capability roots, obligation trees, and callable relationships enter
module summaries and therefore affect both steady-state checking and invalidation.
C0 captures medians over at least ten runs on the same machine and compiler build.
Every representation stage compares against that frozen baseline:

- an unchanged warm `./bin/nupp check` may regress by at most 5% or 2 ms, whichever
  allowance is larger;
- editing a private function body and rechecking may regress by at most 5%;
- editing an exported type and forcing project-wide invalidation may regress by at
  most 10%;
- serialized module summaries and incremental fingerprints may grow by at most 10%
  on the compiler-plus-stdlib corpus; and
- checker peak resident memory may grow by at most 10% on a clean full check.

A result outside a gate blocks the stage unless a separately reviewed benchmark
change explains the cost. Benchmarks must report cache hits and invalidated module
counts so a faster-looking run cannot conceal a wrong invalidation answer.

## Verification matrix

Focused checker tests must prove:

- ordinary tables remain freely aliased and mutable;
- affine values move once and clean up exactly once on every path;
- transfer-only values cannot be silently discarded or dropped;
- aliases with equal representation and cleanup identity interchange;
- aliases with different cleanup identities do not;
- shared roots block invalidation but not ordinary compatible mutation;
- scoped callback values cannot escape directly;
- callable relationships survive assignment, import, and overload selection;
- private inference agrees with an equivalent explicit signature;
- capability-bearing public declarations missing a relationship receive the reserved
  actionable diagnostic, while ordinary public declarations remain unannotated;
- pinning and C retain/release balance roots;
- suspension and cancellation preserve or discharge every capability; and
- every new failure class has a stable code, `explain` entry, related locations, and
  `docs/diagnostics.md` row.

Generation tests must prove that checked capabilities add no per-value wrapper,
hidden dictionary, lifetime token, generation word, closure, or metatable. Benchmarks
cover call overhead, scoped callbacks, moves, and cleanup-heavy unwinding. Checker
benchmarks enforce the separate warm-check, invalidation, summary-size, and memory
gates above.

Fixpoint must pass after every compiler-representation stage. Reflection snapshots,
module fingerprints, LSP fixtures, documentation links, and bootstrap output are part
of the acceptance surface.

## Completion criteria

This plan is complete when:

- the global prelude contains no `Owned`, `Transfer`, or ownership-policy `Drop`;
- source uses `affine(...)`, value relationships, and concrete resource names;
- one capability query answers every ownership subsystem;
- plans 048, 049, and 050 can extend that query without introducing another
  ownership representation;
- higher-order relationships remain safe across storage and module boundaries;
- private code receives useful inference, capability-bearing public code carries
  explicit contracts, and ordinary public APIs remain unannotated;
- pinning uses `pinned(T)` and foreign-only retain/release contracts;
- `nupp.pin` remains the checked introduction operation and `docs/grammar.abnf` is
  regenerated for the final constructors;
- shared Lua mutation remains available when it cannot invalidate a proof;
- checker throughput, invalidation, summary-size, and memory budgets pass;
- generated checked code and C ABI remain representation-compatible; and
- the full suite, fixpoint, bootstrap, documentation, and performance gates pass.
