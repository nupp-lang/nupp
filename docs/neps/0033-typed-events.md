---
title: Typed events with reusable storage
status: Draft
created: 2026-09-06
---

## Summary

`nupp.events` is an addressed, synchronous event bus whose events are ordinary
`record` and `struct` declarations marked `@derive(events.Event)`. Emitting an
event by type constructs it into storage the bus already owns, and only when
something is observing; emitting an existing instance borrows it without
allocating. Observers receive the event as a call-scoped borrow they can mutate
but not keep, and the source that delivered it as an exclusive borrow.

The design needs four things the compiler does not have: an initializer split
out of every constructor, a comptime view of a declaration's construction
contract with parameter names and defaults, closure literals that adopt
parameter modes from the type they are checked against, and a derive recipe
capability that binds an event to its initializer. Those are decided here
alongside the library, because the library is not expressible without them.
The first consumer is Tecs, whose Nupp rewrite lost the pooled and arena-backed
events its Teal router had.

## Goals

- An event is a declaration, not a registration call: its fields, defaults,
  constructor and layout are the ones the language already checks.
- Emission by type is fully typed at the call site, including named arguments
  and defaults, and costs nothing when nobody is observing.
- Warmed emission of a scalar event to non-suspending observers performs no
  allocation the bus owns: no envelope, no closure, no vararg table, no fresh
  payload.
- Registering and clearing observers at entity churn rates allocates nothing
  in steady state, and an unobserved address costs nothing at all, so a world
  of millions of entities pays for the observers it has and not for the
  entities it could have.
- An observer may mutate the payload and may suspend, and cannot retain the
  payload or a view of it past its own return.
- A source that owns observers passes itself to them exclusively, without a
  second bus object whose borrow would overlap its own.
- Struct events keep their fixed layout on every backend that has physical
  storage, and are refused rather than degraded where none exists.
- Every storage and dispatch rule is a checker fixture or a runtime test
  before the dispatcher exists.

## Non-goals

- Cross-worker or cross-runtime transport. A bus is local to one Lua state;
  [NEP 18](0018-structured-worker-tasks.md) owns what crosses one.
- Running dispatch inside an `@aot` body. A kernel is `nosuspend` and calls no
  callbacks ([NEP 9](0009-ahead-of-time-compilation.md)), so delivery always
  runs in Lua and only a payload may reach a kernel.
- Constructor overloads on an event. One declaration has one construction
  contract in this version; the reason is in the specification.
- A static proof that emission does not allocate. A dispatcher calls
  callbacks it cannot see, which widens its effect summary to top
  ([effects.md](../learn/language/effects.md)), so the allocation claim is a
  measured gate rather than a `noalloc` region.
- A frame. Storage epochs end when a source is quiescent; an engine that wants
  a frame boundary owns an allocator and resets it.

## Motivation

Tecs's Teal router let a game declare an event record, write an `init`, and
emit by type. The world checked for observers first, took a table from a pool
or a row from a per-world FFI arena, ran `init` on it, delivered it, and gave
it back. Emission with no observer cost two hash lookups; emission with one
cost no allocation at all. The Nupp rewrite kept the addressing and lost the
rest: an event definition is now a callable that allocates an envelope record
around a payload its `construct` allocated, on every emit, whether or not
anyone is listening.

Putting that back as library code does not work, and the reasons are what
shape this proposal.

**A library cannot run a constructor against storage it already holds.**
`new T(...)` lowers to one generated function that allocates `self`, seeds
the field defaults, runs the body, and returns the instance. Nothing can call
the body on a pooled table or an arena row, so a pool has to reimplement
construction, which is how the Teal router came to generate an unrolled `init`
from field names as a string. Nupp's derives are deliberately not source
generation, so the initializer has to be something the compiler emits.

