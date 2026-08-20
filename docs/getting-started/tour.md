# Tour of Nupp

This walks the whole language in one pass. Nothing here is a preview of a
feature described properly later. It is the short version of each thing, with a
link to the long one.

```nupp
local record Point
    x: number
    y: number
end

local function scale(p: Point, k: number): Point
    return new Point(x = p.x * k, y = p.y * k)
end
```

## It starts as Lua

Every valid LuaJIT program is a valid Nupp program. Rename a `.lua` file to
`.nupp` and it parses, round-trips byte for byte, and checks with no
diagnostics. The compiler's test suite pins that against a large body of
real-world Lua.

```nupp:playground
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

`new Point(...)` lowers to `setmetatable({x = 3, y = 4}, Point)`. The runtime
shape is what you would have written by hand.

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
Fields must be C-representable, so a `string` or a `{T}` field is refused. That
is the trade you make for the layout. A struct binding is never nil and
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
required for that. It is a claim the checker trusts without re-proving, which is
what lets a runtime registrar install the surface later. Interfaces erase
completely and have no runtime value.

## Literal unions are enums

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

```text
warning: NUPP2107 exhaustiveness: every branch returns, so this
handles "green" | "red" and leaves "green" unhandled
```

## Unions, optionals, and narrowing

```nupp
local function widthOf(s: string?): integer
    if s then
        return #s
    end
    return 0
end
```

`T?` is `T | nil`. Inside the `if`, `s` is `string`.

When the alternatives carry data, give each record a literal-typed field and
compare it. That is a tagged union, and the comparison narrows to the one record
that declares the tag:

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
`ffi.istype`. It does **not** read `type(x) == "string"`, which is an ordinary
call returning an ordinary string, and the checker has no way to tie it back to
`x`. Write `x is string`.

[Narrowing](../type-system/narrowing.md) has the full list of what proves what.

## Switches produce values

`switch selector do` makes a total, ordered dispatch readable without nesting
`elseif` expressions. Literal cases are checked for duplicates and
exhaustiveness:

```nupp
local type Mode = "read" | "write"

local access = switch mode do
    case "read" -> "reader"
    case "write" -> "writer"
end
```

Type cases use the same runtime identity and narrowing as `is`. They can bind
the whole matched value and direct fields:

```nupp
local area = switch shape do
    case is Circle as circle {radius} -> math.pi * radius * radius
    case is Rectangle {width, height as h} -> width * h
    else -> 0
end
```

An arm that needs statements writes `-> do`, then `yield value`; `return`
continues to exit the enclosing function. The selector runs once and lowering
adds no arm closure. [Switch expressions](../concepts/switch-expressions.md)
covers the complete syntax and constraints.

## Generics

```nupp
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then
        return items[1]
    end
    return fallback
end

print(firstOr({1, 2, 3}, 0))
```

Type arguments are inferred from the call. Constraints use `is`:
`<T is Callable>`. There is no explicit type-argument syntax at a call site.
`f<number>(x)` parses as two comparisons, the way it does in Lua.

## Ownership

A value with a cleanup obligation carries it in its type, and the checker will
not let you drop it.

A producer declares the obligation, and any type can carry one:

```nupp
local record Session
    closed: boolean

    function drop(takes self): nil
        self.closed = true
    end
end

local function closeSession(takes session: Session): nil
    session.closed = true
end

local function openSession(): affine(Session, closeSession)
    return new Session(closed = false)
end
```

The exact `closeSession` identity is carried statically. An ordinary local is
destroyed automatically:

```nupp
do
    local session = openSession()
    print(session.closed)
end
```

Cleanup runs on fallthrough, `return`, `break`, `continue`, a `goto` leaving
the block, and an error raised anywhere inside. Moving, returning, or explicitly
dropping the owner deactivates its automatic cleanup exactly once.

[Ownership](../concepts/ownership.md) starts from here; the
[ownership reference](../type-system/ownership.md) has the whole model.

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
control must not park; the compiler follows calls to the possible suspension and
reports the path. Libraries subscribe through `nupp.suspension`, [suspension
handlers](../concepts/suspension.md#hosts-supply-scheduling-policy) own
scheduling policy, and `all`, `gather`, `race`, and `batch` compose several
waiting operations without promises.

[Suspension](../concepts/suspension.md) explains the runtime paths, cancellation
contract, coroutine inheritance, and concurrent combinators.

## Calling C

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

That emits `ffi.cdef` and an `ffi.load` lookup. The parameter modes `borrows`,
`takes`, `exclusive`, `retains` and `releases` say what C does with a pointer,
which a header cannot. None of them change the ABI.

For a whole header there are two routes: `nupp import-c` writes a committed,
hand-editable module, and `cheader("mini.h")` types the header at compile time
with no generated file. A manifest C dependency adds a generated bridge when
the API exists only as `static inline` functions or function-like macros.
[C interop](../concepts/c-interop.md) covers all three.

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
