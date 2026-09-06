---
title: Typed keys and stores
status: Accepted
created: 2026-09-06
---

## Summary

`nupp.data` gains a typed heterogeneous bag: `Key<T>` is a phantom-typed
identity with an integer id and an optional name, and `Store` is a table that
reads and writes `T?` through one. A key's type argument is fixed at its
declaration, by an annotation or by the serde binding that will persist its
value, and nowhere else. Names are opaque strings registered once per runtime
state, so declaring a name twice raises rather than returning the earlier key,
and lookup by name returns `unknown` for the caller to cast. A named key
persists as its name, and a store whose keys carry bindings saves and loads
through serde. The whole facility is a few tables and one metatable, portable to every
backend, with no native provider, and the two phantom keys the standard library
already carries, serde's `MetadataKey<T>` and reflection's `ExtensionKey<T>`,
become this one.

## Goals

- A typed map from key to value where the checker rejects a wrong write and
  types a read, without the value type leaking as `any` at either end.
- One implementation of the phantom-key idiom, correct with respect to
  variance, that the standard library and applications share.
- Keys that are cheap to declare at module scope and cheap to index with:
  one table per key, one integer index per access.
- Names that tooling can list and look up, with no structure the runtime
  interprets.
- Persistence by name: a key reference and a store's contents can be written
  out and read back in another process that declares the same names.

## Non-goals

- Persistent ids. Ids are allocated in declaration order inside one runtime
  state, and nothing about them survives a process, a worker, or a save file.
  The name is the only stable identity a key has.
- Extensible key interfaces. An application that wants metadata beside a key
  keeps its own map from id to metadata.
- Same-name reuse across module reloads. A module that is required twice
  declares its keys twice, and the second declaration raises.
- Persisting an anonymous key, or a store holding values under keys that
  carry no binding. Both raise rather than dropping state.

## Motivation

A game world, a request context, or a settings bag wants to hold values of
many types under identities that are not strings, so that a reader gets the
type it stored and a writer cannot store the wrong one. The obvious Lua answer
is `{[string]: any}`, which types nothing. The obvious typed answer is a record
with one field per value, which cannot be extended by a module the record's
author has not seen.

The idiom that answers both is a key carrying a phantom type parameter: a
`Key<T>` whose runtime shape is an id, indexed into a store whose `__index` and
`__newindex` contracts are generic over that `T`. Nupp already holds this idiom
twice. The reflection layer's `ExtensionKey<T>` is one, producer-only, so
covariance is enough for it. Tecs's `tecs.data.Key<T>` is the other, read and
written through, and it is where the idiom goes wrong.

The problem is what the checker does with a type parameter that no member
mentions. A generic interface with members is compared structurally, and a
parameter absent from every member is absent from the comparison, so
`Key<number>` assigns to `Key<string>` and a store then accepts any write
through it. A generic interface with no members is compared by its arguments
instead, but covariantly, so `Key<number>` widens to `Key<number | string>` and
the same wrong write follows. Neither declaration is invariant, and a key that
is written through must be.

The fix is a member that mentions `T` in both positions: an optional function
field that is never present at runtime. Its presence in the declaration is what
makes the checker compare `T` invariantly; its absence from every instance is
what keeps the key a two-field table. That trick is easy to get wrong, hard to
notice going wrong, and worth doing once where a fixture holds it.

## Overview and specification

### Syntax

```nupp
--- A typed identity for one value in a Store.
interface nupp.data.Key<T>
    readonly id: integer
    readonly name: string?
    --- Never present. Mentions T in both positions so keys are invariant.
    readonly _valueType: (function(value: T?): T?)?
end

--- One row of inspectStore.
record nupp.data.StoreEntry
    id: integer
    name: string?
    valueType: string
end

--- An independent typed bag.
record nupp.data.Store
    private values: {[integer]: any}
    metamethod __index: function<T>(self, key: Key<T>): T?
    metamethod __newindex: function<T>(self, key: Key<T>, value: T?)
end

function nupp.data.newKey<T>(name: string?): Key<T>
function nupp.data.findKey(name: string): unknown
function nupp.data.listKeys(): {[string]: integer}
function nupp.data.newStore(): Store
function nupp.data.clearStore(store: Store): nil
function nupp.data.inspectStore(borrows store: Store): {StoreEntry}

--- Serde's side of the design. The store module does not depend on serde.
function nupp.data.serde.key<T>(name: string, binding: Binding<T>): Key<T>
function nupp.data.serde.saveStore(borrows store: Store): {[string]: any}
function nupp.data.serde.loadStore(exclusive store: Store, saved: {[string]: any}): nil
```

### Worked example