**A library cannot type the constructor's arguments.** `emit(address, Damage,
amount = 10, source = player)` needs the parameter list of `Damage`'s
construction, with names so the named arguments bind and with defaults so the
omitted ones fill. Comptime `nupp.types` answers fields, parameters of a
function type, and packs, but nothing about how a declaration is constructed,
and a computed pack carries types without names.

**A library cannot state the borrow it wants from an observer.** The contract
is "borrowed for the call": the observer may read and write the event and
must not store it. That is a `borrows` parameter, and a `borrows` parameter
is exactly what an observer written as `|event| -> ...` cannot have. A
short-function parameter takes a type and no mode, a function literal's modes
are inferred from its body and collapse to plain for anything that is not a
pointer, and callable subtyping requires modes to match exactly. So a slot
typed `function(borrows event: E)` refuses every closure a user would write,
and a slot typed `function(event: E)` lets the closure put `event` in a table
with no diagnostic. `scoped` is the one construct that admits borrowed
captures, and it is restricted to callbacks invoked during the call that
received them, which a stored observer by definition is not.

**Two `emit` overloads cannot be told apart for a struct.** The obvious
surface is one `emit` taking either `Type<E>` and arguments or an `E`
instance. A record's declaration witness is a distinct `Type<T>` and its
instances are not, so the overloads are disjoint. A struct's witness is the
bare nominal, so `emit(address, Contact)` and `emit(address, contact)` are
the same call to the checker and report `NUPP2126`.

**A source and its bus cannot both be borrowed.** Tecs observers take
`exclusive world: World`. If observer state lived in a `world.events` object
with its own exclusive `emit`, the dispatcher would hold `world.events` while
handing `world` to a callback, and a parent region overlaps every descendant
([NEP 4](0004-ownership.md)), so that is `NUPP2607` unconditionally. The
current Tecs world avoids it by keeping observer tables as its own fields and
dispatching from a `World` method, which is the shape a reusable
implementation has to keep.

## Overview and specification

### Syntax

```nupp
local events = require("nupp.events")

@derive(events.Event)
local record Damage
    amount: number
    source: integer
    kind: string = "physical"
end

@derive(events.Event)
@event(name = "tecs.physics.Contact")
local struct Contact
    entityA: double
    entityB: double
    impulse: float
end

local bus = events.newMessageBus<integer>()

bus:observe(enemy, Damage, |event, source| -> print(event.amount, event.kind), "log")
bus:observeOnce(enemy, Damage, |event| -> print(event.amount))

bus:emit(enemy, Damage, amount = 10, source = player)
bus:emit(enemy, Contact, a, b, 0.5)

local damage = new Damage(amount = 10, source = player)
bus:deliver(enemy, damage)
```

Emission by type and delivery of an instance are two names rather than one
overload, for the struct reason above. `deliver` borrows the instance, performs
no acquisition and no release, and is what a caller uses for an event it owns.

### The construction contract

Every record and struct has one construction contract: the parameters of its
single declared constructor, or its stored fields in declaration order when it
declares none. This proposal makes it visible at comptime as
`nupp.types.construction(T)`, a pack whose slots carry a type, a parameter
name, and the default literal if the slot has one.

A computed tail written `...: unpackof nupp.types.construction(E)` is then a
parameter list with names, so a call binds named arguments to it and fills an
omitted defaulted slot with the same literal `new` would have written, at the
call site, where every other default is already decided. That is one
extension to how a computed tail is checked and none to how it is lowered:
named arguments erase to positional Lua arguments as they do everywhere.

An event admits one contract because a computed tail is a parameter list as
soon as it reduces, and there is no way for it to be an overload set. A
declaration with several constructors is refused by the derive with the
reason; a game that wants two ways to build an event writes two events, which
a bus treats as two identities anyway.

### The initializer

Lowering of a declared constructor splits into two generated members. The
initializer takes the instance first and fills it; the constructor allocates
and calls the initializer. A record with no constructor keeps the inline
literal that `new` lowers to today and additionally gets an initializer that
assigns each contract slot to its field:

```lua
function Damage.__nuppInit1(self, amount, source, kind)
    self.amount = amount
    self.source = source
    self.kind = kind
    return self
end

function Damage.__nuppCtor1(amount, source, kind)
    return Damage.__nuppInit1(setmetatable({}, Damage), amount, source, kind)
