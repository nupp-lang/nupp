---
order: 280
---

# Property capabilities

Properties and indexers declared `readonly` or `writeonly` grant read and write
access independently. A type then describes the authority an API needs instead
of turning every member into a read-write slot.

```nupp:playground
local interface Snapshot
    readonly value: string
end

local interface Output
    writeonly value: string
end
```

A `Snapshot` can read `value` but cannot assign it. An `Output` can assign the
member but cannot observe its current value. See
[Interfaces](interfaces.md) for the rest of what an interface declares.

## Declaring a capability

The same syntax works in a [record](records-and-structs.md#records):

```nupp
local record Cell
    readonly value: string
    writeonly value: string | integer
end
```

It works in a structural shape too, which is how a caller states the authority
it needs without naming the declaration that supplies it:

```nupp
local input: {
    readonly value: string
} = Cell{value = "ready"}
local output: {
    writeonly value: string | integer
} = Cell{value = "ready"}
```

The two declarations name one runtime property. They may use different types:
here a write accepts `string | integer`, while every read produces `string`.
Construction may initialize a read-only record field, because the capability
governs access through the constructed view rather than creation of the value.

An unmodified property is shorthand for matching read and write capabilities,
so `Ordinary` and `Expanded` describe the same authority:

```nupp
local type Ordinary = {
    value: string
}

local type Expanded = {
    readonly value: string,
    writeonly value: string
}
```

::: deepdive
Splitting the read type from the write type is what lets a normalizing setter
be described rather than approximated. A property that accepts `string |
integer` and stores a `string` needs both types written down, and collapsing
the pair to a single type has to pick which half to misstate: widening reads
makes
every consumer test a type the value never has, and narrowing writes rejects
calls the implementation accepts. Declaration files for untyped Lua hit this on
almost every setter, which is why the pair is part of the property rather than
a separate declaration form.
:::

## Variance

Readonly types are covariant. If `Dog` fits `Animal`, then
`{readonly value: Dog}` fits `{readonly value: Animal}`, because every value
read through it is still an animal.

Writeonly types are contravariant. A `{writeonly value: Animal}` fits
`{writeonly value: Dog}`, because it accepts every dog the narrower view may
write.

An ordinary property has both constraints, so it is invariant:

```nupp
local interface Animal
    name: string
end

local record Dog is Animal
    name: string
end

local kennel: {value: Dog} = {value = new Dog(name = "rex")}
-- NUPP2001: {value: Dog} is not a {value: Animal}
local pen: {value: Animal} = kennel
```

Code holding `pen` could write another kind of animal and break the type
`kennel` has. Fresh table literals may initialize a contextual type, because no
narrower stored view exists yet.

## Indexers

Indexers take the same capabilities, in shapes, interfaces, and records:

```nupp
local interface ByteView
    readonly [integer]: uint8
end

local interface ByteSink
    writeonly [integer]: uint8
end
```

A split pair works here too, so a normalizing map states what it accepts apart
from what it returns:

```nupp
local type Normalizing = {
    readonly [string]: string,
    writeonly [string]: string | integer
}
```

Reading a map-like indexer stays optional because a key may be absent. The
write type describes a present value accepted by assignment. See [Primitive
types](primitives.md#collections) for how map and array types are written.

## Other qualifiers

Property capabilities are member-level access views. The qualifiers written
next to them answer different questions:

- `const T` makes the whole value read-only rather than selecting members. See
  [Primitive types](primitives.md#const) for the view it produces.
- `borrows` and `exclusive` govern lifetime and aliasing, not whether a member
  may be read or written. See [Ownership and affine
  types](../../runtime/ownership/borrowing.md#borrowing-and-pinning) for the model.
- A `const` binding prevents rebinding the local name. It does not by itself
  make the referenced table immutable.

## Access diagnostics

A read through a write-only view, and an assignment through a read-only view,
are both reported. Compound assignment needs both capabilities, because it first
reads the old value and then writes the result:

```nupp
local record Counter
    value: integer
end

local sink: {writeonly value: integer} = new Counter(value = 0)
sink.value = 1
sink.value += 1 -- NUPP2009: `+=` reads `value` through a write-only view
```

Duplicate capabilities are reported, as is an ordinary property combined with a
separate capability of the same name, and so is a capability property on a
struct. Struct fields are fixed C
memory slots, so they remain ordinary invariant fields. See [Records and
structs](records-and-structs.md#structs) for what a struct field may hold.

::: seealso
- [interfaces.md](interfaces.md) for the declaration these members most often
  appear on
- [records.md](records-and-structs.md) for record and struct members, and the fields a
  struct refuses
- [ownership.md](../../runtime/ownership/borrowing.md) for the qualifiers that govern lifetime rather
  than access
:::
