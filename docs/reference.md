# Nupp language reference

Every construct, the shortest program that uses it, and the diagnostic codes that report getting it wrong. Generated from the compiler: `nupp reference`.

## What Nupp is

A gradually typed superset of LuaJIT's Lua dialect. Every valid LuaJIT program is
a valid Nupp program, and unannotated code checks silently — annotations are what
turn checking on, one declaration at a time.

Two things are not erased. A `struct` lowers to FFI cdata with a fixed layout,
and C headers import as checked declarations. Everything else is ordinary Lua at
run time.

Generated code targets LuaJIT 2.1.1784535649 or newer.

## Declaring things

A typed declaration says where it lives, the way an ordinary Lua definition does:
`local` keeps it to the file, a qualified name puts it on that table, and
`global` publishes it project-wide. Saying none of the three is refused rather
than defaulted, because plain Lua would have made the name a global and the same
silence is not reused for a different meaning.

Inside its own body a declaration answers to its simple name, so a recursive
field reads `User?` rather than `models.User?`.

```nupp
local models = {}

local type UserId = uint32
global type AppId = uint64

record models.User
    id: UserId
    name: string
    email: string?
end

return models
```

Reports: `NUPP2119`. `nupp explain <code>` says more.

## Types

Primitives: `any`, `unknown`, `never`, `nil`, `boolean`, `string`, `number`,
`integer`, `table`, `thread`, `userdata`. The C numeric tower: `float`,
`int8`…`int64`, `uint8`…`uint64`, plus `cdata`, `cstring` (`const char *`) and
`voidptr`.

`any` is gradual: compatible with everything, in both directions, silently.
`unknown` is its sound counterpart — everything fits into it, but it fits
nowhere else until narrowed or cast, the top of the type lattice. `never` is
the bottom: uninhabited, so it fits anywhere and nothing but itself fits it —
what a function that always raises, exits, or loops forever returns.

Postfix suffixes apply left to right: `T?` optional, `T*` pointer, `T[?]` a
variable-length C array and `T[N]` a fixed one. C arrays are zero-based cdata,
unlike the one-based `{T}`. `|` builds a union, a string literal is the type
containing just that value, and `const T` is a read-only view.

Arithmetic on `integer` widens to `number`; annotate a result `number` unless you
have narrowed it back.

```nupp
local m = {}
local type Id = uint32
local type Maybe = string?
local type Either = string | integer
local type Mode = "read" | "write"
local type Counts = {[string]: integer}
local type Row = {integer}
local type Point = {x: integer, y: integer}
local type Handler = function(event: string): boolean
local type Reply = unknown
return m
```

Reports: `NUPP2101`, `NUPP2001`. `nupp explain <code>` says more.

## Functions

Parameters and results are annotated in the usual place. Several results are
listed comma-separated; inside a function *type* a multi-result needs parentheses.

Under `--strict`, an exported function whose signature mentions `any` anywhere is
treated as unannotated and reported: `any` is the absence of a type, not a type.
A function that returns nothing still needs to say so, as `: nil`.

A function that always raises, exits, or loops forever returns `never`; a call
to it leaves the block it stands in, the way an inline `error` does.

```nupp
local m = {}

function m.add(a: integer, b: integer): integer
    return a + b
end

function m.split(text: string): string, integer
    return text, #text
end

function m.log(message: string): nil
    print(message)
end

function m.fail(message: string): never
    error(message)
end

return m
```

Reports: `NUPP2002`, `NUPP2106`. `nupp explain <code>` says more.

## Generics and bounds

Type parameters go in angle brackets after the name. `T is Bound` constrains one,
and the bound is an ordinary type — usually an interface.

```nupp
local m = {}

interface m.Named
    name: string
end

function m.first<T>(xs: {T}): T?
    return xs[1]
end

function m.labelOf<T is m.Named>(value: T): string
    return value.name
end

return m
```

Reports: `NUPP2101`. `nupp explain <code>` says more.

## Type packs and variadic generics

