# Associated types

An interface may state a type it does not name. Whatever takes the contract
names it, and the name is reached through the value that answered it.

```nupp
local interface Reader
    associated type Item

    read: function(self): self.Item?
end

local record Lines is Reader
    associated type Item = string

    handle: LuaFile
end
```

`Lines.Item` is `string`. A function generic over readers reads it back through
the type parameter:

```nupp
local function collect<T is Reader>(source: T): {T.Item}
```

## Four declarations

Where the member is written, and which operator it uses, is the whole of what it
means.

| Where | Written | Means |
| --- | --- | --- |
| `interface` | associated type Item | a requirement |
| `interface` | associated type Item is Bound | …and what may answer it |
| `interface` | associated type Item = T | an overridable default |
| `interface` | associated type Item == T | a fixed equality |
| record/struct | associated type Item = T | an answer |

`==` is refused outside an interface, because a concrete declaration already
answers exactly with `=`. A requirement is refused inside one, because nothing
inherits from a record and nobody could answer it.

## Why a default and a fixed equality are different

A default is a fallback. An implementor may answer otherwise, so a value known
only as the interface **cannot** be said to answer it, so the projection stays
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
being edited, and `ScalarComponent<number>.Value` is provably `number`, even for
a value typed only as the interface.

## Answering one

```nupp
local record JSON is Codec
    associated type Encoded = string
    associated type Decoded = any
end
```

One answer satisfies every contract that asked for that name, and has to fit
every bound they gave. An explicit answer replaces an inherited default with no
`@override`, because a type member has no body to replace.

A default that survives is copied to the implementor, with `self` rebound there,
so `associated type Value = self` on the contract reads as the implementor:

```nupp
local interface Holds
    associated type Value = self
end

local record Node is Holds
    tag: string
end

local itself: Node = nil as Node.Value
```

Leaving a requirement unanswered is **NUPP2127**, as is answering otherwise than
a `==` fixes it, and as are two contracts defaulting it differently. None of
those leaves one answer to take. Answering a name no contract declares,
restating a bound, or stating a requirement outside an interface is
**NUPP2128**. Colliding with a nested alias or declaration is **NUPP2129**; a
field may still share the spelling, since fields and types are separate
namespaces.

## It is not a nested type alias

A declaration body may also hold a plain `type` alias, and the two are different
members:

```nupp
local interface Shape
    type Unit = number -- a static alias
    associated type Scale -- a requirement

    size: Unit
end
```

`Unit` is lexically scoped, reachable from outside as `Shape.Unit`, and **not
inherited**, so a declaration taking `Shape` cannot name it. `Scale` is the
opposite on every count. That is why they are spelled differently: sharing one
word would have made the meaning of every existing alias depend on whether its
declaration was ever inherited.

## Reaching one

Through a concrete declaration by path, through a type parameter, or through the
receiver:

```nupp
local text: Lines.Item = "a line"
local function collect<T is Reader>(source: T): {T.Item}
```

Inside an interface body the name is never bare. `self.Item` is required,
because what it stands for varies by implementor. In a declaration that answered
it, the bare name resolves, because answering it makes it an alias like any
other.

A projection that names nothing is **NUPP2134**: an unbounded binder has no
contract to project through, a bounded one may not state the name, and a union
states it only when every alternative does. A projection takes no type
arguments.

## Opaque projections

A projection whose head is a contract stays opaque, and that is a normal form
rather than a failure. It fits its effective bound, and reads that bound's
members, specialized to the projection, so a `self`-returning member answers
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

Through an **intersection** the requirements coalesce and their bounds
intersect, so one answer satisfies every contract. Through a **union** every
alternative has to state the name, the bounds unite, and the answers distribute:
`(A | B).Item` is `A.Item | B.Item` when both resolve.

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
the same reason.

## Runtime cost

Nothing. An associated type is erased exactly as a type parameter is, and an
interface that adds only associated types still emits nothing.

That has three consequences worth knowing:

- A **reified position**, meaning `nupp.sizeof`, `layoutof`, a struct field, or
  a fixed array, needs a representation, so a projection is legal there only
  once it resolves to a reifiable type. An opaque one is refused by the ordinary
  reification error. An array asks about its element and a pointer does not ask
  about its pointee, so an incomplete pointee is still fine.
- A **`matches` refinement** is a run-time test, so a contract that leaves an
  associated type unsettled cannot carry one, because an implementor may answer
  otherwise and the test cannot tell. Fixing every requirement settles it,
  including inherited ones. `associated type Item == any` is fixed and still
  settles nothing, because there is nothing for a test to check.
- A **cycle** is reported once per component, wherever it is entered from
  (**NUPP2135**). A cyclic default stays latent on the interface that states it
  and surfaces on the first concrete implementor.

## When inference does not reach the head

A projection whose head inference never worked out is checked as `any`, which is
the feature declining to say anything rather than saying the call is right. That
is reported by the `gradual-projection` lint (**NUPP2511**), once per call and
member, where the erasure happened:

```nupp
local erased = collect(nil as any) -- warning: gradual-projection
```

An answer somebody wrote as `any` is a different thing and does not warn.
Suppress the lint with `@allow("gradual-projection")` like any other.

## Why not a type parameter

`Reader<T>` says the same thing until you try to use it. A parameter is an input
the caller chooses, so nothing stops one declaration from taking
`Reader<string>` and `Reader<integer>` both, and `collect(source)` then has
nothing to infer `T` from. An associated type is an output the implementor
chooses, so it is a function of the argument and inference resolves it.

Parameters also propagate: every function that touches a reader carries the
parameter whether or not it mentions the element type. An associated type stays
where it was declared.

The rule is which side chooses. When the caller chooses, write a parameter.

## Diagnostics

- **NUPP2127**: a declaration does not answer an associated type it owes, or
  answers otherwise than a `==` fixes it, or two contracts default it
  differently.
- **NUPP2128**: an associated type member cannot mean anything where it is
  written. Answering a name no contract declares, restating a bound, or stating
  a requirement outside an interface.
- **NUPP2129**: an associated type collides with a nested alias or declaration.
- **NUPP2134**: a projection names something that cannot be projected.
- **NUPP2135**: an associated type answers through itself, reported once per
  component.
- **NUPP2511**: the `gradual-projection` lint, where inference did not reach a
  projection's head and it was erased to `any`.

## Next

- [interfaces.md](interfaces.md): the contracts that declare a requirement.
- [type-level-computation.md](type-level-computation.md): computing a type rather than answering with one.
