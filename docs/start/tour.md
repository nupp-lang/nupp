# A tour of Nupp

This walks the whole language in one pass. Nothing here is a preview of a
feature described properly later — it is the short version of each thing, with
a link to the long one.

## It starts as Lua

Every valid LuaJIT program is a valid Nupp program. Rename a `.lua` file to
`.nupp` and it parses, round-trips byte for byte, and checks with no
diagnostics. The compiler's test suite pins that against a large body of
real-world Lua.

```nupp
local function greet(name)
    return "Hello, " .. name .. "!"
end

print(greet("world"))
```

Unannotated code is `any` and checks silently. Annotations are what turn
checking on, one declaration at a time.

```nupp
local function greet(name: string): string
    return "Hello, " .. name .. "!"
end
```

There is one place the two dialects disagree, and it is documented rather than
discovered: Lua reads `local type Alias = 5` as two statements, and Nupp reads
it as a type alias. A newline or semicolon after `type` picks the Lua meaning.

## Records are tables

A `record` is a Lua table with a known shape and a nominal name. Methods go
inline, beside the fields they use.

```nupp
local record Point
    x: number
    y: number

    function length(): number
        return math.sqrt(self.x * self.x + self.y * self.y)
    end
end

local p = Point{x = 3, y = 4}
print(p:length())
```

`Point{...}` lowers to `setmetatable({x = 3, y = 4}, Point)`. The runtime shape
is what you would have written by hand.

## Structs are cdata

A `struct` is the same declaration syntax over FFI memory: fixed layout, real C
field widths, no hash lookups.

```nupp
local struct Vec2
    x: float
    y: float
end

local v = Vec2{x = 1.0, y = 2.0}
```

That becomes `ffi.metatype(ffi.typeof("struct { float x; float y; }"), ...)`.
Fields must be C-representable, so a `string` or a `{T}` field is refused —
this is the trade you make for the layout. A struct binding is never nil and
zero-initializes, so `local v: Vec2` is complete on its own.

[Records and structs](../type-system/records.md) covers when to reach for each.

## Interfaces are satisfied by shape

```nupp
local interface Named
    name: string
end

local record Tagged is Named
    name: string
    weight: number
end
```

A type satisfies an interface by carrying its members. The `is` clause is not
required for that — it is a claim the checker trusts without re-proving, which
is what lets a runtime registrar install the surface later. Interfaces erase
completely and have no runtime value.

## Enums are strings

```nupp
local enum Color
    "red"
    "green"
end

local function describe(c: Color): string
    if c == "red" then
        return "warm"
    else
        return "cool"
    end
end
```

An enum member is a `string` subtype, so a bare literal lands in it. Drop the
`else` and the checker says which members you left out:

```
warning: NUPP2107 enum-exhaustiveness: every branch returns, so this
handles Color and leaves "green" unhandled
```

## Unions, optionals, and narrowing

```nupp
local type Shape = Point | Vec2

local function widthOf(s: string?): integer
    if s then
        return #s
    end
    return 0
end
```

`T?` is `T | nil`. Inside the `if`, `s` is `string`.

Narrowing reads `is`, `== nil`, truthiness, discriminant fields, and
`ffi.istype`. It does **not** read `type(x) == "string"` — that is an ordinary
call returning an ordinary string, and the checker has no way to tie it back to
`x`. Write `x is string`.

[Narrowing](../type-system/narrowing.md) has the full list of what proves what.

## Generics

```nupp
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then return items[1] end
    return fallback
end

print(firstOr({1, 2, 3}, 0))
```

Type arguments are inferred from the call. Constraints use `is`:
`<T is Callable>`. There is no explicit type-argument syntax at a call site —
`f<number>(x)` parses as two comparisons, the way it does in Lua.

## Ownership

A value with a cleanup obligation carries it in its type, and the checker will
not let you drop it.

A producer declares the obligation, and any type can carry one:

```nupp
local record Session
    closed: boolean

    @dispose
    function close()
        self.closed = true
    end
end

@owned
local function openSession(): Session
    return Session{closed = false}
end
```

`@dispose` marks the operation that consumes the resource; `@owned` marks the
function that produces one. Now the checker will not let the result be dropped,
and `with` discharges it:

```nupp
with session = openSession() do
    print(session.closed)
end
```

`with` releases on fallthrough, `return`, `break`, `continue`, a `goto` leaving
the body, and an error raised anywhere inside. It is the only construct that
closes something for you; an ordinary local owner has to be disposed,
transferred, or returned, and forgetting is a compile error.

[Ownership](ownership.md) starts from here; the
[ownership reference](../ownership.md) has the whole model.

## Calling C

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from "mini"
```

That emits `ffi.cdef` and an `ffi.load` lookup. Parameter modes — `borrows`,
`takes`, `exclusive`, `retains`, `releases` — say what C does with a pointer,
which a header cannot. None of them change the ABI.

For a whole header there are two routes: `nupp import-c` writes a committed,
hand-editable module, and `cheader("mini.h")` types the header at compile time
with no generated file. [C interop](../c-interop.md) covers both.

## Everything is one binary

```bash
nupp check          # type-check the project
nupp build          # compile to Lua
nupp run app.nupp   # compile and run
nupp fmt            # format
nupp doc            # generate this site
nupp lsp serve      # language server
nupp explain NUPP2119
```

The checker, formatter, documentation generator, language server, build system,
profiler, and C importer are the same executable, built from the same parse.
[Tooling](tooling.md) is the guided version of that list.

## What to read next

- [Why use Nupp?](why.md) — the case for each of the pieces above.
- [Nupp syntax](syntax.md) — the syntax in one place, including what LuaJIT
  2.1 does and does not carry.
- [The type system](../type-system/overview.md) — gradual typing, and what the
  checker proves.