`A...` declares a heterogeneous generic value sequence. A pack may have a fixed
head and a generic or homogeneous tail. Only a final unparenthesized call or
`...` expands in an argument, assignment, or return list; parentheses project
one value.

Whole-pack unions preserve relationships between results. This is why testing
the boolean returned by `pcall` narrows its sibling values to the callback's
results or the failure value together. Discarding an affine slot while adjusting
a list is an error.

```nupp
local m = {}

function m.forward<A...>(...: A...): A...
    return ...
end

function m.protected<A..., R...>(
    callback: function(A...): R...,
    ...: A...
): ((true, R...) | (false, any))
    return pcall(callback, ...)
end

return m
```

Reports: `NUPP2010`, `NUPP2121`, `NUPP2605`. `nupp explain <code>` says more.

## Property capabilities

`readonly` and `writeonly` grant member access independently on shapes,
interfaces, records, and indexers. A readonly property is covariant; a
writeonly property is contravariant. Declaring both separately permits
different types, while an unmodified property grants both capabilities at one
invariant type.

These are views of members. `const T` makes a whole value read-only, and
`borrows`/`exclusive` describe lifetime and aliasing instead.

```nupp
local m = {}

local type Input = {readonly value: string | integer}
local type Output = {writeonly value: string}

record m.Cell
    readonly value: string
    writeonly value: string | integer
    readonly [string]: string
    writeonly [string]: string | integer
end

function m.fill(out: Output): nil
    out.value = "ready"
end

function m.show(input: Input): string
    return tostring(input.value)
end

return m
```

Reports: `NUPP2001`, `NUPP2009`. `nupp explain <code>` says more.

## Records

A record is a table with declared fields. It may carry inline methods, whose
`self` is implicit, and it is built with `new`.

`new` is how both records and structs are constructed, and the only way: it
lowers to the metatable stamp and the ctype call directly, installing nothing,
which is what leaves `__call` and `__new` to the program. Calling a record that
declares no `__call` contract is **NUPP2202**, and `new` on anything that is not
a record or a struct is **NUPP2206**.

The word is contextual — a name has to follow it on the same line — so a
variable named `new` still means what it did. A construction's brace stands off
its type, `new Point {x = 1}`, because the fields belong to the type rather than
being an argument to it; the `f{...}` call sugar it is otherwise spelled like
still hugs.

`local p: Point` declares storage and constructs nothing, so it holds nil until
something assigns to it and reading it before that is **NUPP2207**.

A declaration may state how it is built. A `constructor(...)` body is what
`new T(...)` runs: the instance is made before it and returned after it, so the
body fills the fields in. Every field that cannot hold nil has to be filled —
that guarantee is the reason to prefer one over a literal, and it is why
declaring a constructor closes the literal form for that declaration. Failing
either is **NUPP2208**. `constructor` is contextual, so a field may still be
called one.

The name is a value too: the runtime table `new` stamps on the instances it
builds. That table is their metatable, so it holds `metatable<Point>` rather
than `Point`, and the two do not stand for each other — the table may be passed
to `setmetatable` or have a metamethod contract installed on it, an instance may
not, and `Point is Point` is false without running. A function that wants a
declaration rather than one of its values takes `metatable<P>`.

One explicit type per field: grouped names are rejected.

```nupp
local m = {}

--- A point in the plane.
record m.Point
    x: integer
    y: integer

    --- Its distance from the origin, squared.
    function lengthSquared(self): number
        return self.x * self.x + self.y * self.y
    end
end

--- A point on a line through the origin.
record m.Diagonal
    x: integer
    y: integer

    constructor(at: integer)
        self.x = at
        self.y = at
    end
end

local corner = new m.Diagonal(3)
local origin = new m.Point {x = 0, y = 0}
local d = origin:lengthSquared()

return m
```

Reports: `NUPP2004`, `NUPP2118`, `NUPP2202`, `NUPP2206`, `NUPP2207`, `NUPP2208`. `nupp explain <code>` says more.

## Interfaces

