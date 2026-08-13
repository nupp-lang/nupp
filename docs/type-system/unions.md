# Unions

A union is a value that is one of several types, written with `|`:

```nupp:playground
local type Either = string | integer
```

Two shapes of union earn their own names, because they are what other languages
reach for a keyword to express: a union of literals is a closed set of values,
and a union of records sharing a literal-typed field is a tagged union.

## Literal unions are enums

A string literal is a type containing exactly that value, so a union of them is
a closed set of strings:

```nupp
local type Color = "red" | "green" | "blue"
```

Nupp has no `enum` declaration; this is the spelling. Nothing is declared at run
time, since the value is the plain string, and a bare literal lands in the
union:

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

An alias is transparent, so `Color` and its union are interchangeable. That is
also why a diagnostic prints the members rather than the alias: there is no
nominal identity behind the name to print instead.

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
value shows it. That is the trade against a nominal sum type: the discriminant
costs a field, and in exchange the value is a plain table that serializes,
compares, and prints without help.

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
proved. See [narrowing](narrowing.md) for the rest of the rules.

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

When a dispatch on a closed set of literals has every branch return, the checker
reports the members you left out:

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

```
warning: NUPP2107 exhaustiveness: every branch returns, so this handles
"blue" | "green" | "red" and leaves "blue" unhandled
help: add branches for "blue" or add an else clause
```

Adding the branch or an `else` clears it. The diagnostic gives help rather than
an edit, because it cannot invent the body of the branch you are missing.

This is the `exhaustiveness` lint, `NUPP2107`, a `correctness` lint at
`warning`. A project raises it to `error` in `nupp.lua`, and a single deliberate
exception writes `@allow("exhaustiveness")` on the statement.

Exhaustiveness counts single literal types and unions of them. It does not run
over a union of records: a dispatch there tests a field rather than the value,
and the checker does not count the arms.

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

See [narrowing](narrowing.md) for the rest.

## Choosing a union kind

What the alternatives carry decides which of the two you want:

- The alternatives are values, and nothing rides along: a union of literals.
- The alternatives carry different data: a tagged union of records.
- The alternatives are unrelated existing types, told apart by `is`: a plain
  union, no tag needed.

## Diagnostics

- **NUPP2001**: a value is not a member of the union it is bound to.
- **NUPP2107**: the `exhaustiveness` lint, where a dispatch leaves members of a
  closed set unhandled.

## Next

- [narrowing.md](narrowing.md): what proves which member you are holding.
- [primitives.md](primitives.md): the literal types a closed set is built from.