end
```

An initializer receives defaults already filled by its caller, so it never
consults them. A struct's initializer writes fields of the cdata it is handed;
its constructor remains the ctype call. Completeness, effects, overload
selection over the contract, and every constructor diagnostic are unchanged,
because the body is the same body checked the same way. The initializer is
reachable only through a derive recipe; it is not a member a program can name.

Two things the initializer's contract refuses. A constructor whose body
transfers an affine owner into `self`, or lets `self` escape before the body
returns, cannot be run against reused storage, because the next lease would
find the owner already moved or the escaped reference already aliased. Both
are refused on an event declaration, by the derive, naming the field or the
escape.

### The derive

`events.Event` is a provider whose recipe claims the `events.Emittable`
interface and returns data and one member: the event's registered name, its
representation, and a binding of the declaration's initializer. The binding is
a new recipe argument, `nupp.derive.initializer()`, and a new versioned
capability beside `forward.v1`, since `forward.v1` can pass only the receiver,
an argument, the registry entry, a field, or a constant. The registry entry the
derive already writes for every derived type gains the initializer, so the
runtime reaches it through the type witness it was handed, for a record via
the witness table and for a struct via the metatype's index table, the same
route derived methods take today.

The runtime assigns each registered event an integer identity the first time
a bus, `events.id`, or the derive's own registration asks for it, from a
counter local to the Lua state. It is stable for the life of that state and
never persisted, which matches the rule extension slots already live under.
`@event(name = "...")` overrides the registered name; the default is the
declaration's qualified path. Tecs pins six ECS names and twenty-two platform
names as an external surface, which is why the override exists.

The derive admits a concrete record or a fixed-layout struct. A generic
declaration is refused, for the reason `NUPP2806` refuses one for JSON: type
parameters erase ([NEP 24](0024-const-monomorphization.md)), so every
specialization shares one runtime table and would share one event identity.

### Observers and their borrows

An observer's type is `function(borrows event: E, exclusive source: S)`. This
proposal adds one rule to closure checking: a function literal or short
function checked against an expected function type adopts, for each parameter
it leaves without a mode, the mode of the corresponding expected parameter.
The expected type already flows into a short function's parameter types; this
carries the modes with it. A parameter written with an explicit mode keeps
it, and the exact-mode subtyping rule is unchanged, so a closure whose body
does something the adopted mode forbids is refused where it is written rather
than where it is passed.

With `event` a `borrows` parameter, the checks that already exist do the rest:
storing it in a table is `NUPP2603`, returning it or assigning it outward is
`NUPP2608`, and a rooted view derived from it cannot leave the call. Mutation
is permitted because a shared borrow proves non-invalidation, not
non-mutation. An observer that takes one parameter fits, since a callable may
ignore trailing arguments.

`source` is exclusive because the observers Tecs writes mutate the world. The
dispatcher holds the source exclusively as its own parameter and forwards it,
which is the sequential forwarding the checker already admits; nothing else
borrows the source while a callback runs.

### Sources

```nupp
export interface Source<A>
    observers: events.Observers<A>
end

