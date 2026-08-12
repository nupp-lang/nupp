# Intersection types and overloads

`A & B` describes values that satisfy both types. Intersections are structural,
erased at run time, and useful both for composing capabilities and for declaring
overloaded call contracts.

For the complete guide to callable overloads, repeated method bodies,
interface defaults, `@override`, and constructors, see
[Overloads and overrides](overloads.md).

`&` binds more tightly than `|`:

```nupp
local type Readable = {
    readonly value: string
}
local type Named = {
    readonly name: string
}
local type Both = Readable & Named

local type Result = Error | HasCode & HasMessage
```

Nested intersections flatten, duplicate members disappear, and member order
does not affect identity. `unknown` and gradual `any` add no constraint;
`never` makes the whole intersection `never`.

## Capability composition

An intersection exposes capabilities from every member. A readable property
available through several members has the intersection of their read types. A
writable property accepts the union of the types its constituent views accept.
Read-only and write-only views remain independent. Member completion likewise
contains the union of the available names.

```nupp
local type Identified = {
    readonly id: integer
}
local type Labelled = {
    readonly label: string
}
local type Item = Identified & Labelled

local function describe(item: Item): string
    return tostring(item.id) .. ": " .. item.label
end
```

The same composition applies to methods, property indexers, and metamethod
contracts. Method receiver specialization preserves every callable member.

## Subtyping

A value fits `A & B` only when it fits both `A` and `B`. An intersection fits a
target when one member already proves the target or when the members jointly
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

Function parameters remain contravariant and result packs remain covariant.

## Provable emptiness

Nupp reports **NUPP2124** when it can prove that no value can satisfy a written
intersection. Proofs include distinct primitive runtime categories, distinct
literals, distinct concrete nominal identities, unions whose every arm is
disjoint, and incompatible required fields:

```nupp
local type Impossible = string & number
local type ConflictingTags = {
    kind: 'file'
} & {
    kind: 'socket'
}
```

This is intentionally incomplete. Interfaces, `any`, `unknown`, and
unsubstituted type parameters do not prove disjointness merely because the
compiler cannot currently find a shared implementation.

## Overload selection

An intersection containing only function types is an overload set:

```nupp
local type Parse = function(text: string): integer & function(text: string, base: integer): string
```

At a call, Nupp:

1. Applies Lua list adjustment and infers the complete argument pack once.
2. Probes and specializes every candidate without diagnostics or state changes.
3. Applies the selected signature only when exactly one candidate survives.

The winner supplies its complete result pack, ownership modes, borrowing and
FFI output provenance, predicate narrowing, and `noreturn` contract. Rejected
candidates do not move affine arguments or establish borrows.

There is no best-match ranking and declaration order never breaks a tie.
**NUPP2125** means no candidate accepts the pack; **NUPP2126** means several do.
Numeric widening and `any` commonly expose real ambiguities:

```nupp
local type Ambiguous = function(integer): string & function(number): boolean

local f: Ambiguous = nil as any
local value = f(1) -- NUPP2126: both signatures accept integer
```

A correlated argument-pack union must be accepted by one candidate across all
of its alternatives. Selection never adds runtime dispatch. APIs such as
`pcall`, `xpcall`, `select`, `unpack`, and coroutine protocols therefore remain
pack-native rather than being recast as finite overload sets.

## Overloaded methods

The examples below summarize the mechanism. The dedicated
[overload guide](overloads.md#separate-method-bodies) covers interface
contracts, per-entry overrides, generics, dynamic facades, and diagnostics.

Repeated method names form an overload set without an annotation:

```nupp
local record Decoder
    function decode(self, text: string): string
        return "text:" .. text
    end

    function decode(self, value: integer): string
        return "integer:" .. tostring(value)
    end
end
```

The member's visible type is the intersection of its callable signatures, but
the compiler retains each declaration as a separate method entry. A call such
as `decoder:decode("source")` selects exactly one intersection member and emits
a direct call to that entry's hidden runtime method. It does not generate or
invoke a dispatcher.

Parameter packs must be distinct; return types cannot distinguish two entries.
An overloaded method has no single Lua field value, so `decoder.decode` is
**NUPP2126**. Call it with `:`, which supplies the arguments needed to select an
entry. An `any` argument is likewise rejected when it leaves several entries
possible; an explicit cast on the argument can select the intended one.

Interface defaults use the same signature-derived entries. `@override` applies
to the exact inherited parameter pack it replaces, so one overload may be
overridden while the other defaults remain inherited. A bodyless interface may
state the same contract as a callable-intersection field; matching record
bodies use the same hidden slots. `@override` is only for replacing a default
body, not for satisfying a bodyless contract.

## Overloaded constructors

A record may declare several constructors with distinct parameter packs:

```nupp
local record Value
    text: string

    constructor(self, value: integer)
        self.text = tostring(value)
    end

    constructor(self, value: string)
        self.text = value
    end
end

local first = new Value(42)
local second = new Value("ready")
```

`new` uses ordinary overload selection. The selected declaration is emitted as
a direct call to its indexed constructor function; there is no runtime
dispatcher. Duplicate parameter-pack contracts are **NUPP2208**, as are the
existing constructor integrity failures. Declaring any constructor continues
to close named-field construction for that record.
