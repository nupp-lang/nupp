# Comptime types

Nupp has one general compile-time programming language: ordinary Nupp inside
`comptime function` declarations. A comptime function may accept compiler-only `type` and
`typepack` handles and return a structural type or value pack. Calling such a
function in type position executes it while the program is checked and emits no
runtime function or data.

```nupp:playground
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

-- Optional(string) runs while this line is checked and answers string?,
-- so the annotation means exactly what `local value: string?` would mean.
local value: Optional(string) = nil
value = "ready"
if value ~= nil then
    -- Narrowing sees through the call: value is string here.
    print(#value)
end
```

The compiled Lua is `local value = nil` followed by the assignment and the
test. `Optional` itself is not emitted, and nothing calls it at runtime.

Type functions generate types, not declarations. They may construct structural
shapes, tuples, maps, functions, unions, intersections, wrappers, and packs, or
return an existing nominal type. They cannot create a record, interface, method,
module member, name, or runtime identity.

## Inspection and construction

Type handles are opaque and immutable. `nupp.types.describe(T)`, `kind`,
`elements`, `fields`, `readKeys`, `writeKeys`, `readAt`, and `writeAt` expose
checked semantic information without exposing mutable checker state. Builders
such as `literal`, `optional`, `array`, `tuple`, `map`, `shape`, `union`,
`intersection`, `pointer`, `carray`, `constof`, `function_`, and `pack` produce
validated handles.

```nupp
local comptime function DeepElement(T: type): type
    while nupp.types.kind(T) == "array" do
        T = nupp.types.elements(T)[1]
    end
    return T
end

-- The loop peels three array layers off {{{integer}}}, so the annotation
-- is integer and 42 is accepted.
local leaf: DeepElement({{{integer}}}) = 42
print(leaf + 1)
```

`nupp.types.error(message)` deliberately rejects the type application. It is
distinct from an evaluator crash or timeout and reports the authored message at
the application with a bounded comptime call trace.

## Closed and generic calls

A call whose type, pack, and scalar arguments are concrete executes immediately.
An application containing a type parameter or const binder remains an open type
term. Generic substitution executes it as soon as inference makes every argument
concrete.

```nupp
local comptime function Arguments(Kind: type): typepack
    local info = nupp.types.describe(Kind)
    if info.kind == "literal" and info.value == "pair" then
        return nupp.types.pack({nupp.types.string, nupp.types.number})
    end
    return nupp.types.pack({}, nupp.types.any)
end

local function apply<Kind is string>(
    kind: Kind,
    ...: unpackof Arguments(Kind)
): string
    return kind
end

-- Kind infers as the literal "pair", which closes Arguments("pair") to
-- (string, number), so this call is checked against exactly those.
local paired = apply("pair", "left", 2)

-- Any other literal closes it to (...any), so the tail is unconstrained.
local loose = apply("other", true, nil, 3)
```

Until inference makes `Kind` concrete the application stays open: inside
`apply`, the tail is only what `unpackof Arguments(Kind)` promises, not what
either branch happens to return.

`type<Bound>` constrains a generated result. Until an open call closes, ordinary
type consumers may use only facts promised by that bound. Nupp does not
symbolically execute arbitrary comptime branches over unresolved types.

## Direct finite operators

Small, locally readable type operations remain syntax. `keyof T` and
`writekeyof T` enumerate readable and writable keys. `T.[K]` reads a member type
and `writeof T.[K]` gives the accepted write type. Mapped structural shapes,
template construction, const parameters, associated-type projections, and
`unpackof` are also retained.

```nupp
local record Settings
    theme: string
    volume: integer
end

local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]: function(value: T.[K]): nil
}

-- Events<Settings> is {readonly themeChanged: function(string): nil,
-- readonly volumeChanged: function(integer): nil}. Each member's parameter
-- comes from the field it was named after.
local handlers: Events<Settings> = {
    themeChanged = function(value: string): nil end,
    volumeChanged = function(value: integer): nil end,
}

handlers.themeChanged("dark")
```

These bounded operators are preferred when they state the transformation more
clearly than a function and builder calls. User-authored branching, iteration,
parsing, and recursion belong in comptime functions.

## Const parameters

Const parameters admit only `string`, `boolean`, and exactly representable
`integer` values. They erase at runtime. Integer const expressions admit `+`,
`-`, `*`, `//`, `%`, and comparisons.

```nupp
local record Matrix<T, const Rows: integer, const Columns: integer>
    values: T[Rows * Columns]
end

-- The dimensions are type arguments, so Rows * Columns folds to 12 while
-- this is checked and values has the exact array type float[12].
local grid: Matrix<float, 4, 3> = nil as any
local cells: float[12] = grid.values
```

