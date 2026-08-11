# Property capabilities

Properties and indexers declared `readonly` or `writeonly` grant read and write
access independently. This lets a type describe the authority an API actually
needs instead of turning every member into a read-write slot.

```nupp
local interface Snapshot
    readonly value: string
end

local interface Output
    writeonly value: string
end
```

A `Snapshot` can read `value` but cannot assign it. An `Output` can assign the
member but cannot observe its current value. The same syntax works in records
and structural shapes:

```nupp
local record Cell
    readonly value: string
    writeonly value: string | integer
end

local input: {readonly value: string} = Cell{value = "ready"}
local output: {writeonly value: string | integer} = Cell{value = "ready"}
```

The two declarations name one runtime property. They may use different types:
here a write accepts `string | integer`, while every read produces `string`.
This models normalizing setters and declaration-file APIs without weakening
reads to the setter's broader input type. Construction may initialize a
read-only record field; the capability governs access through the constructed
view, not creation of the value.

An unmodified property is shorthand for matching read and write capabilities:

```nupp
local type Ordinary = {value: string}
-- Equivalent capabilities:
local type Expanded = {readonly value: string, writeonly value: string}
```

## Variance

Readonly types are covariant. If `Dog` fits `Animal`, a
`{readonly value: Dog}` fits a `{readonly value: Animal}` because every value
read is still an animal.

Writeonly types are contravariant. A `{writeonly value: Animal}` fits a
`{writeonly value: Dog}` because it accepts every dog the narrower view may
write.

An ordinary property has both constraints, so it is invariant. A stored
`{value: Dog}` does not fit `{value: Animal}`: code using the latter view could
write another kind of animal and break the former type. Fresh table literals
may initialize a contextual type because no narrower stored view exists yet.

## Indexers

Indexers use the same capabilities and may appear in shapes, interfaces, and
records:

```nupp
local interface ByteView
    readonly [integer]: uint8
end

local interface ByteSink
    writeonly [integer]: uint8
end

local type Normalizing = {
    readonly [string]: string,
    writeonly [string]: string | integer
}
```

Reading a map-like indexer remains optional because a key may be absent. The
write type describes a present value accepted by assignment.

## Relationship to other qualifiers

Property capabilities are member-level access views:

- `const T` makes the whole value read-only rather than selecting members.
- `borrows` and `exclusive` govern lifetime and aliasing, not whether a member
  may be read or written.
- A `const` binding prevents rebinding the local name; it does not by itself
  make the referenced table immutable.

## Access diagnostics

NUPP2009 reports a read through a write-only view or an assignment through a
read-only view. Compound assignment needs both capabilities because it first
reads the old value and then writes the result.

NUPP2118 reports duplicate capabilities, an ordinary property combined with a
separate capability of the same name, and capability properties on structs.
Struct fields are fixed C memory slots and remain ordinary invariant fields.
