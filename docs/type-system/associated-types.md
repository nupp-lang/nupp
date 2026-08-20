# Associated types

An [interface](interfaces.md) may state a type it does not name. Whatever takes
the contract names it, and the name is reached through the value that answered
it.

```nupp:playground
local interface Reader
    associated type Item

    read: function(self): self.Item?
end

local record Lines is Reader
    associated type Item = string

    handle: LuaFile
end
```

`Lines.Item` is `string`. A function [generic](generics.md) over readers reads
it back through the type parameter:

```nupp
local function collect<T is Reader>(source: T): {T.Item}
```

## Declaration kinds

Where the member is written, and which operator it uses, is the whole of what
it means.

| Where | Written | Means |
| --- | --- | --- |
| `interface` | `associated type Item` | a requirement |
| `interface` | `associated type Item is Bound` | and what may answer it |
| `interface` | `associated type Item = T` | an overridable default |
| `interface` | `associated type Item == T` | a fixed equality |
| record or struct | `associated type Item = T` | an answer |

`==` is refused outside an interface, because a concrete declaration already
answers exactly with `=`. A requirement is refused inside one, because nothing
inherits from a [record](records.md) and nobody could answer it.

## Defaults and fixed equalities

A default is a fallback. An implementor may answer otherwise, so a value known
only as the interface cannot be said to answer it, and the projection stays
opaque there:

```nupp
local interface Holds
    associated type Value = string
end

local record Otherwise is Holds
    associated type Value = integer
end

local assumed: string = nil as Holds.Value -- refused: Holds.Value is opaque
local known: integer = nil as Otherwise.Value
```

A fixed equality is a promise the contract makes, so it resolves through the
contract, and every implementor answers exactly it:

```nupp
local interface Fixes
    associated type Value == string
end

local settled: string = nil as Fixes.Value -- resolves
```

That is the distinction the feature exists for. A base contract keeps an
overridable default while a derived one fixes it:

```nupp
local interface Component
    componentId: integer
    associated type Value = self
end

local interface ScalarComponent<E> is Component
    componentId: integer
    associated type Value == E
end
```

`Component` hands every implementor the answer "itself" without any of them
being edited, and `ScalarComponent<number>.Value` is provably `number`, even
for a value typed only as the interface.

## Answering a requirement

A record or struct answers by writing the name with `=`:

```nupp
local interface Codec
    associated type Encoded
    associated type Decoded
end

local record JSON is Codec
    associated type Encoded = string
    associated type Decoded = any
end
```

One answer satisfies every contract that asked for that name, and has to fit
every bound they gave. An explicit answer replaces an inherited default with no
`@override`, because a type member has no body to replace.

A default that survives is copied to the implementor, with `self` rebound
there, so `associated type Value = self` on the contract reads as the
implementor:

```nupp
local interface Holds
    associated type Value = self
end

local record Node is Holds
    tag: string
end

local itself: Node = nil as Node.Value
```

Leaving a requirement unanswered is `NUPP2127`, as is answering otherwise than
a `==` fixes it, and as are two contracts defaulting it differently. None of
those leaves one answer to take. Answering a name no contract declares,
restating a bound, or stating a requirement outside an interface is
`NUPP2128`. Colliding with a nested alias or declaration is `NUPP2129`; a field
may still carry the same name, since fields and types are separate namespaces.

## Associated types are not nested aliases

A declaration body may also hold a plain `type` alias, and the two are
different members:

```nupp
local interface Shape
    type Unit = number -- a static alias
    associated type Scale -- a requirement

    size: Unit
end
```

`Unit` is lexically scoped, reachable from outside as `Shape.Unit`, and not
inherited, so a declaration taking `Shape` cannot name it. `Scale` is the
opposite on every count.

::: deepdive
`associated type` is a separate word from a nested `type` alias because they
are different things. An alias is a static namespace member resolved where it
is written, and an associated type is a contract member answered per
implementor. Giving both one word would have changed the meaning of every
existing alias the moment its declaration was inherited.

The workaround this replaces was writing the value type as a parameter of the
bound, which produces no diagnostic and no information, because bounds are
checked at instantiation rather than solved.
:::

## Reaching an associated type

A projection reaches an answer through a concrete declaration by path, through
a type parameter, or through the receiver:

```nupp
local text: Lines.Item = "a line"
local function collect<T is Reader>(source: T): {T.Item}
```

Inside an interface body the name is never bare. `self.Item` is required,
because what it stands for varies by implementor. In a declaration that
answered it, the bare name resolves, because answering it makes it an alias
like any other.

A projection that names nothing is `NUPP2134`: an unbounded binder has no
contract to project through, a bounded one may not state the name, and a union
states it only when every alternative does. A projection takes no type
arguments.

## Opaque projections

