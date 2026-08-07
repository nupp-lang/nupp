# Enums

An enum is a named set of string literals.

```nupp
local enum Color
    "red"
    "green"
    "blue"
end
```

Members are string literals and nothing else. The declaration erases
completely — an enum value at runtime is the plain string.

## Using one

An enum is a subtype of `string`, so a bare literal lands in it:

```nupp
local c: Color = "red"
```

A string that is not a member is rejected by name:

```nupp
local c: Color = "purple"
-- NUPP2001: "purple" is not a member of Color
```

Because the value is a string, everything that works on strings works here,
and an enum member is also accepted where a `cstring` is wanted.

Reading a member through the type name (`Color.red`) type-checks but yields
`any`. The useful spelling is the bare literal.

## Exhaustiveness

When a dispatch on an enum has every branch return, the checker reports the
members you left out:

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
warning: NUPP2107 enum-exhaustiveness: every branch returns, so this
handles Color and leaves "blue" unhandled
help: add branches for "blue" or add an else clause
```

Adding the branch or an `else` clears it. The diagnostic gives help rather than
an edit, because it cannot invent the body of the branch you are missing.

This is the `enum-exhaustiveness` lint, `NUPP2107`, a `correctness` lint at
`warning`. A project raises it to `error` in `nupp.lua`, and a single
deliberate exception writes `@allow("enum-exhaustiveness")` on the statement.

Exhaustiveness works over enums, single literal types, and unions of literals.
It does not apply to a union of records — use a discriminant field for that,
which narrowing understands.

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

See [narrowing](narrowing.md) for the rest.

## When to reach for something else

An enum is a closed set of strings. When you want a closed set of *shapes*, use
a union of records with a discriminant field:

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

Narrowing on `shape.kind == "circle"` gives you `Circle`, which is the pattern
an enum cannot express because its members carry no data.