```nupp
local data = nupp.data

record Settings
    volume: number
    fullscreen: boolean
end

-- T comes from the annotation. Nothing else fixes it.
local settings: data.Key<Settings> = data.newKey("game.settings")
local frames: data.Key<integer> = data.newKey("game.frames")
local scratch: data.Key<string> = data.newKey(nil)

local world = data.newStore()
world[settings] = new Settings(volume = 0.5, fullscreen = false)
world[frames] = (world[frames] or 0) + 1
world[scratch] = "temporary"
world[scratch] = nil -- removes the entry

local current = world[settings] -- Settings?
if current ~= nil then
    print(current.volume)
end

-- Rejected by the checker:
-- world[frames] = "one"                   NUPP2006, Key<integer> is not Key<string | integer>
-- local wide: data.Key<number> = frames    NUPP2001, Key<integer> is not Key<number>
-- frames.id = 4                            NUPP2009, id is read-only

-- Tooling reaches a key by name and states the type itself.
local found = data.findKey("game.frames") as data.Key<integer>
print(world[found])

for _, row in ipairs(data.inspectStore(world)) do
    print(row.id, row.name or "anonymous", row.valueType)
end
```

### Rules

**Type argument.** `newKey` has no witness parameter. `T` appears only in the
result, so the checker takes it from the annotated target of the declaration.
An unannotated `local k = newKey("x")` resolves to `Key<any>`, which is gradual
by the ordinary rule for `any`; the annotation is what makes a key typed, and
the documentation says so.

**Invariance.** `Key<T>` is invariant in `T` through `_valueType`. The field is
declared optional and never assigned, so a key is `{id = n, name = s}` at
runtime. A store's read is `T?` and its write accepts `T?`, with `nil` removing
the entry. `false`, zero, the empty string, and reference identity pass through
unchanged, because the store stores what it was given.

**Names.** A name is an opaque string. The runtime does not parse it, split it,
or reserve any spelling, and no convention about dots or prefixes lives here.
The empty string is rejected. A name already registered is rejected, and both
rejections raise before an id is consumed. Anonymous keys are always fresh and
are retained by nothing but their holders. Named keys are retained for the
runtime state's lifetime.

**Ids.** Ids are allocated from 1 in declaration order, shared by named and
anonymous keys, and never reused. They identify a key inside one runtime state
only: a worker has its own registry and its own counter, and a save file must
never carry one.

**Lookup.** `findKey` returns the registered key or `nil`, typed `unknown`. The
caller casts to `Key<T>` and owns that claim; the registry knows the name's id
and nothing about its type. `listKeys` returns a fresh table from name to id.

**Stores.** `newStore` creates an independent bag; two stores share keys and
nothing else. `clearStore` drops every value and touches no registration.
`inspectStore` returns fresh `StoreEntry` rows sorted by id, one per occupied
key, with `name` nil for an anonymous key and `valueType` the Lua type name of
the value. It never returns the values, so a tool can list a store without
holding what is in it.

### Persistence

A named key's wire form is its name. `serde.key` declares a key whose value
type comes from a `Binding<T>` rather than an annotation, registers the name as
`newKey` would, and retains the binding in a serde-owned table keyed by id.
Because a binding is a properly typed value, the type argument is inferred
from it without the failure the literal witness had, and the key is still
invariant.

```nupp
const serde = nupp.data.serde

@derive(nupp.derive.Serde)
record Settings
    volume: number
end

local settings = serde.key("game.settings", serde.of(Settings)) -- Key<Settings>

local world = nupp.data.newStore()
world[settings] = new Settings(volume = 0.5)
local saved = serde.saveStore(world) -- {["game.settings"] = {volume = 0.5}}

local restored = nupp.data.newStore()
serde.loadStore(restored, saved)
```

`saveStore` walks the occupied keys and encodes each value through its
binding into a plain value under the key's name. An occupied anonymous key, or
one declared without a binding, raises naming the key: a save that silently
drops state is worse than one that fails. `loadStore` looks each name up,
raises for one that is not registered, decodes the value through that key's
binding, and writes the store. The plain values are what `serde.json` and the
other codecs already encode, so a store rides inside whatever document the
application writes.

A `Key<T>` field inside a derived record encodes as its name and decodes by
lookup, the field's declared type being the claim. That needs serde to treat
one nominal interface as a string on the wire, in the way `timestamp` is a
scalar with a representation, and it is the last thing to land.

### The existing copies

Serde's `MetadataKey<T>` becomes an alias of `Key<T>`, `metadataKey` becomes
an anonymous `newKey`, and the metadata a schema or member carries becomes a
`Store` indexed by the key, which is what `schema:metadata(key)` was already
doing by hand with a slot. Reflection's `ExtensionKey<T>` is a `Key<T>` whose
provider lives in a side table under the key's id, and a host's cache is
indexed by that id. Neither changes its public surface: the names stay, the
constructors keep their signatures, and only the leniency goes. The prelude
declares `ExtensionKey<T>` before any module is loaded, so it is declared
there with the same members as `Key<T>` and is the same shape rather than a
reference to it.

### Lowering

The interface erases. A key is a plain table with two fields. A store is a
table carrying a `values` table under a metatable whose `__index` and
`__newindex` are the two generic functions, so `store[key]` is one metamethod
call and one integer index:

```lua
Store.__index = function(self, key)
    return self.values[key.id]
end
Store.__newindex = function(self, key, value)
    self.values[key.id] = value
end
```

Because a key is never a raw field of the store table, every access through a
key reaches the metamethods, and the `values` field is the only raw one.

