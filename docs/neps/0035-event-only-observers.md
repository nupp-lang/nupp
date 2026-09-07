---
title: Event-only observers
status: Implemented
created: 2026-09-07
---

## Summary

An observer of `nupp.events` receives only its borrowed event. The source still
owns registrations and reusable event storage, but delivery does not also hand
that source to every callback. An observer reaches other state through an
ordinary capture or through a field the event explicitly carries.

This replaces the source-bearing observer contract in [NEP
33](0033-typed-events.md). Its event declarations, addressed registration,
reusable storage, and synchronous delivery remain unchanged.

## Goals

- Make the event payload the complete universal observer contract.
- Let each observer or event explicitly choose the state and authority it needs.
- Avoid granting every observer every operation exposed by a concrete source.
- Keep source-owned registrations, allocators, nested delivery, and allocation
  behavior unchanged.

## Non-goals

- Preventing a callback from using state it already holds through a capture.
- Defining a restricted world or application command capability.
- Changing event identity, addressing, storage, or delivery order.

## Motivation

The original observer type passed the source exclusively so a Tecs observer
could mutate the `World` that emitted an event. That makes one particular
consumer's context part of every event callback. It also grants the whole
concrete source API: an observer needing to stage a despawn receives unrelated
publication, snapshot, scheduler, and maintenance operations as well.

Neither event routing nor reusable storage needs that authority. A callback can
capture stable ambient state. When an event deliberately conveys context, an
ordinary record event can carry the world or a narrower capability as one of
its fields. Both choices make the dependency visible where it is used instead
of installing it in every observer invocation.

## Overview and specification

The observer contract has one parameter:

```nupp
type Observer<E> = function(borrows event: E): nil
```

Registration remains source-owned:

```nupp
function observe<A, S is Source<A>, E is Emittable>(
    exclusive source: S,
    address: A,
    event: Type<E>,
    callback: Observer<E>,
    id: string?
): nil
```

The dispatcher invokes `callback(event)`. It does not pass `source` as a
trailing argument. A zero-parameter callable still fits by ordinary callable
subtyping, while a callback declaring a second required parameter is refused.

An observer needing stable surrounding state captures it:

```nupp
local log = game.log
bus:observe(entity, Damage, |event| -> log:write(event.amount))
```

An event for which the world is part of the operation carries it explicitly:

```nupp
@derive(events.Event)
local record DespawnRequested
    world: World
    entity: integer
end

bus:observe(0, DespawnRequested, |event| -> event.world:despawn(event.entity))
```

`Source<A>` continues to mean an object with `Observers<A>` state. It is the
receiver of registration, delivery, and allocator operations, not an implicit
observer argument.

The generated Lua call changes from:

```lua
callback(event, source)
```

to:

```lua
callback(event)
```

No envelope, context record, or adapter closure is introduced.

## Risks and assumptions

- A consumer that previously used the callback source must capture its context
  or add it to an event contract.
- Capturing state can allocate a closure where a shared named callback did not.
  Callers sensitive to that cost can share a callback and carry context in the
  event.
- Carrying a full object in an event deliberately exposes its full API. A
  narrower event field is the way to grant less authority.

## Alternatives considered

**Pass a narrowed source interface.** This still makes application context a
universal part of an event abstraction and requires the source to choose one
authority surface for otherwise unrelated observers.

**Keep the source argument and rely on callbacks to ignore it.** Ignoring a
trailing argument is convenient but does not remove it from the type or stop a
callback from accidentally depending on the concrete source.

**Pass a separate arbitrary context at registration.** A capture already has
that representation and lifetime in Lua. Adding another stored slot and generic
parameter duplicates the language facility.
