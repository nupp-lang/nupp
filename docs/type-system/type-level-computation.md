# Comptime types

A `comptime function` that accepts compiler-only `type` and `typepack` handles
and returns a structural type or value pack is a type generator. Calling one in
type position runs it while the program is checked and emits no runtime
function or data.

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
test. `Optional` itself is not emitted, and nothing calls it at runtime. See
[comptime.md](../concepts/comptime.md) for the value-level half of the same
construct, where `comptime do ... end` folds a computation into a literal.

Type functions generate types, not declarations. They may construct structural
shapes, tuples, maps, functions, unions, intersections, wrappers, and packs, or
return an existing nominal type. They cannot create a record, interface,
method, module member, name, or runtime identity.

## Inspection and construction

Type handles are opaque and immutable. `nupp.types.describe(T)`, `kind`,
`elements`, `fields`, `readKeys`, `writeKeys`, `readAt`, and `writeAt` expose
checked semantic information without exposing mutable checker state. Builders
such as `literal`, `optional`, `array`, `tuple`, `map`, `shape`, `union`,
`intersection`, `pointer`, `carray`, `constof`, `function_`, and `pack` produce
validated handles.

`nupp.types.nonExhaustive()` takes no arguments and answers the one type no
name resolves to: the member that keeps a union open. It is written in a type
directly as well as inside a generator, since a union is where it means
anything. See [Unions that may grow](unions.md#unions-that-may-grow) for what
it does to a switch over that union.

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

`nupp.types.error(message)` rejects the type application deliberately. It is
distinct from an evaluator crash or timeout, and it reports the authored
message at the application with a bounded comptime call trace.

## Closed and generic calls

A call whose type, pack, and scalar arguments are concrete executes
immediately. An application containing a type parameter or const binder remains
an open type term, and [generic](generics.md) substitution executes it as soon
as inference makes every argument concrete.

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
```

`Kind` infers as the literal `"pair"` at the first call below, which closes
`Arguments("pair")` to `(string, number)`. Any other literal closes it to
`(...any)`, so the tail is unconstrained:

```nupp
local paired = apply("pair", "left", 2)
local loose = apply("other", true, nil, 3)
```

Until inference makes `Kind` concrete the application stays open: inside
`apply`, the tail is only what `unpackof Arguments(Kind)` promises, not what
either branch happens to return. `type<Bound>` constrains a generated result,
and until an open call closes, ordinary type consumers may use only facts
promised by that bound. Nupp does not symbolically execute arbitrary comptime
branches over unresolved types. See
[packs.md](packs.md#pack-compatibility) for how the resulting pack is checked.

## Direct finite operators

Small, locally readable type operations remain syntax. `keyof T` and
`writekeyof T` enumerate readable and writable keys, `T.[K]` reads a member
type, and `writeof T.[K]` gives the accepted write type. Mapped structural
shapes, template construction, const parameters, associated-type projections,
and `unpackof` are also retained.

```nupp
local record Settings
    theme: string
    volume: integer
end

local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]: function(value: T.[K]): nil
}
```

`Events<Settings>` is a shape of two read-only members, each named after the
field it came from and each taking that field's type:

```nupp
local handlers: Events<Settings> = {
    themeChanged = function(value: string): nil end,
    volumeChanged = function(value: integer): nil end,
}

handlers.themeChanged("dark")
```

Reach for these operators when they state the transformation more clearly than
a function and a run of builder calls would. User-authored branching,
iteration, parsing, and recursion belong in comptime functions.

::: deepdive
Two ways to write a type transformation is a cost, and the operators are kept
because a general language is the wrong tool for the small cases. A mapped
shape says the whole transformation in one line a reader checks by eye, where
the same thing as a comptime function is a loop over `fields`, a template
concatenation, and a `shape` call, none of which is wrong and all of which have
to be read to find out.

The split is by what the operation needs. Everything an operator does is finite
and structural, so the checker computes it directly without entering the
comptime worker or paying its limits. Anything needing a loop, a branch on a
value, string processing, or recursion crosses into the worker, and that is
where the general language earns its budget.
:::

## Const parameters

Const parameters admit only `string`, `boolean`, and exactly representable
`integer` values, and they erase at runtime. Integer const expressions admit
`+`, `-`, `*`, `//`, `%`, and comparisons.

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
a `Matrix<float, 4, 3>` where a `Matrix<float, 3, 4>` is wanted is reported as
`have different const argument 1`.

## `string.format`

The declarations for the Lua standard library type `string.format` with a
comptime function that reads the format string. A literal format gets exact
argument arity and conversion checks, and a broad runtime `string` retains a
gradual `...any` tail.

```nupp
local message = string.format("%s has %d messages", "Ada", 3)
```

Supported conversions match LuaJIT's bounded formatting surface. This is
implemented through the same type-function mechanism available to user code,
not a format-specific checker branch.

### `%?` formats a `Debug` value

`%?` requires `nupp.Debug`, calls `debug()`, and passes the result to Lua's
`%s`:

