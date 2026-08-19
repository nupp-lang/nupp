# Primitive types

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
| `int64` |  |
| `uint8` | Unsigned physical storage; loads as `uint32` |
| `uint16` | Unsigned physical storage; loads as `uint32` |
| `uint32` | An established unsigned 32-bit Lua integer |
| `uint64` |  |

`metatable<T>`, `ctype<T>`, and `carray<T>` use generic angle-bracket syntax.
`affine(T, cleanup)`, `affine(T)`, and `pinned(T)` are built-in compile-time
type-generator calls, not runtime calls. See [Affine types](affine-types.md).
Bare `metatable` and the removed `Borrowed` and `Pinned` wrapper names are
unknown types.

```nupp
local function decode(payload: string): unknown
    return payload
end

local reply = decode("{}")
local text = reply as string
```

## `unknown`, the top type

`any` is the gradual opt-out: it is compatible with everything in both
directions, silently, which is exactly right for code that has not been
annotated yet. `unknown` is the sound alternative, for a value whose type
genuinely is not known: a JSON decode, a `pcall` result, or reflection over an
undeclared table:

```nupp
local function decode(json: string): unknown
    return nil
end

local reply = decode("{}")
print(reply.status) -- NUPP2004: no field "status" in unknown
```

Anything fits into `unknown`, but it fits nowhere else on its own. Reading a
field, calling it, and comparing it against a typed value all need it narrowed
or cast first, the same as any other concrete type that is not what the
operation wants:

```nupp
local record Status
    ok: boolean
end

if reply is Status then
    print(reply.ok) -- fine: narrowed to Status
end

local text = reply as string -- fine: an explicit cast
```

It names in a function type the same as any other type, in parameter or
return position:

```nupp
local type Reducer = function(acc: unknown, item: unknown): unknown

local sum: Reducer = function(acc: unknown, item: unknown): unknown
    return (acc as number) + (item as number)
end
```

A variadic parameter typed `unknown` takes anything, the way bare `...`
does, but gives each extra argument a type to narrow before use instead of
none at all:

```nupp
local function collect(...: unknown): integer
    return select("#", ...)
end
```

Equality against a literal narrows `unknown` the same way it narrows any
other type, so a chain that checks it against every member of a literal-type
union narrows all the way there:

```nupp
local type Mode = "read" | "write"

local function asMode(v: unknown): Mode
    if v == "read" or v == "write" then
        return v -- narrowed to Mode
    end
    error("bad mode")
end
```

Use `unknown` where `any` would otherwise stand for "I have not looked at
this value yet, and every use of it should have to say how."

## `never`, the bottom type

`never` is uninhabited: no value has it. That makes it fit anywhere any type
is wanted (there being no value of it to violate the expectation) while
nothing but `never` itself fits into it. It is what a function that always
raises, exits, or loops forever returns:

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
`x`. The checker infers this for a body whose every path raises, whether or not
it says `never`. The return type is only needed where the checker cannot see
that for itself: a loop that never ends, or a declaration with no body to read,
such as `local error: function(msg: any, level: number?): never` in the prelude.
Declaring `never` on a function that does return is an ordinary return-type
mismatch, since nothing but `never` fits `never`.

A function type carries it in return position with no special syntax beyond
the name:

```nupp
local type Bailer = function(msg: string): never
```

A `never` variadic parameter takes no extra arguments at all, since nothing but
`never` fits `never`, so any value offered there is refused:

```nupp
local function noExtras(a: integer, ...: never): integer
    return a
end

noExtras(1) -- fine
noExtras(1, "oops") -- NUPP2006: argument 2: string is not a never
```

Because it fits anywhere, a `never`-returning call also satisfies a literal
type, the same as any other declared return:

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

`float`, `int32`, and `uint32` are also value refinements. They remain ordinary
unboxed Lua numbers, but entering one requires evidence that the value belongs
to its set. Exact literals, physical loads, refined parameters and results, and
the explicit conversions establish that evidence:

```nupp
local x: number = 1
local half: float = 0.5
local rounded: float = nupp.math.f32.narrow(x)
local whole: integer = 1
local signed: int32 = nupp.math.i32.wrap(whole)
local unsigned: uint32 = nupp.math.u32.wrap(whole)
```

The erased assertion `as` may claim one of these types but does not establish
it. Ordinary arithmetic over them keeps LuaJIT's numeric semantics and produces
`number`; use the `nupp.math.f32`, `nupp.math.i32`, and `nupp.math.u32`
operations when a particular width is part of the calculation.