An interface declares a shape without a body. `record X is Y` states that X
includes Y, and the checker holds it to that.

```nupp
local m = {}

interface m.Named
    name: string
end

record m.User is m.Named
    name: string
    id: uint32
end

return m
```

Reports: `NUPP2001`. `nupp explain <code>` says more.

## Default implementations

An interface may implement what it declares, and a declaration that takes the
contract takes the behaviour with it. The body is emitted once and referenced,
so an implementor inherits the behaviour rather than a copy — resolved where it
is written rather than looked up at run time.

This is the one thing that gives an interface a runtime presence: one that
declares only signatures still emits nothing.

`@override` is required on a member replacing an inherited default, and is an
error on one replacing nothing. Two interfaces providing the same name are two
implementations and no reason to prefer either, so the declaration writes the
member itself to say which behaviour it means. Both are **NUPP2118**.

```nupp
local m = {}

interface m.Greeter
    name: string

    function greet(): string
        return "hello, " .. self.name
    end
end

record m.Person is m.Greeter
    name: string
end

record m.Shouter is m.Greeter
    name: string

    @override
    function greet(): string
        return "HELLO"
    end
end

return m
```

Reports: `NUPP2118`. `nupp explain <code>` says more.

## Refinements

An interface may carry a `matches` block, which names the runtime test that
decides whether a value is one of these. `x is T` compiles to it, so
`s is m.Circle` below becomes `type(s) == "table" and s.kind == "circle"`.

Only an interface. A record is identified by the metatable `new` stamps and a
struct by its ctype, so both already answer `is` exactly; a refinement beside
either would be a second answer to a settled question. An interface has no
runtime table at all, so this is the only identity it can have — and it is what
lets a value this program did not build, a table off a decoder or anything an
untyped library returned, answer `is` at all.

The test runs wherever `is` is written, so it reads the declaration's own fields
through `self` and nothing else: comparisons against literals, `type()` tests,
and `and`/`or`/`not`. A call, arithmetic, an outside name, a refinement that
always answers the same way, or one on a record or struct is **NUPP2122** — as
is a declaration whose own fields provably fail an interface it declares.

```nupp
local m = {}

interface m.Shape
    kind: string
end

interface m.Circle is m.Shape
    kind: string
    radius: number

    matches
        self.kind == "circle"
    end
end

function m.area(s: m.Shape): number
    if s is m.Circle then return 3 * s.radius * s.radius end
    return 0
end

return m
```

Reports: `NUPP2122`. `nupp explain <code>` says more.

## Structs

A `struct` reifies: it lowers to `ffi.typeof`, so it has a fixed layout and no
hash lookup per field. `T[?]` and `T[N]` give contiguous arrays of them. This is
the one place a type changes what the program does at run time rather than only
what the checker accepts.

```nupp
local m = {}

struct m.Vec3
    x: float
    y: float
    z: float
end

local type Buffer = m.Vec3[?]
local type Fixed = m.Vec3[16]

return m
```

Reports: `NUPP2203`. `nupp explain <code>` says more.

## Literal and tagged unions

A union of string literals is a closed set of values — what other languages
spell `enum`. It erases: the value at run time is the plain string, and a bare
literal lands in it. A dispatch over one that leaves members unhandled is
reported, which is what makes adding a member a compile-time task list rather
than a run-time surprise.

A union of records, each carrying a literal-typed field, is a tagged union:
the field is the tag, and comparing it narrows the union to the one record
that declares that tag. That is the form to reach for when the alternatives
carry data, since a bare literal carries none.

```nupp
local m = {}

type m.Color = "red" | "green" | "blue"

local function describe(c: m.Color): string
    if c == "red" then return "warm"
    elseif c == "green" then return "cool"
    else return "cool" end
end

record m.Circle
    kind: "circle"
    radius: number
end

record m.Square
    kind: "square"
    side: number
end

type m.Shape = m.Circle | m.Square

function m.area(shape: m.Shape): number
    if shape.kind == "circle" then
        return 3.14159 * shape.radius * shape.radius
    end
    return shape.side * shape.side
end

return m
```