`grid` holds one array at runtime and carries no dimension fields: the consts
are checked and then erased. They still tell the two shapes apart, so assigning
a `Matrix<float, 4, 3>` where a `Matrix<float, 3, 4>` is wanted is NUPP2001,
reported as `have different const argument 1`.

## `string.format`

The prelude types `string.format` with a PEG-backed comptime parser. Literal formats get
exact argument arity and conversion checks; a broad runtime `string` retains a
gradual `...any` tail.

```nupp
local count = string.format("%s has %d messages", "Ada", 3)

@derive(nupp.derive.Debug)
local record User
    name: string
end

-- `%?` requires nupp.Debug, calls `debug()`, and passes the result to Lua's `%s`.
local inspected = string.format("user=%?", new User(name = "Ada"))

-- A format the checker cannot read is not an error; the call keeps the
-- gradual ...any tail instead of an exact parameter list.
local function report(template: string, name: string, unread: integer): string
    return string.format(template, name, unread)
end
```

Supported conversions match LuaJIT's bounded formatting surface. Invalid,
missing, surplus, and mismatched arguments report on the ordinary call. This is
implemented through the same type-function mechanism available to user code,
not a format-specific checker branch.

```nupp
-- NUPP2006: omitted argument 3 supplies nil, not number
local missing = string.format("%s has %d messages", "Ada")

-- NUPP2006: argument 2: string is not a number
local mismatched = string.format("%d", "three")

-- NUPP2007: too many arguments (expected 2, got 3)
local surplus = string.format("%s", "Ada", "Grace")

-- NUPP2006: invalid string.format directive starting at "%y"
local invalid = string.format("%q %y", 1, 2)
```

Arity errors report at the call, and a conversion mismatch reports at the
argument that does not fit.

`nupp.format.StringFormatSyntax(Format)` exposes the ordinary Lua directive
computation to typed wrappers:

```nupp
local function format<Format is string>(
    fmt: Format,
    ...: unpackof nupp.format.StringFormatSyntax(Format)
): string
    return string.format(fmt, ...)
end
```

The public computation deliberately rejects `%?`: that directive needs the
compiler to rewrite the format and call `debug()`, so it is available only on
direct `string.format`, literal `:format`, and logging calls.

## Lua string patterns

Literal Lua patterns are parsed by a PEG-backed comptime type function.
`string.match`, `find`, and
`gmatch` receive the pattern's capture pack: ordinary captures are `string`, and
empty `()` captures are `integer`. `match` keeps its first result optional because
the pattern may not match; `find` retains optional endpoints. `gsub` validates a
literal pattern even though its return stays `(string, integer)`. A dynamic pattern
keeps the ordinary gradual result contract.

```nupp
local word: string?, at: integer? = string.match("ready", "([a-z]+)()")
local first, last, name: integer?, integer?, string = string.find("ready", "([a-z]+)")
local nextWord: function(): string = string.gmatch("one two", "[a-z]+")
```

## Limits and isolation

Type functions run in the isolated comptime worker with deterministic iteration,
step, call-depth, wall-clock, memory, protocol, graph-size, and member limits.
Results cross the worker boundary as validated structural blueprints; they
cannot forge nominal identity or escape into generated Lua. Recursive algorithms
use ordinary comptime calls or loops and are governed by those limits.

## FAQ

### Do comptime calls run at runtime?

A `comptime function` runs while source is checked and contributes only its
resulting type or pack. It emits no callable function, cache table, or runtime
branch. [Const parameters](#const-parameters) erase by the same boundary. The
two [reified
exceptions](../concepts/strictness.md#erasure-has-two-exceptions) remain because
structs carry layout and C declarations bind native symbols.

### Why do type generators use parentheses?

`Optional(string)` calls a compile-time function; `Box<string>` applies a
declared generic type. The distinction lets built-in and user-defined
generators share one call syntax. [Affine type
generation](affine-types.md#why-parentheses-instead-of-angle-brackets) uses the
same rule rather than introducing ownership-specific generic syntax.

### Can a type function create a nominal type?

No. A comptime function is intentionally a type generator rather than a full
syntax or declaration macro. It can assemble a structural result or return an
existing nominal type, but it cannot inject a record, interface, method, name,
or module member. That keeps compile-time code from silently expanding the
program's public or runtime surface.

Nominal identity comes from an explicit declaration site, which keeps it stable
across repeated evaluation, caches, incremental rebuilds, and module
boundaries. [Records and structs](records.md) receive identity from those
declarations. [Associated types](associated-types.md) provide computed answers
owned by a declaration without granting comptime code control over names,
visibility, declaration order, runtime tables, metatables, or ABI layouts.

## Next

- [packs.md](packs.md): value sequences and `unpackof`.
- [generics.md](generics.md): type, pack, and const parameters.
- [associated-types.md](associated-types.md): declaration-owned type answers.
