# Dynamic capability boundaries

## Decision

Checked Nupp will not silently erase a live capability into `any`, an untyped Lua
module, reflection storage, a hot-reload state bag, or opaque foreign memory. Code
that needs a dynamic boundary chooses one of three explicit forms:

1. a checked wrapper whose own affine policy encloses the dynamic representation;
2. a generation-checked `nupp.dynamic` store and typed handle; or
3. `unsafe release` and `unsafe adopt`, with the proof owned by the caller.

This is separate from [`047-lua-ownership-capabilities.md`](047-lua-ownership-capabilities.md).
Plan 047 supplies the canonical capability query and the rule that nontrivial facts
cannot disappear. This plan owns the runtime representation, API, hot-reload policy,
diagnostics, and migrations for the places that intentionally cross a dynamic
boundary.

Ordinary rootless values remain ordinary Lua. Passing a string, number, rootless
table, or other obligation-free value through `any` does not allocate a handle and
does not invoke this facility.

## Goals

- Make dynamic capability erasure visible in source and reviewable at one operation.
- Keep cleanup exact even when a typed value is stored heterogeneously.
- Reject stale or mistyped recovery before user code dereferences a value.
- Let hot-reload state retain explicitly enrolled resources transactionally.
- Add no representation or runtime cost to direct checked Nupp-to-Nupp calls.
- Give untyped adapters a stable opaque token rather than a raw owned value.

## Non-goals

- Make arbitrary `any` storage statically typed.
- Infer resource ownership from runtime methods such as `close` or `destroy`.
- Store a transfer-only value whose eventual consumer is unknown.
- Keep an external root alive when only a borrowed child was enrolled.
- Automatically migrate a live value across an incompatible representation or
  cleanup-policy change.
- Replace ordinary tagged unions, interfaces, or checked wrappers when those can
  express the variants statically.

## Prefer a checked wrapper

A private representation may contain `any` when one enclosing affine value owns the
whole policy. Its constructor accepts a typed affine input, consumes it, and
immediately establishes one concrete enclosing cleanup obligation. The single
representation-erasing assignment is an audited `unsafe release` inside that module;
the cleanup performs the matching concrete discharge. No `any` appears in the public
contract and no unprotected raw representation is observable between those steps.

This option is for a closed concrete policy. An erased generic wrapper over arbitrary
`T` cannot recover `T`'s cleanup identity without monomorphization or a hidden
dictionary, so it must use the dynamic store rather than claiming that `any` retained
the policy by itself.

This is the first choice for a small, closed set of backend variants. Prefer a tagged
union or callable interface when it can name those variants. Use `nupp.dynamic` only
when values really must survive in heterogeneous or untyped storage independently of
their defining module.

## Public surface

The standard library exposes one namespace:

```nupp
local dynamic = require("nupp.dynamic")

local store: dynamic.Store = dynamic.newStore()
local handle: dynamic.Handle<File> = store:put(file)

store:with(
    handle,
    scoped function(borrows current: File): nil
        inspect(current)
    end
)

local recovered: File? = store:take(handle)
```

The complete initial API is:

```nupp
global record dynamic.Handle<T>
    -- Opaque outside nupp.dynamic.
end

global type dynamic.Store = affine(dynamic.StoreState, dynamic.destroyStore)

global function dynamic.newStore(): dynamic.Store

global function dynamic.Store:put<T>(
    exclusive self,
    takes value: T
): dynamic.Handle<T>

global function dynamic.Store:with<T, R>(
    exclusive self,
    handle: dynamic.Handle<T>,
    scoped callback: function(borrows value: T): R
): (R?, dynamic.Error?)

global function dynamic.Store:withExclusive<T, R>(
    exclusive self,
    handle: dynamic.Handle<T>,
    scoped callback: function(exclusive value: T): R
): (R?, dynamic.Error?)

global function dynamic.Store:take<T>(
    exclusive self,
    handle: dynamic.Handle<T>
): (T?, dynamic.Error?)

global function dynamic.Store:remove<T>(
    exclusive self,
    handle: dynamic.Handle<T>
): dynamic.Error?

global function dynamic.erase<T>(
    handle: dynamic.Handle<T>
): dynamic.ErasedHandle

global function dynamic.recover<T>(
    handle: dynamic.ErasedHandle,
    expected: Type<T>
): (dynamic.Handle<T>?, dynamic.Error?)
```

`Handle<T>` is a copyable, opaque runtime token. It carries no cleanup obligation and
may cross `any` or untyped Lua because the store, not the handle, owns the value.
`ErasedHandle` is the only form that loses the static `T`; `recover` checks the stored
stable type key before restoring `Handle<T>`. A handle contains a store identity, slot
identity, generation, and type-policy key. Its fields are not user-readable or
constructible.

`put` is a checked ownership introduction into the store. `take` is the corresponding
checked introduction back into flow analysis: on success it moves the exact stored
capability into the result, clears the slot, and increments the generation. It does
not use `preserves` because the source capability resides in a runtime store entry,
not in a source parameter. The intrinsic implementation proves the origin.

