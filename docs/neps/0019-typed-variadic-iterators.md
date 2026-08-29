---
title: Typed variadic iterators
status: Implemented
created: 2026-08-23
---

## Summary

Generic `for` expands a concrete computed result pack before it types the loop
bindings. Comptime may compare the hidden declaration family of two nominal
types with `nupp.types.sameNominal`, and a computed iterator result may mark a
slot `borrowed` or `exclusive`. Such a result borrows the iterator triple for
one execution of the loop body. All three facts erase: the generated Lua is the
generic loop the source already wrote.

## Goals

- Let a library derive any finite number of iterator results from its generic
  inputs without fixed-width overloads.
- Let a type function distinguish applications of nominal access terms without
  inspecting a declaration's name or exposing its identity.
- Keep a yielded view inside the iteration that produced it, including across
  `continue`, `break`, and other structured exits.
- Express a yielded writer as an exclusive borrow of the iterator state.
- Put the opt-in on the iterator's result contract, leaving every loop call site
  as ordinary generic `for`.
- Add no allocation, dispatch, check, or wrapper to the generated program.

## Non-goals

- An iterator, query, column-store, or entity-component-system library in the
  compiler.
- Hash-consing runtime descriptors, resolving columns, caching matches, or
  choosing a query's yielded granularity.
- Callback fusion, coroutine lowering, a dedicated `yield` form, automatic
  specialization, or monomorphization.
- Constructing nominal declarations or nominal applications from comptime.
- Inferring a heterogeneous table literal as a tuple.
- Proving that two independently yielded exclusive subregions of one iterator
  root are disjoint.

## Motivation

A library can already accept a heterogeneous pack and use comptime to derive a
callback's parameters, but the same signature used as an iterator did not carry
through to the loop body: generic `for` read only the function's written fixed
results and left a computed tail as `any`, so a library had to choose a
callback, publish fixed-width iterator overloads, or give up the result types.

The derivation also had no nominal discriminator: `nupp.types.arguments(T)`
could take `Read<Value>` apart, but an unrelated generic application with the
same number of arguments looked the same to the type function, and comparing
names would make aliases, private declarations, and refactors part of type
identity.

Finally, a view produced by an iterator is valid because Lua retains the
iterator function, invariant state, and control value while the loop runs, and
the checker did not attach that root to the loop binding. Marking the result
borrowed without carrying its provenance either rejected a useful iterator or
allowed the type to say more than the flow state could prove.

The useful abstraction is not specific to one data structure. Column stores,
zipped arrays, database rows, parser captures, image planes, foreign views,
chunk stores, and archetype queries all have the same shape: runtime access
terms determine a compile-time result sequence, and one iterator step exposes a
bounded group of those results.

## Overview and specification

### Syntax

No statement syntax is added. A type function uses the new nominal comparison
and the existing pack builder; `exclusive` is added to the builder's result-slot
modes:

```text
nupp.types.sameNominal(left, right)
nupp.types.pack(types, nil, {"borrowed", "exclusive"})

for first, second, third in iterator, state, control do
    -- ordinary generic-for body
end
```

### Nominal declaration comparison

`nupp.types.sameNominal(left, right)` takes two type handles and returns true
when both resolve to the same nominal declaration, ignoring their supplied type,
pack, and const arguments. Aliases and ownership wrappers are transparent, and a
structural type, or two different nominal declarations with identical members,
returns false.

The operation exposes only equality: it returns no declaration handle, name,
allocation identity, source node, or value from which another nominal type could
be constructed.

### Worked example

A column library can carry both the stored value and the already-declared view
type on an access term. Comptime selects that view; it never has to construct a
nominal application:

```nupp
local record Read<Value, View>
    column: integer
end

local record Write<Value, View>
    column: integer
end

local comptime function Views(Terms: typepack): typepack
    const terms = nupp.types.elements(Terms)
    const views = {}
    const modes = {}

    for index = 1, #terms do
        const term = terms[index]
        const arguments = nupp.types.arguments(term)
        if #arguments ~= 2 then
            return nupp.types.error("an access term needs a value and view type")
        end

        views[index] = arguments[2]
        if nupp.types.sameNominal(term, Write<any, any>) then
            modes[index] = "exclusive"
        elseif nupp.types.sameNominal(term, Read<any, any>) then
            modes[index] = "borrowed"
        else
            return nupp.types.error("an access term must be read or write")
        end
    end

    return nupp.types.pack(views, nil, modes)
end

local record Scan<Terms...>
    matches: function(): (integer, unpackof Views(Terms...))
end
```

