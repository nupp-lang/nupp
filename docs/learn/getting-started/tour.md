---
order: 20
---

# Tour of Nupp

Nupp adds a type system, ownership, and checked C interop to LuaJIT without
changing what the syntax underneath means. Each section below is the short
version of one construct, with a link to the page that owns the long one.

```nupp
local record Point
    x: number
    y: number
end

local function scale(p: Point, k: number): Point
    return new Point(x = p.x * k, y = p.y * k)
end
```

## Plain Lua is valid Nupp

Every valid LuaJIT program is valid Nupp syntax. Rename a `.lua` file to
`.g.nupp` to enable typed syntax while keeping the gradual floor; renaming it
directly to `.nupp` also enables strict checks such as unknown-global errors.

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
See [plain Lua is valid
Nupp](../language/syntax.md#plain-lua-is-valid-nupp) for the compatibility
guarantee the test suite pins.

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
```

Construction is by name, because field order in a table is not meaningful:

```nupp
local p = new Point(x = 3, y = 4)
print(p:length())
```

`new Point(...)` lowers to `setmetatable({x = 3, y = 4}, Point)`. The runtime
shape is what you would have written by hand. See
[records](../language/types/records-and-structs.md#records) for constructors, field defaults,
private fields, and recursive declarations.

## Structs have fixed layouts

A `struct` has a fixed, reifiable layout. A native LuaJIT target represents it
as FFI memory with real C field widths and no hash lookups.

```nupp
local struct Vec2
    x: float
    y: float
end
```

On that target it becomes
`ffi.metatype(ffi.typeof("struct { float x; float y; }"), ...)`. A portable
target may select the checked table-backed struct provider instead. A struct
binding is never nil and zero-initializes, so a bare declaration is complete
on its own:

```nupp
local a = new Vec2(1.0, 2.0)
local b: Vec2
```

Fields must be C-representable, so a `string` or a `{T}` field is refused. That
is the trade you make for the layout. See [struct field
types](../language/types/records-and-structs.md#struct-field-types) for what is reifiable, and
[choosing](../language/types/records-and-structs.md#choosing) for when to reach for each.

## Interfaces are structural

A type satisfies an interface by carrying its members, so no declaration links
the two.

```nupp
local interface Named
    name: string
end

local record Tagged
    name: string
    weight: number
end

local n: Named = new Tagged(name = "t", weight = 1)
```

An `is` clause does two further things. It inherits the parent's members, and it
declares satisfaction the checker trusts rather than re-proving, which is what
lets a runtime registrar install the surface later:

```nupp
local record Registered is Named
    weight: number
end
```

Interfaces erase completely and have no runtime value. See
[interfaces](../language/types/interfaces.md#satisfaction-is-structural) for sealed
interfaces, default implementations, and what makes an interface testable at run
time.

## Literal unions are enums

There is no `enum` declaration. A string literal is a type, so a union of them
is a closed set, and a member is a `string` subtype that a bare literal lands
in.

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

Drop the `else` and the checker says which members you left out:

```text
warning: NUPP2107 exhaustiveness: every branch returns, so this
handles "green" | "red" and leaves "green" unhandled
```

See [literal unions are
enums](../language/types/unions.md#literal-unions-are-enums) for how a member
relates to `string`.

## Unions, optionals, and narrowing

`T?` is `T | nil`, and a truthiness test narrows it. Inside the `if`, `s` is
`string`.

```nupp
local function widthOf(s: string?): integer
    if s then
        return #s
    end
    return 0
end
```

When the alternatives carry data, give each record a literal-typed field and
compare it. That is a tagged union:

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
```

The comparison narrows to the one record that declares the tag, so the second
branch reaches `f.side` without a cast:

```nupp
local function area(f: Figure): number
    if f.kind == "circle" then
        return math.pi * f.radius * f.radius
    end
    return f.side * f.side
end
```

Narrowing reads `is`, `== nil`, truthiness, discriminant fields, and
`ffi.istype`. It does not read `type(x) == "string"`, which is an ordinary call
returning an ordinary string, and the checker has no way to tie it back to `x`.
Write `x is string`. See [narrowing
tests](../language/types/narrowing.md#narrowing-tests) for what proves what, and
[tests that do not narrow](../language/types/narrowing.md#tests-that-do-not-narrow)
for the rest.

## Switches produce values

`switch selector do` makes a total, ordered dispatch readable without nesting
`elseif` expressions. Literal cases are checked for duplicates and
exhaustiveness, and a switch the checker proves total emits no `else` branch:

```nupp
local type Mode = "read" | "write"
local mode: Mode = "read"

local access = switch mode do
    case "read" -> "reader"
    case "write" -> "writer"
end
```

Type cases use the same runtime identity and narrowing as `is`. They can bind
the whole matched value with `as` and direct fields with a brace list, so the
`Figure` above dispatches without reading a tag:

```nupp
local function areaOf(shape: Figure): number
    return switch shape do
        case is Circle as circle -> math.pi * circle.radius * circle.radius
        case is Square {side} -> side * side
    end
end
```

An arm that needs statements writes `-> do`, then `yield value`; `return`
continues to exit the enclosing function. The selector runs once and lowering
adds no arm closure. See [switch
expressions](../language/switch-expressions.md) for the complete syntax and
constraints.

## Generics

Type arguments are inferred from the call, and constraints are written with
`is`, as `<T is Callable>`.

```nupp
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then
        return items[1]
    end
    return fallback
end

print(firstOr({1, 2, 3}, 0))
```

There is no explicit type-argument syntax at a call site. `f<number>(x)` parses
as two comparisons, the way it does in Lua. See [call sites take no explicit
type
argument](../language/types/generics.md#call-sites-take-no-explicit-type-argument)
for why, and [generics](../language/types/generics.md) for constraints,
refinements, and instantiation.

## Ownership

A value with a cleanup obligation carries it in its type, and the checker will
not let you drop it. A producer names the policy that discharges it, and any
type can carry one:

```nupp
local record Session
    closed: boolean
end

local function closeSession(takes session: Session): nil
    session.closed = true
end

local function openSession(): affine(Session, closeSession)
    return new Session(closed = false)
end
```

The exact `closeSession` identity is carried statically, so a value produced by
one policy cannot be discharged by another. An ordinary local is destroyed
automatically at its lexical boundary:

```nupp
do
    local session = openSession()
    print(session.closed)
end
```

Cleanup runs on fallthrough, `return`, `break`, `continue`, a `goto` leaving the
block, and an error raised anywhere inside. Moving, returning, or explicitly
dropping the owner deactivates its automatic cleanup exactly once. See
[ownership](../runtime/ownership/index.md) for the annotations a caller writes, and
[ownership and affine types](../runtime/ownership/borrowing.md) for the whole model.

## Waiting is an ordinary call

Nupp has no `async function`, `await`, future return type, or async half of the
standard library. A suspension-aware operation is an ordinary call with an
ordinary result:

```nupp
local process = require("nupp.io.process")

local child = new process.Process({args = {"cc", "--version"}} as process.Options)
local result = assert(child:communicate())
print(result.output)
child:close()
```

With no scheduler, `communicate` blocks by driving the registered readiness
sources. Under an installed scheduler, the same call parks the current coroutine
so other work can run. A ready operation does neither.

Whether a function may suspend is an inferred effect. Use `nosuspend do` where
control must not park; the compiler follows calls to the possible suspension and
reports the path. Libraries subscribe through `nupp.suspension`, [suspension
handlers](../runtime/concurrency/suspension.md#hosts-supply-scheduling-policy) own
scheduling policy, and `all`, `gather`, `race`, and `batch` compose several
waiting operations without promises.

::: deepdive
Without a checked effect, a library that might wait has three options. Blocking
makes it unusable under a scheduler. A second asynchronous surface doubles the
API and splits its callers into two populations that cannot share code. A policy
parameter pushes the decision onto every caller and into every signature between
them.

Suspension is one handled effect rather than general algebraic effects. One
effect with handlers covers the case, and a language where any operation can be
declared and handled is a much larger language than this needs. See [NEP
5](../../neps/0005-suspension.md) for more information.
:::

See [suspension](../runtime/concurrency/suspension.md) for the runtime paths, cancellation
contract, coroutine inheritance, and concurrent combinators.

## Calling C

A `cdef` block declares a C type and a C function against a named library.

```nupp
cdef struct nativePoint
    x: number
    y: number
end

cdef function point_length(borrows point: nativePoint*): number from"mini"
```

That emits `ffi.cdef` and an `ffi.load` lookup. The parameter modes `borrows`,
`takes`, `exclusive`, `retains`, and `releases` say what C does with a pointer,
which a header cannot. None of them change the ABI.

For a whole header there are two routes.
[`nupp import-c`](../runtime/c-interop/index.md#import-a-header) writes a committed,
hand-editable module, and
[`cheader("mini.h")`](../runtime/c-interop/index.md#type-the-header-in-place) types
the header at compile time with no generated file. A manifest C dependency adds
a generated bridge when the API exists only as `static inline` functions or
function-like macros.

::: seealso
- [c-interop.md](../runtime/c-interop/index.md) for all three import routes
- [describe lifetime
  behavior](../runtime/c-interop/index.md#describe-lifetime-behavior) for what each
  parameter mode promises
- [](nupp.mem.span) for bounds-checked views over C storage
:::

## Tooling in one binary

The checker, formatter, documentation generator, language server, build system,
profiler, and C importer are the same executable, built from the same parse.

```bash
nupp check          # type-check the project
nupp build          # compile to Lua
nupp run app.nupp   # compile and run
nupp fmt            # format
nupp doc            # generate this site
nupp lsp serve      # language server
nupp explain NUPP2119
```

Each shares one parse, one type checker, and one incremental engine, so the
editor and the build never disagree about what your code means.

::: seealso
- [tooling.md](../tooling/index.md) for the guided version of that list
- [why.md](why.md) for what each addition buys and what it costs
- [strictness.md](../language/gradual-typing.md) for typing an existing Lua project
  a file at a time
- [overview.md](../language/types/index.md) for the type system as a whole
- [features.md](features.md) for the broader runtime, compilation, and
  deployment features
:::
