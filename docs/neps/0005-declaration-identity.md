---
title: Declaration identity, prototypes, and metatables
status: Implemented
created: 2026-08-19
---

## Summary

`is` answers one question per kind of declaration, and which question is decided
by the kind rather than by a clause in the body: a record is nominal, an
interface is a contract, a struct is its ctype. A declaration's own runtime table
is not an instance of itself and has its own type. A contract declared for an
operator is checked against the value that fulfils it.

[Interfaces](../type-system/interfaces.md),
[refinements](../type-system/refinements.md),
[metamethods](../concepts/metamethods.md), and
[reflection](../concepts/reflection.md) document the surface.

## Goals

- Make `is R` recognise every instance of `R`, including one built by a
  constructor that links back rather than stamping directly.
- Make `is I` work for interfaces on both table and struct implementors, without
  closed-world enumeration.
- Remove the case where `is R` meant different things for two records depending
  on whether one of them wrote a refinement.
- Let a declaration's table say what it is, so the table and its instances stop
  being interchangeable.
- Check the value that fulfils a declared metamethod contract.

## Non-goals

- Runtime type information beyond what a declaration already emits.
- Closed-world enumeration of an interface's implementors. Separate compilation
  forbids it: another module may declare one this unit never saw.
- `is` on foreign cdata. A pointer from an FFI call has no metatype, and reading
  a marker off it raises rather than answering.
- Record-to-record inheritance. Records inherit contracts from interfaces only,
  which is what keeps the nominal test flat.
- Checking computed metatables. `setmetatable(t, buildIt())` stays gradual.
- Requiring a declared contract to be installed. A declaration states a protocol;
  when it is fulfilled is the program's business.

## Motivation

### One operator was answering two questions

`is R` meant "came from `R`" for most records and "matches this predicate" for a
record that wrote a `where` refinement. Two answers to one question, selected by
a clause a reader might not have seen, is the defect that made everything else
here necessary.

Worse, the two could disagree. An interface with a hand-written predicate could
contradict an implementor's declared conformance, and nothing caught it: the
checker would prove `Circle is Shape` from the declaration while the runtime
predicate answered false.

### The prototype idiom did not answer

A constructor that links back rather than stamping directly —

```lua
setmetatable({eventId = id}, {__index = event})
```

— produces a genuine instance whose metatable is not the declaration. `is`
answered false for it. This is the oldest way to write a class in Lua and the
shape a real consumer used.

### A contract nothing enforces is not a contract

A declaration could contract for an operator and nothing checked the value that
fulfilled it. Installing the correct function under the correct key on the
declaration's own table was *refused*, with the same message a typo would get,
so the diagnostic could not tell the two mistakes apart.

## Overview and specification

### The kind decides the question

A record's `is` asks provenance and is never overridden. An interface's asks
satisfaction. A struct's is `ffi.istype`, unchanged.

This follows a doctrine already stated in the checker — structural for shape,
nominal for provenance. What changed is that the doctrine is enforced by the
declaration rather than restated per type.

### Reachability is one step, not a walk

`record S is R` is already refused, so the nominal hierarchy is flat: there is
nothing to encode and nothing to walk. None of the machinery real languages
carry for this — Cohen displays, interval encoding, PQ-encoding, itables —
applies, because the problem those solve does not exist here.

What does exist is one prototype link, so the test reaches the declaration
through one `__index` step. One comparison for a directly stamped instance, two
for a prototype instance. Deeper user-made chains are out of scope, and there is
no cycle hazard because there is no loop.

### Refinements are interface-only

An interface has no nominal identity for a derived or written test to collide
with. A record and a struct already answer exactly, so a second test beside
either would be an answer chosen by a hidden rule — which is the defect being
removed.

The clause is spelled `satisfies` and is a function of the value, written in
either spelling a function takes anywhere else.

### A declaration's table is not an instance

A record declaration binds its name twice: as a type, and as the value that is
its runtime table. Those bindings held the same type, so the table and the
instances it stamps were statically interchangeable, and `Foo is Foo` could only
be asked by casting through `any`.

The value binding now has its own type, distinct from an instance. This is one
line of behaviour; everything else in that work exists to keep it from breaking
the paths that legitimately reach a declaration's members — filling a declared
field on the table, calling a static, constructing through it.

**Divergence from the original design.** This was designed as `metatable<Foo>`,
reusing the type that already named "the thing `getmetatable` returns". It
shipped as `Type<Foo>`. `metatable<T>` remained what `setmetatable` takes, and
the two turned out to want different member rules — a declaration value exposes
what the declaration declares, which is not the same set as what a metatable
carries.

### Metatable literals are checked where the target type is known

For each `__` key in a metatable literal: a declared contract must be satisfied
with `self` specialized to the receiver; a runtime key with no contract gets its
LuaJIT-required shape checked; an unknown `__` spelling keeps its spelling fix;
and a literal `__index` table is checked field-by-field against the receiver's
members, allowing extras and ignoring omissions because late assignment is legal.

Installing a contract on a record's own table is legal, because that table *is*
the metatable its instances carry. A bounded generic receiver falls out of the
same rule with no new mechanism: a registrar checks its own body rather than
relying on its call sites.

