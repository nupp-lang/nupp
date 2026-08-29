---
order: 360
---

# Narrowing

Narrowing is how a [union](unions.md) becomes one of its members inside a
branch. A test proves a fact about a name or a dotted path, and that fact holds
for the rest of the branch that proved it.

```nupp:playground
local function widthOf(s: string?): integer
    if s then
        return #s -- s is string here
    end
    return 0
end
```

## Narrowing tests

Every test below ends up attached to a name or a dotted path, which is the key
the checker records the fact against.

| Construct | Example |
| --- | --- |
| Truthiness of a name | `if s then` |
| Truthiness of a dotted path | `if config.name then` |
| Negation | `if not s then ... else ... end` |
| Nil comparison | `if s ~= nil then` |
| Discriminant field | `if shape.kind == "circle" then` |
| `is` operator | `if v is Point then` |
| C type test | `if ffi.istype<Point>(v) then` |
| Predicate call | `if isPoint(v) then` |
| Short-circuit `and` | `if a and a.b then` |
| `elseif` chain | `elseif shape.kind == "square" then` |
| Ternary arms | `v is Point ? v.x : 0` |
| Loop condition | `while node do` |
| Guard clause | `if not s then return end` |
| Never-returning call | `bail("missing")` |
| `assert` statement | `assert(s)` |

Discriminant narrowing follows a copied local, so binding the tag to a new name
first does not lose the fact:

```nupp
local kind = shape.kind
if kind == "circle" then
    print(shape.radius) -- shape is the circle arm here
end
```

