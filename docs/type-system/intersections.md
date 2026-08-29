---
order: 300
---

# Intersections

`A & B` describes a value that satisfies both types. An intersection is
structural and erased at run time, so it composes capabilities at a boundary
without a declaration that names the combination.

```nupp:playground
local type Identified = {
    readonly id: integer
}
local type Labeled = {
    readonly label: string
}
local type Item = Identified & Labeled

local function describe(item: Item): string
    return tostring(item.id) .. ": " .. item.label
end
```

An [interface](interfaces.md) is the other way to combine two contracts. It
gives the combination a name that implementors declare, where an intersection
states the combination at the one place that needs it.

## Normalization

`&` binds more tightly than `|`, so an intersection groups before a union does:

```nupp
local type HasCode = {
    readonly code: integer
}
local type HasMessage = {
    readonly message: string
}
local type Timeout = {
    readonly timedOut: true
}

local type Failure = Timeout | HasCode & HasMessage
```

A `Failure` is a `Timeout`, or a value carrying both a code and a message.

Nested intersections flatten, duplicate members disappear, and member order
does not affect identity, so `A & (B & A)` and `B & A` are one type. `unknown`
and gradual `any` add no constraint. `never` makes the whole intersection
`never`, since nothing can satisfy a member no value inhabits. See [Primitive
types](primitives.md#never-the-bottom-type) for what `never` means elsewhere.

## Capability composition

An intersection exposes capabilities from every member. A readable property
available through several members has the intersection of their read types, and
a writable property accepts the union of the types its constituent views
accept:

```nupp
local type NarrowRead = {
    readonly value: string
}
local type WideWrite = {
    writeonly value: string | integer
}

local type Cell = NarrowRead & WideWrite
```

Read-only and write-only views stay independent, and member completion contains
the union of the available names. See [Property
capabilities](properties.md#variance) for how the two directions compare.

The same composition applies to methods, property indexers, and [metamethod
contracts](../concepts/metamethods.md). Method receiver specialization
preserves every callable member.

## Subtyping

A value fits `A & B` only when it fits both `A` and `B`. An intersection fits a
target when one member already proves the target, or when the members jointly
provide the target's structural surface:

```nupp
local type A = {
    readonly a: number
}
local type B = {
    readonly b: string
}

local function combined(value: A & B): {
    readonly a: number,
    readonly b: string
}
    return value
end
```

Function parameters remain contravariant and result packs remain covariant. See
[Type packs](packs.md#pack-compatibility) for how a result pack is compared.

## Provable emptiness

Nupp reports a written intersection when it can prove that no value can satisfy
it. Distinct primitive runtime categories, distinct literals, distinct
concrete nominal identities, unions whose every arm is disjoint, and
incompatible required fields are all proofs:

```nupp
local type Impossible = string & number
local type ConflictingTags = {
    kind: 'file'
} & {
    kind: 'socket'
}
```

Two [records](records.md#records) have distinct nominal identities, so
`Circle & Square` is empty however similar their fields are. Interfaces, `any`,
`unknown`, and unsubstituted type parameters prove nothing about
disjointness.

::: deepdive
The check is deliberately one-sided: it reports only what it can prove, and
stays quiet everywhere else. An interface is satisfied structurally by any
value carrying its members, so two interfaces with unrelated members have a
perfectly ordinary implementation that the compiler has not been shown, and a
type parameter has whatever inhabitants its eventual argument has. Reporting
those as empty would make a generic library that intersects its own parameters
unwritable, and the failure would arrive at the declaration rather than at the
instantiation that actually conflicts. The cost is that a genuinely empty
intersection between two interfaces stays silent until a value is required and
no value fits.
:::

## Overload selection

An intersection containing only function types is an overload set, and a call
selects the single member that accepts the argument pack:

```nupp
local type Parse = function(text: string): integer & function(text: string, base: integer): string
```

The checker infers the argument pack once, probes every member without moving
affine arguments or establishing borrows, and applies the one member that
survives. There is no best-match ranking, declaration order never breaks a tie,
and selection never adds runtime dispatch. A call is reported when no member
accepts the pack, and reported differently when several do.

Everything else about overloading has a page of its own. See [Overloads and
overrides](overloads.md) for repeated method bodies, generic entries,
constructors, `@override`, and the diagnostics each of them reports.

## FAQ

### Should this be an intersection or an interface?

Write an [interface](interfaces.md) when the combination has a name worth
declaring and implementors should claim it with `is`. Write an intersection
when one function needs two contracts at once and nothing else in the program
cares about the pair.

### Does an intersection cost anything at run time?

No. Intersections are erased, exactly as the rest of the structural type layer
is, so `A & B` lowers to whatever the underlying value already was. See [Type
system](overview.md#strict-floor) for what does and does not survive to run
time.

### Why is intersecting two records empty?

A record is nominal, so a value comes from one declaration or another and never
from both. Intersect the interfaces those records declare instead, or declare a
third record carrying the members you need.

::: seealso
- [overloads.md](overloads.md) for calling a callable intersection and for
  every other form of overload
- [interfaces.md](interfaces.md) for the named alternative to composing types
  at a use site
- [properties.md](properties.md) for the read and write capabilities an
  intersection composes
:::
