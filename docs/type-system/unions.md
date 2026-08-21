---
order: 290
---

# Unions

A union is a value that is one of several types, written with `|`:

```nupp:playground
local type Either = string | integer
```

Two shapes of union earn their own names, because they are what other languages
reach for a keyword to express: a union of literals is a closed set of values,
and a union of [records](records.md) sharing a literal-typed field is a tagged
union. See [Primitive types](primitives.md#unions-and-optionals) for how a
union interacts with `nil` and the optional shorthand `T?`.

## Literal unions are enums

A [string literal](primitives.md#literal-types) is a type containing exactly
that value, so a union of them is a closed set of strings:

```nupp
local type Color = "red" | "green" | "blue"
```

Nupp has no `enum` declaration, and a literal union is how one is written.
Nothing is declared at run time, since the value is the plain string, and a
bare literal lands in the union:

```nupp
local c: Color = "red"
```

A string that is not a member is rejected, and the message says which values
were on offer:

```nupp
local c: Color = "purple"
-- NUPP2001: "purple" is not a "blue" | "green" | "red"
```

Because the value is a string, everything that works on strings works here, and
a member is also accepted where a `cstring` is wanted.

A union may mix a closed set with an open type, which gives up exhaustiveness
but keeps the named cases:

```nupp
local type Reply = "ok" | "retry" | integer
```

Boolean literals are types too. `false` exists as one on its own so that
`T | false` narrows usefully:

```nupp
local type Flag = string | false
```

An [alias](primitives.md#type-aliases) is transparent, so `Color` and its union
are interchangeable. That is also why a diagnostic prints the members rather
than the alias: there is no nominal identity behind the name to print instead.

## Record unions are tagged unions

A literal member carries no data. When the alternatives need to, give each
record a field whose type is a literal, the tag, and union the records:

```nupp
local record Circle
    kind: "circle"
    radius: number
end

local record Square
    kind: "square"
    side: number
end

local type Shape = Circle | Square
```

Comparing the tag narrows the union to the one record that declares it, so the
fields of that arm are reachable and the other arm's are not:

```nupp
local function area(shape: Shape): number
    if shape.kind == "circle" then
        -- shape is Circle here: `radius` resolves, `side` does not
        return 3.14159 * shape.radius * shape.radius
    end
    -- shape is Square here

    return shape.side * shape.side
end
```

Construction fills the tag like any other field:

```nupp
local s: Shape = Circle{kind = "circle", radius = 2}
```

The tag is an ordinary field, so it survives to run time and a `print` of the
value shows it.

::: deepdive
The discriminant costs a field, which a nominal sum type would not spend. What
it buys is that the value stays a plain Lua table with no hidden header: it
serializes through [](nupp.data.json), compares field by field, prints readably,
and crosses a boundary to untyped Lua without a wrapper. A nominal encoding
would have to hide the tag somewhere the runtime can still find it, which means
either a metatable, and then a decoded table is not one of these, or a reserved
key, and then the cost is the same field under a name nobody chose.
:::

A tag copied into a local is still a tag:

```nupp
local function areaVia(shape: Shape): number
    local kind = shape.kind
    if kind == "circle" then
        -- shape is Circle here too
        return 3.14159 * shape.radius * shape.radius
    end

    return shape.side * shape.side
end
```

Assigning to `shape`, or to anything the copy came from, drops what the copy
proved. See [Narrowing](narrowing.md#facts-live-in-a-scope) for how long a
fact lasts.

### Success and failure

The arms need share nothing but the tag, so the same shape carries a result
and the reason it is not one:

```nupp
local record Ok
    kind: "ok"
    value: string
end

local record Err
    kind: "err"
    message: string
end

local type Result = Ok | Err

local function describe(r: Result): string
    if r.kind == "ok" then
        return "ok: " .. r.value
    end
    return "failed: " .. r.message
end
```

## Exhaustiveness

A closed set of literals is worth having only if something checks that every
member was handled. Two constructs do, and they answer to different severities.

### Switch exhaustiveness

A [switch expression](../concepts/switch-expressions.md) checks exhaustiveness
as a type error rather than a lint, because the expression must always produce
a value:

```nupp
local function describe(c: Color): string
    return switch c do
        case "red" -> "warm"
        case "green", "blue" -> "cool"
    end
end
```

Cases subtract their exact values from the remaining selector union. An `else`
is required for an open alternative such as `string` or `integer`, but is
unreachable once a closed union has been consumed. `1`, `1.0`, and `1e0` name
one numeric value and therefore count as duplicate cases. See [Switch
expressions](../concepts/switch-expressions.md#exhaustiveness-and-reachability)
for the reachability rules that go with them.

### Unions that may grow

A union that lists `nupp.types.nonExhaustive()` among its alternatives carries
one member no value inhabits, no name resolves to, and no case can cover:

::: code-group
```nupp [Nupp]
local type Status = "ok" | "error" | nupp.types.nonExhaustive()

local function describe(status: Status): string
    return switch status do
        case "ok" -> "fine"
        case "error" -> "broken"
        else -> "unrecognized"
    end
end
```

```lua [Generated Lua]
local function describe(status)
    local __nuppT1 = status
    local __nuppT2
    if __nuppT1 == "ok" then __nuppT2 = "fine"
    elseif __nuppT1 == "error" then __nuppT2 = "broken"
    else __nuppT2 = "unrecognized"
    end
    return __nuppT2
end
```
:::

Handling `"ok"` and `"error"` leaves that member behind, so the switch keeps
asking for its `else` and never reports one as unnecessary. `Status` prints as
`"error" | "ok" | ...`, and it does not fit `"ok" | "error"`, which is the same
statement read from the other side: code outside the declaration may not assume
the set is closed. Each alternative still assigns into it, so adding one is not
a breaking change for the callers that write them.

The member is only ever obtained by calling for it. There is no name for it, in
a case, an annotation, or anywhere else. See [Comptime
types](type-level-computation.md#inspection-and-construction) for the rest of
the type builders it belongs to.

### Returning-branch exhaustiveness

When a dispatch on a closed set of literals has every branch return, the
checker reports the members you left out:

```nupp
local function describe(c: Color): string
    if c == "red" then
        return "warm"
    elseif c == "green" then
        return "cool"
    end

    return "unknown"
end
```

```text
warning: NUPP2107 exhaustiveness: every branch returns, so this handles
"blue" | "green" | "red" and leaves "blue" unhandled
help: add branches for "blue" or add an else clause
```

Adding the branch or an `else` clears it. The diagnostic gives help rather than
an edit, because it cannot invent the body of the branch you are missing.

This is the [`exhaustiveness` lint](../reference/lints.md#exhaustiveness), a
`correctness` lint at `warning`. A project raises it to `error`
in `nupp.lua`, and a single deliberate exception writes
`@allow("exhaustiveness")` on the statement.

Exhaustiveness counts single literal types and unions of them. It does not run
over a union of records: a dispatch there tests a field rather than the value,
and the checker does not count the arms.

::: deepdive
The two constructs get different severities because they promise different
things. A switch expression has to produce a value on every path, so an
unhandled member is a hole in the expression's type and nothing weaker than an
error describes it. An `if` chain promises nothing: falling off the end is
legal Lua, and a chain that deliberately handles two of five cases is an
ordinary program. Reporting that as an error would make the closed union
unusable outside a switch, so it is a lint a project raises when it wants the
stronger rule everywhere.
:::

## Narrowing

Comparing against a member narrows in both directions:

```nupp
local function widthOf(c: Color): integer
    if c == "red" then
        -- c is "red" here
        return 3
    else
        -- c is "green" | "blue" here
        return 0
    end
end
```

`e is T` narrows a union whose members are distinguishable by type rather than
by value:

```nupp
local function render(v: string | integer): string
    if v is string then
        return v
    end
    return tostring(v)
end
```

See [Narrowing](narrowing.md#narrowing-tests) for every test that narrows and
the ones that look like they should and do not.

## Choosing a union kind

What the alternatives carry decides which of the two you want:

- The alternatives are values, and nothing rides along: a union of literals.
- The alternatives carry different data: a tagged union of records.
- The alternatives are unrelated existing types, told apart by `is`: a plain
  union, no tag needed.

::: seealso
- [narrowing.md](narrowing.md) for the tests that take a union apart
- [switch-expressions.md](../concepts/switch-expressions.md) for dispatching on
  one as an expression
- [intersections.md](intersections.md) for `&`, which composes types rather
  than offering a choice between them
- [primitives.md](primitives.md#literal-types) for the literal types a closed
  union is built from
:::