### Default bodies are referenced, not copied

An interface may implement what it declares. The body is emitted once in the
interface's file and referenced by each implementor, because Nupp preserves line
counts and there is nowhere in the implementor's file to attribute a duplicate
to. That is also why the interface must be exported when an implementor lives in
another module.

Resolution is at compile time, so there is no chain, no indirection, and no
runtime lookup — which Java cannot do, because it resolves through the itable.

Two supertypes providing the same default is refused, and the record must define
it. `@override` is required in both directions: a member shadowing an inherited
default without it is an error, and an `@override` shadowing nothing is also an
error. That catches the two failures Java cannot — the misspelling that silently
defines a new method, and the interface that later adds a default which silently
shadows an implementor's method.

### Decoded data gets a word per step

A record asserts provenance and JSON gives shape, so casting decoded bytes to a
record asserts something the program does not have. Every downstream problem
follows from it, including the record refinement this design removes, which
existed only to paper over it.

```text
parse     ->  interface        the shape the bytes have
validate  ->  tag narrowing    which shape it actually is
adopt     ->  new Record{...}  provenance is created here, not asserted
```

Adoption is where a value stops being data that looks right and becomes a thing
this program made, and where the invariant is established.

## Risks and assumptions

- **One `__index` step is a guess about how deep people go.** It covers the
  prototype pattern and nothing in the corpus goes deeper. A chain would need a
  loop and a cycle guard for a case that has not appeared. If one does, this is
  the decision to revisit.
- **`Type<R>` exposes instance fields today.** It has to, because a real
  registrar fills a declared field on the table after declaration. Splitting
  "what lives on the table" from "what lives on an instance" would catch a nil
  read, but needs a way to say a field is filled later. That is a real question
  left open.
- **The flip was breaking with no deprecation path.** A registrar taking a
  declaration's table had to change its signature, and the old spelling stopped
  checking rather than warning. That was the right call for a pre-1.0 tree and
  would not be for a released one.
- **A declared contract that is never installed is legal.** It is a runtime
  failure waiting for the first operator use, and the checker knows which names
  the declaring module installed. It would have to be a lint rather than an
  error, and it does not exist yet.

## Alternatives considered

**Declared conformance markers.** Each declaration would register what it
implements — an interface emitting one identity table, keyed by the table rather
than the name, since a name is a spelling two modules can collide on and a table
is an identity they cannot. The test is one field read. Soundness comes free: a
value of a declared type cannot exist unless the module declaring it has loaded,
and loading it runs the registration, which is what makes an open world safe
here where enumeration would not be.

**It was designed, verified, and declined.** The mechanism works. The case it
serves shrank while the rest of this design was implemented: static elision
answers any subject whose type proves conformance, and a derived tag answers a
decoded value. What a marker adds is an *untagged* interface against a subject
whose type does not prove it — one case, paid for by every interface gaining a
runtime table and every declaration gaining a registration set. A tag, static
knowledge, or a `satisfies` block covers the rest, and the diagnostic names all
three where it fires. Paying runtime weight across the language to avoid writing
one of them is the worse trade.

The work also established what does *not* work for structs, which is worth
keeping: `getmetatable(cdata)` returns the string `"ffi"`, `debug.getmetatable`
gives a shared cdata metatable rather than the per-ctype one, and ctypes compare
equal under `==` but hash to different table slots, so a ctype-keyed registry
silently misses. Only routing through the metatype's `__index` works.

**Keeping `where` on records.** Rejected as the source of the ambiguity. The
migration for anyone typing decoded data as a record is to describe it with an
interface and adopt.

**A spelled form for the declaration value, such as `Foo::record`.** Rejected:
`::` is taken by goto labels, and the language could already name the concept.

**Making structs nominal-plus-refinement, symmetric with records.** Rejected. A
struct's runtime value is a ctype and `ffi.istype` answers exactly. The table
doubling as namespace and metatable is a record problem.

**Checking computed metatables.** Rejected as a non-goal rather than an
oversight: it would require tracking a table's shape through arbitrary
construction, and the gradual boundary is documented.

## FAQ

**Why can an interface answer `is` at all, if it has no runtime table?** Three
ways, in order: the subject's own type already settles it and the test compiles
away; the interface's literal-typed fields say what its tag is, which is what
lets a decoded table answer; or a `satisfies` declaration names the test. With
none of those, and against an alias, there is nothing to test and that is a
generation-time diagnostic.

**Why does elision trust the type rather than re-checking?** Because it is the
same trust the checker already extends when it lets a narrowed branch read
fields without a test. A value that reached a union through an undeserved cast
is answered by the cast, not by `is`.

**Can a struct implement any interface?** Only one whose every member is
C-representable. The interface space bifurcates as a result, which is worth
stating once rather than discovering per interface.

**Why is `@override` required in both directions?** Requiring it on a shadow
catches the misspelling that silently defines a new method. Requiring that it
shadow something catches the interface that later adds a default which would
silently shadow an implementor's method. Each direction catches a failure the
other does not.
