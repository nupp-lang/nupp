# Primitive types

A primitive is a builtin type name that resolves without a declaration. They
cover Lua's own values, the gradual and sound ends of the lattice, and the C
numeric tower.

```nupp:playground
local name: string = "ada"
local count: integer = 1
local ratio: number = count / 2
local anything: any = {name, count, ratio}
```

## Builtin names

These names, and only these, resolve as bare builtin types:

| Name | Means |
| --- | --- |
| `any` | The gradual type; compatible with everything |
| `unknown` | The top type; everything fits it, it fits nothing else |
| `never` | The bottom type; fits everything, nothing fits it |
| `nil` | The nil singleton |
| `boolean` | true or false |
| `string` | A Lua string |
| `number` | A LuaJIT double |
| `integer` | A number known to be integral |
| `table` | Any table shape; gradual in both directions |
| `thread` | A coroutine |
| `userdata` | Userdata |
| `float` | An established binary32 Lua number; widens to `number` |
| `cdata` | Any cdata value |
| `cstring` | const char * |
| `voidptr` | void * |
| `int8` | Signed physical storage; loads as `int32` |
| `int16` | Signed physical storage; loads as `int32` |
| `int32` | An established signed 32-bit Lua integer |
| `int64` | A boxed 64-bit signed cdata integer, as LuaJIT's `1LL` |
| `uint8` | Unsigned physical storage; loads as `uint32` |
| `uint16` | Unsigned physical storage; loads as `uint32` |
| `uint32` | An established unsigned 32-bit Lua integer |
| `uint64` | A boxed 64-bit unsigned cdata integer, as LuaJIT's `1ULL` |

`metatable<T>`, `ctype<T>`, and `carray<T>` use generic angle-bracket syntax.
`affine(T, cleanup)`, `affine(T)`, and `pinned(T)` are built-in compile-time
type-generator calls rather than runtime calls. See [affine
types](affine-types.md) for what they generate. Bare `metatable` and the
removed `Borrowed` and `Pinned` wrapper names are unknown types.

## `unknown`, the top type

`any` is the gradual opt-out: compatible with everything in both directions,
silently, which is exactly right for code that has not been annotated yet.
`unknown` is the sound alternative, for a value whose type genuinely is not
known, such as a JSON decode, a `pcall` result, or reflection over an undeclared
table:

```nupp
local function decode(json: string): unknown
    return nil
end

local reply = decode("{}")
print(reply.status) -- NUPP2004: no field "status" in unknown
```

### Narrowing and casting

Anything fits into `unknown`, but it fits nowhere else on its own. Reading a
field, calling it, and comparing it against a typed value all need it narrowed
or cast first, the same as any other concrete type that is not what the
operation wants:

```nupp
local record Status
    ok: boolean
end

if reply is Status then
    print(reply.ok) -- narrowed to Status
end

local text = reply as string -- an explicit cast
```

Equality against a literal narrows `unknown` the same way it narrows any other
type, so a chain that checks it against every member of a literal-type union
narrows all the way there:

```nupp
local type Mode = "read" | "write"

local function asMode(v: unknown): Mode
    if v == "read" or v == "write" then
        return v -- narrowed to Mode
    end
    error("bad mode")
end
```