Reports: `NUPP2107`. `nupp explain <code>` says more.

## Narrowing

`e is T` tests a type and narrows in the branch it proves. A truthiness test
narrows an optional, including through a field path copied into a local. `e as T`
is an explicit cast where you know better than the checker.

A function may return a predicate, `p is T`, meaning it answers whether that
parameter holds the type — the value returned is a boolean, and the caller narrows
on it.

```nupp
local m = {}

local function isString(v: any): v is string
    return type(v) == "string"
end

local function describe(value: string | integer): string
    if value is string then
        return "text of " .. #value .. " bytes"
    end
    return "number " .. value
end

function m.nameOf(user: {name: string?}): string
    local name = user.name
    if not name then return "anonymous" end
    return name
end

return m
```

Reports: `NUPP2001`. `nupp explain <code>` says more.

## Owned resources

`@owned(cleanup)` says a result carries a cleanup obligation. An owned value must
be discharged before it leaves scope: disposed, passed to a `takes` parameter,
returned as an owner, or converted with `intoRaw`. Forgetting is a compile error,
not a leak.

Parameter modes say what a call does with what it is given: `takes` consumes,
`borrows` does not (and the borrow cannot escape), `exclusive` borrows with no
other view live, and `retains`/`releases` describe C holding a pointer across a
call.

```nupp
local m = {}

local function closeFile(file: LuaFile)
    file:close()
end

--- Opens a file the caller must discharge.
---
--- @param path where to read from
--- @return an owned handle
--- @raises when the file cannot be opened
@owned(closeFile)
function m.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

function m.slurp(path: string): string
    with file = m.open(path) do
        return file:read("*a")
    end
end

return m
```

Reports: `NUPP2603`, `NUPP2615`. `nupp explain <code>` says more.

## with scopes

`with` is the only place Nupp closes something for you. The resource is released
when the block ends — on fallthrough, on `return`, on loop control, on a `goto`
leaving the body, and on an error raised anywhere inside.

Each acquisition is a single-value context whose first result must be a
non-optional owner with at least one known cleanup. An optional owner has to be
narrowed first. Inside the body the binding is a borrow. Several resources may
share one scope, separated by commas.

```nupp
local m = {}

local function closeFile(file: LuaFile)
    file:close()
end

@owned(closeFile)
function m.open(path: string, mode: string): LuaFile
    local file = io.open(path, mode)
    if not file then error("cannot open " .. path) end
    return file
end

function m.copy(from: string, to: string): nil
    with
        input = m.open(from, "rb"),
        output = m.open(to, "wb")
    do
        output:write(input:read("*a"))
    end
end

return m
```

Reports: `NUPP2610`. `nupp explain <code>` says more.

## C interop

`cdef function` and `cdef struct` declare C with checked signatures. `from "lib"`
resolves through `ffi.load`; omitting it uses the default namespace.

`cheader('path.h')` types a pinned header at compile time — the compiler hands it
to its own `ffi.cdef` and reads the declarations back through `ffi.typeinfo`, so
LuaJIT's C parser is the source of truth and the sizes are this platform's. No
generated file, and no C compiler for a self-contained header. `nupp import-c`
ejects a committed, hand-editable binding module instead.

Reconstructing a raw pointer is confined to `unsafe do` blocks.

```nupp
local m = {}

cdef struct Point
    x: float
    y: float
end

cdef function labs(n: int32): int32

function m.magnitude(n: int32): int32
    return labs(n)
end

return m
```

Reports: `NUPP2203`, `NUPP2101`. `nupp explain <code>` says more.

## Annotations

An annotation is declared as a record or struct carrying `@annotation`, whose
`targets` list says where it may be applied. Its fields are the annotation's
members, and values are compile-time constants. Unknown annotations, wrong
targets and wrong value types are errors — an annotation never becomes a silently
erased comment.

Applications spell an unqualified `@name`, so a definition is registered
project-wide and is the one declaration exempt from the visibility rule. Both the
definition and every application are erased from the generated Lua.

