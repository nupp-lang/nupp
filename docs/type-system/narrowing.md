# Narrowing

Narrowing is how a union becomes one of its members inside a branch.

```nupp
local function widthOf(s: string?): integer
    if s then
        return #s -- s is string here
    end
    return 0
end
```

## Narrowing tests

| Construct | Example |
| --- | --- |
| Truthiness of a name | if s then |
| Truthiness of a dotted path | if config.name then |
| not <cond> | if not s then ... else ... end |
| == nil / ~= nil | if s ~= nil then |
| A discriminant field | if shape.kind == "circle" then |
| The is operator | if v is Point then |
| ffi.istype<T>(v) | if ffi.istype<Point>(v) then |
| A predicate function | if isPoint(v) then |
| and / or | if a and a.b then |
| if / elseif chains | else-branches accumulate facts |
| Ternary arms | v is Point ? v.x : 0 |
| while cond do | the body sees the condition |
| Guard clauses | if not s then return end |
| never-returning helper calls | bail() narrows like an inline error |

Discriminant narrowing also follows a copied local, so binding the value to a
new name first does not lose the fact.

## Tests that do not narrow

**`type(x) == "string"` does not narrow.** This is the one people expect most:

```nupp
local function f(s: string | number): string
    if type(s) == "string" then
        return s
    end
    return "no"
end

-- NUPP2002: return 1: number | string is not a string
```

`type` is an ordinary function returning an ordinary string, and nothing ties
its result back to `s`. Write `s is string`.

**`assert(x)` as a statement does not narrow `x`.** It narrows through its
*return value*, because its signature subtracts `nil`:

```nupp
assert(s)
local a: string = s -- still an error

local b = assert(s) -- b is string
```

**Only names and dotted paths narrow.** An index like `a[i]`, a call, or any
computed expression has no stable key to attach a fact to.

**`any` never narrows.** It is already compatible with everything.

Two smaller limits: the falsy side of `and` proves nothing, and subtracting
every member of a union leaves the union alone, since there is no bottom type.

## Facts live in a scope

A narrowed fact dies with the scope that proved it, and assigning to a name
clears the facts for that name and everything beneath it:

```nupp
local function f(s: string?)
    if s then
        s = maybeName() -- facts for s are cleared here
    end
end
```

## Predicate functions

When narrowing cannot see what you know, write a predicate. The return type
`v is T` names a parameter and a type:

```nupp
local function isPoint(v: any): v is Point
    return v ~= nil and v.x ~= nil and v.y ~= nil
end

local function use(v: any)
    if isPoint(v) then
        print(v.x)
    end
end
```

The body is trusted. The checker verifies that the name is a parameter
(NUPP2109) and that the parameter could hold that type (NUPP2110), and takes
the rest on faith.

## Guard clauses

A function that returns `never` narrows the code after a call to it, the way
an inline `error` does:

```nupp
local function bail(msg: string): never
    error(msg)
end

local function use(s: string?)
    if not s then
        bail("missing")
    end
    print(#s) -- s is string here
end
```

The checker infers this for a body whose every path raises, so the `never`
return type is only needed where it cannot see that: an imported C `abort`, a
declaration file with no body, or a loop that never ends. See
[primitives](primitives.md#never-the-bottom-type).

## Exhaustiveness

When every branch of a dispatch over a closed set of literals returns, the
checker reports the unhandled members as the `exhaustiveness` lint. See
[unions](unions.md).

Exhaustiveness counts single literal types and unions of them. A union of
records is narrowed by a discriminant field instead.

## Diagnostics

- **NUPP2002**: a returned value does not fit the declared result, which is
  what a union that was never narrowed reports.
- **NUPP2109**: a narrowing test cannot hold, because the type tested for is
  not one the subject could be.
- **NUPP2110**: a parameter could not hold the type a test narrows it to.

## Next

- [refinements.md](refinements.md): the test an interface supplies for `is`.
- [unions.md](unions.md): the closed sets narrowing is usually applied to.
