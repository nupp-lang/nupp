---
order: 320
---

# Generics

A type parameter stands in for a type the caller supplies. It is written in
angle brackets after the name it belongs to, and it goes on functions, function
types, and declarations. Builtin type names keep their primitive meaning and
cannot be used as type parameter names.

```nupp:playground
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then
        return items[1]
    end
    return fallback
end
```

## Parameter positions

A declaration takes parameters after its name, and every member may use them:

```nupp
local record Box<T>
    value: T
end
```

An alias takes them too, which is how a family of function types gets one name:

```nupp
local type Handler<E> = function(event: E): boolean
```

A function type carries its own, so a binding can be generic without a
declaration standing behind it:

```nupp
local mapper: function<A, B>(xs: {A}, f: function(A): B): {B}
```

## Type-pack parameters

A binder ending in `...` is a type-pack parameter. It preserves a
heterogeneous sequence rather than choosing one element type:

```nupp
local function forward<A...>(...: A...): A...
    return ...
end
```

Ordinary binders precede pack binders, and explicit pack arguments use
parentheses to delimit one pack from the next. Those parentheses are type-pack
syntax, not a tuple allocation:

```nupp
local type Adapter<A..., R...> = function(A...): R...
local type PairAdapter = Adapter<(number, string), (boolean, integer)>
```

Pack parameters work uniformly on aliases, records, interfaces, and functions:

```nupp
local interface Source<R...>
    read: function(self): R...
end

local record Values<R...> is Source<R...>
    read: function(self): R...
end
```

See [Type packs](packs.md) for list adjustment, correlation, and ownership
rules.

## Computed pack tails

A computed tuple or array can supply a pack tail with `unpackof`, which is how
a [comptime](../comptime.md) function decides what arguments a call
accepts:

```nupp
@comptime local function Arguments(Kind: type): typepack
    local info = nupp.types.describe(Kind)
    if info.kind == "literal" and info.value == "pair" then
        return nupp.types.pack({nupp.types.string, nupp.types.number})
    elseif info.kind == "literal" and info.value == "flag" then
        return nupp.types.pack({nupp.types.boolean})
    end
    return nupp.types.pack({}, nupp.types.any)
end

local function apply<Kind is string>(kind: Kind, ...: unpackof Arguments(Kind)): string
    return kind
end

apply('pair', 'x', 1)
apply('flag', true)
```

Expansion happens after inference and finite type reduction. A tuple
contributes fixed slots, an array contributes a homogeneous rest tail, and an
undecidable result becomes `...any`. The trailing comma distinguishes the
one-slot tuple `{T,}` from the array `{T}`, and a concrete result of any other
shape is rejected at the call.

### Assembling a tuple

The same operator composes a tuple from a head and a computed tail:

```nupp
local type Prepend<Value, Values> = {Value, unpackof Values}
```