Built-in contracts use the same surface. `@effects` is a complete effect
summary: visible bodies are checked against it and bodyless declarations are
trusted. `const` is the shallow identity promise for a bodyless binding in a
`.d.nupp`; it does not freeze a table's fields. `@relax` records a closed set
of observable guarantees an optimization may change, locally to one function.

```nupp
local m = {}

@annotation(targets = {"record", "struct"})
record serializable
    format: string
    version: integer?
end

@serializable(format = "json")
record m.User
    id: uint32
end

return m
```

Reports: `NUPP2119`. `nupp explain <code>` says more.

## Docblocks

An adjacent `---` run documents the declaration under it. `@param`, `@return`,
`@field`, `@typearg`, `@local` and `@export` are understood, and `nupp doc`
renders them.

`@raises` says what makes a function raise, one line per condition. It is the one
docblock tag the checker reads as well as renders: a documented function that
calls `error` without one is `undocumented-raise`. Raising is part of how a
function is called, and Lua has no signature to find it out from.

```nupp
local m = {}

--- Reads a configuration file.
---
--- @param path where to read from
--- @return the file's contents
--- @raises when the file cannot be read
function m.load(path: string): string
    local file = io.open(path, "r")
    if not file then error("no such file: " .. path) end
    return file:read("*a")
end

return m
```

Reports: `NUPP2506`. `nupp explain <code>` says more.

## Modules

Modules are Lua's: a file returns a value and `require` gets it. A module's type
is whatever the file returned, and a declaration with a runtime value puts itself
on that table, so nothing is merged in behind your back. Another file reaches a
member through the module it was attached to, and a module path also names a type
directly, as in `models.user.User`.

The returned local already identifies the module table; there is no `module`
keyword. Use `const M.field = value` to make an export slot immutable. A fresh
table can mark individual named slots with `const name = value`, or use
`const... M.field = {...}` to mark all of its named slots recursively. These
guarantees are checked in Nupp and preserve exact primitive literals for
constant propagation in consumers.

A `.d.nupp` declaration file is the exception: it describes an interface it does
not own and returns no table, so a bare declaration there is that interface.

`models.nupp`:

```nupp
local models = {}

record models.User
    id: uint32
    name: string
end

return models
```

```nupp
local models = require("models")

local user: models.User = new models.User {id = 1, name = "ada"}

return user
```

Reports: `NUPP2120`, `NUPP2101`. `nupp explain <code>` says more.

## LuaJIT 3.0 syntax

Nupp implements every LuaJIT 3.0 syntax extension and adds to them. Most is
written straight through to the output, because LuaJIT 2.1 backported it.

Available: `continue`; compound assignment (`+= -= *= /= //= %= &= |=`); the
ternary `c ? a : b`; `??` for nil-coalescing; safe navigation `?.`; short
functions `|x| -> e`; `const` bindings including `const function` and immutable
named table fields; and the customary spellings `!`, `&&`, `||`, `!=`.

`const M.field = value` initializes an immutable field. Inside a fresh table
constructor, `const name = value` does the same for a named slot. `const...`
before the outer field declaration is sugar that applies it recursively to the
new table graph:

```nupp
local M = {}
const... M.settings = {name = "nupp", nested = {count = 0}}
return M
```

The checker rejects later writes through those paths. Plain `const M.field`
remains shallow: ordinary inner fields stay mutable unless they are themselves
declared `const`.

The customary spellings are legal but linted: `not`, `and`, `or` and `~=` are the
ones Lua already has, and two spellings of one thing drift apart across a
codebase. Suppress per statement with `@allow("customary-operator")`.

```nupp
local m = {}

function m.demo(n: integer, flag: boolean, label: string?): integer
    local total = n
    total += 1
    local shown = flag ? "on" : "off"
    local name = label ?? "anonymous"
    for i = 1, 10 do
        if i == 5 then continue end
        total += i
    end
    local double = |x: integer| -> x * 2
    return total + #shown + #name + double(2)
end

return m
```