See [narrowing.md](narrowing.md#narrowing-tests) for the complete set of tests
that prove something.

### `unknown` in a signature

It names in a function type the same as any other type, in parameter or result
position:

```nupp
local type Reducer = function(acc: unknown, item: unknown): unknown

local sum: Reducer = function(acc: unknown, item: unknown): unknown
    return (acc as number) + (item as number)
end
```

A variadic parameter typed `unknown` takes anything, the way bare `...` does,
but gives each extra argument a type to narrow before use instead of none at
all:

```nupp
local function collect(...: unknown): integer
    return select("#", ...)
end
```

Use `unknown` where `any` would otherwise stand for "I have not looked at this
value yet, and every use of it should have to say how."

## `never`, the bottom type

`never` is uninhabited: no value has it. That makes it fit anywhere any type is
wanted, there being no value of it to violate the expectation, while nothing but
`never` itself fits into it. It is what a function that always raises, exits, or
loops forever returns:

```nupp
local function fail(msg: string): never
    error(msg)
end

local function use(x: string?)
    if not x then
        fail("missing")
    end
    print(#x) -- x is string here
end
```

A call to a `never`-returning function leaves the block it stands in the same
way an inline `error` does, which is what lets the guard clause above narrow
`x`.

### Inferred `never` results

The checker infers `never` for a body whose every path raises, whether or not it
says so. The annotation is needed only where the checker cannot see that for
itself: a loop that never ends, or a declaration with no body to read, such as
`local error: function(msg: any, level: number?): never` in the prelude.
Declaring `never` on a function that does return is an ordinary result mismatch,
since nothing but `never` fits `never`.

### `never` in a signature

A function type carries it in result position with no syntax beyond the name,
and a `never` variadic parameter takes no extra arguments at all:

```nupp
local type Bailer = function(msg: string): never

local function noExtras(a: integer, ...: never): integer
    return a
end

noExtras(1) -- fine
noExtras(1, "oops") -- NUPP2006: argument 2: string is not a never
```

Because it fits anywhere, a `never`-returning call also satisfies a literal
type, the same as any other declared result:

```nupp
local function pick(ok: boolean): "yes" | "no"
    if ok then
        return "yes"
    end
    return fail("not ok")
end
```

## Numbers

`integer` is a subtype of `number`. The reverse is not true, and there is no
implicit downcast:

```nupp
local x: number = 1
local y: integer = x -- NUPP2001: number is not a integer
```

### Value refinements

`float`, `int32`, and `uint32` remain ordinary unboxed Lua numbers, but entering
one requires evidence that the value belongs to its set. Exact literals,
physical loads, refined parameters and results, and the explicit conversions
establish that evidence:

```nupp
local whole: integer = 1
local signed: int32 = nupp.math.i32.wrap(whole)
local unsigned: uint32 = nupp.math.u32.wrap(whole)
local rounded: float = nupp.math.f32.narrow(0.5)
```

The erased assertion `as` may claim one of these types but does not establish
it, and is reported where the evidence is missing. Ordinary arithmetic
over them keeps LuaJIT's numeric semantics and produces `number`, so use the
`nupp.math.f32`, `nupp.math.i32`, and `nupp.math.u32` operations when a
particular width is part of the calculation. See
[nupp.math](../modules/nupp/math.md) for the complete operation set.

### Storage-only widths

`int8`, `int16`, `uint8`, and `uint16` describe physical layout and nothing
else. They may describe struct fields, C arrays and pointers, cdefs, and
standard spans, but not locals, parameters, results, records, or unrelated
generic arguments:

```nupp
local struct Header
    kind: uint8
    length: uint16
end

local byte: uint8 = 1 -- NUPP2012: a physical storage width is not a value type
```

Signed narrow loads produce `int32` and unsigned narrow loads produce `uint32`.
Stores at those physical boundaries accept wider numeric inputs, because the
store itself performs the narrowing.

::: deepdive
Two names for the same C width would be the obvious alternative, one for storage
and one for the value a load yields. The division here is narrower on purpose:
LuaJIT has no `uint8` register, so every narrow load already arrives as a
32-bit Lua number, and a `uint8` local would be a type describing a
representation that does not exist at run time. Keeping the narrow names to
layout positions means the value types are exactly the ones LuaJIT can hold,
and the diagnostic names the wider type to write instead.
:::

### Numeric literals

Literals type as you would expect: `1` is an `integer` literal, `1.5` and `1e3`
are `number`, `1LL` is `int64`, `1ULL` is `uint64`, and `0xff` is `integer`.

## Unions and optionals

A union lists the types a value may have, and `T?` is sugar for `T | nil`:

```nupp
local type Shape = Circle | Square
local name: string?
```

Unions flatten, deduplicate, and sort, so `A | B` and `B | A` are the same type.
For a union to be assignable, every member has to fit; for a value to fit a
union, it has to match some member.

An optional field on a shape is both nullable and omissible, so leaving it out
satisfies it:

```nupp
local record Options
    verbose: boolean?
end

local o: Options = new Options() -- fine
```

Write `A | B` with spaces. `A||B` lexes as the single `||` operator. See
[unions.md](unions.md) for tagged unions and exhaustiveness.

## Collections

| Form | Means |
| --- | --- |
| `{T}` | Lua array, one-based, dense |
| `{T, U}` | Tuple, fixed positions |
| `{[K]: V}` | Map with an explicit key type |
| `{x: T, y: U}` | Inline shape |
| `T[4]` | C array of fixed length, zero-based |
| `T[?]` | C array of unspecified length, zero-based |

`{T}` and `T[N]` are different types: one is a Lua table, the other is cdata.
Reading a map yields `V?`, because a key may be absent, while reading an array
yields `T`:

```nupp
local counts: {[string]: integer} = {}
local hits: {integer} = {1, 2, 3}

local maybe: integer? = counts["misses"]
local first: integer = hits[1]
```

::: deepdive
An array read yielding `T` rather than `T?` is the one place collections trade
soundness for use. Every index is in bounds until it is not, so the sound
reading would put a `?` on `hits[1]` and force a narrowing test into every loop
body that already knows its own bounds. Maps get the `?` because an absent key
is the ordinary case there, not the exceptional one: a lookup on a fresh table
is nil, and code that reads a map is usually asking whether the key is there at
all.
:::

## Pointers

A pointer type is written `T*`, and a pointer that may be NULL is `T*?`.
Pointers are invariant in their pointee. `nil` is not a `T*`; the diagnostic
says so and names `T*?` as the fix. A struct value is accepted where `struct*`
is wanted, matching LuaJIT's automatic address-of:

```nupp
local struct Vec2
    x: float
    y: float
end

local function length(v: Vec2*): number
    return math.sqrt(v.x * v.x + v.y * v.y)
end

local point = new Vec2(3.0, 4.0)
print(length(point)) -- the struct value is taken by address
```

Every pointer that `import-c` generates is nullable, because a C header does not
say which pointers may be NULL. See [c-interop.md](../concepts/c-interop.md)
for what a C boundary adds to a pointer.

## `const`

`const T` is a read-only view. A mutable value satisfies a `const` parameter; a
`const` value does not satisfy a mutable one:

```nupp
local function render(buffer: const Buffer)
end
```

This is unrelated to the `const` binding modifier, which makes a local
immutable:

```nupp
const LIMIT: integer = 100
```

## Literal types

A string or boolean literal is a type:

```nupp
local type Mode = "read" | "write"
```

`false` exists as a type so that `T | false` narrows usefully. A literal is
assignable to its base type, and to any union that lists it. A union of literals
is the closed set other languages call `enum`. See [literal unions are
enums](unions.md#literal-unions-are-enums) for what that admits.

## Type aliases

An alias introduces a name, not a new nominal identity:

```nupp
local type Id = uint32
local type Handler = function(event: Event): boolean
```

An alias is transparent, so `Id` and `uint32` are interchangeable. Aliases may
be generic, and may refer to each other in any order; an alias defined in terms
of itself is reported.

## Function types

```nupp
local f: function(a: number, b: string): boolean
local g: function(): (number, string)
local h: function<T>(x: T): T
local v: function(...: string)
```

Parameter names are optional, and a multiple result needs parentheses in type
position. Parameters are contravariant and results are covariant, as usual. A
function that takes fewer parameters is usable where more are supplied, because
ignoring arguments is ordinary Lua; taking more is an error unless the target is
variadic.

Function parameters and results are represented as value sequences. See
[packs.md](packs.md) for fixed, homogeneous, generic, and correlated sequences.

### Function declarations

Parameters and results are annotated where they are declared. Several results
are comma-separated in a declaration; only a function *type* needs parentheses
around a multiple result.

```nupp
local function split(text: string): string, integer
    return text, #text
end

local function log(message: string): nil
    print(message)
end
```

In a strict file, an exported function whose signature mentions `any` anywhere
is treated as unannotated, and is reported. `any` is the absence of a
checked type at that boundary, not a way to satisfy the annotation requirement.
A function returning nothing still states `: nil`.

## FAQ

### Is `integer` a different runtime value from `number`?

No. Both are LuaJIT doubles, and `integer` records that the checker has proof
the value is integral. `x is integer` compiles to `type(x) == "number"`, so
integrality is not re-tested at run time.

### When does `int32` earn its place over `integer`?

When the wrapping matters. `integer` says the value is whole, while `int32`,
`uint32`, and `float` say it belongs to a fixed-width set, which is what lets
the `nupp.math` operations wrap and narrow the way C does. See
[nupp.math](../modules/nupp/math.md) for those operations.

### Can `unknown` replace `any` everywhere?

Not without editing the code that uses it. `any` propagates silently, so
adopting `unknown` in its place turns every read, call, and comparison into a
site that needs a narrowing test or an `as`. That is the point of the swap, and
it is also the cost of it.

::: seealso
- [overview.md](overview.md#gradual-escape-hatches) for how `any` and `as`
  relate to the strict floor
- [records.md](records.md) for the nominal types built out of these
- [narrowing.md](narrowing.md) for the tests that turn a union back into one
  member
:::