When `Values` reduces to a tuple its slots are appended, and `{never}`, the
array that cannot contain an element, contributes zero slots. See [Type
packs](packs.md#unpack-and-unpackof) for the runtime operator this mirrors.

### Rejecting a computed contract

A comptime type function can construct and inspect complete packs, and
`nupp.types.error(message)` rejects one with an authored diagnostic:

```nupp
@comptime local function Checked(T: type): typepack
    if T == nupp.types.string then
        return nupp.types.pack({T})
    end
    return nupp.types.error("expected string")
end
```

See [Comptime types](comptime-types.md) for what a type function may
compute and when it runs.

## Constraints use `is`

A bound is an [interface](interfaces.md#bounded-generics), named after `is`:

```nupp
local interface Named
    name: string
end

local record Registry<T is Named>
    entries: {T}
end
```

Inside the body, the parameter's fields, methods, and metamethods are read from
its bound, with `self` specialized back to the parameter.

Bounds are checked where a generic is instantiated, not inside the subtyping
relation. Violating one is reported at the instantiation:

```text
NUPP2116: type argument integer for T: integer is not a Named
```

An `any` argument skips the bound check, which is what keeps a gradual value
usable in a bounded position. An interface named as a bound may carry a
[refinement](refinements.md), which is the test `is` against that interface
runs.

## Inference at a call site

Type arguments come from the arguments:

```nupp
print(firstOr({1, 2, 3}, 0)) -- T = integer
```

Inference is structural unification over parameters against argument types. It
sees through arrays, tuples, maps, unions, shapes, function types, pointers,
and nominal applications, and it strips ownership wrappers first.

Unification makes four decisions a partly inferred call depends on:

- **A binder appearing twice unions the two arguments** rather than failing or
  picking the more specific one.
- **An `any` argument does not bind a parameter.** It is gradual evidence, so a
  result using that parameter is `any` deliberately.
- **A destination can answer an otherwise open result parameter.** In
  `local value: string = make()`, the destination supplies `string`.
- **A parameter with no evidence takes its declared default.** An open result
  parameter without a default is an error instead of silently becoming `any`.

A `T?` parameter subtracts the concrete members from the argument, so the
residue binds. That is how `assert` is typed:

```nupp
-- assert: function<T>(v: T?, msg: any?): T
local name: string? = maybeName()
local sure = assert(name) -- sure is string
```

See [Narrowing](narrowing.md#narrowing-tests) for the other route from `T?` to
`T`.

## Explicit type arguments at a call site

Write a type argument when neither the values nor the destination supply one:

```nupp
local value = make<string>()
local selected = holder:pick<integer>()
```

The parser commits to call type arguments only when the closing `>` is followed
immediately by `(`. The ordinary comparison keeps its Lua reading:

```nupp
a < b > c
```

Adding parentheses after `>` selects the generic-call reading instead:

```nupp
a < b > (c) -- a<b>(c)
```

::: deepdive
The bounded lookahead keeps `a < b > c` and longer comparison expressions
unchanged. Only the form that can immediately become a call is reinterpreted.
Whitespace does not change tokens, so `f < T > ()` is the same generic call as
`f<T>()`.
:::

## Instantiation

`Box<number>` is one type everywhere. Instantiations are memoized, and the
cache is populated before members are filled in, so a self-referential generic
terminates.

An application writes as many arguments as the declaration binds parameters.
Fewer or more is `NUPP2146`, reported where the name is written rather than
left to surface as a mismatch between two types that print the same. A trailing
parameter the declaration defaulted may be left out, and `Type<Box>` and
`metatable<Box>` name the declaration itself and so take none.

The one other place a generic name stands alone is inside its own declaration,
where it means that declaration applied to its own parameters -- `Node` in
`record Node<T>` is the `Node<T>` being described.

Two applications of one generic compare member by member, with the usual
read and write variance: `Box<integer>` is accepted where `Box<number>` is
wanted only as far as a writable `value` field lets it, which is not at all,
since `Box<number>` would write a float into the integer box. Readonly members
read covariantly, so `{@readonly value: T}` applications are covariant in `T`.
An application that exposes no members of its own is opaque, and its arguments
compare covariantly, since nothing can be written through it.

::: deepdive
Mutable arrays likewise preserve their element type: `{integer}` does not fit a
mutable `{number}`, which could write a fractional value into it. A
`const {number}` parameter accepts the integer array for reading. A fresh array
literal takes its context's element type because no earlier alias observes a
narrower type. A generic declaration states each member's capability, so its
variance falls out of the members rather than needing an annotation.
:::

## `self`

`self` is a per-declaration type parameter, rebound to the actual receiver:

```nupp
local record Counter
    value: number

    function increment(self, by: number): self
        self.value = self.value + by
        return self
    end
end
```

A subtype inheriting a `self`-returning contract gets its own type back rather
than the declaring type. This is what makes an inherited
`metamethod __call: function(self, ...): self` return the concrete record.

## Generic metamethods

A [metamethod contract](../metamethods.md#generic-indexing) may carry
its own type parameters, which lets a typed key determine the result of an
index:

```nupp
local record Key<T>
end

local record Store
    metamethod __index: function<T>(self, key: Key<T>): T
    metamethod __newindex: function<T>(self, key: Key<T>, value: T)
end

local store: Store
local nameKey: Key<string>

local name: string = store[nameKey]
store[nameKey] = "saved"
```

`T` is inferred from `Key<T>` for both the read and the write.

::: seealso
- [packs.md](packs.md) for what a type-pack parameter binds to and how a call
  adjusts to it
- [interfaces.md](interfaces.md#bounded-generics) for the bounds a parameter
  can carry
- [refinements.md](refinements.md) for interfaces that answer `is` with a
  runtime test
- [type-level-computation.md](comptime-types.md) for computing a type
  rather than binding one
:::