### Where it lives

The implementation is one internal module beside the bitset,
`nupp.data.internal.store`, and `nupp.data` re-exports the types and
functions, following the pattern the [standard library
page](../learn/runtime/data/standard-library.md) describes. It uses tables,
integers, and one metatable, so it is portable with no native feature to
select and no provider to conform. Nothing in it is newer than the pinned stage
zero.

### What lands

- The module, its exports, and a documentation section covering declaration,
  typed indexing, the cast after lookup, registry lifetime, and inspection.
- Runtime tests: sequential ids, empty and duplicate names raising without
  consuming an id, lookup identity, missing names, detached listings,
  independent stores, `nil` removal, preservation of `false` and zero,
  clearing, and inspection order and shape.
- Checker fixtures: inferred construction from an annotation and from a
  binding, cross-module keys, the wrong write, the wrong read, widening and narrowing between key
  types, the read-only fields, the required cast after lookup, and the
  unannotated key resolving to `Key<any>`.
- `MetadataKey` and `ExtensionKey` on the new key, with a fixture holding
  each to the narrowing and widening rejections.
- Serde's `key`, `saveStore`, and `loadStore`, with tests for round trips,
  the anonymous and unbound rejections, and the unregistered name on load.
  The `Key<T>` field representation follows separately.
- Tecs then replaces `tecs.data` and `tecs.internal.store` with direct use,
  keeps its key strings and its `#<id>` rendering for anonymous rows in tooling,
  and replaces its same-name reuse test with duplicate rejection.

## Risks and assumptions

- **The invariance trick depends on structural comparison of members.** If the
  checker ever compares a generic interface's arguments directly, the field
  becomes redundant. It stays harmless, since it is optional and absent, and
  the fixture that pins widening and narrowing is what notices either way.
- **An unannotated key is gradual.** `Key<any>` accepts anything and is what a
  forgotten annotation produces. This is the language's rule for `any`, not a
  hole this design opens, but it is the one place a user can lose the typing
  without a diagnostic. A lint on a generic call whose parameter resolves to
  `any` would close it and is out of scope here.
- **Module reload raises.** A named key declared at module scope is declared
  again when the module is required again, and the second declaration is a
  duplicate. Nothing in the tree reloads a module; a host that does must find
  the existing key first.
- **Registries are per runtime state.** A key made on one worker means nothing
  on another. The rule is stated rather than enforced.
- **A loaded value is trusted to the key's type.** `loadStore` decodes through
  the binding registered under the name, so the value is checked against that
  schema, but which type a name means is whatever this process declared. A
  save written under one meaning of a name and loaded under another is the
  binding's decode failure, not a silent mismatch.

## Alternatives considered

**Leave it in Tecs.** The idiom is already in the tree three times, and two of
the copies are lenient today: `Key<number>` assigns to `Key<string>` in Tecs
and its store takes any write through the result, and `MetadataKey<string>`
assigns to `MetadataKey<integer>` in serde. The variance fix belongs where a fixture in
the compiler's own suite holds it.

**An inference witness parameter**, `newKey<T>(name: string?, borrows forType:
T?)`, so a caller may write `newKey("speed", 0)` and get `Key<number>`. With an
invariant key this infers from the argument, not the target: `newKey("x", nil)`
is `Key<nil>` and `newKey("x", 0)` is `Key<0>`, and every write through either
is then rejected. Every existing declaration in Tecs is written with an
annotation and a `nil` witness, so the parameter costs exactly the case it was
meant to help.

**Same-name reuse**, where a second `newKey` with a registered name returns the
first key. This hides a double registration behind a type claim nobody checks,
and its stated purpose, surviving module reload, has no caller. `findKey` plus
a visible cast is the same capability with the claim in the open.

**Extensible key interfaces**, an application declaring `WorldKey<T> is
Key<T>` with a domain marker and its own metadata. Lookup by name can only
return the core key, so each domain needs its own registry regardless, and a
core key and its extended view are then two tables with one id, which breaks
identity comparison. Keeping metadata in an application map keyed by id gives
the same result with one registry.

**An empty interface**, relying on argument comparison for distinctness. That
comparison is covariant, which is right for a producer-only key such as
`ExtensionKey` and wrong for one that is written through, and the key needs its
`id` and `name` members anyway.

**A `Type<T>` witness**, passing a record's declaration to fix `T`. Primitive
value types have no such witness, so the annotation is needed regardless.

**A typed lookup**, `findKey<T>(name): Key<T>?`. This is the same unverified
claim as the cast, presented as if the registry had checked it. `unknown` makes
the claim the caller's and visible at the call site.

**A string-keyed store**, `{[string]: any}`. That is what this design replaces.

**Persisting the id.** Ids depend on declaration order, which depends on
module load order, so a save would break on any change to what a program
requires. The name is the identity the program chose, so it is the one that
persists.

**A binding on every key**, making `newKey` take one. Most keys hold state
that is never saved, and a binding for a value type such as a native handle
does not exist. Two constructors keep the store module free of serde and make
the persistable keys visible at their declaration.