Reports: `NUPP2504`. `nupp explain <code>` says more.

## Lints and suppression

A type error says the program does not mean what it says it means: nothing
configures or silences it. A lint says the program means something you probably
did not intend, so it has a name, a level a project can move, and a suppression a
statement can apply.

`@allow` takes lint names or codes, applies to the statement it decorates and
nothing beyond it, and reaches any lint at any level. Bare `@allow` silences every
lint on that statement. It does not reach a type error; naming one is NUPP2108.

Levels are set in `nupp.lua` under `lints`, by name or by category, resolving
registry default → category → name → `@allow`.

```nupp
local m = {}

function m.toggle(flag: boolean): boolean
    @allow("customary-operator")
    local inverted = !flag
    return inverted
end

return m
```

Reports: `NUPP2108`. `nupp explain <code>` says more.

## Built-in lints

| Lint | Code | Category | Default |
| --- | --- | --- | --- |
| `missing-require` | NUPP2120 | correctness | error |
| `exhaustiveness` | NUPP2107 | correctness | warning |
| `string-pointer` | NUPP2501 | suspicious | warning |
| `jit-callback` | NUPP2502 | suspicious | warning |
| `lossy-narrowing` | NUPP2503 | suspicious | warning |
| `customary-operator` | NUPP2504 | style | warning |
| `loop-invariant-closure` | NUPP2505 | suspicious | warning |
| `undocumented-raise` | NUPP2506 | suspicious | warning |

## Diagnostic codes with a worked example

| Code | Meaning |
| --- | --- |
| NUPP0001 | A source file could not be read |
| NUPP1002 | A required token is missing |
| NUPP2001 | A value does not fit the type it is bound to |
| NUPP2004 | The field does not exist on that type |
| NUPP2009 | A property view does not grant the requested access |
| NUPP2010 | A complete value pack does not fit the required sequence |
| NUPP2106 | An exported declaration needs a type annotation |
| NUPP2107 | A dispatch leaves members of a closed set unhandled |
| NUPP2119 | A declaration does not say where it lives |
| NUPP2121 | A type pack is used where only one value type can appear |
| NUPP2122 | A 'where' refinement cannot be enforced |
| NUPP2123 | A metatable value does not fit the key it is written under |
| NUPP2202 | A declaration is built with 'new' |
| NUPP2206 | Only a record or a struct can be constructed |
| NUPP2207 | A binding is read before it holds a value |
| NUPP2208 | A constructor does not hold up its declaration |
| NUPP2605 | Adjusting a value pack would discard an affine value |
| NUPP3001 | `is` has nothing to test against this type |

## Working with the toolchain

Positions are 1-based byte line and column numbers everywhere, matching the
compiler's own diagnostics. Colour is off whenever output is not a terminal, so
piped output never carries escapes.

- `nupp check --strict [FILE...]` type-checks. `--json` returns structured
  diagnostics with `help`, `related`, `notes` and machine-applicable `fixes`.
  Read `help` and `related` before editing, and apply a whole titled fix rather
  than picking single edits out of one: a fix is all-or-nothing.
- `nupp build --json [FILE...]` returns those diagnostics alongside what the
  build wrote, so one call says both what failed and what landed.
- `nupp explain CODE [--json]` gives the rule behind a code, a program that
  reports it, and the same program corrected. Every diagnostic carries a `docs`
  anchor pointing at the same reference.
- `nupp lsp inspect|definition|references|symbols|rename|actions --json` answer
  semantic questions without an editor. `inspect` on a call returns the callee's
  docblock, which is where `@raises` is read at a call site.
- `nupp fmt`, `nupp doc`, `nupp test`, `nupp fixpoint` format, document, test,
  and verify the compiler rebuilds byte-identically.

Every command taking `--json` also takes `--schema`, which prints the JSON Schema
of that output, so a consumer can be written against a contract rather than
against a sample.

The loop that works: run `check --json --strict`, apply a complete fix whose
title matches the intended repair, re-run, and run `nupp test` before committing.