A projection whose head is a contract stays opaque, and that is a normal form
rather than a failure. It fits its effective bound, and reads that bound's
members specialized to the projection, so a `self`-returning member answers
`T.Item`:

```nupp
local interface Cloneable
    clone: function(self): self
end

local interface Copies
    associated type Item is Cloneable
end

local function twice<T is Copies>(item: T.Item): T.Item
    return item:clone():clone()
end
```

The direction matters. `T.Item` fits `Cloneable`; `Cloneable` does not fit
`T.Item`, because an upper bound cannot manufacture the answer.

Through an [intersection](intersections.md) the requirements coalesce and their
bounds intersect, so one answer satisfies every contract. Through a
[union](unions.md) every alternative has to state the name, the bounds unite,
and the answers distribute: `(A | B).Item` is `A.Item | B.Item` when both
resolve.

## Structural values cannot answer

An interface carrying associated requirements is nominal at that part. Members
can still be satisfied by shape, but an answer is a type, nothing registers one
later, and a structural value has nowhere to put it:

```nupp
local interface Holder
    count: integer
    associated type Item
end

local lookalike: {
    count: integer
} = {count = 1}
local held: Holder = lookalike -- refused: it answers nothing
```

A declared `is` edge is trusted for members and still proves the answers, for
the same reason. See
[interfaces.md](interfaces.md#is-is-a-claim-not-a-proof) for what that edge
does and does not check.

## Runtime cost

An associated type is erased exactly as a type parameter is, and an interface
that adds only associated types emits nothing. That has three consequences
worth knowing.

### Reified positions need a resolved answer

A reified position, meaning `nupp.sizeof`, `layoutof`, a struct field, or a
fixed array, needs a representation, so a projection is legal there only once
it resolves to a reifiable type. An opaque one is refused by the ordinary
reification error. An array asks about its element and a pointer does not ask
about its pointee, so an incomplete pointee is still fine.

### Refinements need every requirement fixed

A [`matches` refinement](refinements.md) is a runtime test, so a contract that
leaves an associated type unsettled cannot carry one: an implementor may answer
otherwise and the test cannot tell. Fixing every requirement settles it,
including inherited ones. `associated type Item == any` is fixed and still
settles nothing, because there is nothing for a test to check.

### Cycles report once per component

A cycle is reported once per component, wherever it is entered from
(`NUPP2135`). A cyclic default stays latent on the interface that states it and
surfaces on the first concrete implementor.

## Gradual projections

A projection whose head inference never worked out is checked as `any`, which
is the feature declining to say anything rather than saying the call is right.
That is reported by the `gradual-projection` lint (`NUPP2511`), once per call
and member, where the erasure happened:

```nupp
local erased = collect(nil as any) -- warning: gradual-projection
```

An answer somebody wrote as `any` is a different thing and does not warn.
Suppress the lint with `@allow("gradual-projection")` like any other. See
[lints.md](../reference/lints.md#local-suppressions) for the suppression rules.

## Parameters are chosen by the caller

`Reader<T>` says the same thing until you try to use it. A parameter is an
input the caller chooses, so nothing stops one declaration from taking
`Reader<string>` and `Reader<integer>` both, and `collect(source)` then has
nothing to infer `T` from. An associated type is an output the implementor
chooses, so it is a function of the argument and inference resolves it.

Parameters also propagate: every function that touches a reader carries the
parameter whether or not it mentions the element type. An associated type stays
where it was declared.

The rule is which side chooses. When the caller chooses, write a parameter. See
[generics.md](generics.md#constraints-use-is) for how a bound is written.

## FAQ

### Is this the same as Rust's associated types?

The shape is the same: a contract states a name, an implementor answers it, and
callers project through a bound parameter. The answer lives in the declaration
itself rather than in a separate implementation block, so there is no coherence
question about which answer applies. `=` and `==` are the two things Rust
writes as a trait-level default and as an equality constraint in a `where`
clause.

### Should I write `=` or `==` on an interface?

Write `=` when an implementor may reasonably answer otherwise, and `==` when
every implementor has to answer exactly that. Only `==` lets a value typed as
the interface read the projection, which is what a caller holding the contract
rather than the concrete type needs. See [Defaults and fixed
equalities](#defaults-and-fixed-equalities).

### Why is my table literal refused where the interface is wanted?

An interface with an associated requirement is nominal at that part, and a
table literal has nowhere to record an answer. Declare a record with `is` and
answer the requirement there. See [Structural values cannot
answer](#structural-values-cannot-answer).

::: seealso
- [interfaces.md](interfaces.md) for the contract these members live on
- [generics.md](generics.md) for bounds and the inference that resolves a
  projection
- [refinements.md](refinements.md) for `matches` and what fixing a requirement
  buys it
- [lints.md](../reference/lints.md#local-suppressions) for suppressing
  `gradual-projection`
:::