`with` and `withExclusive` never expose a value beyond a fresh scoped invocation.
They check store identity, generation, and type-policy key before calling the
callback. `remove` runs the stored cleanup and invalidates all copies of the handle.
Destroying the store attempts cleanup for every live slot, preserves the first
failure, and attaches later failures as suppressed errors.

## Admission rule

The store accepts only a self-contained capability:

- it contains no transfer-only obligation leaf;
- every cleanup obligation has an exact runtime-linkable function identity;
- every root or pin anchor is moved inside the same enrolled aggregate or is static;
- it carries no outstanding exclusive loan from a place outside the aggregate; and
- every foreign retention token has a cleanup path inside the aggregate.

A borrowed view by itself is therefore rejected. Code enrolls an owning aggregate
that contains both root and view, shortens the view to a scoped callback, or uses an
unsafe boundary. A transfer-only value is rejected because store destruction has no
legal terminal for it. These restrictions make `destroyStore` total over every live
entry rather than moving an unsolved proof into runtime metadata.

The canonical capability query from plan 047 answers admission. The dynamic module
does not recognize `Owned`, `Pinned`, resource names, methods, or wrapper spellings.

## Runtime entry and generation semantics

Each occupied slot stores:

```text
Entry {
    generation: uint64
    typeKey: StableTypePolicyKey
    representation: erased runtime value
    cleanup: none | stable cleanup declaration key | aggregate cleanup program
}
```

The type-policy key covers the canonical runtime representation, cleanup identities,
aggregate capability shape, and ABI-relevant native target. It does not contain the
source alias name. A slot generation increments on `take`, `remove`, failed reload
migration, and store teardown. Generation wrap is a checked fatal error rather than a
way to revive an old handle.

A stale handle never reaches the stored value. A type mismatch never invokes cleanup
through the requested type. Cleanup uses the policy recorded when the entry was put,
including after the defining module has reloaded.

The first implementation uses Lua tables behind the affine `Store`; no native object
or C ABI is required. A later compact representation must preserve the same keys,
error behavior, and cleanup order before replacing it.

## Untyped Lua boundary

Direct conversion of a nontrivial capability to `any` or an argument of a `.lua`
module reports `NUPP2611`. The diagnostic offers only sound fixes:

- keep the path checked and give the callee a typed contract;
- enclose the value in a checked affine wrapper;
- put it in a dynamic store and pass `dynamic.erase(handle)`; or
- enter `unsafe` and release the representation explicitly.

An untyped module receives only `ErasedHandle`. Checked code calls
`dynamic.recover(handle, File)` before accessing a `File` entry. Merely casting the token
or reconstructing its fields is rejected outside `unsafe`.

Reflection may describe a capability but may not return its live representation as
ordinary data. Reflective registries store erased handles. Opaque foreign storage may
store an encoded token only through a declared adapter that preserves all four handle
components and validates them on recovery.

## Hot reload

The watch host, not a reloaded module, owns any dynamic store that must survive a
patch. Plans [`036-hot-reload.md`](036-hot-reload.md) and
[`039-hardening-hot-reload.md`](039-hardening-hot-reload.md) continue to own patch
transactions, stable declaration identities, and external-input validation. This plan
adds capability entries to that transaction.

A patch computes the set of live type-policy keys in persistent stores:

- an unchanged key keeps its entries and handles valid;
- a cleanup-body change behind the same stable declaration key uses the hot-reload
  function slot while preserving policy identity;
- a representation, aggregate shape, or cleanup-identity change is incompatible while
  a matching live entry exists; and
- the patch is rejected before code installation unless the host first drains or
  explicitly removes those entries.

There is no automatic value migration in the first version. A future migration API
must be transactional, typed on both sides, and prove that the old obligation is
consumed exactly once before it can be added. Until then, rejecting the patch is safer
than guessing whether a Lua table happens to fit the new type.

Patch rollback restores the pre-patch store and generations byte-for-byte. Cleanup
does not run merely because a candidate patch was rejected.

## Existing HTTP migration

The baseline contains an important migration at `src/nupp/io/http.nupp`: `makeBody`
accepts `client: any` and `transfer: any`, then returns an affine body whose cleanup
casts and closes the transfer. Under the new rule, the inputs have already lost their
facts before the wrapper establishes its obligation.

Audit that path in this order:

1. replace `any` with a private tagged union or callable transport interface if the
   backend set is closed;
2. make the body constructor take the typed transport capability and move it directly
   into one affine `BodyState`; or
3. if a backend is genuinely untyped, adopt it once in the backend adapter and enroll
   the resulting self-contained body state in a dynamic store.

Do not hide the current cast behind a new helper and call it migration. Add a fixture
that proves response-body cleanup on success, early close, read failure, cancellation,
and client teardown before removing the old path.

The implementation inventory also records every nontrivial value passed to `any`,
every `.lua` call boundary, reflection registry, hot-reload state slot, and opaque C
storage location. Ordinary `any` uses are excluded from the migration count.

## Unsafe boundary

`unsafe release value` consumes a capability and yields its raw representation without
running cleanup. `unsafe adopt raw as T` asserts one fresh capability origin. They stay
available for adapters whose external system already supplies identity, generation,
and cleanup guarantees.