```nupp
@derive(nupp.derive.Debug)
local record User
    name: string
end

local inspected = string.format("user=%?", new User(name = "Ada"))
```

See [derives.md](../reference/derives.md#debug) for what
`@derive(nupp.derive.Debug)` generates.

### Formats the checker cannot read

A format that is not a literal is not an error. The call keeps the gradual
`...any` tail instead of an exact parameter list:

```nupp
local function report(template: string, name: string, unread: integer): string
    return string.format(template, name, unread)
end
```

### Format diagnostics

Arity errors report at the call:

```nupp
-- NUPP2006: omitted argument 3 supplies nil, not number
local missing = string.format("%s has %d messages", "Ada")

-- NUPP2007: too many arguments (expected 2, got 3)
local surplus = string.format("%s", "Ada", "Grace")
```

A conversion mismatch reports at the argument that does not fit, and an
unreadable directive reports where it starts:

```nupp
-- NUPP2006: argument 2: string is not a number
local mismatched = string.format("%d", "three")

-- NUPP2006: invalid string.format directive starting at "%y"
local invalid = string.format("%q %y", 1, 2)
```

### Typed wrappers

`nupp.types.formatArguments(Format)` exposes the same directive
computation, so a wrapper around `string.format` checks its callers the way
`string.format` checks its own:

```nupp
local function format<Format is string>(
    fmt: Format,
    ...: unpackof nupp.types.formatArguments(Format)
): string
    return string.format(fmt, ...)
end
```

The public computation rejects `%?`, because that directive needs the compiler
to rewrite the format and call `debug()`. It is available only on direct
`string.format`, literal `:format`, and logging calls.

## Lua string patterns

A literal pattern is read by a comptime function that counts its captures, and
`string.match`, `find`, `gmatch`, and `gsub` take their result packs from it.
Ordinary captures are `string` and empty `()` captures are `integer`. A dynamic
pattern keeps the ordinary gradual result contract.

`match` keeps its first result optional, because the pattern may not match at
all:

```nupp
local word: string?, at: integer = string.match("ready", "([a-z]+)()")
```

`find` returns its two endpoints optional and appends the captures after them:

```nupp
local first: integer?, last: integer?, name: string =
    string.find("ready", "([a-z]+)")
```

`gmatch` returns an iterator over the captures, or over the whole match when
the pattern has none:

```nupp
local nextWord: function(): string = string.gmatch("one two", "[a-z]+")
```

`gsub` validates a literal pattern even though its result stays
`(string, integer)`. An unparseable literal pattern is rejected wherever it
appears, with the reason the capture reader found.

## Limits and isolation

Type functions run in the isolated comptime worker under deterministic
iteration, step, call-depth, wall-clock, memory, protocol, graph-size, and
member limits. Results cross the worker boundary as validated structural
blueprints, so they cannot forge nominal identity or escape into generated Lua.
Recursive algorithms use ordinary comptime calls or loops and are governed by
the same limits.

::: deepdive
Running user code during checking makes the compiler's answer depend on that
code terminating and on it seeing the same world twice. The worker is what
makes both true: it is a separate process with its own budgets, so a type
function that loops forever is a diagnostic on one file rather than a compiler
that never returns, and it has no ambient access, so nothing it reads can
differ between two builds of the same source.

The blueprint boundary is the second half. A result is serialized and
revalidated on the way back rather than handed over as a live handle, which is
what keeps a type function from constructing checker state the checker would
then trust.
Nominal identity cannot cross that boundary at all, which is why a type
function returns an existing nominal type rather than making one.
:::

## FAQ

### Do comptime calls run at runtime?

A `comptime function` runs while source is checked and contributes only its
resulting type or pack. It emits no callable function, cache table, or runtime
branch, and [const parameters](#const-parameters) erase by the same boundary.
See
[strictness.md](../concepts/strictness.md#constructs-that-arent-erased) for the
two things that do survive.

### Why do type generators use parentheses?

`Optional(string)` calls a compile-time function; `Box<string>` applies a
declared generic type. The distinction lets built-in and user-defined
generators share one call syntax. See
[affine-types.md](affine-types.md#cleanup-identity-is-part-of-the-type)
for the same rule applied to ownership.

### Can a type function create a nominal type?

No. It can assemble a structural result or return an existing nominal type, but
it cannot inject a record, interface, method, name, or module member, which
keeps compile-time code from expanding the program's public or runtime surface.
Nominal identity comes from an explicit declaration site, so it stays stable
across repeated evaluation, caches, incremental rebuilds, and module
boundaries. See [associated-types.md](associated-types.md) for computed answers
that a declaration owns.

::: seealso
- [comptime.md](../concepts/comptime.md) for `comptime do` and the value-level
  side of compile-time evaluation
- [generics.md](generics.md) for the binders an open call waits on
- [packs.md](packs.md) for `typepack` results and where they may appear
- [NEP 3](../neps/0003-comptime.md) for the record of why the design is one
  language rather than two
:::
