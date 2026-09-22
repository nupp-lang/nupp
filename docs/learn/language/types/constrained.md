---
order: 275
---

# Constrained types

A constrained type is a scalar narrowed to some of the values its base admits.
`nupp.types.range` narrows a number by value and `nupp.types.length` narrows a
string by byte length. Both bounds are inclusive.

```nupp:playground
local type Percent = nupp.types.range(integer, 0, 100)
local type Identifier = nupp.types.length(string, 1, 64)

local ratio: Percent = 50
local name: Identifier = "width"

print(ratio, name)
```

`50` and `"width"` are decided where they are written: the compiler holds the
value, so it runs the constraint and nothing reaches the program. `101` would be
reported as a violation rather than compiled into a test that always fails.

The base is `integer`, `int32` or `uint32` for a range and `string` for a
length. Nothing is converted: a constrained `uint32` has `uint32`'s
representation and rules, and this only decides which of its values are
admitted.

## Narrowing is subtyping; entering one is not

A constrained type goes wherever its base goes, and a narrower one goes where a
wider one is wanted. Containment decides that, so nothing has to declare a
relationship between two constraints.

```nupp:playground
local type Percent = nupp.types.range(integer, 0, 100)
local type Digit = nupp.types.range(Percent, 0, 9)

local function widen(value: Digit): Percent
    return value
end

local function count(value: Percent): integer
    return value
end

print(widen(7), count(50))
```

`Digit` narrows `Percent` rather than replacing it, so it admits `0` through `9`
and carries both constraints. A pair of bounds admitting nothing the base
already admits is refused at the declaration.

Going the other way is not subtyping. A `Percent` may be `50`, which is not a
`Digit`, and a bare `integer` may be anything at all, so neither enters one by
being passed. That is admission, and it is written.

## Admission is written

A value the compiler can prove needs nothing. A value it cannot prove is
refused, and `nupp.admit` is how the program says it meant it.

```nupp:playground
local type ShiftCount = nupp.types.range(integer, 0, 31)

local function shift(bits: integer, by: integer): integer
    local count: ShiftCount = nupp.admit(by)
    return bits * count
end

print(shift(1, 4))
```

`nupp.admit` takes the constrained type from where its result goes -- an
annotated binding, a declared result, a parameter, or an assignment to a
declared binding -- so nothing names the type twice. It raises when the
constraint does not hold.

This is the rule `int32` already follows. `as` is erased, so it can claim a
value is one of these but cannot establish it, and claiming it is an error
rather than an unchecked pass. There is no spelling that enters a constrained
type without either a proof or a written admission.

## Testing without raising

`value is Type` asks the same question and answers a boolean, which is the route
from a value that may not qualify.

```nupp:playground
local type Identifier = nupp.types.length(string, 1, 64)

local function named(text: string): Identifier?
    if text is Identifier then
        return text
    end
    return nil
end

print(named("width"), named(""))
```

The test narrows in the branch it proves, so `text` is an `Identifier` inside
the `if` and a plain `string` after it.

## What is emitted

An admission the compiler could not discharge becomes one call to a test
declared once for the module. Every site carrying the same constraint shares it,
so a constraint used in twenty places costs one function between them, and a
trace inlines it.

```lua
-- from `local count: ShiftCount = nupp.admit(by)`
local __nuppAdmit1 = function(__nuppV)
    if __nuppV % 1 == 0 and (__nuppV <= 31 and __nuppV >= 0) then return __nuppV end
    error("value is not established as ShiftCount", 2)
end
```

The integrality test is not decoration. `type(x) == "number"` is all Lua's own
test says, and an integer base says more than that: without it a fraction inside
the bounds would pass, and so would an infinity and a NaN.

An admission the compiler did discharge emits nothing at all. Writing one around
a value that is already proved is deliberate rather than an error, because a
bound can move and the source that said what it meant should keep compiling when
it does.

Because a retained admission raises, a `noraise` region refuses one and reports
it at the call. A comparison allocates nothing, so a `noalloc` region does not
mind it.

## Computed constraints

`nupp.types.range` and `nupp.types.length` are ordinary comptime type functions,
so a constraint can be built rather than written.

```nupp
local m = {}

@comptime local function Between(T: type, low: integer, high: integer): type
    return nupp.types.range(T, low, high)
end

local type Range<T, const Low: integer, const High: integer> = Between(T, Low, High)

local type ShiftCount = Range<integer, 0, 31>
local type Percent = Range<integer, 0, 100>

function m.widen(value: ShiftCount): Percent
    return value
end

return m
```

An alias is not a brand. One constraint over one base is one type however many
names reach it and however the bounds were computed, so `Range<integer, 0, 31>`
and `nupp.types.range(integer, 0, 31)` written directly are the same type and
each goes where the other does. The alias name is what hover and diagnostics
show, because an interval is longer than a name and says less.

## Where a constraint reaches

Every position a value enters is an admission position: a binding, an argument,
a result, a record field, a collection element, a constructor argument. Each is
proved, written, or refused.

```nupp
local m = {}

local type Small = nupp.types.range(integer, 0, 10)

record m.Box
    n: Small
end

function m.put(box: m.Box, value: integer): nil
    box.n = nupp.admit(value)
end

return m
```

An existing `{integer}` does not become a `{Small}` by being passed. A container
is invariant, and an alias to the original could write an integer the constraint
does not admit after any one-time scan had already passed.

Length counts bytes, matching Nupp's own string length: not code points, not
grapheme clusters, and an embedded NUL counts like any other byte.

See [Refinements](refinements.md) for the interface `satisfies` declaration,
which answers `is` for a table rather than narrowing a scalar, and
[Primitive types](primitives.md) for the fixed-width value refinements a range
can narrow.