`int8`, `int16`, `uint8`, and `uint16` are storage-only. They may describe
struct fields, C arrays and pointers, cdefs, and standard spans, but not locals,
parameters, results, records, or unrelated generic arguments. Signed narrow
loads produce `int32`; unsigned narrow loads produce `uint32`. Stores at those
physical boundaries accept wider numeric inputs because the store itself
performs the narrowing.

Literals type as you would expect: `1` is an `integer` literal, `1.5` and `1e3`
are `number`, `1LL` is `int64`, `1ULL` is `uint64`, `0xff` is `integer`.

## Unions and optionals

```nupp
local type Shape = Circle | Square
local name: string?
```

`T?` is sugar for `T | nil`. Unions flatten, deduplicate, and sort, so
`A | B` and `B | A` are the same type.

For a union to be assignable, every member has to fit. For a value to fit a
union, it has to match some member.

An optional field on a shape is both nullable and omissible, so leaving it out
satisfies it:

```nupp
local record Options
    verbose: boolean?
end

local o: Options = new Options() -- fine
```

Write `A | B` with spaces. `A||B` lexes as the single `||` operator.

## Collections

| Form | Means |
| --- | --- |
| {T} | Lua array, one-based, dense |
| {T, U} | Tuple, fixed positions |
| {[K]: V} | Map with an explicit key type |
| {x: T, y: U} | Inline shape |
| `T[4]` | C array of fixed length, zero-based |
| `T[?]` | C array of unspecified length, zero-based |

Reading a map yields `V?`, because a key may be absent. Reading an array yields
`T` rather than `T?`, a pragmatic choice since almost every array read in
practice is in range.

`{T}` and `T[N]` are different types: one is a Lua table, the other is cdata.

## Pointers

| Form | Means |
| --- | --- |
| T* | Pointer to T |
| T*? | Pointer that may be NULL |

Pointers are invariant in their pointee. `nil` is not a `T*`; the diagnostic
says so and names `T*?` as the fix. A struct value is accepted where `struct*`
is wanted, matching LuaJIT's automatic address-of.

Every pointer that `import-c` generates is nullable, because a C header does
not say which pointers may be NULL.

## `const`

```nupp
local function render(buffer: const Buffer)
end
```

A read-only view. A mutable value satisfies a `const` parameter; a `const`
value does not satisfy a mutable one.

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
is the closed set other languages spell `enum`. See [unions](unions.md).

## Type aliases

```nupp
local type Id = uint32
local type Handler = function(event: Event): boolean
```

An alias is transparent. It introduces a name, not a new nominal identity, so
`Id` and `uint32` are interchangeable. Aliases may be generic, and may refer to
each other in any order; an alias defined in terms of itself is NUPP2115.

## Function types

```nupp
local f: function(a: number, b: string): boolean
local g: function(): (number, string)
local h: function<T>(x: T): T
local v: function(...: string)
```

Parameter names are optional. A multiple return needs parentheses in type
position.

Parameters are contravariant and returns are covariant, as usual. A function
that takes fewer parameters is usable where more are supplied, because ignoring
arguments is ordinary Lua; taking more is an error unless the target is
variadic.

Function parameters and results are represented as value sequences. Fixed,
homogeneous, generic, and correlated sequences are described in [Type
packs](packs.md).

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
is treated as unannotated. `any` is the absence of a checked type at that
boundary, not a way to satisfy the annotation requirement. A function returning
nothing still states `: nil`.

A function that always raises, exits, or loops forever returns `never`. A call
to it leaves the containing block, which lets a guard clause establish
narrowing for the code that follows.

## Diagnostics

- **NUPP2001**: a value does not fit the type it is bound to, which is what a
  widening arithmetic result reports when it is bound back to `integer`.
- **NUPP2004**: the field does not exist on that type, which is what reading a
  field of `unknown` reports before it is narrowed.
- **NUPP2006**: a call's arguments are not arranged in a way it can be given,
  which is what an extra argument to a `never` variadic reports.
- **NUPP2002**: a returned value does not fit the declared result sequence.
- **NUPP2106**: a strict exported declaration is not fully annotated.
- **NUPP2115**: an alias is defined in terms of itself.

## Next

- [records.md](records.md): nominal tables and the structs that lower to C
  memory.
- [unions.md](unions.md): closed sets of literals, and tagged unions of records.