Unsafe release/adoption does not create a `Handle`, does not participate in store
teardown, and does not gain hot-reload compatibility. Documentation must present it as
the manual-proof alternative, not the faster spelling of dynamic storage.

## Diagnostics and runtime errors

Reserve the next ownership-family codes after plan 047:

| Code | Failure class |
| --- | --- |
| `NUPP2611` | implicit erasure of a nontrivial capability |
| `NUPP2612` | dynamic enrollment is not self-contained |
| `NUPP2613` | a typed handle or recovery request has the wrong type-policy key |
| `NUPP2614` | a dynamic handle is stale or names a destroyed store |

`NUPP2611` and `NUPP2612` are checker diagnostics. `NUPP2613` may be reported
statically when typed handles disagree and is otherwise a structured `dynamic.Error`.
`NUPP2614` is necessarily a runtime `dynamic.Error`; it still has a stable code,
`nupp explain` entry, generated reference entry, and `docs/diagnostics.md` row so the
same failure has one searchable identity in logs and tools.

Every error relates the put site when available, the invalidating take/remove/reload
operation, and the attempted recovery. Errors never print raw stored values or opaque
handle bits.

## Implementation order

### D0 — Inventory and API spike

- Verify that `NUPP2611` through `NUPP2614` are unallocated.
- Inventory real capability-erasing boundaries and classify checked-wrapper versus
  dynamic-store migrations.
- Spike the Store/Handle API against HTTP and persistent hot-reload state before
  freezing syntax.
- Record direct-call, store-operation, reload, memory, and cleanup baselines.

### D1 — Erasure diagnostic

- Teach the canonical capability query to answer whether conversion loses a fact.
- Report `NUPP2611` at `any`, `.lua`, reflection, and foreign-storage boundaries.
- Exempt only ordinary values, checked affine wrappers, and the explicit operations in
  this plan.
- Land explain entries, fixes, related locations, and documentation with the code.

### D2 — Store and typed handles

- Implement affine `Store`, opaque `Handle<T>`, entries, generations, and policy keys.
- Implement `put`, scoped access, `take`, `remove`, and store teardown.
- Enforce self-contained admission and aggregate cleanup.
- Prove direct checked code generation remains byte-identical.

### D3 — Erased handles and untyped adapters

- Implement `ErasedHandle`, `erase`, and checked `recover`.
- Add `.lua`, reflection, and foreign-adapter fixtures.
- Reject token forging and mismatched type-policy recovery.

### D4 — Hot-reload transaction

- Add live policy-key inventory to patch validation.
- Preserve entries across compatible function-body changes.
- Reject incompatible live representation or policy changes before installation.
- Prove rollback does not mutate generations or run cleanup.

### D5 — Repository migration

- Migrate the HTTP body path and every other nontrivial dynamic escape from D0.
- Prefer typed wrappers and unions; use stores only for genuinely heterogeneous
  persistence.
- Delete temporary exemptions immediately after their final caller moves.

### D6 — Documentation and gates

- Update the language reference, ownership guide, dynamic module docs, hot-reload
  guarantees, diagnostics, and unsafe guidance.
- Run the full suite, fixpoint, bootstrap comparison, hot-reload transaction tests,
  leak checks, and performance gates.

## Verification matrix

Tests must prove:

- ordinary values still cross `any` and `.lua` unchanged;
- every nontrivial direct erasure receives `NUPP2611`;
- transfer-only, externally rooted, and outstanding-exclusive values are rejected by
  store admission;
- putting a value moves its obligation into exactly one live entry;
- taking moves it back exactly once and invalidates every handle copy;
- removing or destroying a store runs cleanup exactly once;
- scoped shared and exclusive callbacks cannot leak the stored value;
- wrong-type and stale recovery fail before dereference;
- generation wrap cannot revive a handle;
- compatible reload retains entries and incompatible reload is transactional;
- rejected and rolled-back patches run no cleanup and preserve generations;
- the HTTP body closes exactly once on every success and failure path;
- unsafe release/adopt stays explicit and receives no store guarantees; and
- direct checked code receives no handle, generation, registry, or branch overhead.

Benchmark `put`, `with`, `take`, and `remove` separately, plus ten thousand mixed live
entries and a compatible reload. Checker benchmarks measure the erasure query on an
unchanged warm build and project-wide invalidation. No direct checked benchmark may
regress; dynamic operations receive explicit published baselines rather than being
compared to zero-cost checked transport.

## Completion criteria

This plan is complete when:

- no nontrivial capability enters an untyped or heterogeneous boundary implicitly;
- the checked-wrapper option covers closed dynamic representations without a store;
- `nupp.dynamic` has the exact typed, erased, generation, and teardown semantics above;
- store admission accepts only self-contained, droppable capabilities;
- hot reload rejects incompatible live entries transactionally;
- the HTTP body and every inventoried boundary has a reviewed migration;
- `NUPP2611` through `NUPP2614` have explain and documentation coverage;
- direct checked representation and performance remain unchanged; and
- the full suite, fixpoint, bootstrap, leak, transaction, and performance gates pass.