export function emit<S is Source<A>, A, E is Emittable>(
    exclusive source: S,
    address: A,
    event: Type<E>,
    ...: unpackof nupp.types.construction(E)
): nil
```

The reusable implementation is a set of functions generic over the source,
each taking it exclusively and reaching observer state through the
`observers` field. `MessageBus<A>` is a record with that field whose methods
forward to them; Tecs's `World` adds the field and the same forwarding
methods. There is no bus object beside the source to overlap it. The observer
table is an ordinary field, which is what lets the dispatcher read a callback
list from it and then pass the source on exclusively: a plain table field is
not a tracked region, and the fixture that proves the whole shape is the first
thing built.

Addresses are table keys compared by identity. Tecs supplies its packed
entity ids with their generation, so a recycled slot is a new address, and
zero is a Tecs convention for the world rather than anything the bus knows.

### Registrations

Observer state is a map from address to a map from event identity to one flat
array per pair, and nothing exists for an address or a pair until something
observes it. An entity nobody observes has no entry, which is what lets a
world of four million entities with a few thousand observed ones hold a few
thousand entries. Emission at an unobserved address is the source's
registration count, which short-circuits everything when it is zero, and then
two hash lookups that find nothing.

A registration is two slots of that flat array, the callback and its name or
`false`, interleaved, with the live count kept in slot zero rather than in the
array's length. There is no record per registration. The Teal router chose
this layout and the reason survives it: at a million registrations a record
each is on the order of a hundred megabytes where two slots each is on the
order of thirty, and the dispatch loop reads an array slot per observer
instead of a field of a table it had to fetch first. The count lives in slot
zero so that a removal can leave a hole to be swapped out later without the
length lying about how many observers a delivery should visit.

A removal during delivery and a consumed once registration are the same
operation: the callback slot is overwritten with a tombstone, a function that
does nothing. A nested or interleaved delivery that reaches the slot calls the
tombstone, which is how "cannot be invoked again" is guaranteed without a
flags array or a check in the loop. Compaction swaps tombstones out after the
outermost delivery leaves, in one pass over the arrays a removal touched.

The per-address maps, the per-pair arrays, and the deferred-compaction list
come from pools the source owns and go back to them when they empty. Under
entity churn an observer registered at spawn and cleared at despawn would
otherwise allocate two tables per entity per lifetime, which at the entity
counts above is the one steady-state allocation the bus itself would own. A
detached list is returned to its pool only after the last delivery holding it
has exited, since an in-flight loop is reading it.

### Storage

Storage is a general facility that events consume. `nupp.mem.pool` is a table
pool that clears on release and reserves a capacity; `nupp.mem.arena` is a
paged allocator over the `cstorage` capability whose pages never move and
whose reset rewinds every used page's cursor. Both are usable without the bus.
`nupp.events` is classified as requiring `cstorage`, so a backend with no
physical storage refuses the module at build time instead of substituting
table-backed structs: the browser and Wasm backends have it, `portable` does
not.

An allocator is `acquire` and `release` over one representation. A source
creates its defaults lazily, a pool per record event and an arena per struct
event; `setAllocator` installs a caller-owned one, whose lifetime the caller
guarantees. A lease is what `acquire` answers, and it is affine with `release`
as its terminal. Dispatch holds it in a `with` extent, so an initializer
failure, an observer failure, or a cancellation unwinding through a suspended
observer releases exactly once, through the same cleanup region as every
other terminal. The protected lowering that extent needs is a fixed-arity
protected call and not a closure per emission; that is one of the bytecode
gates below.

Reclaimed record storage is cleared before it is leased again; leased struct
storage is zero-filled the way a bare struct binding is. Nested emission of
the same type acquires distinct storage because a lease is not released until
its delivery leaves. A default arena rewinds when its source becomes
quiescent, meaning the outermost delivery has left; an explicit arena rewinds
when its owner says so, and a rewind, close, or replacement that would
invalidate a live lease raises before changing anything.

### Dispatch

Delivery is synchronous. An observer that suspends suspends the emission with
it, and storage stays leased until it returns or is cancelled. Observers run in
array order and see each other's mutations. A delivery reads the array length
on entry, so an observer added during it joins the next emission, including a
nested one. Removal during delivery tombstones the registrations it resolved
when it was asked for and compacts by swap after the outermost delivery
leaves; removal by callback tombstones every match, removal by name the first.
A once registration is tombstoned before its callback is invoked, so nothing
nested or interleaved reaches it again. Clearing an address or resetting the
source detaches its lists; a delivery holding a detached list finishes it, and
the list is recycled after the last such delivery exits. `reset` clears
registrations and nothing else.

A caller who wants to remove by callback keeps the value it registered. A
short function is a fresh object each time its expression runs, so an inline
literal is unremovable by identity, and the documentation says so.

### What lands, and in what order

The compiler half is the initializer split, `nupp.types.construction`, named
slots in computed tails, mode adoption in closure literals, and the
`initializer` recipe capability. The standard library is under the stage-zero
rule ([NEP 32](0032-fetched-stage-zero.md)), so `nupp.events` cannot use a
recipe capability the pinned compiler does not know. The compiler half ships
in one release, the pin moves, and `nupp.mem.pool`, `nupp.mem.arena` and
`nupp.events` land against it. Tecs pins Nupp by revision and migrates last.

The gates before the library lands are checker fixtures for every rule above,
written against the current fixture suites; runtime tests for every storage
and dispatch rule, including the historical Teal cases; a standalone fixture
reproducing the Teal router, pool and arena at the revision that deleted them,
measured five times interleaved against the new bus on the same machine; and
`nupp bc --check` plus a trace-IR count on the emission path, so no closure,
vararg table, or reflective lookup enters it unnoticed. Warmed LuaJIT at the
deliverable optimization level is the measured native path; the browser is
measured separately through the Wasm project harness.

## Risks and assumptions

- **Mode adoption changes what existing closures mean.** A literal passed
  today to a slot with a `borrows` parameter is refused, so no working program
  adopts a mode it did not have; the risk is a literal that was refused for a
  mode mismatch and is now checked under a stricter body rule, reporting a
  different diagnostic. That is the intended change.
- **Named slots in a computed tail bet that names belong to packs.** If a pack
  turns out to need to stay nameless, emission by type falls back to the
  derived static in the alternatives, which costs a generic member recipe.
- **A plain table field is assumed not to be a region.** The dispatcher shape
  depends on reading `source.observers` and then passing `source` exclusively.
  The current Tecs world does exactly this and checks, but the fixture is
  written before anything else in case a later ownership change closes it.
- **The initializer is a second entry to every constructor body.** Anything
  that reasons about a constructor as one whole, such as the refusal of `@aot`
  on one, has to see both.
- **Two releases is the honest cost.** A single worktree cannot land the
  library beside the compiler feature it uses.

## Alternatives considered

**Keep the current definition-object design and add pooling underneath.** The
envelope and the `construct` callback are the allocations; pooling the payload
still leaves construction outside the type system and the borrow of the
payload unstated. The Teal router already showed where that leads, with a
string-generated `init`.

**One `emit` overloaded on `Type<E>` versus an instance.** Reads well for
records and is ambiguous for every struct, because a struct's witness is its
nominal. Giving struct witnesses a real `Type<S>` would touch every
`Type<T>`-directed API that relies on the nominal unifying with the witness.
Two names cost nothing.

**A derived static, `Damage.emit(source, address, ...)`.** The derive knows
the contract and could declare the member with a closed signature, which
needs no pack changes. It fails on the source: the member has to be generic
over the address type and the source type, and the recipe language admits no
generic member. Making it admit one is as much compiler work as naming pack
slots, and buys less, since `nupp.types.construction` serves every other
construct-into API as well.

**Infer observer modes from the body.** Today's rule for function literals,
extended to short functions. It cannot express "borrowed for the call" for a
value that is not pointer-shaped, and it decides the mode after the body has
been checked as plain, which is the wrong order for refusing an escape.

**A `scoped` observer.** `scoped` is the contract for a callback consumed
during the call that receives it. An observer outlives its registration call
by construction, so the contract would have to be widened to stored callables,
which is a different and larger change than adopting a mode.

**A bus object owned by the source.** The natural library shape, and the one
that overlaps: exclusive `world.events` under exclusive `world` is
`NUPP2607`. Functions generic over a `Source<A>` interface keep one root.

**A frame-scoped arena owned by the engine, reset at a host boundary.** Once
observers cannot retain a payload, nothing can read one after the outermost
delivery leaves, so a rewind at quiescence retains exactly what a frame reset
would, minus the concept. An engine that wants a longer epoch installs an
explicit arena.

**A record per registration.** The shape the current Tecs world has, and the
easier one to read. It costs a table per observer, a field fetch per observer
in the dispatch loop, and a flags field or a side list to mark a removal in
flight, and none of that scales with entity count in a direction anyone
wants. The interleaved array is what the Teal router had settled on for the
same reasons.

**Observer tables allocated on demand and left to the collector.** Correct,
and free of bookkeeping, and it makes subscription churn the one thing the bus
allocates for in steady state. The pools cost a few lines and were already
there once.

**Assigning event ids at compile time.** Ids would then have to be stable
across incremental rebuilds and separate compilations, which is a wire
identity in disguise. A per-state counter assigned on first use is what the
runtime's other slot identities already do.
