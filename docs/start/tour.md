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

    function length(self): number
        return math.sqrt(self.x * self.x + self.y * self.y)
    end
end

local p = new Point(x = 3, y = 4)
print(p:length())
```

`new Point(...)` lowers to `setmetatable({x = 3, y = 4}, Point)`. The runtime shape
is what you would have written by hand.

## Structs are cdata

A `struct` is the same declaration syntax over FFI memory: fixed layout, real C
field widths, no hash lookups.

```nupp
local struct Vec2
    x: float
    y: float
end

local v = new Vec2(1.0, 2.0)
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

## A union of literals is an enum

```nupp
local type Color = "red" | "green"

local function describe(c: Color): string
    if c == "red" then
        return "warm"
    else
        return "cool"
    end
end
```

There is no `enum` declaration; a string literal is a type, so a union of them
is a closed set. A member is a `string` subtype, so a bare literal lands in it.
Drop the `else` and the checker says which members you left out:

```
warning: NUPP2107 exhaustiveness: every branch returns, so this
handles "green" | "red" and leaves "green" unhandled
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

When the alternatives carry data, give each record a literal-typed field and
compare it — that is a tagged union, and the comparison narrows to the one
record that declares the tag:

```nupp
local record Circle
    kind: "circle"
    radius: number
end

local record Square
    kind: "square"
    side: number
end

local type Figure = Circle | Square

local function area(f: Figure): number
    if f.kind == "circle" then
        return 3.14159 * f.radius * f.radius
    end
    return f.side * f.side
end
```

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

    @drop
    function close(self)
        self.closed = true
    end
end

@owned
local function openSession(): Session
    return new Session(closed = false)
end
```

`@drop` marks the operation that consumes the resource; `@owned` marks the
function that produces one. An ordinary local is destroyed automatically:

```nupp
do
    local session = openSession()
    print(session.closed)
end
```

Cleanup runs on fallthrough, `return`, `break`, `continue`, a `goto` leaving
the block, and an error raised anywhere inside. Moving, returning, or explicitly
dropping the owner deactivates its automatic cleanup exactly once.

[Ownership](ownership.md) starts from here; the
[ownership reference](../ownership.md) has the whole model.

## Waiting does not change a function's shape

Nupp has no `async function`, `await`, future return type, or async half of the
standard library. A suspension-aware operation is an ordinary call with an
ordinary result:

```nupp
local process = require("nupp.io.process")

local child = assert(process.new({args = {"cc", "--version"}}))
local result = assert(child:communicate())
print(result.output)
child:close()
```

With no scheduler, `communicate` blocks by driving the registered readiness
sources. Under an installed scheduler, the same call parks the current
coroutine so other work can run. A ready operation does neither.

Whether a function may suspend is an inferred effect. Use `nosuspend do` where
control must not park; the compiler follows calls to the possible suspension
and reports the path. Libraries subscribe through `nupp.suspension`,
[suspension handlers](suspension-handlers.md) own scheduling policy, and `all`,
`gather`, `race`, and `batch` compose several waiting operations without
promises.

[Suspension](suspension.md) explains the runtime paths, cancellation contract,
coroutine inheritance, and concurrent combinators.

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

- [Reasons to use Nupp](why.md) — the case for each of the pieces above.
- [Nupp syntax](syntax.md) — the syntax in one place, including what LuaJIT
  2.1 does and does not carry.
- [Suspension](suspension.md) covers ordinary calls that block or park
  according to their context.
- [Type system](../type-system/overview.md) — gradual typing, and what the
  checker proves.
