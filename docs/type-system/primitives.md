# Primitive types

These names, and only these, resolve as bare builtin types:

```
 Name       Means
 ─────────  ──────────────────────────────────────────────────────
 any        The gradual type; compatible with everything
 nil        The nil singleton
 boolean    true or false
 string     A Lua string
 number     A LuaJIT double
 integer    A number known to be integral
 table      Any table shape; gradual in both directions
 thread     A coroutine
 userdata   Userdata
 float      A C float; widens to number
 cdata      Any cdata value
 cstring    const char *
 voidptr    void *
 int8       Sized C integers, signed and unsigned
 int16
 int32
 int64
 uint8
 uint16
 uint32
 uint64
```

There is no `unknown` and no `never`.

`metatable<T>`, `ctype<T>`, `carray<T>`, `owned<T>`, `borrowed<T>`, and
`pinned<T>` are constructors rather than names — each needs a type argument,
and bare `metatable` is an unknown type name.

## Numbers

`integer` is a subtype of `number`. The reverse is not true, and there is no
implicit downcast:

```nupp
local x: number = 1
local y: integer = x   -- NUPP2001: number is not a integer
```

The sized C integers behave differently. Any numeric source is accepted into a
`float` or a sized-integer slot, as in C:

```nupp
local z: int32 = x     -- accepted
```

So `number → integer` is refused while `number → int32` is allowed. The sized
types are a C boundary, where truncation is the expected arithmetic; `integer`
is a claim about a Lua value. Under `--strict`, narrowing a wider numeric into
a small sized type raises the `lossy-narrowing` lint, and the suggested fix is
an explicit `as`.

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

An optional field on a shape is both nullable and omissible — leaving it out
satisfies it:

```nupp
local record Options
    verbose: boolean?
end

local o: Options = Options{}   -- fine
```

Write `A | B` with spaces. `A||B` lexes as the single `||` operator.

## Collections

```
 Form            Means
 ──────────────  ────────────────────────────────────────────────
 {T}             Lua array, one-based, dense
 {T, U}          Tuple, fixed positions
 {[K]: V}        Map with an explicit key type
 {x: T, y: U}    Inline shape
 T[4]            C array of fixed length, zero-based
 T[?]            C array of unspecified length, zero-based
```

Reading a map yields `V?`, because a key may be absent. Reading an array yields
`T` rather than `T?` — a pragmatic choice, since almost every array read in
practice is in range.

`{T}` and `T[N]` are different types: one is a Lua table, the other is cdata.

## Pointers

```
 Form       Means
 ─────────  ────────────────────────────────
 T*         Pointer to T
 T*?        Pointer that may be NULL
```

Pointers are invariant in their pointee. `nil` is not a `T*`; the diagnostic
says so and names `T*?` as the fix. A struct value is accepted where `struct*`
is wanted, matching LuaJIT's automatic address-of.

Every pointer that `import-c` generates is nullable, because a C header does
not say which pointers may be NULL.

## `const`

```nupp
local function render(buffer: const Buffer) end
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
assignable to its base type, and to an enum that lists it.

## Type aliases

```nupp
local type Id = uint32
local type Handler = function(event: Event): boolean
```

An alias is transparent — it introduces a name, not a new nominal identity, so
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