An `elseif` chain subtracts as it goes, so each branch sees only what the
earlier ones left. See [unions.md](unions.md#exhaustiveness) for what the
checker reports when such a chain leaves a member unhandled.

### `assert`

`assert` narrows in both positions. Its signature subtracts `nil` from the
return value, and as a bare statement it narrows its argument the way a
never-returning helper does, because the builtin returns only on the truthy
arm:

```nupp
assert(s)
local a: string = s -- s is string here

local b = assert(s) -- so is b
```

Being truthy, it subtracts `false` as well as `nil`, and it reads a name or a
dotted path like every other test. A message argument makes no difference. It
narrows only when `assert` is the builtin: a locally shadowed `assert` is an
ordinary call and proves nothing.

## Tests that do not narrow

A test proves nothing when the checker cannot tie it to a stable key, or when
there is nothing left for the fact to say.

### `type` compares a string

`type(x) == "string"` does not narrow, which is the limit readers hit first:

```nupp
local function f(s: string | number): string
    if type(s) == "string" then
        return s
    end
    return "no"
end

-- NUPP2002: return 1: number | string is not a string
```

`type` is an ordinary function and nothing ties its result back to `s`. Write
`s is string`.

The *result* narrows even though the argument does not, because `type` answers
from a closed set: `"nil" | "boolean" | "number" | "string" | "table" |
"function" | "thread" | "userdata" | "cdata"`. A comparison against a name
LuaJIT never returns is caught where it is written, and a returning dispatch
over the set reports the
[`exhaustiveness`](../reference/lints.md#exhaustiveness) lint for the names it
leaves out. A guard chain whose remaining cases are handled by the code after
it says so with `@allow("exhaustiveness")`.

### Computed expressions

Only names and dotted paths narrow. An index like `a[i]`, a call result, or any
other computed expression has no stable key to hang a fact on. Bind it to a
local and narrow that:

```nupp
local entry = entries[index]
if entry then
    print(entry.name) -- entry is narrowed; entries[index] would not have been
end
```

::: deepdive
A fact is recorded under a textual path: `s`, or `cfg.server.port`. Two
evaluations of `a[i]` are two separate reads, and nothing in the path says `i`
held the same value both times or that `a` was not written in between. Tracking
one would mean proving that neither the index nor the table changed across
every statement between the test and the use, which is the analysis narrowing
exists to do without.

Assignment is the only thing that clears a fact, and it clears the path
assigned to along with everything under it. A call in between keeps the facts,
including a call that could reach a captured local and reassign it.
:::

### `any`

`any` never narrows, because it is already compatible with everything. Reach
for a [predicate function](#predicate-functions) or an `as` cast where you know
more than the annotation does. See
[overview.md](overview.md#gradual-escape-hatches) for what `any` gives up.

### Falsy `and`

The truthy side of `and` proves both operands. The falsy side proves neither,
since either test could have been the one that failed:

```nupp
if a and a.b then
    print(a.b) -- a is not nil and a.b is truthy
else
    print(a) -- nothing was proved: a may still be nil
end
```

### Exhausted subtraction

Subtracting every member of a union leaves
[`never`](primitives.md#never-the-bottom-type) on that path:

```nupp
local function f(v: string | number)
    if v is string then
        print(v)
    elseif v is number then
        print(v)
    else
        -- v is never here: both members were subtracted
    end
end
```

A type that is not a union survives the same treatment. Subtracting `string`
from `string` leaves `string`, so the false arm of a test that could not have
failed says what the declaration said.

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

The declared type is what an assignment is checked against, so clearing a fact
never lets a wider value in. It only takes back what the test had proved.

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

The body is trusted. The checker verifies that the name is a parameter and that
the parameter could hold that type, and takes the rest on faith.

::: deepdive
Proving a predicate would mean deriving `v is Point` from the body's chain of
field tests, which is the same shape-inference problem the `is` operator exists
to avoid. Trusting the body keeps the escape hatch one function wide: the
signature says what is being asserted, the callers get an ordinary narrowing
test, and the unchecked step is confined to a body a reader can see whole. See
[overview.md](overview.md#deliberate-unsoundness) for the other rules that
trade soundness for compatibility.
:::

## Guard clauses

A function that returns `never` narrows the code after a call to it, the way an
inline `error` does:

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
[primitives.md](primitives.md#never-the-bottom-type) for the rest of what
`never` does.

## Switch arm narrowing

Switch cases apply their facts only within their own arm. A static case narrows
the selector to the matched literal; `case is T` narrows it to `T`. Earlier
cases are subtracted before a later arm is checked, so the `else` arm sees the
unmatched residue:

```nupp
local text = switch value do
    case is string as s -> s
    case is Point as point {x, y} -> `(${x}, ${y})`
    else -> "none" -- value is the portion not covered above
end
```

`as point` is a const binding of the narrowed whole value. `{x, y as vertical}`
introduces const locals for direct fields; those names exist only in that arm.
The original selector remains narrowed too. Type cases are ordered, so a broad
case before a narrower one can make the latter unreachable.

See [switch
expressions](../concepts/switch-expressions.md#type-cases-binding-and-destructuring)
for runtime-testable types and block arms.

## Returning-branch exhaustiveness

When every branch of a dispatch over a closed set of literals returns, the
checker reports the members left out as the `exhaustiveness` lint:

```nupp
local type Color = "red" | "green" | "blue"

local function name(color: Color): string
    if color == "red" then
        return "warm"
    elseif color == "green" then
        return "cool"
    end

    return "unknown" -- NUPP2107: "blue" is unhandled
end
```

Exhaustiveness counts single literal types and unions of them. It does not run
over a union of records, where a dispatch tests a discriminant field rather
than the value. See [unions.md](unions.md#exhaustiveness) for the rule and
[lints.md](../reference/lints.md#exhaustiveness) for the lint's severity and
suppression.

## FAQ

### Does a call between the test and the use lose the narrowing?

No. Assignment is the only thing that clears a fact, so the fact survives any
call in between, including one that could reach a captured local and reassign
it. Reassigning the name yourself clears it, as
[Facts live in a scope](#facts-live-in-a-scope) shows.

### Should I write `is` or a predicate function?

Write `v is T` when `T` is runtime-testable on its own, which covers records,
structs, C types, and literals. Write a [predicate](#predicate-functions) when
the test is a shape check the checker cannot perform, or when the same check is
repeated in several places. See
[interfaces.md](interfaces.md#is-is-a-claim-not-a-proof) for what an `is` edge
proves.

### Does narrowing change the generated Lua?

No. A narrowed type is a fact the checker carries and erases, so the branch
lowers to the Lua you wrote. See
[strictness.md](../concepts/strictness.md#constructs-that-arent-erased) for the
two things that do survive.

::: seealso
- [unions.md](unions.md) for the types narrowing takes apart
- [switch-expressions.md](../concepts/switch-expressions.md) for narrowing per
  arm, with binding and destructuring
- [primitives.md](primitives.md#never-the-bottom-type) for `never` and the
  guard clauses it enables
- [lints.md](../reference/lints.md#exhaustiveness) for the `exhaustiveness`
  lint and how to suppress it
:::
