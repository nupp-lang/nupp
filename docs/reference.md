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

## Records

A record is a table with declared fields. It may carry inline methods, whose
`self` is implicit, and it is constructed by calling it with a table.

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

local origin = m.Point{x = 0, y = 0}
local d = origin:lengthSquared()

return m
```

Reports: `NUPP2004`, `NUPP2118`. `nupp explain <code>` says more.

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

## Enums

An enum is a closed set of string literals. A dispatch over one that leaves
members unhandled is reported, which is what makes adding a member a compile-time
task list rather than a run-time surprise.

```nupp
local m = {}

enum m.Color "red" "green" "blue" end

local function describe(c: m.Color): string
    if c == "red" then return "warm"
    elseif c == "green" then return "cool"
    else return "cool" end
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

local user: models.User = models.User{id = 1, name = "ada"}

return user
```

Reports: `NUPP2120`, `NUPP2101`. `nupp explain <code>` says more.

## LuaJIT 3.0 syntax

Nupp implements every LuaJIT 3.0 syntax extension and adds to them. Most is
written straight through to the output, because LuaJIT 2.1 backported it.

Available: `continue`; compound assignment (`+= -= *= /= //= %= &= |=`); the
ternary `c ? a : b`; `??` for nil-coalescing; safe navigation `?.`; short
functions `|x| -> e`; `const` bindings including `const function`; and the
customary spellings `!`, `&&`, `||`, `!=`.

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

## Every lint

| Lint | Code | Category | Default |
| --- | --- | --- | --- |
| `missing-require` | NUPP2120 | correctness | error |
| `enum-exhaustiveness` | NUPP2107 | correctness | warning |
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
| NUPP2106 | An exported declaration needs a type annotation |
| NUPP2107 | An enum dispatch leaves members unhandled |
| NUPP2119 | A declaration does not say where it lives |
| NUPP2122 | A 'where' refinement is not checked |

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