For `Scan<(Write<Position, PositionWriter>,
Read<Velocity, VelocityReader>)>`, this loop binds all three names exactly:

```nupp
for count, positions, velocities in scan.matches do
    for row = 1, count do
        positions:set(row, positions:get(row) + velocities:get(row))
    end
end
```

The runtime library may hash-cons the access terms and scan descriptor, cache
the iterator closure on the scan, and resolve the columns once per yielded
chunk. None of those policies belong to the language feature.

### Generic-for result expansion

After the first iterator expression has been inferred and its enclosing generic
types have been instantiated, the checker expands the iterator function's
computed parameter and result packs. The expanded result pack types the loop
bindings in order, with a fixed result head before the computed tail.

An open pack which cannot yet reduce retains the gradual result it already
promised, and a closed computation which fails reports against the iterator
contract. Existing Lua adjustment for missing or surplus loop bindings is
unchanged.

### Iteration-scoped results

`borrowed` and `exclusive` in a computed iterator result pack both bind a
borrowed value. The latter additionally records an exclusive loan. The roots
are the evaluated iterator function, invariant state, and initial control
expressions; Lua retains that triple for the loop's duration, including when an
expression was a temporary with no source name.

The static loan begins at the loop binding and ends when that execution of the
body ends, so it ends on fallthrough, `continue`, `break`, `return`, and a
raised error. The result cannot be returned, assigned outside the body, or
retained by an escaping closure; a named iterator root cannot be moved while one
of its yielded results is live; and a shared use of that root conflicts with an
exclusive yielded result.

Every binding gets its own result type and mode, and the root is deliberately
coarse: a library that needs independently writable subregions must expose the
ordinary region proof establishing their disjointness rather than relying on
their positions in a result pack.

### Lowering

Nominal comparison runs only during comptime evaluation, and pack expansion and
borrow provenance exist only while checking. Generic `for` already retains its
protocol values and gives its locals one body scope, so no lifetime object,
guard, callback, closure, table, or dynamic check is emitted.

```nupp
for count, left, right in scan.matches do
    consume(count, left, right)
end
```

lowers as the same Lua generic loop:

```lua
for count, left, right in scan.matches do
   consume(count, left, right)
end
```

The performance contract is zero additional runtime cost relative to the
equivalent hand-written Lua iterator: the protocol still performs one ordinary
invocation per yielded item, and choosing a chunk rather than an element as that
item is a library decision.

## Risks and assumptions

- The iterator triple is one conservative root. An exclusive result can block a
  shared use which a library knows touches another subregion until that library
  supplies a region proof.
- `sameNominal` makes declaration-family equality observable to comptime, so the
  equality token must remain sealed and absent from stable reflection output and
  cannot become a name, serialization key, or nominal constructor.
- A bodyless iterator declaration is trusted to uphold its borrowed-result
  contract, as bodyless function ownership and effect declarations already are.
- A library still controls iterator allocation: storing one closure when a scan
  is created is zero allocation per traversal step, while constructing a closure
  in a hot loop remains the library's cost and is visible to the existing
  bytecode checks.

## Alternatives considered

**Callbacks with computed parameter packs.** Already type correctly and can be
fast, but force control flow through a callback and cannot give the caller
ordinary nested-loop `break` and `continue`.

**Fixed-width iterator overloads.** Keep generic `for`, at the cost of an
arbitrary maximum, duplicated declarations, and worse diagnostics at the
boundary.

**A compiler-recognized query or column construct.** Could infer the same
bindings for one library and would leave every other variadic iterator with the
original problem.

**Expose a nominal declaration handle.** Makes application-head inspection
direct, but grants more identity surface than the use case needs and invites
serialization and nominal-construction pressure, where a sealed equality
predicate is enough.

**Compare reflected names or complete fingerprints.** Names are not identities,
and complete application fingerprints differ precisely when two applications
of one declaration carry different arguments.

**Treat yielded views as ordinary values.** Avoids ownership work and permits a
view to outlive the iterator state which makes it valid.

**Fuse the loop body into the iterator.** Can remove an iterator boundary per
item, but changes control flow, debugging, and compilation strategy, and is not
needed when an iterator yields a whole chunk and the hot inner loop remains a
plain numeric loop.
